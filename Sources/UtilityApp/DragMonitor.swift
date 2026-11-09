import AppKit
import UtilityCore

@MainActor final class DragMonitor {
    unowned let delegate:UtilityDelegate
    var timer:Timer?,eventMonitor:Any?
    var panel:NSPanel? { panels.first }
    var panels:[NSPanel]=[]
    var animation:Timer?
    var active=false,wasDown=false
    var token=UUID(),lastCount = -1
    var downPoint=CGPoint.zero,anchor=CGPoint.zero
    var urls:[URL]=[]
    init(delegate:UtilityDelegate) { self.delegate=delegate }
    func start() {
        guard timer==nil else { return };lastCount=NSPasteboard(name:.drag).changeCount
        eventMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] _ in Task { @MainActor in self?.tick() } }
        timer=Timer(timeInterval:1/30,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } };RunLoop.main.add(timer!,forMode:.common)
    }
    func stop() { timer?.invalidate();timer=nil;if let eventMonitor { NSEvent.removeMonitor(eventMonitor) };eventMonitor=nil;active=false;wasDown=false;token=UUID();hide() }
    func hide() { animation?.invalidate();animation=nil;panels.forEach { ($0.contentView as? ActionDropView)?.hoverWork?.cancel();$0.orderOut(nil) };panels=[] }
    func tick() {
        guard !delegate.isPaused else { return }
        let down=NSEvent.pressedMouseButtons & 1 != 0
        if down && !wasDown { downPoint=NSEvent.mouseLocation };wasDown=down
        if !down {
            lastCount=NSPasteboard(name:.drag).changeCount
            if active { active=false;let t=token;DispatchQueue.main.asyncAfter(deadline:.now()+0.32) { if self.token==t { self.hide() } } };return
        }
        let pb=NSPasteboard(name:.drag),point=NSEvent.mouseLocation
        guard !active,AppModel.shared.settings.trigger.matches(NSEvent.modifierFlags),pb.changeCount != lastCount,hypot(point.x-downPoint.x,point.y-downPoint.y)>3 else { return }
        let files=(pb.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
        guard !files.isEmpty else { return };lastCount=pb.changeCount;active=true;token=UUID();present(files)
    }
    struct Choice { let title:String,symbol:String;var color:NSColor = .systemOrange;var accepts:((URL)->Bool)?=nil;let action:([URL])->Void }
    func present(_ files:[URL]) {
        guard !delegate.isPaused else { return };hide();urls=files;anchor=NSEvent.mouseLocation
        let image=files.contains { AssetKind(url:$0) == .image }
        var upper:[Choice]=[],lower:[Choice]=[Choice(title:"Shelf",symbol:"tray.and.arrow.down",color:.systemTeal,action:{AppModel.shared.stage($0)})]
        if image { for format in ImageEngine.writableFormats { upper.append(Choice(title:format == "jpg" ? "JPEG" : format.uppercased(),symbol:"photo",color:.systemBlue,accepts:{AssetKind(url:$0) == .image},action:{ self.delegate.convert($0,format:format) })) } }
        let images=files.filter {AssetKind(url:$0) == .image}
        let pdfs=files.filter {AssetKind(url:$0) == .pdf}
        if !images.isEmpty {
            upper.append(Choice(title:images.count>1 ? "Combine to PDF":"PDF",symbol:"doc.on.doc",color:.systemBlue,accepts:{AssetKind(url:$0) == .image},action:{PageOrganizer.show($0.filter {AssetKind(url:$0) == .image})}))
        }
        if !pdfs.isEmpty {
            lower.append(Choice(title:pdfs.count>1 ? "Combine PDFs":"Adjust PDF",symbol:"square.stack",accepts:{AssetKind(url:$0) == .pdf},action:{PageOrganizer.show($0.filter {AssetKind(url:$0) == .pdf})}))
        }
        let offersMarkdown:(URL)->Bool={ [.pdf,.word,.presentation,.text].contains(AssetKind(url:$0)) }
        if files.contains(where:offersMarkdown) { upper.append(Choice(title:"Markdown",symbol:"doc.text",color:.systemBlue,accepts:offersMarkdown,action:{self.delegate.action(.documentMarkdown,urls:$0.filter(offersMarkdown))})) }
        if files.contains(where:{AssetKind(url:$0) == .markdown}) {
            upper.append(Choice(title:"Live Editor",symbol:"square.and.pencil",color:.systemBlue,accepts:{AssetKind(url:$0) == .markdown},action:{ EditorController.shared.show(files:$0.filter {AssetKind(url:$0) == .markdown}) }))
        }
        if image { for kind in [ActionKind.cropImage,.compressImage,.resizeImage,.rotateImage,.flipHorizontal,.flipVertical] { lower.append(Choice(title:kind == .flipHorizontal ? "Flip H" : kind == .flipVertical ? "Flip V" : kind.title,symbol:kind.symbol,accepts:{kind.accepts(AssetKind(url:$0))},action:{self.delegate.action(kind,urls:$0)})) } }
        if files.contains(where:{AssetKind(url:$0) == .video}) { lower.append(Choice(title:"Compress video",symbol:"film",accepts:{AssetKind(url:$0) == .video},action:{self.delegate.action(.compressVideo,urls:$0)})) }
        if files.contains(where:{AssetKind(url:$0) == .video}) {
            for kind in [ActionKind.muteVideo,.speedVideo] {lower.append(Choice(title:kind.title,symbol:kind.symbol,accepts:{AssetKind(url:$0) == .video},action:{self.delegate.action(kind,urls:$0)}))}
        }
        let screen=NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main!
        let layout=RadialLayout.make(anchor:anchor,screen:screen.visibleFrame,upper:upper.count,lower:lower.count,compact:upper.count+lower.count<=3,upperColumns:image ? 4:3,preset:image)
        let choices=upper+lower+(image ? [Choice(title:"Preset",symbol:"flowchart",color:.systemPurple,accepts:{AssetKind(url:$0) == .image},action:{WorkflowController.show(inputs:$0)})]:[])
        for (i,frame) in layout.frames.enumerated() where choices.indices.contains(i) {
            let choice=choices[i]
            let p=NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.level = .popUpMenu;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            let view=ActionDropView(frame:NSRect(origin:.zero,size:frame.size),choice:choice,count:files.count) { actual in
                self.token=UUID();self.hide();guard !self.delegate.isPaused else { return };choice.action(actual)
            }
            let eligible=choice.accepts.map { predicate in files.filter(predicate).count } ?? files.count
            if eligible>0,eligible<files.count {view.badge="\(eligible)/\(files.count)";view.toolTip="\(choice.title) · \(eligible) of \(files.count) files"}
            p.contentView=view;p.orderFrontRegardless();panels.append(p)
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,!panels.isEmpty else { return }
        // Targets stay at their final coordinates throughout the entrance.
        let local=panels,start=Date.timeIntervalSinceReferenceDate
        local.forEach { $0.alphaValue=0 }
        animation=Timer(timeInterval:1/60,repeats:true) { [weak self] clock in MainActor.assumeIsolated {
            let t=min(1,(Date.timeIntervalSinceReferenceDate-start)/0.14)
            local.forEach { $0.alphaValue=t }
            if t>=1 { clock.invalidate();self?.animation=nil }
        } };RunLoop.main.add(animation!,forMode:.common)
    }
}
@MainActor final class ActionDropView:NSView {
    let choice:DragMonitor.Choice,count:Int
    let picked:([URL])->Void
    var onHover:(()->Void)?
    var hoverWork:DispatchWorkItem?
    var hovered=false
    var badge:String?
    init(frame:NSRect,choice:DragMonitor.Choice,count:Int,picked:@escaping([URL])->Void) { self.choice=choice;self.count=count;self.picked=picked;super.init(frame:frame);registerForDraggedTypes([.fileURL]);setAccessibilityElement(true);setAccessibilityRole(.button);setAccessibilityLabel(choice.title);toolTip="\(choice.title) · \(count) file\(count==1 ? "" : "s")" }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) {
        let card=bounds.insetBy(dx:2,dy:2)
        let path=NSBezierPath(roundedRect:card,xRadius:12,yRadius:12)
        let dark=effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        (dark ? NSColor(calibratedWhite:0.15,alpha:0.98) : NSColor(calibratedWhite:0.98,alpha:0.98)).setFill();path.fill()
        choice.color.withAlphaComponent(hovered ? (dark ? 0.3:0.17):(dark ? 0.1:0.055)).setFill();path.fill()
        (hovered ? choice.color : NSColor.separatorColor.withAlphaComponent(0.5)).setStroke();path.lineWidth=hovered ? 2:1;path.stroke()
        let image=NSImage(systemSymbolName:choice.symbol,accessibilityDescription:choice.title)?.withSymbolConfiguration(.init(pointSize:19,weight:.medium))?.withSymbolConfiguration(.init(paletteColors:[choice.color]))
        image?.isTemplate=false
        image?.draw(in:NSRect(x:(bounds.width-22)/2,y:30,width:22,height:22))
        if let badge { (badge as NSString).draw(at:NSPoint(x:bounds.width-30,y:bounds.height-16),withAttributes:[.font:NSFont.systemFont(ofSize:9,weight:.medium),.foregroundColor:NSColor.secondaryLabelColor]) }
        let style=NSMutableParagraphStyle();style.alignment = .center;style.lineBreakMode = .byTruncatingTail
        (choice.title as NSString).draw(in:NSRect(x:6,y:9,width:bounds.width-12,height:16),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.medium),.foregroundColor:NSColor.labelColor,.paragraphStyle:style])
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { hovered=true;needsDisplay=true;if let onHover { let work=DispatchWorkItem(block:onHover);hoverWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work) };return .copy }
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation { .copy }
    override func draggingExited(_ sender:NSDraggingInfo?) { hovered=false;hoverWork?.cancel();needsDisplay=true }
    override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool { true }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        hoverWork?.cancel();let urls=(sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false };DispatchQueue.main.async { self.picked(urls) };return true
    }
}
