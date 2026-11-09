import AppKit
import Quartz
import UtilityCore

@MainActor final class PreviewController {
    static let shared = PreviewController()
    var window: NSWindow?
    var lease: AccessLease?
    func show(_ url: URL) {
        lease = AccessLease(urls: [url])
        if window == nil {
            window = NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:650),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window?.isReleasedWhenClosed = false; window?.center()
        }
        let preview = QLPreviewView(frame:NSRect(x:0,y:0,width:700,height:650),style:.normal)!
        preview.autostarts = true; preview.previewItem = url as NSURL
        window?.title = url.lastPathComponent; window?.contentView = preview
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
}
