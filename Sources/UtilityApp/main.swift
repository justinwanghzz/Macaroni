import AppKit
import SwiftUI
import UtilityCore

@MainActor final class UtilityDelegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!; var windows: [String: NSWindow] = [:]; var monitor: DragMonitor!
    private(set) var isPaused = false
    private var restoreRecording = false
    private var pausedWindows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = MacaroniIcon.menuBarImage()
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, action, key) in [("File shelf", #selector(shelf), "s"), ("Clipboard history", #selector(clipboard), "h"), ("Markdown editor", #selector(editor), "e"), ("Workflows", #selector(workflows), "w"), ("Settings…", #selector(settings), ","), ("Recent results", #selector(results), "r"), ("Quit Macaroni", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.insertItem(pause, at: menu.items.count - 1)
        status.menu = menu
        let mainMenu=NSMenu(),appItem=NSMenuItem(),appMenu=NSMenu(),windowItem=NSMenuItem(),windowMenu=NSMenu(title:"Window")
        mainMenu.autoenablesItems=false
        let quitItem=NSMenuItem(title:"Quit Macaroni",action:#selector(quit),keyEquivalent:"q");quitItem.target=self;appMenu.addItem(quitItem);appItem.submenu=appMenu;mainMenu.addItem(appItem)
        windowMenu.addItem(NSMenuItem(title:"Close",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w"))
        windowMenu.addItem(NSMenuItem(title:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m"))
        let editItem=NSMenuItem(),editMenu=NSMenu(title:"Edit")
        let undo=NSMenuItem(title:"Undo",action:NSSelectorFromString("undo:"),keyEquivalent:"z")
        let redo=NSMenuItem(title:"Redo",action:NSSelectorFromString("redo:"),keyEquivalent:"z");redo.keyEquivalentModifierMask=[.command,.shift]
        editMenu.addItem(undo);editMenu.addItem(redo);editMenu.addItem(.separator())
        for (title,action,key) in [("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {editMenu.addItem(NSMenuItem(title:title,action:action,keyEquivalent:key))}
        editItem.title="Edit";editItem.submenu=editMenu;mainMenu.addItem(editItem)
        windowItem.title="Window";windowItem.submenu=windowMenu;mainMenu.addItem(windowItem);editMenu.addItem(.separator())
        for (title,action,key,tag,shift) in [("Find",#selector(EditorController.findText),"f",1,false),("Find Next",#selector(EditorController.findNext),"g",2,false),("Find Previous",#selector(EditorController.findPrevious),"g",3,true)] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:key);item.target=EditorController.shared;item.tag=tag;item.keyEquivalentModifierMask=shift ? [.command,.shift]:.command;editMenu.addItem(item)
        }
        NSApp.mainMenu=mainMenu;NSApp.windowsMenu=windowMenu
        AppModel.shared.shelfChanged = { [weak self] in self?.shelfDidChange() }
        if !AppModel.shared.shelf.isEmpty { shelfDidChange() }
        monitor = DragMonitor(delegate: self); monitor.start();ClipboardController.shared.start()
        if CommandLine.arguments.contains("--clipboard-review") {ClipboardReview.shared.start()}
        if CommandLine.arguments.contains("--show-shelf") { shelf() }
        if CommandLine.arguments.contains("--smoke-test") { Task { await SmokeRunner.run(self) } }
    }
    func show<V: View>(_ name: String, view: V, size: NSSize,title:String?=nil) {
        guard !isPaused else { return }
        if let window = windows[name] { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        window.title = title ?? name; window.isReleasedWhenClosed = false; window.contentView = NSHostingView(rootView: view)
        window.center(); windows[name] = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func togglePause() {
        isPaused.toggle()
        let model = AppModel.shared
        if isPaused {
            monitor.stop();ClipboardController.shared.pasteTask?.cancel();ClipboardController.shared.dismiss(restore:false)
            restoreRecording = model.recording
            model.recording = false
            model.task?.cancel()
            pausedWindows = (Array(windows.values) + ([EditorController.shared.window, PreviewController.shared.window, ShelfController.shared.panel, ActivityController.shared.panel].compactMap { $0 }) + Array(ImageAdjustmentController.shared.windows.values)).filter { $0.isVisible }
            pausedWindows.forEach { $0.orderOut(nil) }
        } else {
            model.pasteboardCount = model.pasteboard.changeCount
            model.recording = restoreRecording
            monitor.start()
            pausedWindows.forEach { $0.orderFront(nil) }
            pausedWindows = []
        }
        for item in status.menu?.items ?? [] {
            if item.action == #selector(togglePause) { item.title = isPaused ? "Resume" : "Pause" }
            else if item.action != #selector(quit) { item.isEnabled = !isPaused }
        }
        NSApp.mainMenu?.items.filter { $0.submenu === NSApp.windowsMenu }.forEach { $0.isEnabled = !isPaused }
        ClipboardController.shared.registerShortcut()
        status.button?.image = isPaused ? NSImage(systemSymbolName:"pause.circle",accessibilityDescription:"Macaroni paused") : MacaroniIcon.menuBarImage()
        status.button?.toolTip = isPaused ? "Macaroni paused — choose Resume to enable" : "Macaroni"
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if ClipboardReview.shared.enabled {windows["Desktop clipboard review"]?.makeKeyAndOrderFront(nil);return true};shelf();return true }
    @objc func shelf() { guard !isPaused else { return };ShelfController.shared.focus();windows["File shelf"]=ShelfController.shared.panel }
    func shelfDidChange() { guard !isPaused else { return };ShelfController.shared.changed();if let p=ShelfController.shared.panel { windows["File shelf"]=p } }
    @objc func results() { guard !isPaused else {return};ActivityController.shared.show() }
    @objc func settings() { show("Settings",view:SettingsView(),size:NSSize(width:520,height:490)) }
    @objc func clipboard() { ClipboardController.shared.show() }
    @objc func workflows() { WorkflowController.show(inputs:AppModel.shared.shelf.map(\.url)) }
    @objc func editor() { guard !isPaused else { return }; EditorController.shared.show() }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if !CommandLine.arguments.contains("--smoke-test"),EditorController.shared.window != nil,!EditorController.shared.confirmDiscard() {return .terminateCancel}
        return .terminateNow
    }
    func applicationWillTerminate(_ notification:Notification) {ClipboardReview.shared.restore()}
    @objc func quit() { NSApp.terminate(nil) }
    func convert(_ urls:[URL],format:String) { guard !isPaused else { return };AppModel.shared.run(urls,workflow:.init(name:"Save as \(format.uppercased())",steps:[.init(kind:.convertImage,format:format)])) }
    func action(_ kind:ActionKind,urls:[URL]) {
        guard !isPaused else { return }
        if [.cropImage,.resizeImage,.compressImage,.rotateImage].contains(kind) { ImageAdjustmentController.shared.show(kind,urls:urls);return }
        if kind == .speedVideo {windows.removeValue(forKey:"Video speed")?.close();show("Video speed",view:VideoSpeedView(urls:urls),size:NSSize(width:650,height:580));return}
        if kind == .compressVideo { windows.removeValue(forKey:"Compress video")?.close();show("Compress video",view:VideoCompressionView(urls:urls),size:NSSize(width:510,height:urls.filter {AssetKind(url:$0) == .video}.count>1 ? 440:350));return }
        if kind == .convertImage {
            let alert=NSAlert();alert.messageText="Save image as";let choices=NSPopUpButton(frame:NSRect(x:0,y:0,width:220,height:28));choices.addItems(withTitles:ImageEngine.writableFormats.map { $0.uppercased() });alert.accessoryView=choices;alert.addButton(withTitle:"Convert");alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return };convert(urls,format:(choices.titleOfSelectedItem ?? "jpg").lowercased());return
        }
        AppModel.shared.run(urls,workflow:.init(name:kind.title,steps:[.init(kind:kind)]),openMarkdown:kind == .documentMarkdown && urls.contains {AssetKind(url:$0) == .image})
    }
}
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { UtilityDelegate() }
app.delegate = delegate
app.run()
