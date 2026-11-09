import AppKit
import SwiftUI
import UtilityCore

@MainActor final class WorkflowEditorModel:ObservableObject {
    let inputs:[URL],location:ExportLocation
    @Published var selection:UUID?
    @Published var draft=WorkflowDefinition(name:"New workflow",steps:[.init(kind:.convertImage)]) {didSet {save();estimate()}}
    @Published var error=""
    @Published var estimatedBytes:Int64?
    var estimateTask:Task<Void,Never>?
    var loading=false
    var workflows:[WorkflowDefinition] {AppModel.shared.workflows.filter{$0.steps.allSatisfy{ActionKind.imageSteps.contains($0.kind)}}.sorted {($0.pinned == true) && ($1.pinned != true)}}
    init(inputs:[URL]) {
        self.inputs=inputs.filter{AssetKind(url:$0) == .image};location=ExportLocation(inputs:inputs,filename:"")
        if let first=workflows.first {select(first.id)} else {create()}
    }
    func select(_ id:UUID) {guard let w=workflows.first(where:{$0.id==id}) else {return};loading=true;selection=id;draft=w;loading=false;error="";estimate()}
    func create() {var value=WorkflowDefinition(name:"New workflow",steps:[.init(kind:.convertImage)]);value.isPreset=true;AppModel.shared.workflows.append(value);AppModel.shared.persist();select(value.id)}
    func delete() {guard let selection else {return};AppModel.shared.workflows.removeAll{$0.id==selection};AppModel.shared.persist();if let next=workflows.first {select(next.id)} else {self.selection=nil;loading=true;draft = .init(name:"",steps:[]);loading=false}}
    func rename(_ name:String) {draft.name=name}
    func save() {
        guard !loading,let id=selection,let i=AppModel.shared.workflows.firstIndex(where:{$0.id==id}) else {return}
        var value=draft;value.isPreset=true;AppModel.shared.workflows[i]=value;AppModel.shared.persist()
    }
    func add(_ kind:ActionKind) {guard draft.steps.count<12 else {return};var step=ActionStep(kind:kind);if kind == .cropImage {step.crop=CropRegion()};if kind == .resizeImage {step.width=1600;step.height=1000;step.aspectLocked=true};if let i=draft.steps.firstIndex(where:{$0.kind == .exportPDF}) {guard kind != .exportPDF else {return};draft.steps.insert(step,at:i)} else {draft.steps.append(step)}}
    func changeKind(_ id:UUID,to kind:ActionKind) {
        guard ActionKind.imageSteps.contains(kind),let index=draft.steps.firstIndex(where:{$0.id==id}) else {return}
        if draft.steps[index].kind==kind {return}
        if kind == .exportPDF,draft.steps.contains(where:{$0.kind == .exportPDF && $0.id != id}) {error="A workflow can have one PDF step, at the end";return}
        var changed=ActionStep(kind:kind,id:id)
        if kind == .resizeImage {changed.width=1600;changed.height=1000;changed.aspectLocked=true}
        if kind == .cropImage {changed.crop=CropRegion()}
        var steps=draft.steps;steps[index]=changed
        if kind == .exportPDF {steps.remove(at:index);steps.append(changed)}
        draft.steps=steps;error=""
    }
    func move(_ id:UUID,by amount:Int) {guard let i=draft.steps.firstIndex(where:{$0.id==id}),draft.steps.indices.contains(i+amount),draft.steps[i].kind != .exportPDF,draft.steps[i+amount].kind != .exportPDF else {return};draft.steps.swapAt(i,i+amount)}
    func chooseCrop(_ id:UUID) {
        guard let first=inputs.first else {error="Drop an image on Preset to choose a visual crop";return}
        // Preview the preceding steps so crop coordinates match the actual pipeline stage.
        let steps=Array(draft.steps.prefix { $0.id != id })
        Task { [weak self] in
            guard let self else {return}
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent("utility-workflow-crop-"+UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let source:URL
                if steps.isEmpty {source=first} else {source=try await ProcessingEngine.run(input:first,workflow:.init(name:"Crop preview",steps:steps),outputDirectory:folder)}
                ImageAdjustmentController.shared.show(.cropImage,urls:[source],onCommit:{ [weak self] chosen in
                    guard let self,let index=self.draft.steps.firstIndex(where:{$0.id==id}) else {return};self.draft.steps[index].crop=chosen.crop
                },onDismiss:{try? FileManager.default.removeItem(at:folder)})
            } catch {try? FileManager.default.removeItem(at:folder);self.error=error.localizedDescription}
        }
    }
    func run() {
        do {guard !inputs.isEmpty else {throw UtilityError.message("Drop images on Preset, or add images to the shelf first")};try draft.validate(for:.image);var value=draft;value.isPreset=true;AppModel.shared.run(inputs,workflow:value,destination:location.directory);error=""} catch {self.error=error.localizedDescription}
    }
    func estimate() {
        estimateTask?.cancel();estimatedBytes=nil
        guard !loading,!inputs.isEmpty,let index=draft.steps.firstIndex(where:{$0.kind == .compressImage}) else {return}
        let urls=inputs,steps=Array(draft.steps.prefix(index+1))
        estimateTask=Task {
            do {
                try await Task.sleep(nanoseconds:300_000_000)
                let job=Task.detached { () async throws -> Int64 in
                    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("utility-workflow-estimate-"+UUID().uuidString)
                    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
                    var total:Int64=0
                    for url in urls {try Task.checkCancellation();let out=try await ProcessingEngine.run(input:url,workflow:.init(name:"Estimate",steps:steps),outputDirectory:folder);total+=FileServices.bytes(out)}
                    return total
                }
                let bytes=try await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()})
                guard !Task.isCancelled else {return};estimatedBytes=bytes
            } catch {}
        }
    }
}
@MainActor enum WorkflowController {
    static func show(inputs:[URL]) {delegate.windows.removeValue(forKey:"Image workflows")?.close();delegate.show("Image workflows",view:WorkflowView(inputs:inputs),size:NSSize(width:900,height:740))}
}
struct WorkflowView:View {
    @StateObject var editor:WorkflowEditorModel
    @ObservedObject var app=AppModel.shared
    init(inputs:[URL]=[]) {_editor=StateObject(wrappedValue:WorkflowEditorModel(inputs:inputs))}
    var body:some View {
        HSplitView {
            VStack(spacing:12) {
                HStack {Text("Presets").font(.headline);Spacer();Button {editor.create()} label:{Image(systemName:"plus")}.help("New workflow")}.padding(.horizontal,12)
                WorkflowSidebar(editor:editor,workflows:editor.workflows)
                HStack {Button("Delete") {editor.delete()}.disabled(editor.selection==nil);Spacer();Button {editor.draft.pinned = editor.draft.pinned != true} label:{Image(systemName:editor.draft.pinned == true ? "pin.fill":"pin")}.help("Pin workflow").disabled(editor.selection==nil)}.padding(.horizontal,12)
            }.padding(.vertical,16).frame(minWidth:180,idealWidth:210,maxWidth:270)
            VStack(alignment:.leading,spacing:12) {
                if editor.selection != nil {
                    TextField("Workflow name",text:$editor.draft.name).font(.title2.bold()).textFieldStyle(.plain)
                    Text("Changes save automatically · \(editor.inputs.count) input images").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(spacing:10) {ForEach($editor.draft.steps) {$step in
                            VStack(alignment:.leading,spacing:10) {
                                HStack {Text("\((editor.draft.steps.firstIndex(where:{$0.id==step.id}) ?? 0)+1)").font(.caption.bold()).foregroundStyle(.secondary);Picker("Action",selection:Binding(get:{step.kind},set:{editor.changeKind(step.id,to:$0)})) {ForEach(ActionKind.imageSteps) {kind in Text(kind.title).tag(kind)}}.labelsHidden().frame(maxWidth:220);Spacer();Button {editor.move(step.id,by:-1)} label:{Image(systemName:"arrow.up")};Button {editor.move(step.id,by:1)} label:{Image(systemName:"arrow.down")};Button {editor.draft.steps.removeAll{$0.id==step.id}} label:{Image(systemName:"minus.circle")}}
                                ImageWorkflowStep(step:$step,editor:editor)
                            }.padding(14).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:13))
                        }}
                    }
                    HStack {Menu("Add step") {ForEach(ActionKind.imageSteps) {kind in Button(kind.title) {editor.add(kind)}}}.disabled(editor.draft.steps.count>=12);Spacer();Text("Up/Down: select · Enter: run").font(.caption).foregroundStyle(.secondary)}
                    Text("Crop uses the same relative region across the batch. Locked resize fits each image inside the chosen dimensions. PDF creates one file per image.").font(.caption).foregroundStyle(.secondary)
                    if !editor.error.isEmpty {Text(editor.error).font(.caption).foregroundStyle(.red)}
                    HStack(spacing:12) {ExportDestinationControl(location:editor.location);Spacer(minLength:8);Button("Run workflow") {editor.run()}.buttonStyle(PrimaryActionStyle()).disabled(app.busy || editor.inputs.isEmpty)}
                } else {ContentUnavailableView("Create a workflow",systemImage:"flowchart",description:Text("Use + to add your first image preset"))}
            }.padding(20).frame(minWidth:500)
        }.utilityStyle().onDisappear {editor.estimateTask?.cancel()}
    }
}
struct ImageWorkflowStep:View {
    @Binding var step:ActionStep
    @ObservedObject var editor:WorkflowEditorModel
    var body:some View {
        switch step.kind {
        case .convertImage:Picker("Format",selection:$step.format) {ForEach(ImageEngine.writableFormats,id:\.self) {Text($0.uppercased()).tag($0)}}
        case .compressImage:
            VStack(alignment:.leading) {HStack {Text("Smaller");Slider(value:$step.amount,in:1...100);Text("Sharper")};Text(editor.estimatedBytes.map{"Estimated compressed output: "+ByteCountFormatter.string(fromByteCount:$0,countStyle:.file)} ?? "Estimating compressed output…").font(.caption).foregroundStyle(.secondary)}
        case .resizeImage:
            HStack {TextField("Width",value:Binding(get:{step.width ?? 1600},set:{step.width=$0}),format:.number).frame(width:90);Text("×");TextField("Height",value:Binding(get:{step.height ?? 1000},set:{step.height=$0}),format:.number).frame(width:90);Text("px");Button {step.aspectLocked = !(step.aspectLocked ?? true)} label:{Image(systemName:(step.aspectLocked ?? true) ? "lock.fill":"lock.open")}.help("Keep image proportions when fitting these bounds")}
        case .rotateImage:
            HStack {ForEach([90.0,180,270],id:\.self) {angle in Button("\(Int(angle))° ↻") {step.amount=angle}.buttonStyle(ChoicePillStyle(selected:step.amount==angle,compact:true))};Spacer();TextField("Angle",value:$step.amount,format:.number).frame(width:60);Text("° clockwise").font(.caption)}
        case .cropImage:
            HStack {Button("Choose crop visually") {editor.chooseCrop(step.id)}.buttonStyle(ChoicePillStyle(compact:true));if let region=step.crop {Text("\(Int(region.width*100))% × \(Int(region.height*100))% of each image").font(.caption).foregroundStyle(.secondary)}}
        case .exportPDF:Text("Final step · one PDF per image").font(.caption).foregroundStyle(.secondary)
        default:EmptyView()
        }
    }
}
// A native sidebar gives arrows and Finder-style second-click renaming predictable focus.
struct WorkflowSidebar:NSViewRepresentable {
    @ObservedObject var editor:WorkflowEditorModel
    let workflows:[WorkflowDefinition]
    func makeCoordinator()->Coordinator {Coordinator(editor:editor)}
    func makeNSView(context:Context)->NSScrollView {
        let table=WorkflowTable(frame:NSRect(x:0,y:0,width:210,height:600));table.autoresizingMask=[.width];table.headerView=nil;table.rowHeight=34;table.style = .sourceList;table.allowsEmptySelection=false;table.addTableColumn(NSTableColumn(identifier:.init("Workflow")));table.delegate=context.coordinator;table.dataSource=context.coordinator;table.editor=editor
        let scroll=ShelfScrollView();scroll.hasVerticalScroller=true;scroll.documentView=table;context.coordinator.table=table;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        let c=context.coordinator;guard let table=c.table else {return}
        if let text=table.window?.firstResponder as? NSTextView,text.isFieldEditor,let field=text.delegate as? NSTextField,field.isDescendant(of:table) {return}
        c.updating=true
        if c.workflows != workflows {c.workflows=workflows;table.reloadData()}
        if let index=workflows.firstIndex(where:{$0.id==editor.selection}),table.selectedRow != index {table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}
        c.updating=false
    }
    @MainActor final class Coordinator:NSObject,NSTableViewDelegate,NSTableViewDataSource,NSTextFieldDelegate {
        let editor:WorkflowEditorModel;weak var table:NSTableView?;var workflows:[WorkflowDefinition]=[];var updating=false
        init(editor:WorkflowEditorModel) {self.editor=editor}
        func numberOfRows(in tableView:NSTableView)->Int {workflows.count}
        func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {let field=WorkflowNameField(string:workflows[row].name);field.isBordered=false;field.drawsBackground=false;field.delegate=self;field.tag=row;field.isEditable=false;field.isSelectable=false;let cell=NSTableCellView();cell.addSubview(field);field.translatesAutoresizingMaskIntoConstraints=false;NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:workflows[row].pinned == true ? 22:8),field.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-6),field.centerYAnchor.constraint(equalTo:cell.centerYAnchor)]);if workflows[row].pinned == true {let pin=NSImageView(image:NSImage(systemSymbolName:"pin.fill",accessibilityDescription:"Pinned")!);pin.frame=NSRect(x:5,y:9,width:12,height:14);cell.addSubview(pin)};cell.textField=field;return cell}
        func tableViewSelectionDidChange(_ notification:Notification) {guard !updating,let table,workflows.indices.contains(table.selectedRow) else {return};editor.select(workflows[table.selectedRow].id)}
        func controlTextDidEndEditing(_ notification:Notification) {guard let field=notification.object as? NSTextField,workflows.indices.contains(field.tag) else {return};let id=workflows[field.tag].id;if editor.selection==id {editor.rename(field.stringValue)};field.isEditable=false;field.isSelectable=false;table?.window?.makeFirstResponder(table)}
    }
}
final class WorkflowTable:NSTableView {
    weak var editor:WorkflowEditorModel?
    override func keyDown(with event:NSEvent) {if event.keyCode==36 || event.keyCode==76 {MainActor.assumeIsolated {editor?.run()};return};super.keyDown(with:event)}
    override func mouseDown(with event:NSEvent) {let point=convert(event.locationInWindow,from:nil),row=row(at:point),previous=selectedRow;super.mouseDown(with:event);if row>=0,row==previous,let cell=view(atColumn:0,row:row,makeIfNecessary:false) as? NSTableCellView,let text=cell.textField {text.isEditable=true;text.isSelectable=true;window?.makeFirstResponder(text);text.selectText(nil)}}
}

final class WorkflowNameField:NSTextField {
    override func hitTest(_ point:NSPoint)->NSView? {isEditable ? super.hitTest(point):nil}
}
