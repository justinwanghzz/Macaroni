import AppKit
import SwiftUI
import UtilityCore

/// Explicit developer-only desktop review; keeps its data separate and restores the prior clipboard on exit.
@MainActor final class ClipboardReview {
    static let shared=ClipboardReview()
    var previous:[[NSPasteboard.PasteboardType:Data]]=[]
    var root:URL!
    var enabled=false
    func start() {
        guard let directory=ProcessInfo.processInfo.environment["UTILITY_DATA_HOME"],let fixtures=ProcessInfo.processInfo.environment["UTILITY_FIXTURES"] else {return}
        previous=(NSPasteboard.general.pasteboardItems ?? []).map {item in Dictionary(uniqueKeysWithValues:item.types.compactMap {type in item.data(forType:type).map {(type,$0)}})}
        enabled=true;root=URL(fileURLWithPath:directory).appendingPathComponent("Desktop-review")
        do {
            for name in ["Source","Destination"] {try FileManager.default.createDirectory(at:root.appendingPathComponent(name),withIntermediateDirectories:true)}
            for name in ["Large-photo.jpg","Transparent.png"] {try FileManager.default.copyItem(at:URL(fileURLWithPath:fixtures).appendingPathComponent(name),to:root.appendingPathComponent("Source/"+name))}
            try Data("UTILITY clipboard file fixture".utf8).write(to:root.appendingPathComponent("Source/Notes.txt"))
        } catch {AppModel.shared.showError(error)}
        AppModel.shared.settings.historyShortcut="controlShiftV";ClipboardController.shared.registerShortcut()
        delegate.show("Desktop clipboard review",view:ClipboardReviewView(),size:NSSize(width:620,height:260))
    }
    func restore() {
        guard enabled else {return};AppModel.shared.recording=false;NSPasteboard.general.clearContents()
        let items=previous.map {values -> NSPasteboardItem in let item=NSPasteboardItem();for (type,data) in values {item.setData(data,forType:type)};return item}
        if !items.isEmpty {NSPasteboard.general.writeObjects(items)}
        previous=[];enabled=false
    }
    func copyText() {NSPasteboard.general.clearContents();NSPasteboard.general.setString("UTILITY newer text fixture",forType:.string);AppModel.shared.pollClipboard()}
    func copyImage() {
        do {let bytes=try Data(contentsOf:root.appendingPathComponent("Source/Transparent.png"));NSPasteboard.general.clearContents();NSPasteboard.general.setData(bytes,forType:.png);AppModel.shared.pollClipboard()}
        catch {AppModel.shared.showError(error)}
    }
}
struct ClipboardReviewView:View {
    @ObservedObject var model=AppModel.shared
    var body:some View {
        VStack(spacing:16) {
            Text("Disposable clipboard review").font(.title2)
            HStack {Button("Open source") {NSWorkspace.shared.open(ClipboardReview.shared.root.appendingPathComponent("Source"))};Button("Open destination") {NSWorkspace.shared.open(ClipboardReview.shared.root.appendingPathComponent("Destination"))};Button("Copy test text") {ClipboardReview.shared.copyText()};Button("Copy test image") {ClipboardReview.shared.copyImage()}}
            HStack {Button("Clipboard") {delegate.clipboard()};Button("Quit and restore clipboard") {NSApp.terminate(nil)}}
            Text("\(model.clips.count) isolated entries · Control–Shift–V for this review").font(.caption).foregroundStyle(.secondary)
        }.padding(22).utilityStyle()
    }
}
