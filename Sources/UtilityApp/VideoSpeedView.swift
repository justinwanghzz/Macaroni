import SwiftUI
import AVKit
import UtilityCore

@MainActor final class VideoSpeedModel:ObservableObject {
    let inputs:[URL],player:AVPlayer,location:ExportLocation
    @Published var selectedIndex=0 {didSet {selectVideo()}}
    @Published var speeds:[String:Double]=[:]
    @Published var error=""
    var speed:Double {
        get {inputs.indices.contains(selectedIndex) ? speeds[inputs[selectedIndex].path] ?? 1:1}
        set {guard inputs.indices.contains(selectedIndex) else {return};speeds[inputs[selectedIndex].path]=newValue;applyPreviewRate()}
    }
    init(urls:[URL]) {
        var seen=Set<URL>();inputs=urls.filter{AssetKind(url:$0) == .video && seen.insert($0).inserted}
        location=ExportLocation(inputs:inputs,filename:"");player=inputs.first.map{AVPlayer(url:$0)} ?? AVPlayer();player.currentItem?.audioTimePitchAlgorithm = .spectral
    }
    func selectVideo() {
        guard inputs.indices.contains(selectedIndex) else {return}
        let playing=player.rate != 0;player.pause();let item=AVPlayerItem(url:inputs[selectedIndex]);item.audioTimePitchAlgorithm = .spectral;player.replaceCurrentItem(with:item);player.defaultRate=Float(speed);if playing {player.playImmediately(atRate:Float(speed))}
    }
    func applyPreviewRate() {player.defaultRate=Float(speed);if player.rate != 0 {player.rate=Float(speed)}}
    func applyToAll() {let value=speed;for url in inputs {speeds[url.path]=value}}
    var exportSpeeds:[String:Double] {Dictionary(uniqueKeysWithValues:inputs.map{($0.path,speeds[$0.path] ?? 1)})}
    func run() {
        do {
            for value in exportSpeeds.values {try ActionStep(kind:.speedVideo,amount:value).validate()}
            player.pause();AppModel.shared.run(inputs,workflow:.init(name:"Video speed",steps:[.init(kind:.speedVideo,amount:speed)]),destination:location.directory,videoSpeeds:exportSpeeds)
            if AppModel.shared.busy {delegate.windows["Video speed"]?.close()}
        } catch {self.error=error.localizedDescription}
    }

}
struct NativeVideoPlayer:NSViewRepresentable {
    let player:AVPlayer
    func makeNSView(context:Context)->AVPlayerView {let view=AVPlayerView();view.player=player;view.controlsStyle = .inline;view.showsFullScreenToggleButton=false;return view}
    func updateNSView(_ view:AVPlayerView,context:Context) {}
}
struct VideoSpeedView:View {
    @StateObject var model:VideoSpeedModel
    @ObservedObject var app=AppModel.shared
    init(urls:[URL]) {_model=StateObject(wrappedValue:VideoSpeedModel(urls:urls))}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Text("Video speed").font(.title2.bold());Spacer();if model.inputs.count>1 {Text("\(model.selectedIndex+1) / \(model.inputs.count)").font(.caption).foregroundStyle(.secondary)}}
            if model.inputs.count>1 {
                Picker("Preview",selection:$model.selectedIndex) {ForEach(Array(model.inputs.enumerated()),id:\.offset) {index,url in Text(url.lastPathComponent).tag(index)}}
            } else if let input=model.inputs.first {Text(input.lastPathComponent).font(.callout).foregroundStyle(.secondary).lineLimit(1)}
            NativeVideoPlayer(player:model.player).frame(minHeight:260).clipShape(RoundedRectangle(cornerRadius:12))
            HStack {Text("Speed");Slider(value:Binding(get:{model.speed},set:{model.speed=$0}),in:0.25...3,step:0.05);Text("\(OutputNaming.number(model.speed))×").monospacedDigit().frame(width:55)}
            HStack {ForEach([0.25,0.5,1,1.5,2,3],id:\.self) {s in Button("\(OutputNaming.number(s))×") {model.speed=s}.buttonStyle(ChoicePillStyle(selected:model.speed==s,compact:true))}}
            if model.inputs.count>1 {HStack {Spacer();Button("Apply this speed to all") {model.applyToAll()}.buttonStyle(ChoicePillStyle(compact:true))}}
            if !model.error.isEmpty {Text(model.error).font(.caption).foregroundStyle(.red)}
            HStack(spacing:12) {ExportDestinationControl(location:model.location);Spacer(minLength:8);Button(model.inputs.count>1 ? "Export \(model.inputs.count) videos":"Export video") {model.run()}.buttonStyle(PrimaryActionStyle()).disabled(app.busy || model.inputs.isEmpty)}
        }.padding(22).utilityStyle().onDisappear{model.player.pause()}
    }
}
