import AppKit
import SwiftUI
import UtilityCore

typealias Clip=ClipboardEntry
@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    let home = ProcessInfo.processInfo.environment["UTILITY_DATA_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UtilityApp")
    @Published var shelf: [FileReference] = []
    @Published var workflows: [WorkflowDefinition] = []
    @Published var clips: [Clip] = []
    @Published var recording = false
    @Published var results: [ItemResult] = []
    @Published var progress = 0.0
    @Published var busy = false
    @Published var message = "Ready"
    @Published var settings = UtilitySettings()
    @Published var selected: Set<UUID> = []
    var shelfChanged: (() -> Void)?
    lazy var folderAccess = FolderAccess(home: home)
    var promiseBatch: UUID?
    var suppressFinder = CommandLine.arguments.contains("--smoke-test")
    var task: Task<Void, Never>?
    let pasteboard: NSPasteboard = CommandLine.arguments.contains("--smoke-test") ? NSPasteboard(name: .init("org.local.UtilityApp.smoke")) : .general
    var clipboardLease:AccessLease?
    var clipboardError=""
    var clipTimer: Timer?; var pasteboardCount = -1
    var exports: URL { home.appendingPathComponent("Exports") }
    init() {
        settings = JSONStore.load(UtilitySettings.self, from: home.appendingPathComponent("settings.json")) ?? UtilitySettings()
        shelf = JSONStore.load([FileReference].self, from: home.appendingPathComponent("shelf.json")) ?? []
        workflows = JSONStore.load([WorkflowDefinition].self, from: home.appendingPathComponent("workflows.json")) ?? []
        // Retire the unchanged bundled sample while preserving edited/custom workflows.
        let stock=WorkflowDefinition.examples[0]
        let previousCount=workflows.count
        workflows.removeAll { workflow in
            guard workflow.name==stock.name,workflow.steps.count==stock.steps.count else { return false }
            return zip(workflow.steps,stock.steps).allSatisfy { a,b in
                var lhs=a;let rhs=b;lhs.id=rhs.id
                return lhs==rhs
            }
        }
        if workflows.count != previousCount { try? JSONStore.save(workflows,to:home.appendingPathComponent("workflows.json")) }
        clips = JSONStore.load([Clip].self, from: home.appendingPathComponent("clipboard.json")) ?? []
        recording = settings.recordsClipboard
        // Start with subsequent clipboard changes, never capture old contents at launch.
        pasteboardCount = pasteboard.changeCount
        clipTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in Task { @MainActor in self.pollClipboard() } }
    }
    func persist() {
        do {
            try JSONStore.save(settings, to: home.appendingPathComponent("settings.json"))
            try JSONStore.save(shelf, to: home.appendingPathComponent("shelf.json"))
            try JSONStore.save(workflows, to: home.appendingPathComponent("workflows.json"))
            try JSONStore.save(clips, to: home.appendingPathComponent("clipboard.json"))
        } catch { message = error.localizedDescription }
    }
    func stage(_ urls: [URL]) {
        for url in urls where !shelf.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { shelf.append(FileReference(url: url)) }
        persist(); shelfChanged?()
    }
    var selectedReferences: [FileReference] { shelf.filter { selected.contains($0.id) } }
    func removeReferences(_ ids:Set<UUID>) { shelf.removeAll { ids.contains($0.id) }; selected.subtract(ids); persist(); shelfChanged?() }
    func copyShelf() {
        pasteboard.clearContents()
        let references = selected.isEmpty ? shelf : selectedReferences
        if pasteboard.writeObjects(references.map { $0.url as NSURL }) {
            pasteboardCount = pasteboard.changeCount
            message = "\(references.count) files copied — paste into Finder with ⌘V"
        } else { message = "Could not copy file references" }
    }
    func setRecording(_ value:Bool) { recording=value;settings.recordsClipboard=value;pasteboardCount=pasteboard.changeCount;persist() }
    func pollClipboard() {
        guard recording else { return }
        let pb = pasteboard
        if #available(macOS 15.4, *), pb.accessBehavior == .alwaysDeny { recording = false; message = "Clipboard access is disabled in macOS settings"; return }
        guard pb.changeCount != pasteboardCount else {return}
        let captured=pb.changeCount
        guard let entry=Clip.capture(from:pb) else {pasteboardCount=captured;return}
        pasteboardCount=captured;recordClip(entry)
    }
    func recordClip(_ entry:Clip) {
        if let index=clips.firstIndex(where:{$0.sameContent(as:entry)}) {let item=clips.remove(at:index);clips.insert(item,at:0)}
        else {clips.insert(entry,at:0)}
        while clips.filter({!$0.pinned}).count>100 || clips.filter({!$0.pinned}).reduce(0,{$0+$1.storedBytes})>50_000_000 {
            guard let i=clips.lastIndex(where:{!$0.pinned}) else {break};clips.remove(at:i)
        }
        persist()
    }
    @discardableResult func copy(_ clip:Clip)->Bool {
        do {
            clipboardLease=try clip.restore(to:pasteboard);clipboardError="";pasteboardCount=pasteboard.changeCount
            if let index=clips.firstIndex(where:{$0.id==clip.id}) {let entry=clips.remove(at:index);clips.insert(entry,at:0);persist()}
            return true
        } catch {clipboardError=error.localizedDescription;return false}
    }
    func run(_ urls: [URL], workflow: WorkflowDefinition, reveal: Bool = true,videoTargets:[String:Double]=[:],openMarkdown:Bool=false,destination:URL?=nil,videoSpeeds:[String:Double]=[:]) {
        if busy {ActivityController.shared.show();return}
        guard !urls.isEmpty else { return }
        let eligible = urls.filter { (try? workflow.validate(for:AssetKind(url:$0))) != nil }
        let folderLease:AccessLease
        do { folderLease = try folderAccess.prepare(eligible.map { destination ?? $0.deletingLastPathComponent() }) }
        catch { showError(error); return }
        busy=true;results=[];progress=0;message=workflow.name;ActivityController.shared.show()
        let naming=settings.naming
        task = Task.detached { [self] in
            let lease=AccessLease(urls:urls);defer { _=lease;_=folderLease }
            for (i,url) in urls.enumerated() {
                let result:ItemResult
                if Task.isCancelled { result = .init(input:url.path,status:.cancelled,message:"Cancelled") }
                else if (try? workflow.validate(for:AssetKind(url:url))) == nil { result = .init(input:url.path,status:.skipped,message:"Skipped · different file type") }
                else {
                    do {
                        var applied=workflow
                        if let target=videoTargets[url.path],applied.steps.first?.kind == .compressVideo { applied.steps[0].amount=target }
                        if let speed=videoSpeeds[url.path],applied.steps.first?.kind == .speedVideo {applied.steps[0].amount=speed}
                        let out=try await ProcessingEngine.run(input:url,workflow:applied,outputDirectory:destination ?? url.deletingLastPathComponent(),progress:{ value in Task { @MainActor in self.progress=(Double(i)+value)/Double(urls.count) } },naming:naming)
                        result = .init(input:url.path,output:out.path,status:.succeeded,message:"\(FileServices.sizeLabel(url)) → \(FileServices.sizeLabel(out))")
                    } catch is CancellationError { result = .init(input:url.path,status:.cancelled,message:"Cancelled") }
                    catch { result = .init(input:url.path,status:.failed,message:error.localizedDescription) }
                }
                await MainActor.run { self.results.append(result) }
            }
            await MainActor.run {
                self.finish(reveal:reveal)
                if openMarkdown,!delegate.isPaused,!self.suppressFinder {
                    let files=self.results.filter {$0.status == .succeeded}.compactMap(\.output).map {URL(fileURLWithPath:$0)}
                    if !files.isEmpty {EditorController.shared.show(files:files)}
                }
            }
        }
    }
    func finish(reveal:Bool = true) {
        busy=false;task=nil;progress=1
        let success=results.filter { $0.status == .succeeded }, failed=results.filter { $0.status == .failed }.count, skipped=results.filter { $0.status == .skipped }.count, cancelled=results.filter { $0.status == .cancelled }.count
        message="\(success.count) saved" + (failed>0 ? " · \(failed) failed" : "") + (skipped>0 ? " · \(skipped) skipped" : "") + (cancelled>0 ? " · Cancelled" : "")
        let outputs=success.compactMap(\.output).map { URL(fileURLWithPath:$0) }
        if reveal, !delegate.isPaused, Set(outputs.map { $0.deletingLastPathComponent() }).count == 1, !suppressFinder { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        persist()
        if !reveal { ActivityController.shared.hide() } else { ActivityController.shared.show();if failed==0 && skipped==0 && cancelled==0 && Set(outputs.map { $0.deletingLastPathComponent() }).count<=1 { ActivityController.shared.dismissSoon() } }
    }
    func recordDelivery(_ ref:FileReference,output:URL?,error:Error?,move:Bool,batch:UUID,clearCopied:Bool=false) {
        if promiseBatch != batch { results=[];promiseBatch=batch }
        if let error { message="Some files couldn’t be delivered";results.append(.init(input:ref.path,status:.failed,message:error.localizedDescription)) }
        else { message=move ? "Moved":"Copied";results.append(.init(input:ref.path,output:output?.path,status:.succeeded,message:message));if move || clearCopied { removeReferences([ref.id]) } }
        ActivityController.shared.show()
        if !results.contains(where:{$0.status == .failed}) { ActivityController.shared.dismissSoon() }
    }
    func showError(_ error:Error) { message=error.localizedDescription;results=[.init(input:"",status:.failed,message:message)];ActivityController.shared.show() }
    func transfer(move:Bool) {
        guard !busy else { return }
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.prompt=move ? "Move here" : "Copy here"
        guard panel.runModal() == .OK, let directory=panel.url else { return }
        transfer(selected.isEmpty ? shelf : selectedReferences,to:directory,move:move)
    }
    func transfer(_ refs:[FileReference],to directory:URL,move:Bool) {
        guard !busy,!refs.isEmpty else { return }
        let clearCopied=settings.clearAfterCopy
        busy=true;results=[];progress=0;message=move ? "Moving files" : "Copying files";ActivityController.shared.show()
        task=Task.detached { [self] in
            let lease=AccessLease(urls:refs.map(\.url)+[directory]);defer { _=lease }
            for (i,ref) in refs.enumerated() {
                let result:ItemResult
                do { let out=try FileServices.transfer(ref.url,to:directory,move:move);result = .init(input:ref.path,output:out.path,status:.succeeded,message:move ? "Moved" : "Copied") }
                catch is CancellationError { result = .init(input:ref.path,status:.cancelled,message:"Cancelled") }
                catch { result = .init(input:ref.path,status:.failed,message:error.localizedDescription) }
                await MainActor.run { self.results.append(result);self.progress=Double(i+1)/Double(refs.count);if (move || clearCopied) && result.status == .succeeded { self.removeReferences([ref.id]) } }
            }
            await MainActor.run { self.finish() }
        }
    }
}
