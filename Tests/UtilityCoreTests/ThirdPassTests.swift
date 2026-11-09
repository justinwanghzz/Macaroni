import XCTest
import AppKit
import PDFKit
import ZIPFoundation
@testable import UtilityCore

final class ThirdPassTests:XCTestCase {
    var folder:URL!
    override func setUpWithError() throws {folder=FileManager.default.temporaryDirectory.appendingPathComponent("utility-third-tests-"+UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
    override func tearDownWithError() throws {try? FileManager.default.removeItem(at:folder)}
    func textImage()throws->URL {
        let image=NSImage(size:CGSize(width:1800,height:700));image.lockFocus();NSColor.white.setFill();NSRect(x:0,y:0,width:1800,height:700).fill()
        ("UTILITY OCR TEST 2026" as NSString).draw(at:NSPoint(x:100,y:500),withAttributes:[.font:NSFont.systemFont(ofSize:64),.foregroundColor:NSColor.black])
        ("Hello world. Local document conversion." as NSString).draw(at:NSPoint(x:100,y:350),withAttributes:[.font:NSFont.systemFont(ofSize:48),.foregroundColor:NSColor.black])
        ("文件转换 测试" as NSString).draw(at:NSPoint(x:100,y:200),withAttributes:[.font:NSFont.systemFont(ofSize:56),.foregroundColor:NSColor.black]);image.unlockFocus()
        let url=folder.appendingPathComponent("OCR.png");try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:url);return url
    }
    func textPDF(_ name:String,_ values:[String])throws->URL {
        let document=PDFDocument()
        for text in values {
            let data=NSMutableData();var rect=CGRect(x:0,y:0,width:300,height:400)
            let context=CGContext(consumer:CGDataConsumer(data:data)!,mediaBox:&rect,nil)!
            context.beginPDFPage(nil);NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
            (text as NSString).draw(at:NSPoint(x:30,y:300),withAttributes:[.font:NSFont.systemFont(ofSize:20)])
            NSGraphicsContext.restoreGraphicsState();context.endPDFPage();context.closePDF();document.insert(PDFDocument(data:data as Data)!.page(at:0)!,at:document.pageCount)
        }
        let url=folder.appendingPathComponent(name+".pdf");XCTAssertTrue(document.write(to:url));return url
    }
    func testFileHistoryRestoresOneAndMultipleNativeReferences()throws {
        let a=folder.appendingPathComponent("First file.txt"),b=folder.appendingPathComponent("Second.txt")
        try Data("first".utf8).write(to:a);try Data("second".utf8).write(to:b)
        let pb=NSPasteboard(name:.init("utility-files-"+UUID().uuidString));defer {pb.releaseGlobally()}
        for urls in [[a],[a,b]] {
            pb.clearContents();XCTAssertTrue(pb.writeObjects(urls.map {$0 as NSURL}))
            let entry=try XCTUnwrap(ClipboardEntry.capture(from:pb));XCTAssertTrue(entry.isFiles);XCTAssertEqual(entry.files?.count,urls.count)
            pb.clearContents();pb.setString("Newer text",forType:.string)
            let lease=try entry.restore(to:pb);_=lease
            let restored=try XCTUnwrap(pb.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL])
            XCTAssertEqual(restored.map(\.lastPathComponent),urls.map(\.lastPathComponent));XCTAssertEqual(restored.count,urls.count)
            let roundTrip=try JSONDecoder().decode(ClipboardEntry.self,from:JSONEncoder().encode(entry));XCTAssertTrue(entry.sameContent(as:roundTrip))
        }
    }
    func testImageTextAndFilesRemainDistinctAndPasteable()throws {
        let png=try Data(contentsOf:textImage()),pb=NSPasteboard(name:.init("utility-image-"+UUID().uuidString));defer {pb.releaseGlobally()}
        pb.clearContents();pb.setData(png,forType:.png)
        let image=try XCTUnwrap(ClipboardEntry.capture(from:pb));XCTAssertNotNil(image.png)
        pb.clearContents();pb.setString("newer text",forType:.string);let text=try XCTUnwrap(ClipboardEntry.capture(from:pb))
        let lease=try image.restore(to:pb);_=lease
        XCTAssertNil(pb.string(forType:.string));XCTAssertNotNil(pb.data(forType:.tiff))
        let destination=NSTextView();destination.isRichText=true;destination.importsGraphics=true
        XCTAssertTrue(destination.readSelection(from:pb));XCTAssertTrue(destination.attributedString().containsAttachments)
        _=try text.restore(to:pb);destination.string="";XCTAssertTrue(destination.readSelection(from:pb));XCTAssertEqual(destination.string,"newer text");XCTAssertNil(pb.data(forType:.png))
    }
    func testMissingFilesDoNotReplaceExistingClipboardAndLegacyHistoryLoads()throws {
        let entry=ClipboardEntry(text:"missing",files:[FileReference(url:folder.appendingPathComponent("Missing.txt"))])
        let pb=NSPasteboard(name:.init("utility-missing-"+UUID().uuidString));defer {pb.releaseGlobally()};pb.setString("Keep me",forType:.string)
        XCTAssertThrowsError(try entry.restore(to:pb));XCTAssertEqual(pb.string(forType:.string),"Keep me")
        let json="{\"id\":\"00000000-0000-0000-0000-000000000001\",\"text\":\"Old entry\",\"pinned\":true}"
        let old=try JSONDecoder().decode(ClipboardEntry.self,from:Data(json.utf8));XCTAssertFalse(old.isFiles);XCTAssertTrue(old.pinned)
    }
    func testPDFAssemblyPreservesTextAndPageEdits()throws {
        let first=try textPDF("First",["Alpha","Beta"]),second=try textPDF("Second",["Gamma"])
        var pages=try PDFAssembly.load([first,second]);XCTAssertEqual(pages.count,3)
        pages=AssemblyPage.moving(pages,ids:[pages[2].id],before:0);pages[1].quarterTurns=1;pages.removeLast()
        let output=folder.appendingPathComponent("Edited.pdf");try PDFAssembly.write(pages,to:output)
        let result=try XCTUnwrap(PDFDocument(url:output));XCTAssertEqual(result.pageCount,2);XCTAssertTrue(result.page(at:0)!.string!.contains("Gamma"));XCTAssertTrue(result.page(at:1)!.string!.contains("Alpha"));XCTAssertEqual(result.page(at:1)!.rotation,90)
        XCTAssertEqual(PDFDocument(url:first)?.pageCount,2);XCTAssertThrowsError(try PDFAssembly.write(pages,to:first,overwrite:true))
    }
    func testSingleImagePDFSizingAndSafeOutput()throws {
        let source=try textImage(),pages=try PDFAssembly.load([source]);XCTAssertEqual(pages.count,1)
        let output=folder.appendingPathComponent("Letter.pdf");try PDFAssembly.write(pages,to:output,size:.letter,margin:24)
        XCTAssertEqual(PDFDocument(url:output)?.page(at:0)?.bounds(for:.mediaBox).size,CGSize(width:612,height:792))
        XCTAssertThrowsError(try PDFAssembly.write(pages,to:output));XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
    }
    func testImageAndScannedPDFOCR()throws {
        let image=try textImage(),recognized=try DocumentEngine.markdown(from:image)
        XCTAssertTrue(recognized.contains("UTILITY"));XCTAssertTrue(recognized.localizedCaseInsensitiveContains("Hello world"))
        XCTAssertTrue(recognized.filter {!$0.isWhitespace}.contains("文件转换"))
        let pdf=PDFDocument();pdf.insert(PDFPage(image:NSImage(contentsOf:image)!)!,at:0)
        let scan=folder.appendingPathComponent("Scanned.pdf");XCTAssertTrue(pdf.write(to:scan))
        let extracted=try DocumentEngine.markdown(from:scan);XCTAssertTrue(extracted.contains("UTILITY"));XCTAssertTrue(extracted.contains("## Page 1"))
    }

}
