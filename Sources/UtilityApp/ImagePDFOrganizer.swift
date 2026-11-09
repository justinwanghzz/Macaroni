import AppKit
import SwiftUI
import PDFKit
import UtilityCore
import UniformTypeIdentifiers

@MainActor final class PageOrganizerModel:ObservableObject {
    @Published var pages:[AssemblyPage]=[]
    @Published var selected:Set<UUID>=[]
    @Published var documentMode=false
    @Published var busy=false
    @Published var error:String?
    @Published var completed=0
    @Published var imageSize:ImagePageSize = .image
    @Published var margin=24.0
    var exportTask:Task<Void,Never>?
    var importTask:Task<Void,Never>?
    var dirty=false
    let windowName:String
    let location:ExportLocation
    var onExport:((URL)->Void)?
    init(urls:[URL],name:String) {
        location=ExportLocation(inputs:urls,filename:AppModel.shared.settings.naming.pdfName(inputs:urls));windowName=name;documentMode=urls.count>1 && urls.allSatisfy {AssetKind(url:$0) == .pdf};add(urls)
    }
    var documents:[AssemblyPage] {var seen=Set<UUID>();return pages.filter {seen.insert($0.documentID).inserted}}
    var visiblePages:[AssemblyPage] {documentMode ? documents:pages}
    var canOrderDocuments:Bool {
        var last:UUID?,segments=0
        for page in pages {if page.documentID != last {segments+=1;last=page.documentID}}
        return segments==documents.count
    }
    var canReorder:Bool {!documentMode || canOrderDocuments}
    var selectedPageIDs:Set<UUID> {
        if !documentMode {return selected}
        let documents=Set(visiblePages.filter {selected.contains($0.id)}.map(\.documentID))
        return Set(pages.filter {documents.contains($0.documentID)}.map(\.id))
    }
    func rotate(_ direction:Int) {let ids=selectedPageIDs;for i in pages.indices where ids.contains(pages[i].id) {pages[i].quarterTurns=(pages[i].quarterTurns+direction+4)%4};dirty=true;completed=0}
    func removeSelected() {let ids=selectedPageIDs;pages.removeAll {ids.contains($0.id)};selected=[];dirty=true;completed=0}
    func move(ids:Set<UUID>,before index:Int) {
        guard canReorder else {return}
        if documentMode {
            let reordered=AssemblyPage.moving(documents,ids:ids,before:index)
            pages=reordered.flatMap {doc in pages.filter {$0.documentID==doc.documentID}}
        } else {pages=AssemblyPage.moving(pages,ids:ids,before:index)}
        dirty=true;completed=0
    }
    func add(_ urls:[URL],before position:Int?=nil) {
        guard !busy else {return};busy=true;error=nil
        let index=position.flatMap { i in visiblePages.indices.contains(i) ? pages.firstIndex(where:{$0.id==visiblePages[i].id}):nil } ?? pages.count
        importTask=Task {
            defer {busy=false}
            do {
                let job=Task.detached {try PDFAssembly.load(urls)}
                let added=try await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()})
                guard !Task.isCancelled else {return}
                guard pages.count+added.count<=500 else {throw UtilityError.message("Choose up to 500 pages")}
                pages.insert(contentsOf:added,at:min(index,pages.count));dirty=true;completed=0
            } catch {if !(error is CancellationError) {self.error=error.localizedDescription}}
            busy=false
        }
    }
    func export(window:NSWindow?) {
        guard !busy,!pages.isEmpty else {return}
        let lease:AccessLease
        do {lease=try AppModel.shared.folderAccess.prepare([location.directory])} catch {self.error=error.localizedDescription;return}
        busy=true;error=nil;let snapshot=pages,size=imageSize,margin=margin,folder=location.directory,name=location.filename
        exportTask=Task {
            defer {busy=false;_=lease}
            do {
                let job=Task.detached {try ExportFiles.pdf(snapshot,directory:folder,filename:name,size:size,margin:margin)}
                let output=try await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()})
                completed=snapshot.count;dirty=false
                if !AppModel.shared.suppressFinder {NSWorkspace.shared.activateFileViewerSelecting([output])}
                onExport?(output);window?.close()
            } catch {if !(error is CancellationError) {self.error=error.localizedDescription}}
        }
    }
}

@MainActor enum PageOrganizer {
    static func show(_ urls:[URL]) {
        guard !delegate.isPaused else {return}
        let files=urls.filter {[AssetKind.image,.pdf].contains(AssetKind(url:$0))};guard !files.isEmpty else {return}
        let name=files.count==1 && AssetKind(url:files[0]) == .pdf ? "Adjust PDF":"Create PDF"
        let model=PageOrganizerModel(urls:files,name:name)
        // Independent windows preserve any unfinished arrangement from a previous invocation.
        delegate.show(name+" · "+String(UUID().uuidString.prefix(5)),view:PageOrganizerView(model:model),size:NSSize(width:860,height:740),title:name)
    }
}
// Compatibility for existing contextual entry points.
@MainActor enum ImagePDFOrganizer {static func show(_ urls:[URL]) {PageOrganizer.show(urls)}}

struct PageOrganizerView:View {
    @ObservedObject var model:PageOrganizerModel
    @State private var window:NSWindow?
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text(model.windowName).font(.title2.bold());Text("\(model.documents.count) files · \(model.pages.count) pages").font(.caption).foregroundStyle(.secondary);Spacer()
                Button("Add files…") {let panel=NSOpenPanel();panel.allowedContentTypes=[.image,.pdf];panel.allowsMultipleSelection=true;if panel.runModal() == .OK {model.add(panel.urls)}}.disabled(model.busy)
            }
            if model.documents.count>1 && model.pages.contains(where:{$0.pageIndex != nil}) {
                SoftChoice(values:[(true,"Documents"),(false,"Organize pages")],selection:$model.documentMode).onChange(of:model.documentMode) {_,_ in model.selected=[]}
                if model.documentMode,!model.canOrderDocuments {Text("Pages are interleaved. Use Organize pages to keep their current order.").font(.caption).foregroundStyle(.secondary)}
            }
            HStack {
                Button {model.rotate(-1)} label:{Label("Rotate left",systemImage:"rotate.left")}.buttonStyle(ChoicePillStyle(compact:true))
                Button {model.rotate(1)} label:{Label("Rotate right",systemImage:"rotate.right")}.buttonStyle(ChoicePillStyle(compact:true))
                Button(role:.destructive) {model.removeSelected()} label:{Label("Remove",systemImage:"trash")}.buttonStyle(ChoicePillStyle(compact:true))
                Spacer();Text("\(model.selected.count) selected").foregroundStyle(.secondary)
            }.disabled(model.selected.isEmpty || model.busy)
            PDFPageGrid(model:model).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
            if model.pages.contains(where:{$0.pageIndex==nil}) {
                HStack {Picker("Image pages",selection:$model.imageSize) {ForEach(ImagePageSize.allCases) {Text($0.title).tag($0)}}.frame(width:220)
                    if model.imageSize != .image {Text("Margins");Slider(value:$model.margin,in:0...72).frame(width:120);Text("\(Int(model.margin)) pt").monospacedDigit()};Spacer()}.disabled(model.busy)
            }
            ExportFilenameField(location:model.location).disabled(model.busy)
            if let error=model.error {Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)}
            HStack(spacing:12) {
                ExportDestinationControl(location:model.location).disabled(model.busy)
                Spacer(minLength:8)
                if model.busy {ProgressView().controlSize(.small);Button("Cancel") {model.exportTask?.cancel();model.importTask?.cancel()}}
                else {if model.completed>0 {Text("PDF saved").foregroundStyle(.secondary)};Button("Export PDF") {model.export(window:window)}.buttonStyle(PrimaryActionStyle()).disabled(model.pages.isEmpty)}
            }
        }.padding(20).utilityStyle().frame(minWidth:660,minHeight:460)
        .background(WindowReference {window=$0})
        .onDisappear {model.exportTask?.cancel();model.importTask?.cancel()}
    }
}
struct WindowReference:NSViewRepresentable {
    let found:(NSWindow?)->Void
    func makeNSView(context:Context)->NSView {let view=NSView();DispatchQueue.main.async {found(view.window)};return view}
    func updateNSView(_ view:NSView,context:Context) {DispatchQueue.main.async {found(view.window)}}
}

private struct PDFPageGrid:NSViewRepresentable {
    @ObservedObject var model:PageOrganizerModel
    func makeCoordinator()->Coordinator {Coordinator(model:model)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        let layout=NSCollectionViewFlowLayout();layout.itemSize=NSSize(width:156,height:192);layout.minimumInteritemSpacing=12;layout.minimumLineSpacing=16;layout.sectionInset=NSEdgeInsets(top:16,left:16,bottom:16,right:16)
        let grid=NSCollectionView();grid.collectionViewLayout=layout;grid.isSelectable=true;grid.allowsMultipleSelection=true;grid.backgroundColors=[.clear]
        grid.register(PDFPageItem.self,forItemWithIdentifier:.init("page"));grid.dataSource=context.coordinator;grid.delegate=context.coordinator
        grid.registerForDraggedTypes([Coordinator.pageType,.fileURL]);grid.setDraggingSourceOperationMask(.move,forLocal:true)
        scroll.documentView=grid;context.coordinator.grid=grid;return scroll
    }
    func updateNSView(_ view:NSScrollView,context:Context) {
        let c=context.coordinator;c.model=model
        if c.snapshot != model.visiblePages || c.size != model.imageSize || c.margin != model.margin { c.snapshot=model.visiblePages;c.size=model.imageSize;c.margin=model.margin;c.grid?.reloadData() }
        c.grid?.selectionIndexPaths=Set(model.visiblePages.enumerated().filter {model.selected.contains($0.element.id)}.map {IndexPath(item:$0.offset,section:0)})
    }
    @MainActor final class Coordinator:NSObject,NSCollectionViewDataSource,NSCollectionViewDelegate {
        static let pageType=NSPasteboard.PasteboardType("org.local.UtilityApp.pdf-page")
        var model:PageOrganizerModel;var snapshot:[AssemblyPage]=[];var size:ImagePageSize = .image;var margin=24.0;weak var grid:NSCollectionView?
        init(model:PageOrganizerModel) {self.model=model}
        func collectionView(_ collectionView:NSCollectionView,numberOfItemsInSection section:Int)->Int {model.visiblePages.count}
        func collectionView(_ collectionView:NSCollectionView,itemForRepresentedObjectAt indexPath:IndexPath)->NSCollectionViewItem {
            let item=collectionView.makeItem(withIdentifier:.init("page"),for:indexPath) as! PDFPageItem
            item.configure(model.visiblePages[indexPath.item],number:indexPath.item+1,detail:model.documentMode ? "\(model.pages.filter {$0.documentID==model.visiblePages[indexPath.item].documentID}.count) pages":nil,size:model.imageSize,margin:model.margin);return item
        }
        func collectionView(_ collectionView:NSCollectionView,didSelectItemsAt indexPaths:Set<IndexPath>) { syncSelection(collectionView) }
        func collectionView(_ collectionView:NSCollectionView,didDeselectItemsAt indexPaths:Set<IndexPath>) { syncSelection(collectionView) }
        func syncSelection(_ grid:NSCollectionView) {model.selected=Set(grid.selectionIndexPaths.compactMap {model.visiblePages.indices.contains($0.item) ? model.visiblePages[$0.item].id:nil})}
        func collectionView(_ collectionView:NSCollectionView,pasteboardWriterForItemAt indexPath:IndexPath)->NSPasteboardWriting? {
            guard !model.busy,model.canReorder else {return nil};let item=NSPasteboardItem();item.setString(model.visiblePages[indexPath.item].id.uuidString,forType:Self.pageType);return item
        }
        func collectionView(_ collectionView:NSCollectionView,validateDrop draggingInfo:NSDraggingInfo,proposedIndexPath proposedDropIndexPath:AutoreleasingUnsafeMutablePointer<NSIndexPath>,dropOperation proposedDropOperation:UnsafeMutablePointer<NSCollectionView.DropOperation>)->NSDragOperation {
            guard !model.busy else {return []};proposedDropOperation.pointee = .before
            return draggingInfo.draggingSource as? NSCollectionView === collectionView ? (model.canReorder ? .move:[]):.copy
        }
        func collectionView(_ collectionView:NSCollectionView,acceptDrop draggingInfo:NSDraggingInfo,indexPath:IndexPath,dropOperation:NSCollectionView.DropOperation)->Bool {
            guard !model.busy else {return false}
            if draggingInfo.draggingSource as? NSCollectionView === collectionView {
                let ids=Set((draggingInfo.draggingPasteboard.pasteboardItems ?? []).compactMap {$0.string(forType:Self.pageType)}.compactMap {UUID(uuidString:$0)})
                guard !ids.isEmpty else {return false};model.move(ids:ids,before:indexPath.item);return true
            }
            let files=(draggingInfo.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []).filter {[AssetKind.image,.pdf].contains(AssetKind(url:$0))}
            guard !files.isEmpty else {return false}
            model.add(files,before:indexPath.item);return true
        }
    }
}

@MainActor private final class PDFPageItem:NSCollectionViewItem {
    let preview=NSImageView(),caption=NSTextField(labelWithString:"")
    var loadTask:Task<Void,Never>?
    override func loadView() {
        view=NSView();view.wantsLayer=true;view.layer?.cornerRadius=10
        preview.imageScaling = .scaleProportionallyUpOrDown;caption.alignment = .center;caption.lineBreakMode = .byTruncatingMiddle;caption.font = .systemFont(ofSize:11)
        for v in [preview,caption] {v.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(v)}
        NSLayoutConstraint.activate([preview.topAnchor.constraint(equalTo:view.topAnchor,constant:8),preview.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:8),preview.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-8),preview.bottomAnchor.constraint(equalTo:caption.topAnchor,constant:-8),caption.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-10),caption.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:6),caption.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-6)])
    }
    override var isSelected:Bool {didSet {highlight()} }
    func highlight() {view.layer?.backgroundColor=(isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.14):NSColor.windowBackgroundColor).cgColor;view.layer?.borderWidth=isSelected ? 2:1;view.layer?.borderColor=(isSelected ? NSColor.controlAccentColor:NSColor.separatorColor).cgColor}
    func configure(_ page:AssemblyPage,number:Int,detail:String?=nil,size:ImagePageSize = .image,margin:Double=0) {
        loadTask?.cancel();preview.image=nil;caption.stringValue="\(number) · \(detail == nil ? page.caption:page.url.lastPathComponent)"+(detail.map {" · "+$0} ?? "");view.toolTip=page.url.lastPathComponent;view.setAccessibilityLabel("Page \(number), \(page.url.lastPathComponent)");highlight()
        loadTask=Task {
            let image=await Task.detached { ()->NSImage? in
                let lease=AccessLease(urls:[page.url]);defer {_=lease}
                if page.pageIndex != nil || size != .image {
                    guard let rendered=try? PDFAssembly.page(page,size:size,margin:margin,maximumImageSide:500) else {return nil}
                    return rendered.thumbnail(of:CGSize(width:280,height:330),for:.mediaBox)
                }
                guard let source=try? ImageEngine.load(page.url,maximumSide:320),let result=try? ImageEngine.transformed(.init(kind:.rotateImage,amount:Double(page.quarterTurns*90)),image:source) else {return nil}
                return NSImage(cgImage:result,size:.zero)
            }.value
            guard !Task.isCancelled else {return}
            preview.image=image ?? NSImage(systemSymbolName:"exclamationmark.triangle",accessibilityDescription:"Page could not be loaded")
        }
    }
    override func prepareForReuse() {super.prepareForReuse();loadTask?.cancel()}
}
