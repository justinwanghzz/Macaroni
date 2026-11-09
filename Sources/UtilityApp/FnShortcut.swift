import AppKit
import ApplicationServices

/// Observes only the chosen chord. Ordinary letters/modifier changes pass through untouched.
@MainActor final class FnShortcut {
    var port:CFMachPort?,source:CFRunLoopSource?
    var consumedV=false
    var activate:(()->Void)?
    static func matches(keyCode:Int64,flags:CGEventFlags)->Bool {
        keyCode==9 && flags.intersection([.maskShift,.maskControl,.maskAlternate,.maskCommand,.maskSecondaryFn]) == [.maskShift,.maskSecondaryFn]
    }
    func start()->Bool {
        stop()
        guard AXIsProcessTrusted() else {return false}
        let mask=(CGEventMask(1)<<CGEventType.keyDown.rawValue)|(CGEventMask(1)<<CGEventType.keyUp.rawValue)
        let context=Unmanaged.passUnretained(self).toOpaque()
        guard let tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:{ _,type,event,context in
            guard let context else {return Unmanaged.passUnretained(event)}
            let listener=Unmanaged<FnShortcut>.fromOpaque(context).takeUnretainedValue()
            let consume=MainActor.assumeIsolated { ()->Bool in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port=listener.port {CGEvent.tapEnable(tap:port,enable:true)};return false
                }
                guard event.getIntegerValueField(.keyboardEventKeycode)==9 else {return false}
                if type == .keyUp,listener.consumedV {listener.consumedV=false;return true}
                if type == .keyDown,FnShortcut.matches(keyCode:9,flags:event.flags) {
                    if !listener.consumedV,event.getIntegerValueField(.keyboardEventAutorepeat)==0 {
                        listener.consumedV=true;DispatchQueue.main.async {listener.activate?()}
                    }
                    return true
                }
                return false
            }
            return consume ? nil:Unmanaged.passUnretained(event)
        },userInfo:context) else {return false}
        port=tap;source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
        CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes);CGEvent.tapEnable(tap:tap,enable:true);return true
    }
    func stop() {
        if let source {CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)}
        if let port {CFMachPortInvalidate(port)}
        source=nil;port=nil;consumedV=false
    }
}
