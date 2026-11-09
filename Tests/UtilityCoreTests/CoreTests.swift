import XCTest
import AppKit
import ImageIO
import PDFKit
import ZIPFoundation
@testable import UtilityCore

final class CoreTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws { dir = FileManager.default.temporaryDirectory.appendingPathComponent("utility-test-"+UUID().uuidString); try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:dir) }
    func image() throws -> URL {
        let c = CGContext(data:nil,width:120,height:80,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1)); c.fill(CGRect(x:0,y:0,width:60,height:80))
        c.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1)); c.fill(CGRect(x:60,y:0,width:60,height:80))
        let u = dir.appendingPathComponent("sample.png"); let d = CGImageDestinationCreateWithURL(u as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(d,c.makeImage()!,nil); XCTAssertTrue(CGImageDestinationFinalize(d)); return u
    }
    func pixels(_ url: URL) -> CGImage { CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)! }
    func testImageTransformsAndWorkflow() async throws {
        let input = try image(); let before = try Data(contentsOf:input)
        let rotated = try ImageEngine.apply(.init(kind:.rotateImage),input:input,directory:dir,name:"rotated")
        XCTAssertEqual(pixels(rotated).width,80); XCTAssertEqual(pixels(rotated).height,120)
        let out = try await ProcessingEngine.run(input:input,workflow:.init(name:"Share",steps:[.init(kind:.convertImage),.init(kind:.resizeImage,amount:60),.init(kind:.compressImage,amount:50)]),outputDirectory:dir)
        XCTAssertEqual(out.pathExtension,"jpg"); XCTAssertEqual(pixels(out).width,60); XCTAssertEqual(pixels(out).height,40)
        XCTAssertEqual(try Data(contentsOf:input),before)
        let second = try await ProcessingEngine.run(input:input,workflow:.init(name:"PNG",steps:[.init(kind:.convertImage,format:"png")]),outputDirectory:dir)
        XCTAssertNotEqual(out,second)
    }
    func testOrientationFlipAndHEIC() throws {
        let input = try image()
        let flipped = try ImageEngine.apply(.init(kind:.flipHorizontal),input:input,directory:dir,name:"flipped")
        let c = CGContext(data:nil,width:120,height:80,bitsPerComponent:8,bytesPerRow:480,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(pixels(flipped),in:CGRect(x:0,y:0,width:120,height:80))
        let pixel = c.data!.assumingMemoryBound(to:UInt8.self)
        XCTAssertGreaterThan(pixel[2],pixel[0]) // The blue right half moved to the left.
        let oriented = dir.appendingPathComponent("phone.jpg")
        let dest = CGImageDestinationCreateWithURL(oriented as CFURL,"public.jpeg" as CFString,1,nil)!
        CGImageDestinationAddImage(dest,pixels(input),[kCGImagePropertyOrientation:6] as CFDictionary); XCTAssertTrue(CGImageDestinationFinalize(dest))
        let resized = try ImageEngine.apply(.init(kind:.resizeImage,amount:60),input:oriented,directory:dir,name:"upright")
        XCTAssertEqual(pixels(resized).width,40); XCTAssertEqual(pixels(resized).height,60)
        if ImageEngine.writableFormats.contains("heic") {
            let heic = try ImageEngine.apply(.init(kind:.convertImage,format:"heic"),input:input,directory:dir,name:"heic")
            XCTAssertEqual(pixels(heic).width,120)
            let jpg = try ImageEngine.apply(.init(kind:.convertImage,format:"jpg"),input:heic,directory:dir,name:"from-heic")
            XCTAssertEqual(pixels(jpg).height,80)
        }
    }
    func testCollisionAndMove() throws {
        let source = dir.appendingPathComponent("original"); try Data("unchanged".utf8).write(to:source)
        let destination = dir.appendingPathComponent("dest"); try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let first = try FileServices.transfer(source,to:destination,move:false)
        let second = try FileServices.transfer(source,to:destination,move:true)
        XCTAssertNotEqual(first,second); XCTAssertEqual(first.pathExtension, ""); XCTAssertEqual(try Data(contentsOf:first),Data("unchanged".utf8)); XCTAssertFalse(FileManager.default.fileExists(atPath:source.path))
    }
    func testInvalidWorkflows() throws {
        XCTAssertThrowsError(try WorkflowDefinition(name:"Bad",steps:[.init(kind:.documentMarkdown),.init(kind:.compressImage)]).validate(for:.pdf))
        XCTAssertThrowsError(try ActionStep(kind:.compressVideo,amount:0).validate())
        XCTAssertThrowsError(try ActionStep(kind:.resizeImage,amount:.nan).validate())
        let value = WorkflowDefinition.examples[0]
        XCTAssertEqual(try JSONDecoder().decode(WorkflowDefinition.self,from:JSONEncoder().encode(value)),value)
    }
    func zip(_ files: [String:String], ext: String) throws -> URL {
        let url = dir.appendingPathComponent("test."+ext); let archive = try Archive(url:url,accessMode:.create)
        for (path,text) in files { let data = Data(text.utf8); try archive.addEntry(with:path,type:.file,uncompressedSize:Int64(data.count),provider:{ position,size in data.subdata(in:Int(position)..<Int(position)+size) }) }
        return url
    }
    func testOfficeAndSlideOrdering() throws {
        let docx = try zip(["word/document.xml":"<w:document xmlns:w='urn:w'><w:body><w:p><w:pPr><w:pStyle w:val='Heading1'/></w:pPr><w:r><w:t>Title</w:t></w:r></w:p><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Hello 世界</w:t></w:r></w:p></w:body></w:document>","word/styles.xml":"<w:styles xmlns:w='urn:w'><w:style w:styleId='Heading1'><w:name w:val='heading 1'/></w:style></w:styles>"],ext:"docx")
        let md = try DocumentEngine.markdown(from:docx); XCTAssertTrue(md.contains("# Title")); XCTAssertTrue(md.contains("**Hello 世界**"))
        var files = ["ppt/presentation.xml":"<p:presentation xmlns:p='urn:p' xmlns:r='urn:r'><p:sldIdLst><p:sldId r:id='second'/><p:sldId r:id='first'/></p:sldIdLst></p:presentation>","ppt/_rels/presentation.xml.rels":"<Relationships><Relationship Id='first' Target='slides/slide1.xml'/><Relationship Id='second' Target='slides/slide12.xml'/></Relationships>"]
        for (name,text) in [("slide1","Alpha"),("slide12","Omega")] { files["ppt/slides/\(name).xml"] = "<p:sld xmlns:p='urn:p' xmlns:a='urn:a'><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>\(text)</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>" }
        let ppt = try DocumentEngine.markdown(from:zip(files,ext:"pptx")); XCTAssertTrue(ppt.range(of:"Omega")!.lowerBound < ppt.range(of:"Alpha")!.lowerBound)
    }
    func testMalformedOfficeAndScannedPDF() throws {
        let bad = try zip(["word/document.xml":"<!DOCTYPE a [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><a>&x;</a>"],ext:"docx")
        XCTAssertThrowsError(try DocumentEngine.markdown(from:bad))
        let blank = PDFDocument(); blank.insert(PDFPage(image:NSImage(contentsOf:try image())!)!,at:0)
        let url = dir.appendingPathComponent("scan.pdf"); blank.write(to:url)
        XCTAssertThrowsError(try DocumentEngine.markdown(from:url))
    }
    func testCancellationPreservesInput() async throws {
        let input = try image()
        let task = Task { try await ProcessingEngine.run(input:input,workflow:.examples[0],outputDirectory:dir) }; task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error \(error)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath:input.path))
    }
}
