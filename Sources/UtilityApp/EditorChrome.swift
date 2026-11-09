import SwiftUI
import AppKit

@MainActor final class EditorChrome:ObservableObject {
    @Published var searchVisible=false
    @Published var query=""
    @Published var matchCount=0
    @Published var currentMatch=0
    @Published var searchFocus=0
    @Published var fileNames:[String]=[]
    @Published var fileIndex=0
    @Published var exporting=false
}
struct EditorToolbar:View {
    @ObservedObject var chrome:EditorChrome
    let controller:EditorController
    var body:some View {
        HStack(spacing:8) {
            Button {controller.openFile()} label:{Label("Open",systemImage:"folder")}.buttonStyle(ChoicePillStyle(compact:true))
            Button {controller.saveFile()} label:{Label("Save",systemImage:"square.and.arrow.down")}.buttonStyle(ChoicePillStyle(compact:true)).keyboardShortcut("s",modifiers:.command)
            Menu {Button("Save As…") {controller.saveAs()}} label:{Image(systemName:"ellipsis").frame(width:14)}.menuStyle(.borderlessButton).fixedSize().help("More file actions")
            if chrome.fileNames.count>1 {Picker("Document",selection:Binding(get:{chrome.fileIndex},set:{controller.filePicker.selectItem(at:$0);controller.chooseFile()})) {ForEach(Array(chrome.fileNames.enumerated()),id:\.offset) {index,name in Text(name).tag(index)}}.labelsHidden().frame(maxWidth:210)}
            Spacer(minLength:12)
            Button {controller.findText()} label:{Label("Search",systemImage:"magnifyingglass")}.buttonStyle(ChoicePillStyle(selected:chrome.searchVisible,compact:true)).help("Search · ⌘F")
            Divider().frame(height:18).padding(.horizontal,3)
            Button {controller.exportPDF()} label:{Label("Export PDF",systemImage:"square.and.arrow.up")}.buttonStyle(ChoicePillStyle(compact:true))
        }.disabled(chrome.exporting).padding(.horizontal,16).padding(.vertical,12).background(Color.utilitySurface)
    }
}
struct EditorSearchBar:View {
    @ObservedObject var chrome:EditorChrome
    let controller:EditorController
    @FocusState var focused:Bool
    var body:some View {
        HStack(spacing:10) {
            HStack(spacing:8) {
                Image(systemName:"magnifyingglass").foregroundStyle(Color.utilityAccent)
                TextField("Find in document",text:Binding(get:{chrome.query},set:{controller.updateSearch($0)})).textFieldStyle(.plain).focused($focused).onSubmit{controller.findNext()}
                if !chrome.query.isEmpty {Text(chrome.matchCount==0 ? "No matches":"\(chrome.currentMatch) of \(chrome.matchCount)").font(.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()}
            }.padding(.horizontal,11).padding(.vertical,8).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(Color.utilityAccent.opacity(0.16)))
            HStack(spacing:3) {
                Button {controller.findPrevious()} label:{Image(systemName:"chevron.up")}.help("Previous match · ⇧⌘G")
                Button {controller.findNext()} label:{Image(systemName:"chevron.down")}.help("Next match · ⌘G")
            }.buttonStyle(ChoicePillStyle(compact:true)).disabled(chrome.matchCount==0)
            Button {controller.closeSearch()} label:{Image(systemName:"xmark")}.buttonStyle(.plain).foregroundStyle(.secondary).help("Close search · Escape")
        }.padding(.horizontal,16).padding(.bottom,10).background(Color.utilitySurface)
        .onAppear{focused=true}.onChange(of:chrome.searchFocus){_,_ in focused=true}.onExitCommand{controller.closeSearch()}
    }
}
struct EditorHeader:View {
    @ObservedObject var chrome:EditorChrome
    let controller:EditorController
    var body:some View {VStack(spacing:0) {EditorToolbar(chrome:chrome,controller:controller);if chrome.searchVisible {EditorSearchBar(chrome:chrome,controller:controller)};Rectangle().fill(Color.primary.opacity(0.065)).frame(height:1)}}
}
struct EditorExportSheet:View {
    @ObservedObject var chrome:EditorChrome
    @ObservedObject var location:ExportLocation
    let controller:EditorController
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Label("Export PDF",systemImage:"doc.richtext").font(.title2.bold())
            ExportLocationView(location:location)
            HStack {Spacer();Button("Cancel") {controller.dismissExport()}.buttonStyle(ChoicePillStyle()).keyboardShortcut(.cancelAction);Button("Export PDF") {controller.performPDFExport()}.buttonStyle(PrimaryActionStyle()).keyboardShortcut(.defaultAction)}
        }.padding(24).frame(width:420).utilityStyle()
    }
}
