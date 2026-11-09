import AppKit
import SwiftUI
import WebKit
import PDFKit
import AVFoundation
import UtilityCore

/// Deterministic integration check of this application's own controls and local renderer.
/// Never reads or writes the user's general pasteboard; use UTILITY_DATA_HOME to isolate storage.
@MainActor enum SmokeRunner {
    static func run(_ delegate: UtilityDelegate) async {
        guard let directory = ProcessInfo.processInfo.environment["UTILITY_DATA_HOME"], let fixturePath = ProcessInfo.processInfo.environment["UTILITY_FIXTURES"] else { exit(2) }
        let home = URL(fileURLWithPath:directory)
        let fixtures = home.appendingPathComponent("Inputs")
        var report: [String:Any] = [:]
        do {
            try FileManager.default.createDirectory(at:home,withIntermediateDirectories:true)
            try FileManager.default.copyItem(at:URL(fileURLWithPath:fixturePath),to:fixtures)
            let model = AppModel.shared
            guard model.recording,model.settings.recordsClipboard else {throw UtilityError.message("Clipboard did not default to active")}
            model.setRecording(false)
            guard JSONStore.load(UtilitySettings.self,from:home.appendingPathComponent("settings.json"))?.recordsClipboard == false else {throw UtilityError.message("Clipboard Pause preference did not persist")}
            model.setRecording(true)
            report["clipboardDefaultAndPersistentPause"]=true
            let legacy=try JSONDecoder().decode(UtilitySettings.self,from:Data("{\"trigger\":\"shift\",\"shelfWidth\":126,\"shelfHeight\":440,\"moveFiles\":false}".utf8))
            guard legacy.recordsClipboard,!legacy.clearAfterCopy,legacy.historyShortcut=="optionShiftV",legacy.shelfList,legacy.naming==OutputNaming() else {throw UtilityError.message("Legacy settings migration failed")}

            guard FnShortcut.matches(keyCode:9,flags:[.maskSecondaryFn,.maskShift]),!FnShortcut.matches(keyCode:9,flags:[.maskShift]),!FnShortcut.matches(keyCode:9,flags:[.maskShift,.maskSecondaryFn,.maskCommand]) else {throw UtilityError.message("Fn chord filtering failed")}
            report["fnShiftVExactChord"]=true
            var oldFn=legacy;oldFn.clipboardShortcut="fnShiftV"
            guard oldFn.historyShortcut=="optionShiftV" else {throw UtilityError.message("Fn shortcut migration failed")}
            oldFn.historyShortcut="controlShiftV"
            guard oldFn.historyShortcut=="controlShiftV" else {throw UtilityError.message("Custom shortcut changed unexpectedly")}
            report["optionShiftVDefaultAndFnMigration"]=true

            model.stage([fixtures.appendingPathComponent("Large-photo.jpg"),fixtures.appendingPathComponent("Brief.docx")])
            guard model.shelf.count == 2 else { throw UtilityError.message("Shelf did not retain references") }
            delegate.shelf()
            if let panel=ShelfController.shared.panel {
                let originalFrame=panel.frame
                guard model.settings.shelfList,abs(originalFrame.height-(panel.screen?.visibleFrame.height ?? originalFrame.height/0.6)*0.6)<2 else {throw UtilityError.message("Shelf adaptive List default failed")}

                model.selected=Set(model.shelf.prefix(1).map(\.id))
                for (name,width,appearance) in [("shelf-narrow",126.0,NSAppearance.Name.aqua),("shelf-wide",190.0,NSAppearance.Name.aqua),("shelf-dark",126.0,NSAppearance.Name.darkAqua)] {
                    panel.appearance=NSAppearance(named:appearance)
                    panel.setFrame(NSRect(x:originalFrame.minX,y:originalFrame.minY,width:width,height:440),display:true)
                    try await Task.sleep(nanoseconds:250_000_000)
                    guard let view=panel.contentView else {throw UtilityError.message("Shelf content unavailable")}
                    view.layoutSubtreeIfNeeded()
                    func shelfTable(in v:NSView)->NSTableView? {
                        if let table=v as? NSTableView {return table}
                        return v.subviews.lazy.compactMap {shelfTable(in:$0)}.first
                    }
                    if let table=shelfTable(in:view),let clip=table.enclosingScrollView?.contentView {
                        guard table.frame.width<=clip.bounds.width+1,table.tableColumns.first!.width<=clip.bounds.width+1 else {throw UtilityError.message("Shelf files exceeded the visible column")}
                    }
                    guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {throw UtilityError.message("Shelf snapshot unavailable")}
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    try bitmap.representation(using:.png,properties:[:])?.write(to:home.appendingPathComponent(name+".png"))
                }
                panel.appearance=nil;panel.setFrame(originalFrame,display:true);model.selected=[]
                report["shelfAppearanceSnapshots"]=true
            }
            delegate.clipboard(); delegate.workflows()
            ShelfController.shared.panel?.orderOut(nil)
            delegate.monitor.present([fixtures.appendingPathComponent("Large-photo.jpg")])
            guard ShelfController.shared.panel?.isVisible != true,delegate.monitor.panels.count>=8 else { throw UtilityError.message("Palette opened shelf or omitted image actions") }
            let expectedImage=ImageEngine.writableFormats.map {$0=="jpg" ? "JPEG":$0.uppercased()}+["PDF","Shelf","Crop","Compress","Resize","Rotate","Flip H","Flip V","Preset"]
            let imageNames=delegate.monitor.panels.compactMap {($0.contentView as? ActionDropView)?.choice.title}
            guard imageNames==expectedImage,let shelfIndex=imageNames.firstIndex(of:"Shelf") else {throw UtilityError.message("Incorrect image menu: \(imageNames)")}
            let shelfFrame=delegate.monitor.panels[shelfIndex].frame
            let formats=Array(delegate.monitor.panels.prefix(shelfIndex)).map(\.frame)
            guard formats.allSatisfy({$0.minY>shelfFrame.maxY}),abs(shelfFrame.midX-(formats[2].midX+formats[3].midX)/2)<0.01 else {throw UtilityError.message("Shelf was not below and centered between HEIC and PDF")}
            try snapshotPalette(delegate.monitor,to:home.appendingPathComponent("action-palette.png"))
            report["imageMenuWithPreset"]=true
            delegate.monitor.hide();delegate.shelf()
            report["explicitCompactShelfAndRadialMenu"] = true
            for (file,expected) in [("Notes.md",["Live Editor","Shelf"]),("Color-motion.mp4",["Shelf","Compress video","Mute video","Video speed"]),("Brief.docx",["Markdown","Shelf"])] {
                delegate.monitor.present([fixtures.appendingPathComponent(file)])
                let names=delegate.monitor.panels.compactMap {($0.contentView as? ActionDropView)?.choice.title}
                guard names==expected,(file == "Color-motion.mp4" || Set(delegate.monitor.panels.map {$0.frame.minY}).count==1) else {throw UtilityError.message("Incorrect compact menu for \(file): \(names)")}
            }
            delegate.monitor.present([fixtures.appendingPathComponent("Large-photo.jpg"),fixtures.appendingPathComponent("Brief.docx")])
            let markdownChoice=delegate.monitor.panels.compactMap {($0.contentView as? ActionDropView)?.choice}.first {$0.title=="Markdown"}
            guard let accepts=markdownChoice?.accepts,accepts(fixtures.appendingPathComponent("Brief.docx")),!accepts(fixtures.appendingPathComponent("Large-photo.jpg")) else {throw UtilityError.message("Mixed menu Markdown choice included image inputs")}
            delegate.monitor.hide()
            report["plannedFileTypeMenus"]=true

            let oldTrigger=model.settings.trigger;model.settings.trigger = .controlShift;model.persist()
            guard UtilitySettings.Trigger.controlShift.matches([.control,.shift]),!UtilitySettings.Trigger.controlShift.matches(.shift),JSONStore.load(UtilitySettings.self,from:home.appendingPathComponent("settings.json"))?.trigger == .controlShift else { throw UtilityError.message("Activation settings failed") };model.settings.trigger=oldTrigger;model.persist()
            report["activationSettings"] = true
            model.recording = true
            delegate.togglePause()
            guard delegate.isPaused, delegate.monitor.timer == nil, delegate.monitor.eventMonitor == nil, !model.recording,
                  delegate.windows.values.allSatisfy({ !$0.isVisible }),
                  delegate.status.menu?.items.first(where: { $0.action == #selector(UtilityDelegate.shelf) })?.isEnabled == false,
                  delegate.status.menu?.items.first(where: { $0.action == #selector(UtilityDelegate.togglePause) })?.title == "Resume" else { throw UtilityError.message("Pause did not disable the utility") }
            delegate.monitor.present([fixtures.appendingPathComponent("Large-photo.jpg")])
            ActivityController.shared.show()
            guard ActivityController.shared.panel?.isVisible != true else {throw UtilityError.message("Activity appeared while paused")}
            guard delegate.monitor.panel?.isVisible != true else { throw UtilityError.message("Drag palette appeared while paused") }
            model.pasteboard.clearContents(); model.pasteboard.setString("Copied while paused", forType: .string); model.pollClipboard()
            delegate.togglePause()
            model.pollClipboard()
            guard !delegate.isPaused, delegate.monitor.timer?.isValid == true, model.recording, model.clips.isEmpty,
                  delegate.status.menu?.items.allSatisfy({ $0.isEnabled }) == true else { throw UtilityError.message("Resume did not restore the utility or captured paused clipboard content") }
            model.recording = false
            delegate.togglePause(); delegate.togglePause()
            guard !model.recording else { throw UtilityError.message("Resume changed the clipboard recording preference") }
            report["pauseResume"] = true
            model.copyShelf()
            let copied = model.pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]
            guard copied?.count == 2 else { throw UtilityError.message("Shelf file-reference copy failed") }
            report["shelfFileCopy"] = true
            model.recording = true
            model.pasteboard.clearContents(); model.pasteboard.setString("A harmless smoke-test phrase",forType:.string); model.pollClipboard()
            guard model.clips.first?.text == "A harmless smoke-test phrase" else { throw UtilityError.message("Text clipboard capture failed") }
            model.clips[0].pinned = true; model.persist(); model.copy(model.clips[0])
            guard model.pasteboard.string(forType:.string) == "A harmless smoke-test phrase" else { throw UtilityError.message("Clipboard recopy failed") }
            let png = try Data(contentsOf:fixtures.appendingPathComponent("Transparent.png"))
            model.pasteboard.clearContents(); model.pasteboard.setData(png,forType:.png); model.pollClipboard()
            guard model.clips.first?.png != nil else { throw UtilityError.message("Image clipboard capture failed") }
            model.copy(model.clips[0]); guard model.pasteboard.data(forType:.png) != nil else { throw UtilityError.message("Image recopy failed") }
            let imageClip=model.clips.first!
            model.pasteboard.clearContents();model.pasteboard.setString("Newer than the image",forType:.string);model.pollClipboard()
            guard model.copy(imageClip),model.pasteboard.data(forType:.png)==imageClip.png,model.pasteboard.string(forType:.string)==nil,NSImage(pasteboard:model.pasteboard) != nil else {throw UtilityError.message("Older image did not replace newer text")}
            let receiver=NSTextView();receiver.isRichText=true;receiver.importsGraphics=true
            guard receiver.readSelection(from:model.pasteboard),receiver.attributedString().containsAttachments else {throw UtilityError.message("Restored image was not pasteable into a rich text destination")}
            guard let textClip=model.clips.first(where:{$0.text=="A harmless smoke-test phrase"}),model.copy(textClip),model.pasteboard.data(forType:.png)==nil else {throw UtilityError.message("Older text did not replace newer image")}
            receiver.string="";guard receiver.readSelection(from:model.pasteboard),receiver.string==textClip.text else {throw UtilityError.message("Restored text did not paste correctly")}
            let popup=ClipboardController.shared
            popup.show();popup.selection=imageClip.id;popup.commit(paste:false)
            guard !popup.isOpen,NSImage(pasteboard:model.pasteboard) != nil else {throw UtilityError.message("Clipboard Enter did not restore image and dismiss")}
            let before=model.pasteboard.changeCount;popup.show();popup.move(1);popup.dismiss(restore:false)
            guard model.pasteboard.changeCount==before else {throw UtilityError.message("Cancelling clipboard selection changed its content")}
            report["clipboardOlderImageTextDestinationPasteAndEnter"]=true
            model.recording=true
            for paths in [[fixtures.appendingPathComponent("Large-photo.jpg")],[fixtures.appendingPathComponent("Large-photo.jpg"),fixtures.appendingPathComponent("Brief.docx")]] {
                model.pasteboard.clearContents();model.pasteboard.writeObjects(paths.map {$0 as NSURL});model.pollClipboard()
                guard let fileClip=model.clips.first,fileClip.isFiles,fileClip.files?.count==paths.count else {throw UtilityError.message("File clipboard capture failed")}
                model.pasteboard.clearContents();model.pasteboard.setString("Newer file test text",forType:.string);model.pollClipboard()
                popup.show();popup.selection=fileClip.id;popup.commit(paste:false)
                let restored=model.pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]
                guard !popup.isOpen,restored?.map(\.lastPathComponent)==paths.map(\.lastPathComponent) else {throw UtilityError.message("File Enter restoration failed")}
            }
            report["clipboardSingleAndMultipleFileReferences"]=true

            model.recording = false
            report["clipboardTextImageRecopyPin"] = true
            let restored = JSONStore.load([Clip].self,from:home.appendingPathComponent("clipboard.json"))
            guard restored?.contains(where: { $0.pinned }) == true else { throw UtilityError.message("Pin persistence failed") }
            model.run(model.shelf.map(\.url),workflow:.examples[0])
            for _ in 0..<200 where model.busy { try await Task.sleep(nanoseconds:50_000_000) }
            guard !model.busy, model.results.contains(where: { $0.status == .succeeded }), model.results.contains(where: { $0.status == .skipped }) else { throw UtilityError.message("Mixed-batch reporting failed") }
            guard model.results.filter({$0.status == .succeeded}).allSatisfy({URL(fileURLWithPath:$0.output!).deletingLastPathComponent().standardizedFileURL.path==fixtures.standardizedFileURL.path}) else { throw UtilityError.message("Output was not saved beside the source") }
            report["mixedBatch"] = true;report["sameFolderOutputs"] = true
            let adjusted=ImageAdjustmentModel(kind:.resizeImage,urls:[fixtures.appendingPathComponent("Large-photo.jpg")])
            for _ in 0..<100 where adjusted.source == nil { try await Task.sleep(nanoseconds:50_000_000) }
            guard adjusted.source != nil else { throw UtilityError.message("Resize preview did not load") }
            adjusted.changeWidth(300);guard adjusted.height==200 else { throw UtilityError.message("Ratio lock failed") };adjusted.locked=false;adjusted.changeHeight(100);guard adjusted.width==300 else {throw UtilityError.message("Unlocked resize changed the width")}
            adjusted.setScale(50);guard adjusted.width==900,adjusted.height==300 else {throw UtilityError.message("Resize slider did not scale current dimensions")};adjusted.close()
            let cropped=ImageAdjustmentModel(kind:.cropImage,urls:[fixtures.appendingPathComponent("Large-photo.jpg")])
            for _ in 0..<100 where cropped.source == nil {try await Task.sleep(nanoseconds:50_000_000)}
            cropped.setRatio("1:1");let actual=try ImageEngine.transformed(cropped.step,image:cropped.source!);guard actual.width==actual.height else {throw UtilityError.message("Crop preset did not produce a square")};cropped.close()
            let compressed=ImageAdjustmentModel(kind:.compressImage,urls:[fixtures.appendingPathComponent("Large-photo.jpg")]);compressed.quality=30
            for _ in 0..<200 where compressed.estimate == nil { try await Task.sleep(nanoseconds:50_000_000) }
            guard let bytes=compressed.estimate,bytes>0,compressed.preview != nil else {throw UtilityError.message("Compression size preview failed")}
            let comparison=home.appendingPathComponent("Compression-check");try FileManager.default.createDirectory(at:comparison,withIntermediateDirectories:true)
            let encoded=try ImageEngine.apply(compressed.step,input:compressed.url,directory:comparison,name:"compare")
            guard FileServices.bytes(encoded)==bytes else {throw UtilityError.message("Compression size preview differs from encoded output")};compressed.close()
            report["visualImageControlsAndActualCompressionEstimate"] = true
            let promiseSource=home.appendingPathComponent("Promise-source.txt");try Data("Disposable promised file".utf8).write(to:promiseSource)
            let promiseDestination=home.appendingPathComponent("Promise-destination");try FileManager.default.createDirectory(at:promiseDestination,withIntermediateDirectories:true)
            let writer=ShelfPromiseWriter(reference:FileReference(url:promiseSource),move:true);let provider=RetainedFilePromise(fileType:"public.plain-text",delegate:writer);provider.keeper=writer
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in writer.filePromiseProvider(provider,writePromiseTo:promiseDestination.appendingPathComponent("Renamed.txt")) { error in if let error {continuation.resume(throwing:error)} else {continuation.resume()} } }
            guard !FileManager.default.fileExists(atPath:promiseSource.path),try String(contentsOf:promiseDestination.appendingPathComponent("Renamed.txt"))=="Disposable promised file" else {throw UtilityError.message("Promised Move failed")}
            report["nativeFilePromiseMove"] = true
            let kept=home.appendingPathComponent("Keep.txt"),delivered=home.appendingPathComponent("Copy.txt")
            try Data("keep".utf8).write(to:kept);try Data("copy".utf8).write(to:delivered)
            model.stage([kept,delivered])
            guard let copiedRef=model.shelf.first(where:{$0.path==delivered.standardizedFileURL.path}),let failedRef=model.shelf.first(where:{$0.path==kept.standardizedFileURL.path}) else {throw UtilityError.message("Disposable shelf references not found")}
            model.recordDelivery(failedRef,output:nil,error:UtilityError.message("Disposable failure"),move:false,batch:UUID(),clearCopied:true)
            guard model.shelf.contains(where:{$0.id==failedRef.id}) else {throw UtilityError.message("Failed copy removed its shelf item")}
            let copyWriter=ShelfPromiseWriter(reference:copiedRef,move:false,clearAfterCopy:true)
            let copyProvider=RetainedFilePromise(fileType:"public.plain-text",delegate:copyWriter);copyProvider.keeper=copyWriter
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in copyWriter.filePromiseProvider(copyProvider,writePromiseTo:promiseDestination.appendingPathComponent("Copy.txt")) {error in if let error {continuation.resume(throwing:error)} else {continuation.resume()} } }
            for _ in 0..<30 where model.shelf.contains(where:{$0.id==copiedRef.id}) {try await Task.sleep(nanoseconds:20_000_000)}
            guard FileManager.default.fileExists(atPath:delivered.path),!model.shelf.contains(where:{$0.id==copiedRef.id}),model.shelf.contains(where:{$0.id==failedRef.id}) else {throw UtilityError.message("Copy cleanup removed originals or unrelated shelf items")}
            report["copyCleanupOnlyAfterDelivery"]=true
            let video=VideoCompressionModel(urls:[fixtures.appendingPathComponent("Color-motion.mp4")])
            guard video.percentage==100,abs(video.maximumMB-Double(video.sizes[0])/1_000_000)<0.000001 else {throw UtilityError.message("Video did not start at source size")}
            let original=video.reference.sourceBytes;video.maximumMB=Double(original)/4_000_000
            guard abs(video.percentage-25)<0.0001 else {throw UtilityError.message("Video MB to percentage failed")};video.sliderValue=40
            guard abs(video.maximumMB-Double(original)*0.4/1_000_000)<0.000001 else {throw UtilityError.message("Video percentage to MB failed")}
            report["videoSizeControlSynchronization"]=true
            let anotherVideo=fixtures.appendingPathComponent("Second-video.mp4");try FileManager.default.copyItem(at:fixtures.appendingPathComponent("Color-motion.mp4"),to:anotherVideo)
            let speeds=VideoSpeedModel(urls:[fixtures.appendingPathComponent("Color-motion.mp4"),anotherVideo]);speeds.speed=2;speeds.selectedIndex=1
            guard speeds.speed==1,(speeds.player.currentItem?.asset as? AVURLAsset)?.url==anotherVideo else {throw UtilityError.message("Video preview selection/default failed")}
            speeds.speed=0.5;speeds.selectedIndex=0;guard speeds.speed==2,speeds.exportSpeeds[anotherVideo.path]==0.5 else {throw UtilityError.message("Per-video speeds did not persist across preview selection")}
            speeds.location.directory=home;speeds.run()
            for _ in 0..<200 where model.busy {try await Task.sleep(nanoseconds:20_000_000)}
            let speedOutputs=model.results.filter{$0.status == .succeeded}.compactMap(\.output)
            guard speedOutputs.count==2,speedOutputs.contains(where:{$0.hasSuffix("Color-motion_2x.mp4")}),speedOutputs.contains(where:{$0.hasSuffix("Second-video_0.5x.mp4")}) else {throw UtilityError.message("Per-video speeds were not applied to exported files")}
            let fast=AVURLAsset(url:URL(fileURLWithPath:speedOutputs.first(where:{$0.hasSuffix("_2x.mp4")})!)),slow=AVURLAsset(url:URL(fileURLWithPath:speedOutputs.first(where:{$0.hasSuffix("_0.5x.mp4")})!))
            let fastDuration=try await fast.load(.duration).seconds,slowDuration=try await slow.load(.duration).seconds
            guard abs(fastDuration-2)<0.1,abs(slowDuration-8)<0.1 else {throw UtilityError.message("Individual exported video durations were incorrect")}
            speeds.applyToAll();guard Set(speeds.exportSpeeds.values)==[2] else {throw UtilityError.message("Apply speed to all failed")}
            report["perVideoPreviewSpeedPersistenceAndBatchExport"]=true


            let photo=fixtures.appendingPathComponent("Large-photo.jpg")
            let transparent=fixtures.appendingPathComponent("Transparent.png")
            let sourcePDF=fixtures.appendingPathComponent("Alpha-pages.pdf")
            let wordFile=fixtures.appendingPathComponent("Brief.docx")
            let mixedInputs=[sourcePDF,photo,wordFile,transparent]
            delegate.monitor.present(mixedInputs)
            let pdfChoices=delegate.monitor.panels.compactMap {($0.contentView as? ActionDropView)?.choice}.filter {$0.title.contains("PDF")}
            guard pdfChoices.count==1,let combine=pdfChoices.first,combine.title=="Combine to PDF",
                  let accepts=combine.accepts,mixedInputs.filter(accepts)==[sourcePDF,photo,transparent] else {
                throw UtilityError.message("Mixed drag did not offer a single Combine to PDF action")
            }
            delegate.monitor.hide()
            combine.action(mixedInputs)
            guard let window=delegate.windows.values.first(where:{$0.title=="Combine to PDF"}),
                  let mixed=(window.contentView as? NSHostingView<PageOrganizerView>)?.rootView.model else {
                throw UtilityError.message("Combine to PDF did not open the PDF organizer")
            }
            for _ in 0..<100 where mixed.busy {try await Task.sleep(nanoseconds:20_000_000)}
            guard let source=PDFDocument(url:sourcePDF),source.pageCount>0,mixed.error==nil,mixed.documentMode,
                  mixed.pages.map(\.url)==[photo,transparent]+Array(repeating:sourcePDF,count:source.pageCount),
                  mixed.pages.map(\.pageIndex)==[nil,nil]+(0..<source.pageCount).map(Optional.some) else {
                throw UtilityError.message("Mixed PDF organizer did not place image pages before the original PDF pages")
            }
            mixed.imageSize = .letter
            mixed.location.directory=home;mixed.location.filename="Mixed pages.pdf"
            mixed.export(window:window)
            for _ in 0..<200 where mixed.busy {try await Task.sleep(nanoseconds:20_000_000)}
            guard mixed.error==nil,let result=PDFDocument(url:home.appendingPathComponent("Mixed pages.pdf")),
                  result.pageCount==source.pageCount+2,
                  result.page(at:0)?.bounds(for:.mediaBox).size==ImagePageSize.letter.size,
                  let originalText=source.page(at:0)?.string,!originalText.isEmpty,
                  result.page(at:2)?.string==originalText else {
                throw UtilityError.message("Mixed PDF export did not preserve image layout and searchable PDF text")
            }
            report["mixedImageAndPDFCombine"]=true

            let imagePDF=home.appendingPathComponent("One-image.pdf")
            let imagePages=try PDFAssembly.load([fixtures.appendingPathComponent("Large-photo.jpg"),fixtures.appendingPathComponent("Transparent.png")])
            try PDFAssembly.write(imagePages,to:imagePDF)
            let otherPDF=home.appendingPathComponent("Other-images.pdf");try PDFAssembly.write(imagePages,to:otherPDF,size:.letter,margin:24)
            let organizer=PageOrganizerModel(urls:[imagePDF,otherPDF],name:"Smoke pages")
            for _ in 0..<100 where organizer.busy {try await Task.sleep(nanoseconds:20_000_000)}
            guard organizer.documentMode,organizer.documents.count==2,organizer.pages.count==4 else {throw UtilityError.message("PDF document grouping failed")}
            let secondID=organizer.documents[1].id,secondDocument=organizer.documents[1].documentID
            organizer.move(ids:[secondID],before:0)
            guard organizer.pages[0].documentID==secondDocument else {throw UtilityError.message("Whole-document reorder failed")}
            organizer.documentMode=false
            let third=organizer.pages[2].id;organizer.move(ids:[third],before:1)
            guard !organizer.canOrderDocuments else {throw UtilityError.message("Interleaved page order was not detected")}
            let preservedOrder=organizer.pages.map(\.id);organizer.documentMode=true;organizer.move(ids:[organizer.documents[0].id],before:2)
            guard organizer.pages.map(\.id)==preservedOrder else {throw UtilityError.message("Document view regrouped interleaved pages")}
            report["sharedPDFDocumentAndPageOrdering"]=true
            let exportedPDF=home.appendingPathComponent("Direct export.pdf")
            organizer.location.directory=home;organizer.location.filename=exportedPDF.lastPathComponent
            let exportWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:200),styleMask:[.titled],backing:.buffered,defer:false);exportWindow.isReleasedWhenClosed=false;exportWindow.orderFront(nil)
            organizer.export(window:exportWindow)
            for _ in 0..<200 where organizer.busy {try await Task.sleep(nanoseconds:20_000_000)}
            guard organizer.error==nil,FileManager.default.fileExists(atPath:exportedPDF.path),!exportWindow.isVisible else {throw UtilityError.message("PDF direct export or auto-close failed")}
            organizer.export(window:nil)
            for _ in 0..<200 where organizer.busy {try await Task.sleep(nanoseconds:20_000_000)}
            guard FileManager.default.fileExists(atPath:home.appendingPathComponent("Direct export_2.pdf").path) else {throw UtilityError.message("PDF custom name collision was unsafe")}
            report["directPDFExportCollisionAndAutoClose"]=true
            let workflowEditor=WorkflowEditorModel(inputs:[fixtures.appendingPathComponent("Large-photo.jpg")])
            workflowEditor.location.directory=home;workflowEditor.draft.name="Fifth pass preset";workflowEditor.draft.pinned=true;workflowEditor.add(.exportPDF)
            guard let saved=JSONStore.load([WorkflowDefinition].self,from:home.appendingPathComponent("workflows.json"))?.first(where:{$0.id==workflowEditor.selection}),saved.name=="Fifth pass preset",saved.pinned==true,saved.steps.last?.kind == .exportPDF else {throw UtilityError.message("Workflow autosave failed")}
            workflowEditor.run()
            for _ in 0..<200 where model.busy {try await Task.sleep(nanoseconds:20_000_000)}
            guard model.results.count==1,model.results.first?.status == .succeeded,model.results.first?.output?.hasSuffix("Large-photo_Fifth_pass_preset.pdf")==true else {throw UtilityError.message("Dropped-image preset did not run")}
            let changing=workflowEditor.draft.steps[0].id
            workflowEditor.changeKind(changing,to:.cropImage);guard workflowEditor.draft.steps[0].crop?.isValid==true else {throw UtilityError.message("Changing a workflow action did not initialize crop settings")}
            workflowEditor.changeKind(changing,to:.resizeImage);guard workflowEditor.draft.steps[0].width==1600 else {throw UtilityError.message("Changing a workflow action did not initialize resize settings")}
            let terminal=workflowEditor.draft.steps.last!.id;workflowEditor.changeKind(terminal,to:.rotateImage);workflowEditor.changeKind(changing,to:.exportPDF)
            guard workflowEditor.draft.steps.last?.id==changing,workflowEditor.draft.steps.first?.kind == .rotateImage else {throw UtilityError.message("Changed PDF action did not move to the end")}
            workflowEditor.changeKind(terminal,to:.exportPDF);guard workflowEditor.draft.steps.filter({$0.kind == .exportPDF}).count==1 else {throw UtilityError.message("Changing an action allowed duplicate PDF steps")}
            report["workflowActionPickerDefaultsAndPDFOrdering"]=true
            workflowEditor.delete();guard !model.workflows.contains(where:{$0.id==saved.id}) else {throw UtilityError.message("Workflow deletion failed")}
            report["imagePresetAutosavePinPDFRunAndDelete"]=true
            let cropOwner=WorkflowEditorModel(inputs:[fixtures.appendingPathComponent("Large-photo.jpg")]);cropOwner.add(.cropImage)
            let cropID=cropOwner.draft.steps.last!.id;cropOwner.chooseCrop(cropID)
            for _ in 0..<200 where ImageAdjustmentController.shared.models.isEmpty {try await Task.sleep(nanoseconds:20_000_000)}
            guard let cropAdjustment=ImageAdjustmentController.shared.models.values.first else {throw UtilityError.message("Workflow visual crop window did not open")}
            cropAdjustment.region=CropRegion(x:0.1,y:0.2,width:0.5,height:0.6);cropAdjustment.apply()
            guard cropOwner.draft.steps.last?.crop==CropRegion(x:0.1,y:0.2,width:0.5,height:0.6),ImageAdjustmentController.shared.models.isEmpty,!model.busy else {throw UtilityError.message("Workflow crop exported instead of returning its step")}
            report["workflowVisualCropReturnsRegionWithoutExport"]=true


            delegate.editor()
            let editor = EditorController.shared
            for _ in 0..<100 where !editor.ready { try await Task.sleep(nanoseconds:100_000_000) }
            guard editor.ready else { throw UtilityError.message("Offline renderer did not load") }
            editor.show(files:[fixtures.appendingPathComponent("Notes.md")])
            guard editor.file?.lastPathComponent=="Notes.md",editor.text.string==(try String(contentsOf:fixtures.appendingPathComponent("Notes.md"))) else {throw UtilityError.message("Direct Markdown editor did not load the dropped file")}
            guard !editor.text.usesFindBar,!editor.chrome.searchVisible,editor.exportLocation.directory==editor.file?.deletingLastPathComponent(),editor.exportLocation.filename=="Notes.pdf" else {throw UtilityError.message("Editor find or default export destination failed")}
            let compactHeaderHeight=editor.window.contentView?.subviews.first?.frame.height ?? 0
            editor.text.string="Alpha café ALPHA\n文件转换 café"
            editor.findText();editor.updateSearch("alpha")
            try await Task.sleep(nanoseconds:150_000_000);editor.window.contentView?.layoutSubtreeIfNeeded()
            guard let expandedHeaderHeight=editor.window.contentView?.subviews.first?.frame.height,expandedHeaderHeight>compactHeaderHeight+20 else {throw UtilityError.message("Editor search did not expand only when opened")}

            guard editor.chrome.searchVisible,editor.chrome.matchCount==2,editor.chrome.currentMatch==1,editor.text.selectedRange()==NSRange(location:0,length:5) else {throw UtilityError.message("Editor search did not select/count case-insensitive matches")}
            editor.findNext();guard editor.chrome.currentMatch==2,editor.text.selectedRange()==NSRange(location:11,length:5) else {throw UtilityError.message("Search next match failed")}
            editor.findNext();guard editor.chrome.currentMatch==1 else {throw UtilityError.message("Search wrap failed")}
            editor.findPrevious();guard editor.chrome.currentMatch==2 else {throw UtilityError.message("Search previous failed")}
            editor.updateSearch("文件转换");guard editor.chrome.matchCount==1,(editor.text.string as NSString).substring(with:editor.text.selectedRange())=="文件转换" else {throw UtilityError.message("Unicode search failed")}
            editor.updateSearch("absent");guard editor.chrome.matchCount==0,editor.chrome.currentMatch==0 else {throw UtilityError.message("No-match state failed")}
            editor.closeSearch();guard !editor.chrome.searchVisible else {throw UtilityError.message("Search did not close")}
            editor.exportPDF();guard editor.exportSheet != nil,editor.window.sheets.count==1 else {throw UtilityError.message("Editor export sheet did not open")};editor.dismissExport()
            guard editor.exportSheet==nil,editor.window.sheets.isEmpty else {throw UtilityError.message("Export cancellation did not close the sheet")}
            editor.load(try String(contentsOf:fixtures.appendingPathComponent("Notes.md")),url:fixtures.appendingPathComponent("Notes.md"))
            report["editorCustomSearchWrapUnicodeAndExportSheet"]=true
            try await EditorSyncChecks.run(editor)
            report["editorBidirectionalSourceNavigationAndStaleMapProtection"]=true

            report["directMarkdownEditor"]=true

            editor.text.string = "# Smoke preview\n\n$$\\frac{1}{2} + \\frac{1}{2} = 1$$\n\n**Live edit**\n\n<script>alert('blocked')</script>"
            editor.render()
            let visible = try await editor.web.evaluateJavaScript("document.querySelector('h1')?.textContent === 'Smoke preview' && document.querySelectorAll('.katex').length === 1 && document.querySelectorAll('#preview script').length === 0")
            guard visible as? Bool == true else { throw UtilityError.message("Markdown/math render or HTML escaping failed") }
            report["offlineMarkdownMathAndEscaping"] = true
            let snapshot = try await editor.web.takeSnapshot(configuration:nil)
            if let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff) { try bitmap.representation(using:.png,properties:[:])?.write(to:home.appendingPathComponent("preview.png")) }
            editor.text.string = (1...80).map { "## Section \($0)\n\nA paragraph for checking that PDF export continues over multiple pages without clipping the final section.\n" }.joined(separator:"\n")
            editor.render()
            _ = try await editor.web.evaluateJavaScript("document.body.offsetHeight")
            let pdfPath = home.appendingPathComponent("editor-long.pdf")
            try await editor.writePDF(to:pdfPath)
            guard let pdf = PDFDocument(url:pdfPath), pdf.pageCount > 1, pdf.pageCount < 30, pdf.page(at:0)?.string?.contains("Section 1") == true, pdf.page(at:0)?.string?.contains("Section 80") == false, pdf.page(at:pdf.pageCount-1)?.string?.contains("Section 80") == true else { throw UtilityError.message("Paginated PDF export failed") }
            report["pdfPages"] = pdf.pageCount
            report["passed"] = true
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:home.appendingPathComponent("report.json"))
            if ProcessInfo.processInfo.environment["UTILITY_REVIEW_HOLD"]=="1" {
                delegate.windows.values.forEach {$0.orderOut(nil)};editor.window.orderOut(nil);ActivityController.shared.hide()
                delegate.show("Review controls",view:ReviewControls(fixtures:fixtures),size:NSSize(width:860,height:370))
                ImageAdjustmentController.shared.show(.cropImage,urls:[fixtures.appendingPathComponent("Large-photo.jpg")])
                return
            }
            exit(0)
        } catch {
            report["passed"] = false; report["error"] = error.localizedDescription
            try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:home.appendingPathComponent("report.json"))
            fputs("Smoke test: \(error.localizedDescription)\n",stderr); exit(1)
        }
    }
    static func snapshotPalette(_ monitor:DragMonitor,to url:URL) throws {
        guard let first=monitor.panels.first else {return}
        let bounds=monitor.panels.dropFirst().reduce(first.frame) {$0.union($1.frame)}.insetBy(dx:-14,dy:-14)
        let image=NSImage(size:bounds.size);image.lockFocus()
        NSColor(calibratedWhite:0.94,alpha:1).setFill();NSRect(origin:.zero,size:bounds.size).fill()
        for panel in monitor.panels {
            if let view=panel.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                view.cacheDisplay(in:view.bounds,to:bitmap)
                bitmap.draw(in:panel.frame.offsetBy(dx:-bounds.minX,dy:-bounds.minY))
            }
        }
        let point=CGPoint(x:monitor.anchor.x-bounds.minX,y:monitor.anchor.y-bounds.minY)
        NSImage(systemSymbolName:"doc.fill",accessibilityDescription:nil)?.draw(in:CGRect(x:point.x-15,y:point.y-18,width:30,height:36))
        image.unlockFocus()
        if let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let data=bitmap.representation(using:.png,properties:[:]) {try data.write(to:url)}
    }

}

struct ReviewControls:SwiftUI.View {
    let fixtures:URL
    var body:some SwiftUI.View {
        SwiftUI.VStack(spacing:16) {
            SwiftUI.Text("Isolated UI review").font(.title2)
            SwiftUI.HStack { ForEach([ActionKind.cropImage,.resizeImage,.compressImage,.rotateImage]) { kind in SwiftUI.Button(kind.title) { delegate.action(kind,urls:[fixtures.appendingPathComponent("Large-photo.jpg")]) } } }
            SwiftUI.HStack { SwiftUI.Button("PDF pages") {PageOrganizer.show([fixtures.appendingPathComponent("Large-photo.jpg"),fixtures.appendingPathComponent("Transparent.png")])};SwiftUI.Button("Clipboard") {delegate.clipboard()};SwiftUI.Button("Video") {delegate.action(.compressVideo,urls:[fixtures.appendingPathComponent("Color-motion.mp4")])};SwiftUI.Button("Shelf") {delegate.shelf()};SwiftUI.Button("Settings") {delegate.settings()} }
            SwiftUI.HStack {SwiftUI.Button("PDF documents") {PageOrganizer.show([fixtures.appendingPathComponent("Alpha-pages.pdf"),fixtures.appendingPathComponent("Beta-pages.pdf")])};SwiftUI.Button("OCR image") {delegate.action(.documentMarkdown,urls:[fixtures.appendingPathComponent("OCR-English-Chinese.png")])}}
            SwiftUI.HStack {SwiftUI.Button("Palette") {delegate.monitor.present([fixtures.appendingPathComponent("Large-photo.jpg")])};SwiftUI.Button("Results") {ActivityController.shared.show();ActivityController.shared.panel?.makeKeyAndOrderFront(nil)};SwiftUI.Button("Convert and reveal") {AppModel.shared.suppressFinder=false;delegate.convert([fixtures.appendingPathComponent("Large-photo.jpg")],format:"png")};SwiftUI.Button("Quit review") {NSApp.terminate(nil)} }
        }.padding(24).utilityStyle()
    }
}
