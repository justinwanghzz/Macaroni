import AppKit
import SwiftUI
import Carbon
import ApplicationServices

final class ClipboardPanel:NSPanel { override var canBecomeKey:Bool { true } }

@MainActor final class ClipboardController:NSObject,ObservableObject,NSWindowDelegate {
    static let shared=ClipboardController()
    @Published var query=""
    @Published var selection:UUID?
    @Published var shortcutError=""
    @Published var error=""
    @Published var focusToken=UUID()
    var panel:ClipboardPanel?
    var destinationWindow:NSWindow?
    var destinationResponder:NSResponder?
    var destination:NSRunningApplication?
    var lastExternal:NSRunningApplication?
    var keyMonitor:Any?,outsideMonitor:Any?,activationObserver:Any?
    let fnShortcut=FnShortcut()
    var hotKey:EventHotKeyRef?,handler:EventHandlerRef?
    var pasteTask:Task<Void,Never>?
    var isOpen=false
    var entries:[Clip] {
        AppModel.shared.clips.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }.sorted { a,b in a.pinned && !b.pinned }
    }
    func start() {
        lastExternal=NSWorkspace.shared.frontmostApplication
        NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { if AppModel.shared.settings.historyShortcut=="fnShiftV",self?.fnShortcut.port==nil {self?.registerShortcut()} }
        }
        activationObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] note in
            guard let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.lastExternal=app }
        }
        var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _,_,_ in
            Task { @MainActor in ClipboardController.shared.show() };return noErr
        },1,&type,nil,&handler)
        registerShortcut()
    }
    func registerShortcut() {
        fnShortcut.stop()
        if let hotKey { UnregisterEventHotKey(hotKey);self.hotKey=nil };shortcutError=""
        guard !delegate.isPaused,!CommandLine.arguments.contains("--smoke-test") else { return }
        let key=AppModel.shared.settings.historyShortcut
        guard key != "none" else { return }
        if key=="fnShiftV" {
            fnShortcut.activate={ [weak self] in self?.show() }
            if !fnShortcut.start() {shortcutError="Enable keyboard access for Fn + Shift + V."}
            return
        }
        let mods:UInt32=key=="optionShiftV" ? UInt32(optionKey|shiftKey):key=="optionCommandV" ? UInt32(optionKey|cmdKey):key=="commandShiftV" ? UInt32(cmdKey|shiftKey):UInt32(controlKey|shiftKey)
        let status=RegisterEventHotKey(UInt32(kVK_ANSI_V),mods,EventHotKeyID(signature:0x5554494C,id:1),GetApplicationEventTarget(),0,&hotKey)
        if status != noErr { shortcutError="Shortcut unavailable. Choose another in Settings." }
    }
    func enableKeyboardAccess() {
        let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _=AXIsProcessTrustedWithOptions(options)
        registerShortcut()
    }
    func show() {
        guard !delegate.isPaused else { return }
        if isOpen { dismiss();return }
        pasteTask?.cancel()
        let front=NSWorkspace.shared.frontmostApplication
        destinationWindow=nil;destinationResponder=nil
        if front?.processIdentifier==ProcessInfo.processInfo.processIdentifier,let window=NSApp.keyWindow,window !== panel,!(window is ActivityPanel),window.isVisible {
            destination=front;destinationWindow=window;destinationResponder=window.firstResponder
        } else {destination=front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternal:front}
        query="";error="";selection=AppModel.shared.clips.first?.id
        if panel==nil {
            let p=ClipboardPanel(contentRect:NSRect(x:0,y:0,width:380,height:460),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isReleasedWhenClosed=false;p.level = .popUpMenu;p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.hidesOnDeactivate=false;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];p.delegate=self
            p.contentView=NSHostingView(rootView:ClipboardPopupView());panel=p
        }
        let point=NSEvent.mouseLocation,screen=(NSScreen.screens.first {$0.frame.contains(point)} ?? NSScreen.main!).visibleFrame
        panel?.setFrameOrigin(CGPoint(x:max(screen.minX+12,min(point.x-190,screen.maxX-392)),y:max(screen.minY+12,min(point.y-230,screen.maxY-472))))
        isOpen=true;panel?.makeKeyAndOrderFront(nil);focusToken=UUID()
        keyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            let handled=MainActor.assumeIsolated { self?.handle(event)==nil }
            return handled ? nil:event
        }
        outsideMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss(restore:false) }
        }
    }
    func handle(_ event:NSEvent)->NSEvent? {
        guard isOpen else { return event }
        if event.keyCode==53 { dismiss();return nil }
        if event.keyCode==125 || event.keyCode==126 { move(event.keyCode==125 ? 1:-1);return nil }
        if event.keyCode==36 || event.keyCode==76 { commit(paste:false);return nil }
        if event.modifierFlags.intersection([.command,.control,.option,.shift]) == .command,event.charactersIgnoringModifiers=="v" { commit(paste:true);return nil }
        return event
    }
    func move(_ delta:Int) {
        let values=entries;guard !values.isEmpty else {selection=nil;return}
        let index=values.firstIndex(where:{$0.id==selection}) ?? (delta>0 ? -1:values.count)
        selection=values[max(0,min(values.count-1,index+delta))].id
    }
    func commit(paste:Bool) {
        guard let clip=entries.first(where:{$0.id==selection}) else { return }
        if paste,destinationWindow==nil,!CommandLine.arguments.contains("--smoke-test"),!AXIsProcessTrusted() {
            let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
            _=AXIsProcessTrustedWithOptions(options)
            error="Enable Accessibility for ⌘V, or press Enter to copy and close."
            return
        }
        guard AppModel.shared.copy(clip) else { error=AppModel.shared.clipboardError;return }
        let target=destination,ownWindow=destinationWindow
        dismiss()
        if paste,ownWindow != nil,!CommandLine.arguments.contains("--smoke-test") {
            NSApp.sendAction(#selector(NSText.paste(_:)),to:nil,from:nil);return
        }
        guard paste,!CommandLine.arguments.contains("--smoke-test"),let target,!target.isTerminated,target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        // Send once, only after the original app has regained focus. Never paste into a different app.
        pasteTask=Task {
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds:20_000_000)
                guard !Task.isCancelled,!delegate.isPaused else { return }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier==target.processIdentifier {
                    let source=CGEventSource(stateID:.combinedSessionState)
                    let down=CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(kVK_ANSI_V),keyDown:true)
                    let up=CGEvent(keyboardEventSource:source,virtualKey:CGKeyCode(kVK_ANSI_V),keyDown:false)
                    down?.flags = .maskCommand;up?.flags = .maskCommand
                    down?.postToPid(target.processIdentifier);up?.postToPid(target.processIdentifier)
                    return
                }
            }
        }
    }
    func dismiss(restore:Bool=true) {
        guard isOpen else { return };isOpen=false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor);self.keyMonitor=nil }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor);self.outsideMonitor=nil }
        panel?.orderOut(nil)
        if restore,let window=destinationWindow,window.isVisible {
            window.makeKeyAndOrderFront(nil);if let responder=destinationResponder {window.makeFirstResponder(responder)}
        } else if restore,let destination,!destination.isTerminated { destination.activate(options:[]) }
    }
    func windowDidResignKey(_ notification:Notification) { if isOpen { dismiss(restore:false) } }
}

struct ClipboardPopupView:View {
    @ObservedObject var controller=ClipboardController.shared
    @ObservedObject var model=AppModel.shared
    @FocusState private var searchFocused:Bool
    var body:some View {
        VStack(spacing:10) {
            HStack { Image(systemName:"doc.on.clipboard").foregroundStyle(Color.utilityAccent);Text("Clipboard").font(.headline);Spacer();Button(model.recording ? "Pause":"Resume") {model.setRecording(!model.recording)}.buttonStyle(.borderless) }
            TextField("Search history",text:$controller.query).textFieldStyle(.roundedBorder).focused($searchFocused).onAppear {searchFocused=true}.onChange(of:controller.focusToken) {_,_ in searchFocused=true}.onChange(of:controller.query) { _,_ in controller.selection=controller.entries.first?.id }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing:5) {
                        ForEach(controller.entries) { clip in
                            HStack(spacing:10) {
                                if clip.isFiles {
                                    Image(nsImage:NSWorkspace.shared.icon(forFile:clip.files!.first!.url.path)).resizable().scaledToFit().frame(width:42,height:42)
                                }
                                else if let data=clip.png,let image=NSImage(data:data) {Image(nsImage:image).resizable().scaledToFit().frame(width:56,height:42)}
                                else {Image(systemName:"text.alignleft").foregroundStyle(.secondary).frame(width:22)}
                                VStack(alignment:.leading,spacing:3) {
                                    Text(clip.text).font(.system(size:12)).lineLimit(2)
                                    if clip.isFiles {Text(clip.unavailableFiles.isEmpty ? "\(clip.files!.count) file\(clip.files!.count==1 ? "":"s")":"Files unavailable").font(.caption2).foregroundStyle(clip.unavailableFiles.isEmpty ? Color.secondary:Color.red)}
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                Button {if let i=model.clips.firstIndex(where:{$0.id==clip.id}) {model.clips[i].pinned.toggle();model.persist()}} label:{Image(systemName:clip.pinned ? "pin.fill":"pin")}.buttonStyle(.borderless)
                                Button {controller.selection=clip.id;controller.commit(paste:false)} label:{Image(systemName:"doc.on.doc")}.buttonStyle(.borderless).help("Copy and close")
                            }.padding(9).frame(minHeight:42).background(controller.selection==clip.id ? Color.utilityAccent.opacity(0.17):Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9)).contentShape(Rectangle()).onTapGesture {controller.selection=clip.id}.id(clip.id)
                        }
                        if controller.entries.isEmpty { Text(model.recording ? "Copied text, images and files appear here":"History paused").foregroundStyle(.secondary).padding(.top,40) }
                    }
                }.onChange(of:controller.selection) { _,value in if let value {scroll.scrollTo(value)} }.onChange(of:controller.focusToken) {_,_ in if let id=controller.selection {scroll.scrollTo(id,anchor:.top)} }
            }
            if !controller.error.isEmpty {Text(controller.error).font(.caption).foregroundStyle(.red)}
            HStack {Text("↑ ↓ Choose   ↩ Copy   ⌘V Paste").font(.system(size:10)).foregroundStyle(.secondary);Spacer();Button("Clear unpinned") {model.clips.removeAll{!$0.pinned};model.persist()}.buttonStyle(ChoicePillStyle(compact:true))
                Button("Clear all") {model.clips=[];model.persist()}.buttonStyle(ChoicePillStyle(compact:true))}
        }.padding(16).background(.regularMaterial,in:RoundedRectangle(cornerRadius:17)).overlay(RoundedRectangle(cornerRadius:17).stroke(Color.primary.opacity(0.08))).clipShape(RoundedRectangle(cornerRadius:17))
    }
}
