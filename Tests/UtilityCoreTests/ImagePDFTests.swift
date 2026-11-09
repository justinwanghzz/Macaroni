import XCTest
import ImageIO
import PDFKit
@testable import UtilityCore

final class ImagePDFTests:XCTestCase {
    func testGroupReorderPreservesRelativeOrderAndSelectionDestination() {
        let pages=(0..<6).map {ImagePDFPage(url:URL(fileURLWithPath:"/\($0).png"))}
        let selection=Set([pages[1].id,pages[3].id])
        XCTAssertEqual(ImagePDFPage.moving(pages,ids:selection,before:6).map(\.url.lastPathComponent),["0.png","2.png","4.png","5.png","1.png","3.png"])
        XCTAssertEqual(ImagePDFPage.moving(pages,ids:selection,before:0).map(\.url.lastPathComponent),["1.png","3.png","0.png","2.png","4.png","5.png"])
        XCTAssertEqual(ImagePDFPage.moving(pages,ids:Set([pages[1].id,pages[2].id]),before:2),pages)
    }
    func testPDFPageOrderRotationAndSafeReplacement() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        func image(_ name:String,_ width:Int,_ height:Int)->URL {
            let url=folder.appendingPathComponent(name+".png")
            let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));c.fill(CGRect(x:0,y:0,width:width,height:height))
            let d=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!;CGImageDestinationAddImage(d,c.makeImage()!,nil);XCTAssertTrue(CGImageDestinationFinalize(d));return url
        }
        let a=image("landscape",120,80),b=image("portrait",50,100)
        let output=folder.appendingPathComponent("Combined.pdf")
        try ImagePDF.write([ImagePDFPage(url:b),ImagePDFPage(url:a,quarterTurns:1)],to:output)
        let pdf=try XCTUnwrap(PDFDocument(url:output));XCTAssertEqual(pdf.pageCount,2)
        XCTAssertEqual(pdf.page(at:0)?.bounds(for:.mediaBox).size,CGSize(width:50,height:100))
        XCTAssertEqual(pdf.page(at:1)?.bounds(for:.mediaBox).size,CGSize(width:80,height:120))
        let saved=try Data(contentsOf:output)
        XCTAssertThrowsError(try ImagePDF.write([ImagePDFPage(url:a)],to:output))
        XCTAssertEqual(try Data(contentsOf:output),saved)
        XCTAssertThrowsError(try ImagePDF.write([ImagePDFPage(url:a),ImagePDFPage(url:folder.appendingPathComponent("missing.png"))],to:output,overwrite:true))
        XCTAssertEqual(try Data(contentsOf:output),saved)
        try ImagePDF.write([ImagePDFPage(url:a)],to:output,overwrite:true)
        XCTAssertEqual(PDFDocument(url:output)?.pageCount,1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:a.path));XCTAssertTrue(FileManager.default.fileExists(atPath:b.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:folder.path).contains {$0.hasPrefix(".utility-pdf-")})
    }
}
