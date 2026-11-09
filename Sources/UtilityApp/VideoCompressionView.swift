import AppKit
import SwiftUI
import UtilityCore

@MainActor final class VideoCompressionModel:ObservableObject {
    let location:ExportLocation
    let inputs:[URL]
    let videos:[URL]
    let sizes:[Int64]
    @Published var percentage=100.0
    @Published var fixedMB=5.0
    @Published var fixed=false
    @Published var error=""
    init(urls:[URL]) {
        location=ExportLocation(inputs:urls,filename:"");inputs=urls;var seen=Set<URL>();videos=urls.filter {seen.insert($0).inserted}.filter {AssetKind(url:$0) == .video};sizes=videos.map(FileServices.bytes)
        fixedMB=Double(sizes.first ?? 0)/1_000_000
    }
    var reference:VideoSizeTarget { VideoSizeTarget(sourceBytes:sizes.first ?? 0,percentage:percentage) }
    var maximumMB:Double { get {fixed ? fixedMB:reference.megabytes} set {
        guard newValue.isFinite else {return}
        if fixed { fixedMB=max(0,newValue) } else {var value=reference;value.setMegabytes(max(0,newValue));percentage=value.percentage}
    } }
    var sliderValue:Double { get {fixed ? fixedMB/max(0.01,Double(sizes.first ?? 0)/1_000_000)*100:percentage} set {
        percentage=newValue;if fixed {fixedMB=reference.megabytes}
    } }
    var targets:[String:Double] { Dictionary(uniqueKeysWithValues:zip(videos,sizes).map {url,size in (url.path,fixed ? fixedMB:reference.targetMegabytes(for:size))}) }
    func run() {
        do {
            guard !videos.isEmpty else {throw UtilityError.message("No videos selected")}
            for value in targets.values {try ActionStep(kind:.compressVideo,amount:value).validate()}
            if !fixed {try reference.validate()}
            AppModel.shared.run(inputs,workflow:.init(name:"Compress video",steps:[.init(kind:.compressVideo,amount:targets.values.first ?? 5)]),videoTargets:targets,destination:location.directory)
            if AppModel.shared.busy {delegate.windows["Compress video"]?.close()}
        } catch {self.error=error.localizedDescription}
    }
}
struct VideoCompressionView:View {
    @StateObject private var model:VideoCompressionModel
    @ObservedObject var app=AppModel.shared
    init(urls:[URL]) { _model=StateObject(wrappedValue:VideoCompressionModel(urls:urls)) }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Image(systemName:"film").foregroundStyle(Color.utilityAccent);Text("Compress video").font(.title2.bold());Spacer()}
            if model.videos.count>1 {
                Picker("Target",selection:$model.fixed) {Text("Percentage of each video").tag(false);Text("Maximum per video").tag(true)}.pickerStyle(.segmented)
            }
            ScrollView {
                VStack(spacing:10) {ForEach(Array(model.videos.enumerated()),id:\.element.path) { index,url in
                    HStack {VStack(alignment:.leading,spacing:3) {Text(url.lastPathComponent).lineLimit(1);Text("Source: \(decimalMB(model.sizes[index])) MB").font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"arrow.right").foregroundStyle(.secondary);Text("\(decimalMB(Int64(max(0,min(10_000_000_000,(model.targets[url.path] ?? 0)*1_000_000))))) MB").monospacedDigit().fontWeight(.medium)}
                }}
            }.frame(height:CGFloat(min(3,max(1,model.videos.count)))*48)
            HStack {Text("Target size");Spacer();Text("\(model.sliderValue.formatted(.number.precision(.fractionLength(0...1))))% of source").monospacedDigit()}
            Slider(value:Binding(get:{max(0,model.sliderValue.isFinite ? model.sliderValue:0)},set:{model.sliderValue=$0}),in:0...max(100,model.sliderValue.isFinite ? model.sliderValue:100))
            HStack {Text("Maximum size");TextField("MB",value:Binding(get:{model.maximumMB},set:{model.maximumMB=$0}),format:.number.precision(.fractionLength(0...4))).frame(width:115);Text("MB").foregroundStyle(.secondary);Spacer()}
            if !model.error.isEmpty {Text(model.error).font(.caption).foregroundStyle(.red)}
            HStack(spacing:12) {ExportDestinationControl(location:model.location);Spacer(minLength:8);Button("Compress") {model.run()}.buttonStyle(PrimaryActionStyle()).disabled(app.busy).keyboardShortcut(.defaultAction)}
        }.padding(24).utilityStyle()
    }
    func decimalMB(_ bytes:Int64)->String { (Double(bytes)/1_000_000).formatted(.number.precision(.fractionLength(0...3))) }
}
