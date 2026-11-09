import AppKit
import SwiftUI
import UtilityCore

@MainActor final class ImageAdjustmentModel: ObservableObject {
    let location:ExportLocation
    var onCommitStep:((ActionStep)->Void)?
    let kind:ActionKind
    let inputs:[URL]
    let urls:[URL]
    @Published var index=0
    @Published var source:CGImage?
    @Published var rotationImage:NSImage?
    @Published var preview:NSImage?
    @Published var width=1.0
    @Published var height=1.0
    @Published var locked=true
    @Published var scale=100.0
    @Published var quality=70.0
    @Published var angle=0.0
    @Published var region=CropRegion()
    @Published var ratio="Free"
    @Published var estimate:Int64?
    @Published var rendering=false
    @Published var error=""
    var originalSize=CGSize(width:1,height:1)
    var version=UUID()
    var loader:Task<Void,Never>?
    var debounce:Task<Void,Never>?
    var worker:Task<AdjustmentPreview,Error>?
    var onClose:(()->Void)?
    var fileChanged:(()->Void)?
    var closed=false
    init(kind:ActionKind,urls:[URL]) { self.location=ExportLocation(inputs:urls,filename:"");self.kind=kind;self.inputs=urls;self.urls=urls.filter {AssetKind(url:$0) == .image};load(0,reset:true) }
    var url:URL { urls[index] }
    var step:ActionStep {
        var s=ActionStep(kind:kind)
        switch kind {
        case .resizeImage:s.width=width.isFinite && (1...16000).contains(width) ? Int(width.rounded()):0;s.height=height.isFinite && (1...16000).contains(height) ? Int(height.rounded()):0;s.aspectLocked=locked
        case .compressImage:s.amount=quality
        case .rotateImage:s.amount=angle
        case .cropImage:s.crop=region
        default:break
        }
        return s
    }
    func load(_ index:Int,reset:Bool=false) {
        guard urls.indices.contains(index) else { return };self.index=index;fileChanged?();source=nil;preview=nil;error="";loader?.cancel();cancelPreview()
        let url=self.url
        loader=Task {
            do {
                let loaded=try await Task.detached { let lease=AccessLease(urls:[url]);defer { _=lease };return try ImageEngine.load(url) }.value
                guard !Task.isCancelled,!closed else { return }
                source=loaded;rotationImage=NSImage(cgImage:loaded,size:CGSize(width:loaded.width,height:loaded.height));originalSize=CGSize(width:loaded.width,height:loaded.height)
                if reset { width=Double(loaded.width);height=Double(loaded.height);region=CropRegion();ratio="Free";scale=100 }
                refresh()
            } catch { self.error=error.localizedDescription }
        }
    }
    func cancelPreview() { debounce?.cancel();worker?.cancel();version=UUID();rendering=false }
    func close() { guard !closed else { return };closed=true;loader?.cancel();cancelPreview();onClose?() }
    func changeWidth(_ v:Double) { width=v; if locked { height=(v*originalSize.height/originalSize.width).rounded() };synchronizeScale();refresh() }
    func changeHeight(_ v:Double) { height=v; if locked { width=(v*originalSize.width/originalSize.height).rounded() };synchronizeScale();refresh() }
    func synchronizeScale() { scale=width.isFinite && width>0 && width<=16000 ? width/originalSize.width*100 : 100;scaleBase=nil }
    var scaleBase:CGSize?
    func setScale(_ value:Double) {
        if scaleBase == nil { scaleBase=CGSize(width:width/max(0.01,scale/100),height:height/max(0.01,scale/100)) }
        scale=value;width=max(1,(scaleBase!.width*value/100).rounded());height=max(1,(scaleBase!.height*value/100).rounded());refresh()
    }
    func setRatio(_ value:String) {
        ratio=value
        guard value != "Free" else { return }
        let bits=value.split(separator:":").compactMap { Double($0) };guard bits.count==2 else { return }
        let aspect=bits[0]/bits[1];var w=originalSize.width;var h=w/aspect
        if h > originalSize.height { h=originalSize.height;w=h*aspect }
        region=CropRegion(x:(1-w/originalSize.width)/2,y:(1-h/originalSize.height)/2,width:w/originalSize.width,height:h/originalSize.height)
    }
    func refresh() {
        guard source != nil,!closed else { return }
        debounce?.cancel();worker?.cancel();let token=UUID();version=token;rendering=true;estimate=nil;error=""
        if kind == .cropImage { rendering=false;return }
        if kind == .rotateImage { rendering=false;if !angle.isFinite || abs(angle)>360 {error="Enter an angle from −360° to 360°"};return }
        let url=self.url,s=self.step,kind=self.kind
        debounce=Task {
            do {
                try await Task.sleep(nanoseconds:180_000_000);try Task.checkCancellation()
                let job=Task.detached { () throws -> AdjustmentPreview in
                    let lease=AccessLease(urls:[url]);defer { _=lease }
                    if kind == .compressImage {
                        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("utility-preview-"+UUID().uuidString)
                        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer { try? FileManager.default.removeItem(at:folder) }
                        let out=try ImageEngine.apply(s,input:url,directory:folder,name:"preview")
                        return AdjustmentPreview(image:try ImageEngine.load(out,maximumSide:1400),bytes:FileServices.bytes(out))
                    }
                    let image=try ImageEngine.load(url,maximumSide:1400);var adjusted=s
                    if kind == .resizeImage,let w=s.width,let h=s.height { let factor=min(1,1400/Double(max(w,h)));adjusted.width=max(1,Int(Double(w)*factor));adjusted.height=max(1,Int(Double(h)*factor)) }
                    var result=try ImageEngine.transformed(adjusted,image:image)
                    if ["jpg","jpeg"].contains(url.pathExtension.lowercased()) { result=try ImageEngine.flattenForJPEG(result) }
                    return AdjustmentPreview(image:result,bytes:nil)
                }
                worker=job;let result=try await job.value
                guard version==token,!closed,!Task.isCancelled else { return }
                preview=NSImage(cgImage:result.image,size:CGSize(width:result.image.width,height:result.image.height));estimate=result.bytes;rendering=false
            } catch is CancellationError {} catch { if version==token { self.error=error.localizedDescription;rendering=false } }
        }
    }
    func apply() {
        do { try step.validate() } catch { self.error=error.localizedDescription;return }
        if let onCommitStep {onCommitStep(step);close();return}
        guard !AppModel.shared.busy else { return }
        let crop=kind == .cropImage
        AppModel.shared.run(crop ? [url] + (index==0 ? inputs.filter {AssetKind(url:$0) != .image}:[]) : inputs,workflow:.init(name:kind.title,steps:[step]),reveal:!crop || index+1==urls.count,destination:location.directory)
        guard AppModel.shared.busy else { return }
        if crop,index+1<urls.count {
            Task { while AppModel.shared.busy { try? await Task.sleep(nanoseconds:100_000_000) };guard !closed else { return };load(index+1,reset:true) }
        } else { close() }
    }
}
struct AdjustmentPreview: @unchecked Sendable { let image:CGImage;let bytes:Int64? }

@MainActor final class ImageAdjustmentController:NSObject,NSWindowDelegate {
    static let shared=ImageAdjustmentController()
    var windows:[UUID:NSWindow]=[:]
    var models:[UUID:ImageAdjustmentModel]=[:]
    func show(_ kind:ActionKind,urls:[URL],onCommit:((ActionStep)->Void)?=nil,onDismiss:(()->Void)?=nil) {
        let images=urls.filter { AssetKind(url:$0) == .image };guard !images.isEmpty else { return }
        let id=UUID();let model=ImageAdjustmentModel(kind:kind,urls:urls);model.onCommitStep=onCommit
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:740),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="\(kind.title) · \(images[0].lastPathComponent)";window.isReleasedWhenClosed=false;window.delegate=self;window.minSize=NSSize(width:720,height:580)
        window.contentView=NSHostingView(rootView:ImageAdjustmentView(model:model));window.center();windows[id]=window;models[id]=model
        model.fileChanged={ [weak window,weak model] in if let model { window?.title="\(kind.title) · \(model.url.lastPathComponent)" } }
        model.onClose={ [weak self,weak window] in self?.models.removeValue(forKey:id);if let window { self?.windows.removeValue(forKey:id);window.close() };onDismiss?() }
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func windowWillClose(_ notification:Notification) { if let w=notification.object as? NSWindow,let key=windows.first(where: { $0.value === w })?.key { models[key]?.close() } }
}
struct ImageAdjustmentView:View {
    @ObservedObject var model:ImageAdjustmentModel
    @ObservedObject var app=AppModel.shared
    var body:some View {
        VStack(spacing:16) {
            HStack { Text(model.kind.title).font(.title2.bold());Text(model.url.lastPathComponent).foregroundStyle(.secondary).lineLimit(1);Spacer();if model.urls.count>1 { Button { model.load(model.index-1) } label: { Image(systemName:"chevron.left") }.disabled(model.index==0 || model.kind == .cropImage);Text("\(model.index+1) / \(model.urls.count)").monospacedDigit();Button { model.load(model.index+1) } label: { Image(systemName:"chevron.right") }.disabled(model.index+1==model.urls.count || model.kind == .cropImage) } }
            ZStack {
                RoundedRectangle(cornerRadius:18).fill(Color.black.opacity(0.82))
                if let source=model.source {
                    if model.kind == .cropImage { CropCanvas(image:source,region:$model.region,ratio:model.ratio).padding(20) }
                    else if model.kind == .rotateImage,let image=model.rotationImage {
                        RotationPreview(image:image,size:model.originalSize,angle:model.angle,whiteCanvas:["jpg","jpeg"].contains(model.url.pathExtension.lowercased())).padding(20)
                    }
                    else if let preview=model.preview { Image(nsImage:preview).resizable().scaledToFit().padding(20) }
                    else { Image(nsImage:NSImage(cgImage:source,size:.zero)).resizable().scaledToFit().padding(20).opacity(0.65) }
                }
                if model.source == nil { ProgressView().tint(.white) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            controls
            if !model.error.isEmpty {Text(model.error).foregroundStyle(.red).font(.callout).frame(maxWidth:.infinity,alignment:.leading)}
            HStack(spacing:12) {
                if model.onCommitStep == nil {ExportDestinationControl(location:model.location)}
                Spacer(minLength:8);Button("Cancel") { model.close() }.buttonStyle(ChoicePillStyle()).keyboardShortcut(.cancelAction)
                Button(model.onCommitStep != nil ? "Use crop" : model.kind == .cropImage ? "Crop" : model.kind == .compressImage ? "Compress" : "Apply") { model.apply() }.buttonStyle(PrimaryActionStyle()).keyboardShortcut(.defaultAction).disabled(model.source==nil || app.busy || !model.error.isEmpty)
            }
        }.padding(22).utilityStyle()
    }
    @ViewBuilder var controls:some View {
        switch model.kind {
        case .cropImage:
            HStack { ForEach(["Free","1:1","4:3","3:2","16:9","9:16"],id:\.self) { ratio in Button(ratio) { model.setRatio(ratio) }.buttonStyle(ChoicePillStyle(selected:model.ratio==ratio)) };Spacer();Text("\(Int((model.region.width*model.originalSize.width).rounded())) × \(Int((model.region.height*model.originalSize.height).rounded())) px").monospacedDigit().foregroundStyle(.secondary) }
        case .resizeImage:
            VStack(spacing:12) {
                HStack { Text("Width");TextField("Width",value:Binding(get:{model.width},set:{model.scaleBase=nil;model.changeWidth($0)}),format:.number.precision(.fractionLength(0))).frame(width:95);Text("px").foregroundStyle(.secondary)
                    Button { model.locked.toggle();model.scaleBase=nil;if model.locked { model.changeWidth(model.width) } } label: { Image(systemName:model.locked ? "lock.fill" : "lock.open") }.help("Lock proportions")
                    Text("Height");TextField("Height",value:Binding(get:{model.height},set:{model.scaleBase=nil;model.changeHeight($0)}),format:.number.precision(.fractionLength(0))).frame(width:95);Text("px").foregroundStyle(.secondary);Spacer() }
                HStack { Text("Size");Slider(value:Binding(get:{model.scale},set:{model.setScale($0)}),in:1...200);Text("\(Int(model.scale))%").monospacedDigit().frame(width:48) }
            }
        case .compressImage:
            VStack(spacing:10) { HStack { Text("Smaller");Slider(value:$model.quality,in:1...100).onChange(of:model.quality) { _,_ in model.refresh() };Text("Sharper") }
                HStack { Text(FileServices.sizeLabel(model.url));Image(systemName:"arrow.right");if let estimate=model.estimate { Text(ByteCountFormatter.string(fromByteCount:estimate,countStyle:.file)).fontWeight(.semibold);let original=FileServices.bytes(model.url);if estimate<original { Text("\(Int((1-Double(estimate)/Double(max(1,original)))*100))% smaller").foregroundStyle(.secondary) } else { Text("No reduction").foregroundStyle(.secondary) } } else { ProgressView().controlSize(.small);Text("Calculating size…").foregroundStyle(.secondary) };Spacer() }
            }
        case .rotateImage:
            VStack(spacing:12) { HStack { ForEach([90.0,180,270],id:\.self) { value in
                    Button {model.angle=value;model.refresh()} label: {
                        VStack(spacing:5) { Image(systemName:"rectangle.portrait.tophalf.filled").font(.system(size:24)).rotationEffect(.degrees(value));Text("\(Int(value))°").font(.system(size:12,weight:.semibold)) }.frame(width:76,height:58)
                    }.buttonStyle(ChoicePillStyle(selected:model.angle==value))
                };Button {model.angle=0;model.refresh()} label:{VStack(spacing:5) {Image(systemName:"arrow.counterclockwise").font(.system(size:24));Text("Reset").font(.system(size:12,weight:.semibold))}.frame(width:76,height:58)}.buttonStyle(ChoicePillStyle(selected:model.angle==0));Spacer();TextField("Angle",value:$model.angle,format:.number.precision(.fractionLength(0...1))).frame(width:70).onChange(of:model.angle) { _,_ in model.refresh() };Text("°") };Slider(value:$model.angle,in:-360...360).onChange(of:model.angle) { _,_ in model.refresh() } }
        default:EmptyView()
        }
    }
}

struct CropCanvas:NSViewRepresentable {
    let image:CGImage
    @Binding var region:CropRegion
    var ratio:String
    func makeNSView(context:Context)->CropSelectionView { CropSelectionView() }
    func updateNSView(_ view:CropSelectionView,context:Context) { view.image=image;view.region=region;view.ratio=ratio;view.changed={region=$0};view.needsDisplay=true }
}
final class CropSelectionView:NSView {
    override var isFlipped:Bool { true }
    var image:CGImage?
    var region=CropRegion()
    var ratio="Free"
    var changed:((CropRegion)->Void)?
    var start=CGPoint.zero
    var initial=CropRegion()
    var mode=0
    var imageRect:CGRect {
        guard let image else { return .zero };let scale=min(bounds.width/CGFloat(image.width),bounds.height/CGFloat(image.height));let size=CGSize(width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale);return CGRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height)
    }
    var selection:CGRect { let r=imageRect;return CGRect(x:r.minX+region.x*r.width,y:r.minY+region.y*r.height,width:region.width*r.width,height:region.height*r.height) }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.crosshair) }
    override func draw(_ dirtyRect:NSRect) {
        guard let image else { return };let r=imageRect
        NSImage(cgImage:image,size:CGSize(width:image.width,height:image.height)).draw(in:r,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        let s=selection;let shade=NSBezierPath(rect:r);shade.append(NSBezierPath(rect:s));shade.windingRule = .evenOdd;NSColor.black.withAlphaComponent(0.5).setFill();shade.fill()
        NSColor.white.setStroke();let border=NSBezierPath(rect:s);border.lineWidth=1.5;border.stroke()
        let grid=NSBezierPath();for n in 1...2 { let x=s.minX+s.width*CGFloat(n)/3;grid.move(to:CGPoint(x:x,y:s.minY));grid.line(to:CGPoint(x:x,y:s.maxY));let y=s.minY+s.height*CGFloat(n)/3;grid.move(to:CGPoint(x:s.minX,y:y));grid.line(to:CGPoint(x:s.maxX,y:y)) };grid.lineWidth=0.5;grid.stroke()
        for p in [CGPoint(x:s.minX,y:s.minY),CGPoint(x:s.maxX,y:s.minY),CGPoint(x:s.minX,y:s.maxY),CGPoint(x:s.maxX,y:s.maxY)] { NSColor.white.setFill();NSBezierPath(roundedRect:CGRect(x:p.x-5,y:p.y-5,width:10,height:10),xRadius:3,yRadius:3).fill() }
    }
    override func mouseDown(with event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil);guard imageRect.contains(p) else { return };start=p;initial=region
        let s=selection;let corners=[CGPoint(x:s.minX,y:s.minY),CGPoint(x:s.maxX,y:s.minY),CGPoint(x:s.minX,y:s.maxY),CGPoint(x:s.maxX,y:s.maxY)]
        if let i=corners.firstIndex(where:{hypot($0.x-p.x,$0.y-p.y)<16}) { mode=i+2 }
        else { mode = s.contains(p) && region.width<0.999 && region.height<0.999 ? 1 : 0 }
    }
    override func mouseDragged(with event:NSEvent) {
        let r=imageRect;guard r.width>0,r.height>0 else { return };let p=convert(event.locationInWindow,from:nil);var next=initial
        if mode==1 { next.x=max(0,min(1-initial.width,initial.x+(p.x-start.x)/r.width));next.y=max(0,min(1-initial.height,initial.y+(p.y-start.y)/r.height)) }
        else {
            let corner:CGPoint
            if mode>=2 { let s=CGRect(x:initial.x,y:initial.y,width:initial.width,height:initial.height);corner = CGPoint(x:[2,4].contains(mode) ? s.maxX : s.minX,y:[2,3].contains(mode) ? s.maxY : s.minY) }
            else { corner=CGPoint(x:(start.x-r.minX)/r.width,y:(start.y-r.minY)/r.height) }
            var x=max(0,min(1,(p.x-r.minX)/r.width)),y=max(0,min(1,(p.y-r.minY)/r.height))
            let parts=ratio.split(separator:":").compactMap { Double($0) }
            if parts.count==2 {
                let normalized=(parts[0]/parts[1])*r.height/r.width
                let dx=x-corner.x,dy=y-corner.y
                let w=min(abs(dx),abs(dy)*normalized),h=w/normalized
                x=corner.x+(dx<0 ? -w:w);y=corner.y+(dy<0 ? -h:h)
            }
            next=CropRegion(x:min(corner.x,x),y:min(corner.y,y),width:max(1/Double(image?.width ?? 1),abs(x-corner.x)),height:max(1/Double(image?.height ?? 1),abs(y-corner.y)))
            next.width=min(next.width,1-next.x);next.height=min(next.height,1-next.y)
        }
        guard next.isValid else { return };region=next;changed?(next);needsDisplay=true
    }
}

struct RotationPreview:View {
    let image:NSImage,size:CGSize,angle:Double,whiteCanvas:Bool
    var body:some View {
        GeometryReader { proxy in
            let radians=(angle.isFinite ? angle:0) * .pi/180
            let w=abs(cos(radians))*size.width+abs(sin(radians))*size.height
            let h=abs(sin(radians))*size.width+abs(cos(radians))*size.height
            let scale=min(proxy.size.width/max(1,w),proxy.size.height/max(1,h))
            ZStack {
                if whiteCanvas {Rectangle().fill(.white).frame(width:w*scale,height:h*scale)}
                Image(nsImage:image).resizable().frame(width:size.width*scale,height:size.height*scale).rotationEffect(.degrees(angle.isFinite ? angle:0))
            }.frame(width:proxy.size.width,height:proxy.size.height)
        }
    }
}
