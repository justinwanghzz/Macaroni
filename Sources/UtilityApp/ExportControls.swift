import AppKit
import SwiftUI
import UtilityCore

@MainActor final class ExportLocation:ObservableObject {
    @Published var directory:URL
    @Published var filename:String
    var lease:AccessLease?
    init(inputs:[URL],filename:String) {
        directory=inputs.first?.deletingLastPathComponent() ?? FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        self.filename=filename
    }
    func choose() {
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.directoryURL=directory;panel.prompt="Export here"
        if panel.runModal() == .OK,let url=panel.url {directory=url;lease=AccessLease(urls:[url])}
    }
}
struct ExportLocationView:View {
    @ObservedObject var location:ExportLocation
    var showsName=true
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if showsName {HStack {Text("Name").foregroundStyle(.secondary);TextField("Filename",text:$location.filename).textFieldStyle(.roundedBorder)}}
            HStack(spacing:10) {
                Image(systemName:"folder.fill").foregroundStyle(Color.utilityAccent)
                VStack(alignment:.leading,spacing:2) {Text("Export to").font(.caption2).foregroundStyle(.secondary);Text(location.directory.lastPathComponent.isEmpty ? "Current folder":location.directory.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)}.help(location.directory.path)
                Spacer(minLength:8)
                Button("Change…") {location.choose()}.buttonStyle(ChoicePillStyle(compact:true)).help("Choose a different export folder")
            }

        }.padding(10).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
    }
}
struct ExportFilenameField:View {
    @ObservedObject var location:ExportLocation
    var body:some View {HStack {Text("Name").font(.caption).foregroundStyle(.secondary);TextField("Filename",text:$location.filename).textFieldStyle(.roundedBorder)}}
}
/// A single-line destination control for action footers; the editor keeps its export sheet.
struct ExportDestinationControl:View {
    @ObservedObject var location:ExportLocation
    var body:some View {
        HStack(spacing:7) {
            Image(systemName:"folder").foregroundStyle(Color.utilityAccent)
            Text("Export to").font(.caption).foregroundStyle(.secondary).fixedSize()
            Text(location.directory.lastPathComponent.isEmpty ? "Current folder":location.directory.lastPathComponent)
                .font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                .help(location.directory.path)
            Button("Change…") {location.choose()}.buttonStyle(ChoicePillStyle(compact:true)).fixedSize().help("Choose a different export folder")
        }.frame(maxWidth:330,alignment:.leading)
    }
}
struct SoftChoice<Value:Hashable>:View {
    let values:[(Value,String)]
    @Binding var selection:Value
    var body:some View {HStack(spacing:5) {ForEach(values,id:\.0) {value,title in Button(title) {selection=value}.buttonStyle(SoftChoiceStyle(selected:selection==value))}}.padding(4).background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:12))}
}

struct SoftChoiceStyle:ButtonStyle {
    var selected=false
    func makeBody(configuration:Configuration)->some View {configuration.label.font(.system(size:12,weight:.medium)).padding(.horizontal,13).padding(.vertical,7).foregroundStyle(selected ? Color.utilityAccent:Color.secondary).background(selected ? Color.utilityAccent.opacity(configuration.isPressed ? 0.19:0.11):Color.clear,in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(selected ? Color.utilityAccent.opacity(0.12):Color.clear))}
}
