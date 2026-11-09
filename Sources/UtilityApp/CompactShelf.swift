import SwiftUI
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import UtilityCore

final class ShelfPanel:NSPanel { override var canBecomeKey:Bool { true } }
@MainActor final class ShelfController:NSObject,NSWindowDelegate {
    static let shared=ShelfController()
    var panel:NSPanel?
    var applyingFrame=false
    func show() {
        guard !delegate.isPaused else { return }
        let model=AppModel.shared
        if panel == nil {
            let p=ShelfPanel(contentRect:NSRect(x:0,y:0,width:model.settings.shelfWidth,height:model.settings.shelfHeight),styleMask:[.titled,.closable,.resizable,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="Shelf";p.titlebarAppearsTransparent=true;p.backgroundColor=NSColor.windowBackgroundColor;p.hasShadow=true;p.standardWindowButton(.miniaturizeButton)?.isHidden=true;p.standardWindowButton(.zoomButton)?.isHidden=true;p.isReleasedWhenClosed=false;p.level = .floating;p.hidesOnDeactivate=false;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];p.minSize=NSSize(width:112,height:220);p.maxSize=NSSize(width:420,height:1600);p.contentView=NSHostingView(rootView:CompactShelfView());p.setFrame(NSRect(x:0,y:0,width:model.settings.shelfWidth,height:model.settings.shelfHeight),display:false);p.delegate=self;panel=p
        }
        let screen=NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        applyingFrame=true
        let width=min(panel!.frame.width,screen.visibleFrame.width),height=min(model.settings.shelfHeightCustomized == true ? panel!.frame.height:screen.visibleFrame.height*0.6,screen.visibleFrame.height-30)
        panel?.setFrame(NSRect(x:screen.visibleFrame.maxX-width-10,y:max(screen.visibleFrame.minY+10,min(model.settings.shelfHeightCustomized != true || panel!.frame.minY == 0 ? screen.visibleFrame.midY-height/2 : panel!.frame.minY,screen.visibleFrame.maxY-height)),width:width,height:height),display:true)
        applyingFrame=false;panel?.orderFrontRegardless()
    }
    func focus() {
        show();panel?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        DispatchQueue.main.async { [weak self] in
            func table(in view:NSView)->NSTableView? { if let t=view as? NSTableView {return t};for child in view.subviews {if let t=table(in:child){return t}};return nil }
            if let root=self?.panel?.contentView,let t=table(in:root) { self?.panel?.makeFirstResponder(t) }
        }
    }
    func changed() { if AppModel.shared.shelf.isEmpty { panel?.orderOut(nil) } else { show() } }
    func windowDidResize(_ notification:Notification) {
        guard !applyingFrame,let panel else { return };AppModel.shared.settings.shelfHeightCustomized=true;AppModel.shared.settings.shelfWidth=panel.frame.width;AppModel.shared.settings.shelfHeight=panel.frame.height;AppModel.shared.persist()
    }
}
struct CompactShelfView:View {
    @ObservedObject var model=AppModel.shared
    var body:some View {
        VStack(spacing:0) {
            VStack(spacing:9) {
                HStack(spacing:2) {
                    ForEach([false,true],id:\.self) { move in
                        Button {
                            withAnimation(.easeInOut(duration:0.16)) { model.settings.moveFiles=move }
                            model.persist()
                        } label: {
                            Text(move ? "Move":"Copy")
                                .font(.system(size:11,weight:.semibold))
                                .frame(maxWidth:.infinity).padding(.vertical,6)
                                .foregroundStyle(model.settings.moveFiles==move ? Color.white:Color.secondary)
                                .background {
                                    if model.settings.moveFiles==move {
                                        RoundedRectangle(cornerRadius:8).fill(Color.utilityAccent.gradient)
                                            .shadow(color:Color.utilityAccent.opacity(0.18),radius:3,y:1)
                                    }
                                }
                                .contentShape(RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain)
                            .accessibilityLabel(move ? "Move files":"Copy files")
                            .accessibilityValue(model.settings.moveFiles==move ? "Selected":"")
                    }
                }.padding(3).background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:11))
                HStack(spacing:4) {ForEach([true,false],id:\.self) { list in
                    Button {model.settings.shelfList=list;model.persist()} label:{Image(systemName:list ? "list.bullet":"square.grid.2x2").frame(maxWidth:.infinity)}.buttonStyle(ChoicePillStyle(selected:model.settings.shelfList==list,compact:true)).help(list ? "List view":"Icon view")
                }}
                if !model.settings.moveFiles {
                    Button {
                        model.settings.clearAfterCopy.toggle();model.persist()
                    } label: {
                        HStack(spacing:5) {
                            Image(systemName:model.settings.clearAfterCopy ? "checkmark.circle.fill":"circle")
                                .font(.system(size:12)).foregroundStyle(model.settings.clearAfterCopy ? Color.utilityAccent:Color.secondary)
                            Text("Clear after copy").font(.system(size:10,weight:.medium)).foregroundStyle(.secondary)
                                .fixedSize(horizontal:false,vertical:true)
                        }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Clear shelf after copy")
                        .accessibilityValue(model.settings.clearAfterCopy ? "On":"Off")
                }
            }.padding(.horizontal,9).padding(.top,8).padding(.bottom,10)
            Rectangle().fill(Color.primary.opacity(0.055)).frame(height:1).padding(.horizontal,10)
            ShelfFileList().frame(maxWidth:.infinity,maxHeight:.infinity).padding(.horizontal,5).padding(.vertical,6)
            HStack(spacing:4) {
                Text("\(model.shelf.count) \(model.shelf.count == 1 ? "file":"files")")
                    .font(.system(size:10,weight:.medium)).monospacedDigit().foregroundStyle(.secondary)
                Spacer(minLength:0)
                Menu {
                    Button("Add files…") { let p=NSOpenPanel();p.allowsMultipleSelection=true;if p.runModal() == .OK { model.stage(p.urls) } }
                    Button("Copy selected") { model.copyShelf() }
                    Button("Copy to folder…") { model.transfer(move:false) }
                    Button("Move to folder…") { model.transfer(move:true) }
                    Divider()
                    Menu("Process selected") {
                        ForEach(ActionKind.allCases) { kind in Button(kind.title) { delegate.action(kind,urls:(model.selected.isEmpty ? model.shelf:model.selectedReferences).map(\.url)) } }
                        ForEach(model.workflows) { w in Button(w.name) { model.run((model.selected.isEmpty ? model.shelf:model.selectedReferences).map(\.url),workflow:w) } }
                    }
                    Divider()
                    Button("Remove selected") { model.removeReferences(model.selected) }
                    Button("Clear shelf") { model.removeReferences(Set(model.shelf.map(\.id))) }
                } label: {
                    Image(systemName:"ellipsis").font(.system(size:12,weight:.semibold))
                        .foregroundStyle(.secondary).frame(width:24,height:22)
                        .background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:7))
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }.padding(.horizontal,11).padding(.top,5).padding(.bottom,9)
        }
        .background(LinearGradient(colors:[Color.utilitySurface,Color(nsColor:.windowBackgroundColor)],startPoint:.top,endPoint:.bottom))
        .tint(.utilityAccent)
    }
}
/// Draw selection as an inset card, preserving native multi-selection and dragging.
final class ShelfRowView:NSTableRowView {
    override var isEmphasized:Bool { get {true} set {} }
    override var interiorBackgroundStyle:NSView.BackgroundStyle { .normal }
    private var cardRect:NSRect { bounds.insetBy(dx:3,dy:3) }
    override func drawBackground(in dirtyRect:NSRect) {
        let path=NSBezierPath(roundedRect:cardRect,xRadius:11,yRadius:11)
        NSColor.controlBackgroundColor.withAlphaComponent(0.78).setFill();path.fill()
        NSColor.separatorColor.withAlphaComponent(0.22).setStroke();path.lineWidth=0.5;path.stroke()
    }
    override func drawSelection(in dirtyRect:NSRect) {
        let path=NSBezierPath(roundedRect:cardRect,xRadius:11,yRadius:11)
        NSColor(calibratedRed:0.34,green:0.36,blue:0.72,alpha:0.12).setFill();path.fill()
        NSColor(calibratedRed:0.34,green:0.36,blue:0.72,alpha:0.6).setStroke();path.lineWidth=1.2;path.stroke()
    }
}

struct ShelfFileList:NSViewRepresentable {
    @ObservedObject var model=AppModel.shared
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeNSView(context:Context)->NSScrollView {
        let table=ShelfTable(frame:NSRect(x:0,y:0,width:126,height:400));table.autoresizingMask=[.width];table.headerView=nil;table.style = .plain;table.backgroundColor = .clear;table.rowHeight=56;table.intercellSpacing=NSSize(width:0,height:2);table.allowsMultipleSelection=true;table.allowsEmptySelection=true;table.selectionHighlightStyle = .regular
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("File"));column.resizingMask = .autoresizingMask;table.addTableColumn(column);table.columnAutoresizingStyle = .noColumnAutoresizing
        table.delegate=context.coordinator;table.dataSource=context.coordinator;table.doubleAction=#selector(Coordinator.preview);table.target=context.coordinator;table.coordinator=context.coordinator
        table.registerForDraggedTypes([.fileURL]);table.setDraggingSourceOperationMask(.copy,forLocal:false)
        let scroll=ShelfScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false;scroll.documentView=table;context.coordinator.table=table;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        let c=context.coordinator;let model=AppModel.shared
        let list=model.settings.shelfList
        if c.references != model.shelf || c.list != list { c.references=model.shelf;c.list=list;c.table?.rowHeight=list ? 56:120;c.table?.reloadData() }
        let indexes=IndexSet(c.references.indices.filter { model.selected.contains(c.references[$0].id) })
        if c.table?.selectedRowIndexes != indexes { c.updating=true;c.table?.selectRowIndexes(indexes,byExtendingSelection:false);c.updating=false }
    }
    @MainActor final class Coordinator:NSObject,NSTableViewDelegate,NSTableViewDataSource {
        weak var table:ShelfTable?
        var list=true
        var references:[FileReference]=[]
        var writers:[ShelfPromiseWriter]=[]
        var deliveryBatch=UUID()
        var updating=false
        func numberOfRows(in tableView:NSTableView)->Int { references.count }
        func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? { ShelfRowView() }
        func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
            guard references.indices.contains(row) else { return nil };let ref=references[row]
            let cell=NSTableCellView();let image=NSImageView();image.image=NSWorkspace.shared.icon(forFile:ref.url.path);image.imageScaling = .scaleProportionallyUpOrDown;image.wantsLayer=true;image.layer?.cornerRadius=6;image.layer?.masksToBounds=true
            let label=NSTextField(wrappingLabelWithString:ref.url.lastPathComponent);label.font = .systemFont(ofSize:11,weight:.medium);label.textColor = .labelColor;label.alignment = .center;label.maximumNumberOfLines=2;label.lineBreakMode = .byWordWrapping
            let size=FileServices.bytes(ref.url)
            let detail=NSTextField(labelWithString:size>0 ? ByteCountFormatter.string(fromByteCount:size,countStyle:.file):ref.url.pathExtension.uppercased())
            detail.font = .systemFont(ofSize:9);detail.textColor = .secondaryLabelColor;detail.alignment = .center
            for view in [image,label,detail] { cell.addSubview(view);view.translatesAutoresizingMaskIntoConstraints=false }
            if list {
                label.alignment = .left;detail.alignment = .left
                NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:7),image.centerYAnchor.constraint(equalTo:cell.centerYAnchor),image.widthAnchor.constraint(equalToConstant:24),image.heightAnchor.constraint(equalToConstant:28),label.leadingAnchor.constraint(equalTo:image.trailingAnchor,constant:6),label.topAnchor.constraint(equalTo:cell.topAnchor,constant:6),label.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-6),detail.leadingAnchor.constraint(equalTo:label.leadingAnchor),detail.topAnchor.constraint(equalTo:label.bottomAnchor,constant:2),detail.bottomAnchor.constraint(lessThanOrEqualTo:cell.bottomAnchor,constant:-4)])
            } else {
                NSLayoutConstraint.activate([image.topAnchor.constraint(equalTo:cell.topAnchor,constant:10),image.centerXAnchor.constraint(equalTo:cell.centerXAnchor),image.widthAnchor.constraint(equalToConstant:58),image.heightAnchor.constraint(equalToConstant:58),label.topAnchor.constraint(equalTo:image.bottomAnchor,constant:6),label.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:7),label.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-7),detail.topAnchor.constraint(equalTo:label.bottomAnchor,constant:3),detail.centerXAnchor.constraint(equalTo:cell.centerXAnchor),detail.bottomAnchor.constraint(lessThanOrEqualTo:cell.bottomAnchor,constant:-7)])
            }
            cell.imageView=image;cell.textField=label;cell.toolTip=ref.url.path
            let request=QLThumbnailGenerator.Request(fileAt:ref.url,size:CGSize(width:120,height:120),scale:2,representationTypes:.thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for:request) { thumbnail,_ in if let thumbnail { DispatchQueue.main.async { image.image=thumbnail.nsImage } } }
            return cell
        }
        func tableViewSelectionDidChange(_ notification:Notification) { guard !updating,let table else { return };AppModel.shared.selected=Set(table.selectedRowIndexes.compactMap { references.indices.contains($0) ? references[$0].id : nil }) }
        @objc func preview() { guard let table, references.indices.contains(table.clickedRow) else { return };PreviewController.shared.show(references[table.clickedRow].url) }
        func tableView(_ tableView:NSTableView,pasteboardWriterForRow row:Int)->NSPasteboardWriting? {
            guard references.indices.contains(row) else { return nil }
            if writers.isEmpty {deliveryBatch=UUID()}
            let writer=ShelfPromiseWriter(reference:references[row],move:AppModel.shared.settings.moveFiles,clearAfterCopy:AppModel.shared.settings.clearAfterCopy,batch:deliveryBatch);writers.append(writer)
            let provider=RetainedFilePromise(fileType:UTType(filenameExtension:references[row].url.pathExtension)?.identifier ?? UTType.data.identifier,delegate:writer)
            provider.keeper=writer;return provider
        }
        func tableView(_ tableView:NSTableView,draggingSession session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) { writers.removeAll() }
    }
}
final class ShelfScrollView:NSScrollView {
    private var columnWidth:CGFloat = -1
    override func layout() {
        super.layout()
        let width=contentSize.width
        guard width>0,abs(width-columnWidth)>0.5 else {return}
        columnWidth=width
        // Resize after the layout transaction, never from NSTableView's layout callback.
        DispatchQueue.main.async { [weak self] in
            guard let self,let table=self.documentView as? NSTableView else {return}
            table.tableColumns.first?.width=self.contentSize.width
        }
    }
}
final class ShelfTable:NSTableView {
    weak var coordinator:ShelfFileList.Coordinator?
    override func keyDown(with event:NSEvent) {
        if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers == "a" { selectAll(nil);return }
        if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers == "c" { MainActor.assumeIsolated { AppModel.shared.copyShelf() };return }
        if event.keyCode==49 { MainActor.assumeIsolated { if let c=coordinator,c.references.indices.contains(selectedRow) { PreviewController.shared.show(c.references[selectedRow].url) } };return }
        if event.keyCode==51 { MainActor.assumeIsolated { AppModel.shared.removeReferences(AppModel.shared.selected) };return }
        super.keyDown(with:event)
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { .copy }
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool { true }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        let urls=(sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false };Task { @MainActor in AppModel.shared.stage(urls) };return true
    }
}
final class RetainedFilePromise:NSFilePromiseProvider { var keeper:ShelfPromiseWriter? }
final class ShelfPromiseWriter:NSObject,NSFilePromiseProviderDelegate {
    let reference:FileReference
    let move:Bool
    let batch:UUID
    let clearAfterCopy:Bool
    static let queue:OperationQueue = { let q=OperationQueue();q.name="Macaroni file delivery";q.maxConcurrentOperationCount=2;return q }()
    init(reference:FileReference,move:Bool,clearAfterCopy:Bool=false,batch:UUID=UUID()) { self.reference=reference;self.move=move;self.clearAfterCopy=clearAfterCopy;self.batch=batch }
    func filePromiseProvider(_ provider:NSFilePromiseProvider,fileNameForType fileType:String)->String { reference.url.lastPathComponent }
    func operationQueue(for filePromiseProvider:NSFilePromiseProvider)->OperationQueue { Self.queue }
    func filePromiseProvider(_ provider:NSFilePromiseProvider,writePromiseTo url:URL,completionHandler:@escaping(Error?)->Void) {
        let source=reference.url;let lease=AccessLease(urls:[source,url.deletingLastPathComponent()]);defer { _=lease }
        do {
            let output=try FileServices.transfer(source,to:url.deletingLastPathComponent(),move:move,promisedName:url.lastPathComponent)
            Task { @MainActor in AppModel.shared.recordDelivery(self.reference,output:output,error:nil,move:self.move,batch:self.batch,clearCopied:self.clearAfterCopy) }
            completionHandler(nil)
        } catch { Task { @MainActor in AppModel.shared.recordDelivery(self.reference,output:nil,error:error,move:self.move,batch:self.batch,clearCopied:self.clearAfterCopy) };completionHandler(error) }
    }
}
