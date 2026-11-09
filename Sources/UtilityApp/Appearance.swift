import SwiftUI
import AppKit
import UtilityCore

extension Color {
    static let utilityAccent = Color(red:0.34,green:0.36,blue:0.72)
    static let utilitySurface = Color(nsColor:NSColor(name:nil) { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(calibratedRed:0.14,green:0.15,blue:0.18,alpha:1) : NSColor(calibratedRed:0.97,green:0.975,blue:0.99,alpha:1) })
}
struct UtilityBackground: ViewModifier {
    func body(content:Content)->some View { content.background(Color.utilitySurface).tint(.utilityAccent) }
}
extension View { func utilityStyle()->some View { modifier(UtilityBackground()) } }

struct UtilitySettings: Codable {
    enum Trigger: String,Codable,CaseIterable,Identifiable {
        case shift, controlShift, optionShift
        var id:String { rawValue }
        var label:String { switch self { case .shift:return "Shift"; case .controlShift:return "Control + Shift"; case .optionShift:return "Option + Shift" } }
        var flags:NSEvent.ModifierFlags { switch self { case .shift:return .shift; case .controlShift:return [.control,.shift]; case .optionShift:return [.option,.shift] } }
        func matches(_ flags:NSEvent.ModifierFlags)->Bool { flags.intersection([.shift,.control,.option,.command,.function]) == self.flags }
    }
    var trigger:Trigger = .shift
    var shelfWidth:Double = 126
    var shelfHeight:Double = 440
    var moveFiles = false
    // Optional backing values keep settings from earlier releases readable.
    var clearCopiedItems:Bool?
    var clipboardPaused:Bool?
    var clipboardShortcut:String?
    var outputNaming:OutputNaming?
    var shelfDisplayMode:String?
    var shelfHeightCustomized:Bool?
    var naming:OutputNaming {get {outputNaming ?? OutputNaming()} set {outputNaming=newValue}}
    var shelfList:Bool {get {shelfDisplayMode != "icons"} set {shelfDisplayMode=newValue ? "list":"icons"}}
    var clearAfterCopy:Bool { get { clearCopiedItems ?? false } set { clearCopiedItems=newValue } }
    var recordsClipboard:Bool { get { !(clipboardPaused ?? false) } set { clipboardPaused = !newValue } }
    var historyShortcut:String { get { clipboardShortcut == nil || clipboardShortcut == "fnShiftV" ? "optionShiftV":clipboardShortcut! } set { clipboardShortcut=newValue } }

}
struct SettingsView: View {
    @ObservedObject var clipboard=ClipboardController.shared
    @ObservedObject var model = AppModel.shared
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Settings").font(.title2.bold())
            Picker("During a file drag",selection:$model.settings.trigger) { ForEach(UtilitySettings.Trigger.allCases) { Text($0.label).tag($0) } }.onChange(of:model.settings.trigger) { _,_ in model.persist() }
            Text("Hold the selected keys after starting a Finder drag.").font(.callout).foregroundStyle(.secondary)
            Divider()
            Toggle("Move files when dragging out of the shelf",isOn:$model.settings.moveFiles).onChange(of:model.settings.moveFiles) { _,_ in model.persist() }
            Text("Copy keeps the originals. Move relocates the selected files.").font(.callout).foregroundStyle(.secondary)
            Toggle("Clear shelf after successful copies",isOn:Binding(get:{model.settings.clearAfterCopy},set:{model.settings.clearAfterCopy=$0;model.persist()}))
            Picker("Clipboard shortcut",selection:Binding(get:{model.settings.historyShortcut},set:{model.settings.historyShortcut=$0;model.persist();ClipboardController.shared.registerShortcut()})) {
                Text("Option + Shift + V").tag("optionShiftV")
                Text("Control + Shift + V").tag("controlShiftV")
                Text("Option + Command + V").tag("optionCommandV")
                Text("Command + Shift + V").tag("commandShiftV")
                Text("None").tag("none")
            }
            if !clipboard.shortcutError.isEmpty {
                HStack {Text(clipboard.shortcutError).font(.caption).foregroundStyle(.secondary);Button("Enable…") {clipboard.enableKeyboardAccess()}}
            }
            Button("Output naming…") {delegate.show("Output naming",view:NamingView(),size:NSSize(width:480,height:640))}.buttonStyle(ChoicePillStyle())
            Spacer()
        }.padding(24).utilityStyle()
    }
}

@MainActor final class FolderAccess {
    let home:URL
    var grants:[FileReference]
    var lease:AccessLease?
    init(home:URL) { self.home=home; grants=JSONStore.load([FileReference].self,from:home.appendingPathComponent("folders.json")) ?? [] }
    func prepare(_ folders:[URL]) throws -> AccessLease {
        lease = AccessLease(urls:grants.map(\.url))
        for folder in Set(folders) {
            if canWrite(folder) { continue }
            let panel=NSOpenPanel(); panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.directoryURL=folder;panel.prompt="Allow folder";panel.message="Allow Macaroni to save results in \(folder.lastPathComponent)."
            NSApp.activate(ignoringOtherApps:true)
            guard panel.runModal() == .OK, let picked=panel.url, folder.standardizedFileURL.path == picked.standardizedFileURL.path || folder.standardizedFileURL.path.hasPrefix(picked.standardizedFileURL.path+"/") else { throw UtilityError.message("Folder access wasn’t granted") }
            let grant=FileReference(url:picked);grants.removeAll { $0.path == grant.path };grants.append(grant)
            lease=AccessLease(urls:grants.map(\.url))
            guard canWrite(folder) else { throw UtilityError.message("Can’t save in \(folder.lastPathComponent). Choose a writable folder or update its permissions.") }
            try JSONStore.save(grants,to:home.appendingPathComponent("folders.json"))
        }
        return AccessLease(urls:grants.map(\.url)+folders)
    }
    private func canWrite(_ folder:URL)->Bool {
        let probe=folder.appendingPathComponent(".utility-access-"+UUID().uuidString)
        do { try Data().write(to:probe,options:.withoutOverwriting);try FileManager.default.removeItem(at:probe);return true } catch { return false }
    }
}

final class ActivityPanel:NSPanel { override var canBecomeKey:Bool {true} }
@MainActor final class ActivityController {
    static let shared=ActivityController(); var panel:NSPanel?;var hideToken=UUID()
    func show() {
        guard !delegate.isPaused else {return}
        hideToken=UUID()
        if panel == nil {
            let p=ActivityPanel(contentRect:NSRect(x:0,y:0,width:340,height:200),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="Macaroni";p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.isReleasedWhenClosed=false;p.level = .floating;p.contentView=NSHostingView(rootView:ActivityView());panel=p
        }
        panel?.setContentSize(NSSize(width:340,height:AppModel.shared.busy ? 100:min(290,64+AppModel.shared.results.count*52)))
        let screen=NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        panel?.setFrameOrigin(NSPoint(x:screen.visibleFrame.maxX-360,y:screen.visibleFrame.minY+30));panel?.orderFrontRegardless()
    }
    func hide() { hideToken=UUID();panel?.orderOut(nil) }
    func dismissSoon() { let token=hideToken;DispatchQueue.main.asyncAfter(deadline:.now()+3) { if token==self.hideToken { self.hide() } } }
}
struct ActivityView:View {
    @ObservedObject var model=AppModel.shared
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Image(systemName:model.busy ? "sparkles" : model.results.contains(where:{$0.status == .failed}) ? "exclamationmark.triangle" : model.results.contains(where:{$0.status == .cancelled}) ? "xmark.circle" : "checkmark.circle").foregroundStyle(Color.utilityAccent);Text(model.message).font(.headline).lineLimit(1);Spacer();if model.busy { Button("Cancel") { model.task?.cancel() } };Button {ActivityController.shared.hide()} label:{Image(systemName:"xmark").font(.system(size:10,weight:.semibold))}.buttonStyle(.borderless).help("Dismiss") }
            if model.busy { ProgressView(value:model.progress).tint(.utilityAccent) }
            if !model.results.isEmpty {
                ScrollView { VStack(alignment:.leading,spacing:8) { ForEach(model.results) { r in
                    HStack { VStack(alignment:.leading) { Text(URL(fileURLWithPath:r.output ?? r.input).lastPathComponent).fontWeight(.medium).lineLimit(1);Text(r.message).font(.caption).foregroundStyle(r.status == .failed ? Color.red : Color.secondary).textSelection(.enabled) };Spacer();if let path=r.output { Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:path)]) }.buttonStyle(.borderless) } }
                } } }
            }
        }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(Color.primary.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius:16))
    }
}

struct PrimaryActionStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View { configuration.label.font(.system(size:14,weight:.semibold)).padding(.horizontal,20).padding(.vertical,10).foregroundStyle(.white).background(Color.utilityAccent.opacity(!enabled ? 0.35 : configuration.isPressed ? 0.8:1),in:Capsule()) }
}
struct ChoicePillStyle:ButtonStyle {
    var selected=false
    var compact=false
    func makeBody(configuration:Configuration)->some View { configuration.label.font(.system(size:compact ? 11:13,weight:.medium)).padding(.horizontal,compact ? 8:14).padding(.vertical,compact ? 6:9).foregroundStyle(selected ? Color.white:Color.primary).background(selected ? Color.utilityAccent:Color.utilityAccent.opacity(configuration.isPressed ? 0.2:0.08),in:Capsule()) }
}
