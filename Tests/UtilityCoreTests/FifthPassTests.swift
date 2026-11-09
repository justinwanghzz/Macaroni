import XCTest
import AppKit
import PDFKit
import AVFoundation
import AudioToolbox
@testable import UtilityCore

final class FifthPassTests:XCTestCase {
    var folder:URL!
    var fixtures:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")}
    override func setUpWithError() throws {folder=FileManager.default.temporaryDirectory.appendingPathComponent("utility-fifth-"+UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
    override func tearDownWithError() throws {try? FileManager.default.removeItem(at:folder)}
    func testNamingDefaultsAndCustomization() throws {
        let naming=OutputNaming(),input=URL(fileURLWithPath:"/Photo.heic")
        for (kind,name) in [(ActionKind.convertImage,"Photo"),(.compressImage,"Photo_compressed"),(.rotateImage,"Photo_rotated"),(.cropImage,"Photo_cropped"),(.flipHorizontal,"Photo_flipped"),(.flipVertical,"Photo_flipped"),(.muteVideo,"Photo_muted"),(.documentMarkdown,"Photo"),(.exportPDF,"Photo")] {
            XCTAssertEqual(naming.basename(input:input,workflow:.init(name:"Action",steps:[.init(kind:kind)])),name)
        }
        XCTAssertEqual(naming.basename(input:input,workflow:.init(name:"Speed",steps:[.init(kind:.speedVideo,amount:0.5)])),"Photo_0.5x")
        XCTAssertEqual(naming.basename(input:input,workflow:.init(name:"Resize",steps:[.init(kind:.resizeImage)]),dimensions:CGSize(width:1600,height:900)),"Photo_1600x900")
        var preset=WorkflowDefinition(name:"Class notes",steps:[.init(kind:.convertImage)]);preset.isPreset=true
        XCTAssertEqual(naming.basename(input:input,workflow:preset),"Photo_Class_notes")
        for base in ["Photo_compressed","Photo_compressed_2","Photo_compressed_10","Photo_compressed_100"] {XCTAssertEqual(OutputNaming.appending(base,suffix:"compressed"),"Photo_compressed")}
        XCTAssertEqual(OutputNaming.appending("Photo_cropped",suffix:"1600x900"),"Photo_cropped_1600x900")
        var custom=naming;custom.compressed="small";XCTAssertEqual(custom.basename(input:input,workflow:.init(name:"Compress",steps:[.init(kind:.compressImage)])),"Photo_small")
        XCTAssertEqual(try JSONDecoder().decode(OutputNaming.self,from:JSONEncoder().encode(custom)),custom)
    }
    func testDirectPDFNamesCollisionAndOriginalSafety() throws {
        let image=fixtures.appendingPathComponent("Large-photo.jpg"),pdf=fixtures.appendingPathComponent("Alpha-pages.pdf"),n=OutputNaming()
        XCTAssertEqual(n.pdfName(inputs:[image]),"Large-photo.pdf");XCTAssertEqual(n.pdfName(inputs:[image,image]),"Combined_images.pdf");XCTAssertEqual(n.pdfName(inputs:[pdf,pdf]),"Combined_documents.pdf");XCTAssertEqual(n.pdfName(inputs:[pdf,image]),"Combined_pages.pdf");XCTAssertEqual(n.pdfName(inputs:[pdf]),"Alpha-pages_edited.pdf")
        let pages=try PDFAssembly.load([image]),first=try ExportFiles.pdf(pages,directory:folder,filename:"My notes.pdf"),original=try Data(contentsOf:first)
        let second=try ExportFiles.pdf(pages,directory:folder,filename:"My notes.pdf")
        XCTAssertEqual(first.lastPathComponent,"My notes.pdf");XCTAssertEqual(second.lastPathComponent,"My notes_2.pdf");XCTAssertEqual(try Data(contentsOf:first),original);XCTAssertEqual(PDFDocument(url:second)?.pageCount,1)
    }
    func testImagePipelineNamesActualDimensionsAndPresetPDF() async throws {
        let image=fixtures.appendingPathComponent("Large-photo.jpg"),source=try Data(contentsOf:image)
        var resize=ActionStep(kind:.resizeImage);resize.width=800;resize.height=800;resize.aspectLocked=true
        let out=try await ProcessingEngine.run(input:image,workflow:.init(name:"Resize",steps:[resize]),outputDirectory:folder),decoded=try ImageEngine.load(out)
        XCTAssertEqual(out.lastPathComponent,"Large-photo_\(decoded.width)x\(decoded.height).jpg")
        var preset=WorkflowDefinition(name:"Reading PDF",steps:[resize,.init(kind:.exportPDF)]);preset.isPreset=true
        let pdf=try await ProcessingEngine.run(input:image,workflow:preset,outputDirectory:folder)
        XCTAssertEqual(pdf.lastPathComponent,"Large-photo_Reading_PDF.pdf");XCTAssertEqual(PDFDocument(url:pdf)?.pageCount,1);XCTAssertEqual(try Data(contentsOf:image),source)
        XCTAssertThrowsError(try WorkflowDefinition(name:"Invalid",steps:[.init(kind:.exportPDF),resize]).validate(for:.image))
        let legacy=Data("{\"schemaVersion\":1,\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Legacy\",\"steps\":[]}".utf8)
        XCTAssertNil(try JSONDecoder().decode(WorkflowDefinition.self,from:legacy).pinned)
    }
    func testPresetGeometryAndSourceClearance() {
        for screen in [CGRect(x:0,y:0,width:1440,height:900),CGRect(x:-800,y:100,width:800,height:600)] {
            for anchor in [CGPoint(x:screen.midX,y:screen.midY),CGPoint(x:screen.minX+10,y:screen.minY+10),CGPoint(x:screen.maxX-10,y:screen.maxY-10),CGPoint(x:screen.midX,y:screen.maxY-10)] {
                let layout=RadialLayout.make(anchor:anchor,screen:screen,upper:4,lower:7,upperColumns:4,preset:true)
                XCTAssertEqual(layout.frames.count,12)
                let preset=layout.frames.last!,shelf=layout.frames[4],source=CGRect(x:anchor.x-36,y:anchor.y-36,width:72,height:72)
                XCTAssertEqual(preset.midY,shelf.midY);XCTAssertEqual(preset.midX,(layout.frames[0].midX+layout.frames[1].midX)/2,accuracy:0.01)
                for i in layout.frames.indices {XCTAssertTrue(screen.contains(layout.frames[i]));XCTAssertFalse(layout.frames[i].intersects(source));for j in layout.frames.indices where j>i {XCTAssertFalse(layout.frames[i].intersects(layout.frames[j]))}}
            }
        }
    }
    func toneFrequency(_ url:URL) async throws ->Double {
        let asset=AVURLAsset(url:url),tracks=try await asset.loadTracks(withMediaType:.audio),track=try XCTUnwrap(tracks.first)
        let reader=try AVAssetReader(asset:asset),output=AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false])
        reader.add(output);XCTAssertTrue(reader.startReading());var mono:[Float]=[];var rate=44100.0
        while mono.count<44100,let sample=output.copyNextSampleBuffer() {
            let desc=try XCTUnwrap(CMSampleBufferGetFormatDescription(sample)),format=try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(desc)).pointee
            rate=format.mSampleRate;let channels=max(1,Int(format.mChannelsPerFrame)),block=try XCTUnwrap(CMSampleBufferGetDataBuffer(sample)),length=CMBlockBufferGetDataLength(block)
            var values=[Float](repeating:0,count:length/4)
            let status=values.withUnsafeMutableBytes {CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:$0.baseAddress!)};XCTAssertEqual(status,kCMBlockBufferNoErr)
            mono.append(contentsOf:stride(from:0,to:values.count,by:channels).map{values[$0]})
        }
        reader.cancelReading();let trimmed=Array(mono.dropFirst(Int(rate*0.1)).prefix(Int(rate*0.7)))
        XCTAssertGreaterThan(trimmed.count,1000)
        // Find the strongest spectral component, rather than counting crossings
        // introduced by AAC/time-stretch transients around an otherwise steady tone.
        let samples=stride(from:0,to:trimmed.count,by:4).map{Double(trimmed[$0])},sampleRate=rate/4
        var bestFrequency=0.0,bestPower=0.0
        for frequency in stride(from:80.0,through:1800,by:2) {
            let coefficient=2*cos(2*Double.pi*frequency/sampleRate);var previous=0.0,prior=0.0
            for (i,value) in samples.enumerated() {let window=0.5-0.5*cos(2*Double.pi*Double(i)/Double(samples.count-1));let next=value*window+coefficient*previous-prior;prior=previous;previous=next}
            let power=previous*previous+prior*prior-coefficient*previous*prior
            if power>bestPower {bestPower=power;bestFrequency=frequency}
        }
        return bestFrequency
    }
    func testVideoMuteAndSpeedDurationAudioAndEndFrame() async throws {
        let source=fixtures.appendingPathComponent("Color-motion.mp4"),before=try Data(contentsOf:source)
        let sourceFrequency=try await toneFrequency(source);XCTAssertGreaterThan(sourceFrequency,100)
        for (speed,muted) in [(1.0,true),(0.25,false),(0.5,false),(2.0,false),(3.0,false)] {
            let out=folder.appendingPathComponent("\(speed)-\(muted).mp4")
            try await VideoEngine.adjust(source,to:out,speed:speed,muted:muted)
            let asset=AVURLAsset(url:out),duration=try await asset.load(.duration).seconds,audio=try await asset.loadTracks(withMediaType:.audio)
            XCTAssertEqual(duration,4/speed,accuracy:0.15);XCTAssertEqual(audio.count,muted ? 0:1)
            if !muted {let frequency=try await toneFrequency(out);XCTAssertEqual(frequency,sourceFrequency,accuracy:8,"Speed \(speed) export changed audio pitch")}
            let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true
            let frame=try await generator.image(at:CMTime(seconds:max(0,duration-0.2),preferredTimescale:600));XCTAssertGreaterThan(frame.image.width,0)
        }
        XCTAssertEqual(try Data(contentsOf:source),before)
        XCTAssertThrowsError(try ActionStep(kind:.speedVideo,amount:0.1).validate())
    }
    func testVideoAdjustmentCancellationAndExistingOutputSafety() async throws {
        let source=fixtures.appendingPathComponent("Color-motion.mp4"),out=folder.appendingPathComponent("existing.mp4"),sentinel=Data("keep existing file".utf8)
        try sentinel.write(to:out)
        do {try await VideoEngine.adjust(source,to:out);XCTFail("Existing export was accepted")} catch {}
        XCTAssertEqual(try Data(contentsOf:out),sentinel)
        let cancelled=folder.appendingPathComponent("cancelled.mp4")
        let task=Task {try await VideoEngine.adjust(source,to:cancelled,speed:0.25)};task.cancel()
        do {try await task.value;XCTFail("Expected cancellation")} catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
        XCTAssertFalse(FileManager.default.fileExists(atPath:cancelled.path))
    }
    func testSameNamedInputsAndRepeatedCompressionDoNotOverwrite() async throws {
        let a=folder.appendingPathComponent("A"),b=folder.appendingPathComponent("B"),out=folder.appendingPathComponent("Outputs")
        for dir in [a,b,out] {try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)}
        let first=a.appendingPathComponent("Photo.jpg"),second=b.appendingPathComponent("Photo.jpg"),data=try Data(contentsOf:fixtures.appendingPathComponent("Large-photo.jpg"))
        try data.write(to:first);try data.write(to:second)
        let convert=WorkflowDefinition(name:"Convert",steps:[.init(kind:.convertImage,format:"png")])
        let x=try await ProcessingEngine.run(input:first,workflow:convert,outputDirectory:out),y=try await ProcessingEngine.run(input:second,workflow:convert,outputDirectory:out)
        XCTAssertEqual(x.lastPathComponent,"Photo.png");XCTAssertEqual(y.lastPathComponent,"Photo_2.png")
        let compress=WorkflowDefinition(name:"Compress",steps:[.init(kind:.compressImage,amount:65)])
        let compressed=try await ProcessingEngine.run(input:first,workflow:compress,outputDirectory:out)
        let repeated=try await ProcessingEngine.run(input:compressed,workflow:compress,outputDirectory:out)
        XCTAssertEqual(repeated.lastPathComponent,"Photo_compressed_2.jpg");XCTAssertEqual(try Data(contentsOf:first),data);XCTAssertEqual(try Data(contentsOf:second),data)
    }
    func testOCRBeforeAfterBenchmarkAndMultipageQuality() throws {
        let source=fixtures.appendingPathComponent("Scanned-OCR.pdf"),pdf=try XCTUnwrap(PDFDocument(url:source)),page=try XCTUnwrap(pdf.page(at:0))
        func legacy(_ page:PDFPage)throws->String {let rect=page.bounds(for:.mediaBox),factor=min(3,5000/max(rect.width,rect.height));let image=page.thumbnail(of:CGSize(width:rect.width*factor,height:rect.height*factor),for:.mediaBox);var box=CGRect(origin:.zero,size:image.size);return try OCREngine.recognize(XCTUnwrap(image.cgImage(forProposedRect:&box,context:nil,hints:nil)))}
        // Warm up the shared Vision models equally before measuring either renderer.
        _=try OCREngine.recognize(page:page)
        let rasterStart=Date(),raster=try OCREngine.render(page:page),rasterSeconds=Date().timeIntervalSince(rasterStart)
        XCTAssertLessThanOrEqual(max(raster.width,raster.height),2601)
        let recognizeStart=Date();_=try OCREngine.recognize(raster);let recognitionSeconds=Date().timeIntervalSince(recognizeStart)
        page.rotation=90;let rotated=try OCREngine.render(page:page);XCTAssertEqual(rotated.width,raster.height);XCTAssertEqual(rotated.height,raster.width);page.rotation=0
        var measurements:[String:Any]=["afterPhases":["renderSeconds":rasterSeconds,"recognitionSeconds":recognitionSeconds,"width":raster.width,"height":raster.height]]
        for count in [1,3] {
            var oldText="",newText="";let start=Date()
            for _ in 0..<count {oldText+=try legacy(page)}
            let oldSeconds=Date().timeIntervalSince(start),next=Date()
            let multi=PDFDocument();for i in 0..<count {multi.insert(page.copy() as! PDFPage,at:i)}
            let input=folder.appendingPathComponent("Scan-\(count).pdf");XCTAssertTrue(multi.write(to:input));newText=try DocumentEngine.markdown(from:input)
            let newSeconds=Date().timeIntervalSince(next)
            XCTAssertTrue(oldText.contains("UTILITY"));XCTAssertTrue(newText.contains("UTILITY"));XCTAssertTrue(newText.filter{!$0.isWhitespace}.contains("文件转换"));XCTAssertTrue(newText.contains("## Page \(count)"))
            measurements["\(count)page"]=["beforeSeconds":oldSeconds,"afterSeconds":newSeconds,"beforeText":oldText,"afterText":newText]
            print("OCR BENCHMARK \(count) pages: before=\(oldSeconds)s after=\(newSeconds)s")
        }
        let data=try JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]);let report=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("utility-fifth-ocr-benchmark.json");try data.write(to:report);print("OCR report: \(report.path)")
    }
}
