import AppKit
import SwiftUI
import WebKit
import PDFKit
import UtilityCore

@MainActor final class EditorController: NSObject, NSTextViewDelegate, WKNavigationDelegate,NSWindowDelegate {
    static let shared = EditorController()
    var window: NSWindow!
    var text: NSTextView!
    var web: WKWebView!
    var renderTask: DispatchWorkItem?
    var navigationTask:DispatchWorkItem?
    var renderGeneration=0
    var renderedGeneration=0
    var renderedSource=""
    var handlingPreviewNavigation=false
    var sourceMap=SourceLineMap("")
    var sourceMapText=""
    var ready = false
    var file: URL?
    var exporting = false
    var savedText=""
    var openedFiles:[URL]=[]
    var filePicker:NSPopUpButton!
    var fileLease:AccessLease?
    let chrome=EditorChrome()
    var matches:[NSRange]=[]
    var matchIndex = -1
    var exportSheet:NSWindow?
    let exportLocation=ExportLocation(inputs:[],filename:"Untitled.pdf")
    func show(files:[URL]) {
        guard !files.isEmpty else {show();return}
        if window != nil,!confirmDiscard() {return}
        show()
        do {
            let lease=AccessLease(urls:files)
            let content=try String(contentsOf:files[0],encoding:.utf8)
            openedFiles=files;fileLease=lease
            filePicker.removeAllItems();filePicker.addItems(withTitles:files.map(\.lastPathComponent));filePicker.isHidden=files.count<2
            load(content,url:files[0])
        } catch {showError(error)}
    }
    func load(_ content:String,url:URL) {text.undoManager?.removeAllActions();text.string=content;savedText=content;file=url;exportLocation.directory=url.deletingLastPathComponent();exportLocation.filename=url.deletingPathExtension().lastPathComponent+".pdf";window.title=url.lastPathComponent;syncChrome();rebuildSearch(selectFirst:false);render()}
    func confirmDiscard()->Bool {
        guard !exporting else {return false}
        guard text.string != savedText else {return true}
        let alert=NSAlert();alert.messageText="Save your changes?";alert.informativeText=file?.lastPathComponent ?? "Untitled Markdown";alert.addButton(withTitle:"Save…");alert.addButton(withTitle:"Discard");alert.addButton(withTitle:"Cancel")
        switch alert.runModal() {case .alertFirstButtonReturn:return saveCurrent();case .alertSecondButtonReturn:text.string=savedText;render();return true;default:return false}
    }
    func windowShouldClose(_ sender:NSWindow)->Bool {confirmDiscard()}
    @objc func chooseFile() {
        let index=filePicker.indexOfSelectedItem
        guard openedFiles.indices.contains(index) else {return}
        let previous=openedFiles.firstIndex(where:{$0==file}) ?? 0
        guard confirmDiscard() else {filePicker.selectItem(at:previous);syncChrome();return}
        do {let url=openedFiles[index];load(try String(contentsOf:url,encoding:.utf8),url:url)} catch {filePicker.selectItem(at:previous);syncChrome();showError(error)}
    }
    func show() {
        if window != nil { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:1050,height:720), styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "Markdown & math"; window.delegate=self;window.isReleasedWhenClosed = false; window.backgroundColor = NSColor(Color.utilitySurface)
        let root = NSView(); window.contentView = root
        filePicker=NSPopUpButton();filePicker.target=self;filePicker.action=#selector(chooseFile)
        let bar=NSHostingView(rootView:EditorHeader(chrome:chrome,controller:self))
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        text = NSTextView();text.usesFindBar=false;text.allowsUndo=true; text.isRichText = false; text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false; text.font = .monospacedSystemFont(ofSize: 14,weight: .regular); text.textContainerInset = NSSize(width:16,height:16); text.delegate = self
        text.minSize = NSSize(width:0,height:0); text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude); text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        let config = WKWebViewConfiguration(); config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.add(EditorPreviewBridge(controller:self),name:"sourceNavigation")
        web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = self
        split.addArrangedSubview(scroll); split.addArrangedSubview(web)
        for view in [bar,split] {view.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(view)}
        NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo:root.leadingAnchor),bar.topAnchor.constraint(equalTo:root.topAnchor),bar.trailingAnchor.constraint(equalTo:root.trailingAnchor),split.leadingAnchor.constraint(equalTo:root.leadingAnchor),split.trailingAnchor.constraint(equalTo:root.trailingAnchor),split.topAnchor.constraint(equalTo:bar.bottomAnchor),split.bottomAnchor.constraint(equalTo:root.bottomAnchor)])
        window.minSize=NSSize(width:760,height:480)
        text.string = "# A lighter place to edit\n\nMake a quick adjustment on the left. See it immediately on the right.\n\n- **Markdown** formatting\n- Tables and code blocks\n- LaTeX-style math\n\n$$\\int_0^1 x^2\\,dx = \\frac{1}{3}$$\n\n| Tool | Purpose |\n|---|---|\n| Shelf | Collect files |\n| Workflows | Prepare a batch |\n"
        savedText=text.string
        let packagedBundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("UtilityApp_UtilityApp.bundle")) }
        let resource = (packagedBundle?.url(forResource: "Resources", withExtension: nil) ?? Bundle.module.url(forResource: "Resources", withExtension: nil))!.appendingPathComponent("Renderer")
        web.loadFileURL(resource.appendingPathComponent("index.html"), allowingReadAccessTo: resource)
        window.center(); window.makeKeyAndOrderFront(nil); split.setPosition(500, ofDividerAt: 0); NSApp.activate(ignoringOtherApps: true)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render() }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
        if navigationAction.navigationType == .linkActivated { if let url = navigationAction.request.url, ["https","http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }; decisionHandler(.cancel) }
        else { decisionHandler(.allow) }
    }
    func textView(_ textView:NSTextView,doCommandBy commandSelector:Selector)->Bool {if commandSelector==NSSelectorFromString("cancelOperation:"),chrome.searchVisible {closeSearch();return true};return false}
    func textViewDidChangeSelection(_ notification:Notification) {
        guard !handlingPreviewNavigation,!exporting else {return}
        navigationTask?.cancel();let task=DispatchWorkItem { [weak self] in self?.syncPreviewToSelection() };navigationTask=task
        DispatchQueue.main.asyncAfter(deadline:.now()+0.06,execute:task)
    }
    func currentSourceMap()->SourceLineMap {
        if sourceMapText != text.string {sourceMapText=text.string;sourceMap=SourceLineMap(sourceMapText)}
        return sourceMap
    }
    func syncPreviewToSelection() {
        guard ready,!exporting,!handlingPreviewNavigation,renderedSource==text.string,renderedGeneration==renderGeneration else {return}
        let line=currentSourceMap().line(atUTF16Offset:text.selectedRange().location)
        web.evaluateJavaScript("revealSourceLine(\(line),\(renderedGeneration))",completionHandler:nil)
    }
    func navigateFromPreview(line:Int,column:Int,revision:Int) {
        guard ready,!exporting,revision==renderedGeneration,revision==renderGeneration,renderedSource==text.string,line>=0,column>=0 else {return}
        let map=currentSourceMap();guard line<map.lineStarts.count else {return}
        navigationTask?.cancel();handlingPreviewNavigation=true
        defer {handlingPreviewNavigation=false}
        let offset=map.utf16Offset(forLine:line,column:column)
        text.setSelectedRange(NSRange(location:offset,length:0));text.scrollRangeToVisible(NSRange(location:offset,length:0));window.makeFirstResponder(text)
    }
    func textDidChange(_ notification: Notification) {
        rebuildSearch(selectFirst:false)
        renderTask?.cancel(); let work = DispatchWorkItem { self.render() }; renderTask = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.15, execute: work)
    }
    func render() {
        guard ready,!exporting,let data=try? JSONSerialization.data(withJSONObject:[text.string]),let json=String(data:data,encoding:.utf8) else {return}
        renderGeneration+=1;let generation=renderGeneration,source=text.string
        web.evaluateJavaScript("renderSource(\(json)[0],\(generation))") { [weak self] _,error in
            guard let self,error==nil,self.renderGeneration==generation,self.text.string==source else {return}
            self.renderedSource=source;self.renderedGeneration=generation;self.syncPreviewToSelection()
        }
    }
    @objc func openFile() {
        let p=NSOpenPanel();p.allowedContentTypes=[.plainText,.text];p.allowsMultipleSelection=true
        guard p.runModal() == .OK else {return};show(files:p.urls)
    }
    func syncChrome() {chrome.fileNames=openedFiles.map(\.lastPathComponent);chrome.fileIndex=openedFiles.firstIndex(where:{$0==file}) ?? 0}
    @objc func findText() {
        guard window != nil else {return};chrome.searchVisible=true;chrome.searchFocus+=1
        let selection=(text.string as NSString).substring(with:text.selectedRange())
        if !selection.isEmpty,!selection.contains("\n"),selection.count<=200 {updateSearch(selection)} else {rebuildSearch(selectFirst:false)}
    }
    func closeSearch() {chrome.searchVisible=false;clearSearchHighlights();window.makeFirstResponder(text)}
    func clearSearchHighlights() {text.layoutManager?.removeTemporaryAttribute(.backgroundColor,forCharacterRange:NSRange(location:0,length:(text.string as NSString).length))}
    func updateSearch(_ query:String) {chrome.query=query;rebuildSearch(selectFirst:true)}
    func rebuildSearch(selectFirst:Bool) {
        guard text != nil else {return};clearSearchHighlights();matches=[];matchIndex = -1
        let source=text.string as NSString,query=chrome.query
        if chrome.searchVisible,!query.isEmpty {
            var remaining=NSRange(location:0,length:source.length)
            while remaining.length>0 {let range=source.range(of:query,options:.caseInsensitive,range:remaining);if range.location==NSNotFound {break};matches.append(range);remaining=NSRange(location:NSMaxRange(range),length:source.length-NSMaxRange(range))}
            for range in matches {text.layoutManager?.addTemporaryAttribute(.backgroundColor,value:NSColor.controlAccentColor.withAlphaComponent(0.18),forCharacterRange:range)}
        }
        chrome.matchCount=matches.count;chrome.currentMatch=0
        if let index=matches.firstIndex(where:{$0.location>=text.selectedRange().location}) ?? (matches.isEmpty ? nil:0) {matchIndex=index;chrome.currentMatch=index+1;if selectFirst {selectMatch()}}
    }
    func selectMatch() {guard matches.indices.contains(matchIndex) else {return};let range=matches[matchIndex];text.setSelectedRange(range);text.scrollRangeToVisible(range);chrome.currentMatch=matchIndex+1}
    func navigateSearch(_ direction:Int) {guard window != nil else {return};if !chrome.searchVisible {findText()};guard !matches.isEmpty else {return};matchIndex=(matchIndex+direction+matches.count)%matches.count;selectMatch()}
    @objc func findNext() {navigateSearch(1)}
    @objc func findPrevious() {navigateSearch(-1)}
    @objc func saveAs() {_=saveCurrent(asNew:true)}
    @objc func saveFile() { _=saveCurrent() }
    @discardableResult func saveCurrent(asNew:Bool=false)->Bool {
        guard !exporting else {return false}
        var destination=file
        if asNew || destination==nil {
            let panel=NSSavePanel();panel.nameFieldStringValue=file?.lastPathComponent ?? "Untitled.md";panel.directoryURL=file?.deletingLastPathComponent() ?? exportLocation.directory
            guard panel.runModal() == .OK,let selected=panel.url else {return false};destination=selected
        }
        guard let url=destination else {return false}
        do {
            try text.string.write(to:url,atomically:true,encoding:.utf8)
            if let old=file,let index=openedFiles.firstIndex(of:old) {openedFiles[index]=url;filePicker.item(at:index)?.title=url.lastPathComponent}
            file=url;savedText=text.string;window.title=url.lastPathComponent;exportLocation.directory=url.deletingLastPathComponent();exportLocation.filename=url.deletingPathExtension().lastPathComponent+".pdf";syncChrome();return true
        } catch {showError(error);return false}
    }
    @objc func exportPDF() {
        guard ready,!exporting,exportSheet==nil else {return}
        let sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:468,height:230),styleMask:[.titled],backing:.buffered,defer:false)
        sheet.title="Export PDF";sheet.isReleasedWhenClosed=false;sheet.contentView=NSHostingView(rootView:EditorExportSheet(chrome:chrome,location:exportLocation,controller:self));exportSheet=sheet;window.beginSheet(sheet)
    }
    func dismissExport() {guard let sheet=exportSheet else {return};window.endSheet(sheet);sheet.orderOut(nil);exportSheet=nil}
    func performPDFExport() {
        guard ready,!exporting else {return}
        dismissExport()
        do {let lease=try AppModel.shared.folderAccess.prepare([exportLocation.directory]);let directory=exportLocation.directory,name=exportLocation.filename
            Task {
                let folder=FileManager.default.temporaryDirectory.appendingPathComponent("utility-editor-export-"+UUID().uuidString)
                defer {try? FileManager.default.removeItem(at:folder);_=lease}
                do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let temporary=folder.appendingPathComponent("Rendered.pdf");try await writePDF(to:temporary);let output=try FileServices.commit(temporary,to:directory,baseName:ExportFiles.stem(name,extension:"pdf"));if !CommandLine.arguments.contains("--smoke-test") {NSWorkspace.shared.activateFileViewerSelecting([output])}} catch {showError(error)}
            }
        } catch {showError(error)}
    }
    func writePDF(to url: URL) async throws {
        guard ready, !exporting else { throw NSError(domain:"Macaroni",code:1,userInfo:[NSLocalizedDescriptionKey:"Preview is not ready"]) }
        render(); exporting = true;chrome.exporting=true; text.isEditable = false
        defer { exporting = false;chrome.exporting=false; text.isEditable = true; web.evaluateJavaScript("endPDF()",completionHandler:nil) }
        let count = try await web.callAsyncJavaScript("return await beginPDF()", arguments: [:], in: nil, contentWorld: .page) as? Int ?? 0
        guard count > 0, count <= 500 else { throw NSError(domain:"Macaroni",code:2,userInfo:[NSLocalizedDescriptionKey:"Document needs between 1 and 500 PDF pages"]) }
        let result = PDFDocument()
        for index in 0..<count {
            let config = WKPDFConfiguration(); config.rect = CGRect(x:0,y:index * 792,width:612,height:792)
            let data = try await web.pdf(configuration: config)
            guard let page = PDFDocument(data:data)?.page(at:0) else { throw NSError(domain:"Macaroni",code:3,userInfo:[NSLocalizedDescriptionKey:"Could not render a PDF page"]) }
            result.insert(page,at:result.pageCount)
        }
        guard let data = result.dataRepresentation() else { throw NSError(domain:"Macaroni",code:4,userInfo:[NSLocalizedDescriptionKey:"Could not encode the PDF"]) }
        try data.write(to:url,options:.atomic)
    }
    func showError(_ error: Error) { let a = NSAlert(error: error); a.runModal() }
}

/// WKWebView retains message handlers; the bridge keeps its editor reference weak.
@MainActor final class EditorPreviewBridge:NSObject,WKScriptMessageHandler {
    weak var controller:EditorController?
    init(controller:EditorController) {self.controller=controller}
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.name=="sourceNavigation",message.frameInfo.isMainFrame,let controller,message.webView === controller.web,
              let body=message.body as? [String:Any],let line=body["line"] as? Int,let column=body["column"] as? Int,let revision=body["revision"] as? Int else {return}
        controller.navigateFromPreview(line:line,column:column,revision:revision)
    }
}
