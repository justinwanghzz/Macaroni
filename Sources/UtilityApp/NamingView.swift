import SwiftUI
import UtilityCore

struct NamingView:View {
    @ObservedObject var app=AppModel.shared
    func field(_ title:String,_ key:WritableKeyPath<OutputNaming,String>)->some View {
        HStack {Text(title).frame(width:135,alignment:.leading);TextField(title,text:Binding(get:{app.settings.naming[keyPath:key]},set:{var naming=app.settings.naming;naming[keyPath:key]=$0;app.settings.naming=naming;app.persist()})).textFieldStyle(.roundedBorder)}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Output names").font(.title2.bold())
            Text("Original name + operation. Existing files get _2, _3…").font(.caption).foregroundStyle(.secondary)
            ScrollView {VStack(spacing:10) {
                field("Compressed",\.compressed);field("Cropped",\.cropped);field("Rotated",\.rotated);field("Flipped",\.flipped);field("Edited PDF",\.edited);field("Muted",\.muted)
                field("Resize",\.resizePattern);field("Speed",\.speedPattern);field("Workflow",\.workflowPattern)
                field("Combined images",\.combinedImages);field("Combined documents",\.combinedDocuments);field("Combined pages",\.combinedPages)
            }}
            let sample=WorkflowDefinition(name:"Sample",steps:[.init(kind:.compressImage)])
            Text("Example: "+app.settings.naming.basename(input:URL(fileURLWithPath:"/Photo.jpg"),workflow:sample)+".jpg").font(.callout).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.utilityAccent.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
            Text("Resize: {width}, {height} · Speed: {speed} · Workflow: {workflow}").font(.caption).foregroundStyle(.secondary)
            Button("Restore defaults") {app.settings.naming=OutputNaming();app.persist()}.buttonStyle(ChoicePillStyle(compact:true))
        }.padding(22).utilityStyle()
    }
}
