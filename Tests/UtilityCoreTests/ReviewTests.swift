import XCTest
import CoreGraphics
import ImageIO
@testable import UtilityCore

final class ReviewTests:XCTestCase {
    func image()->CGImage {
        let c=CGContext(data:nil,width:120,height:80,bitsPerComponent:8,bytesPerRow:480,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));c.fill(CGRect(x:0,y:0,width:60,height:80));c.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1));c.fill(CGRect(x:60,y:0,width:60,height:80));return c.makeImage()!
    }
    func testPreciseResizeAndLockedBatchFit() throws {
        var step=ActionStep(kind:.resizeImage);step.width=300;step.height=100
        let stretched=try ImageEngine.transformed(step,image:image());XCTAssertEqual(stretched.width,300);XCTAssertEqual(stretched.height,100)
        step.aspectLocked=true;let fit=try ImageEngine.transformed(step,image:image());XCTAssertEqual(fit.width,150);XCTAssertEqual(fit.height,100)
        step.width=0;XCTAssertThrowsError(try step.validate())
    }
    func testCropAndCustomRotation() throws {
        var step=ActionStep(kind:.cropImage);step.crop=CropRegion(x:0.5,y:0,width:0.5,height:1)
        let crop=try ImageEngine.transformed(step,image:image());XCTAssertEqual(crop.width,60);XCTAssertEqual(crop.height,80)
        let rotation=try ImageEngine.transformed(.init(kind:.rotateImage,amount:45),image:image());XCTAssertEqual(rotation.width,142);XCTAssertEqual(rotation.height,142)
        step.crop=CropRegion(x:0.8,y:0,width:0.4,height:1);XCTAssertThrowsError(try step.validate())
        XCTAssertThrowsError(try ActionStep(kind:.rotateImage,amount:361).validate())
    }
    func testPNGCompressionKeepsAlphaAndUsesRealPixels() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:folder)}
        let c=CGContext(data:nil,width:240,height:160,bitsPerComponent:8,bytesPerRow:960,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        let p=c.data!.assumingMemoryBound(to:UInt8.self)
        for i in 0..<(240*160) { p[i*4]=UInt8((i*17)%127);p[i*4+1]=UInt8((i*31)%127);p[i*4+2]=UInt8((i*47)%127);p[i*4+3]=128 }
        let input=folder.appendingPathComponent("alpha.png");let dest=CGImageDestinationCreateWithURL(input as CFURL,"public.png" as CFString,1,nil)!;CGImageDestinationAddImage(dest,c.makeImage()!,nil);XCTAssertTrue(CGImageDestinationFinalize(dest))
        let low=try ImageEngine.apply(.init(kind:.compressImage,amount:10),input:input,directory:folder,name:"low"),high=try ImageEngine.apply(.init(kind:.compressImage,amount:90),input:input,directory:folder,name:"high")
        XCTAssertNotEqual(FileServices.bytes(low),FileServices.bytes(high));XCTAssertEqual(low.pathExtension,"png")
        let out=try ImageEngine.load(low);XCTAssertEqual(out.width,240);c.setBlendMode(.copy);c.draw(out,in:CGRect(x:0,y:0,width:240,height:160));XCTAssertEqual(Int(p[3]),128,accuracy:1)
    }
    func testLegacyWorkflowDecode() throws {
        let json="""
        {"schemaVersion":1,"id":"00000000-0000-0000-0000-000000000001","name":"Old preset","steps":[{"id":"00000000-0000-0000-0000-000000000002","kind":"resizeImage","amount":60,"format":"jpg"}]}
        """
        let workflow=try JSONDecoder().decode(WorkflowDefinition.self,from:Data(json.utf8));try workflow.validate(for:.image)
        let output=try ImageEngine.transformed(workflow.steps[0],image:image());XCTAssertEqual(output.width,60);XCTAssertEqual(output.height,40)
    }
    func testRadialPlacementKeepsFileClearAtEdges() {
        for screen in [CGRect(x:0,y:0,width:1440,height:860),CGRect(x:-1024,y:100,width:1024,height:720),CGRect(x:0,y:0,width:800,height:600)] {
            for anchor in [CGPoint(x:screen.midX,y:screen.midY),CGPoint(x:screen.minX+10,y:screen.maxY-10),CGPoint(x:screen.maxX-10,y:screen.maxY-10),CGPoint(x:screen.minX+10,y:screen.minY+10),CGPoint(x:screen.maxX-10,y:screen.minY+10)] {
                let layout=RadialLayout.make(anchor:anchor,screen:screen,upper:3,lower:8)
                XCTAssertEqual(layout.frames.count,11,"\(screen), \(anchor)")
                for (i,r) in layout.frames.enumerated() {
                    XCTAssertTrue(screen.contains(r));XCTAssertFalse(r.contains(anchor))
                    for other in layout.frames.dropFirst(i+1) { XCTAssertFalse(r.intersects(other),"Overlapping targets") }
                    if i<3 { XCTAssertGreaterThan(r.minY,layout.center.y) } else if i==3 {XCTAssertEqual(r.midY,layout.center.y)} else { XCTAssertLessThan(r.maxY,layout.center.y) }
                }
            }
        }
    }
    func testPaletteUsesAlignedRowsAndMovesAsAGroup() {
        let screen=CGRect(x:0,y:0,width:1440,height:900)
        let anchor=CGPoint(x:720,y:450)
        let layout=RadialLayout.make(anchor:anchor,screen:screen,upper:3,lower:7)
        XCTAssertEqual(layout.frames,RadialLayout.make(anchor:anchor,screen:screen,upper:3,lower:7).frames)
        XCTAssertEqual(Set(layout.frames.prefix(3).map(\.minY)).count,1)
        XCTAssertEqual(Set(layout.frames[4...6].map(\.minY)).count,1)
        XCTAssertEqual(Set(layout.frames[7...9].map(\.minY)).count,1)
        XCTAssertEqual(layout.frames[3].minX,layout.frames[2].minX)
        XCTAssertEqual(layout.frames[0].minX,layout.frames[4].minX)
        XCTAssertEqual(layout.frames[1].midX,anchor.x)
        XCTAssertEqual(layout.frames[3].midY,anchor.y)
        let shifted=RadialLayout.make(anchor:CGPoint(x:730,y:460),screen:screen,upper:3,lower:7)
        for (a,b) in zip(layout.frames,shifted.frames) { XCTAssertEqual(b.minX-a.minX,10);XCTAssertEqual(b.minY-a.minY,10) }
        for point in [CGPoint(x:400,y:100),CGPoint(x:50,y:200),CGPoint(x:750,y:400),CGPoint(x:400,y:550)] {
            let small=CGRect(x:0,y:0,width:800,height:600)
            let result=RadialLayout.make(anchor:point,screen:small,upper:4,lower:8)
            for frame in result.frames { XCTAssertTrue(small.contains(frame));XCTAssertFalse(frame.intersects(CGRect(x:point.x-30,y:point.y-30,width:60,height:60))) }
        }
    }
    func testSparseAndMixedMenuGeometry() {
        for (upper,lower,compact) in [(0,1,true),(0,2,true),(1,1,true),(3,7,false),(5,9,false)] {
            for screen in [CGRect(x:0,y:0,width:1440,height:900),CGRect(x:-800,y:0,width:800,height:600)] {
                for anchor in [CGPoint(x:screen.midX,y:screen.midY),CGPoint(x:screen.minX+10,y:screen.minY+10),CGPoint(x:screen.maxX-10,y:screen.maxY-10)] {
                    let layout=RadialLayout.make(anchor:anchor,screen:screen,upper:upper,lower:lower,compact:compact)
                    XCTAssertEqual(layout.frames.count,upper+lower)
                    for (i,frame) in layout.frames.enumerated() {
                        XCTAssertTrue(screen.contains(frame));XCTAssertFalse(frame.contains(anchor))
                        for next in layout.frames.dropFirst(i+1) {XCTAssertFalse(frame.intersects(next))}
                    }
                    if compact {XCTAssertEqual(Set(layout.frames.map(\.minY)).count,1)}
                }
            }
        }
    }
    func testImageMenuHasShelfBelowHEICAndPDFToRightOfFile() {
        for screen in [CGRect(x:0,y:0,width:1440,height:900),CGRect(x:-800,y:100,width:800,height:600)] {
            for anchor in [CGPoint(x:screen.midX,y:screen.midY),CGPoint(x:screen.minX+10,y:screen.minY+10),CGPoint(x:screen.maxX-10,y:screen.maxY-10),CGPoint(x:screen.midX,y:screen.maxY-10)] {
                let layout=RadialLayout.make(anchor:anchor,screen:screen,upper:4,lower:7,upperColumns:4)
                XCTAssertEqual(layout.frames.count,11)
                let formats=Array(layout.frames.prefix(4)),shelf=layout.frames[4],tools=Array(layout.frames.suffix(6))
                XCTAssertEqual(Set(formats.map(\.minY)).count,1)
                XCTAssertLessThan(shelf.maxY,formats.map(\.minY).min()!)
                XCTAssertEqual(shelf.midX,(formats[2].midX+formats[3].midX)/2)
                XCTAssertEqual(shelf.midY,layout.center.y)
                XCTAssertGreaterThan(shelf.minX,layout.center.x+36)
                XCTAssertEqual(Set(tools.map(\.minY)).count,2)
                XCTAssertEqual(Set(tools.map(\.minX)).count,3)
                XCTAssertEqual((formats[0].minX+formats[3].maxX)/2,layout.center.x)
                XCTAssertEqual((tools[0].minX+tools[2].maxX)/2,layout.center.x)
                let source=CGRect(x:anchor.x-36,y:anchor.y-36,width:72,height:72)
                for (i,frame) in layout.frames.enumerated() {
                    XCTAssertTrue(screen.contains(frame))
                    XCTAssertFalse(frame.intersects(source))
                    for next in layout.frames.dropFirst(i+1) {XCTAssertFalse(frame.intersects(next))}
                }
            }
        }
    }
    func testVideoPercentageAndMBRoundTrip() throws {
        var target=VideoSizeTarget(sourceBytes:100_000_000,percentage:40)
        XCTAssertEqual(target.megabytes,40);try target.validate()
        target.setMegabytes(25);XCTAssertEqual(target.percentage,25)
        XCTAssertEqual(target.targetMegabytes(for:20_000_000),5)
        target.setMegabytes(0);XCTAssertThrowsError(try target.validate())
        target.setMegabytes(101);XCTAssertThrowsError(try target.validate())
        target.percentage = .nan;XCTAssertThrowsError(try target.validate())
    }
    func testPromisedFileCollisionNeverDeletesOriginal() throws {
        let d=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true);defer { try? FileManager.default.removeItem(at:d) }
        let src=d.appendingPathComponent("receipt.txt"),dest=d.appendingPathComponent("dest");try FileManager.default.createDirectory(at:dest,withIntermediateDirectories:true);try Data("original".utf8).write(to:src)
        let existing=dest.appendingPathComponent("receipt.txt");try Data("existing".utf8).write(to:existing)
        XCTAssertThrowsError(try FileServices.transfer(src,to:dest,move:true,promisedName:"receipt.txt"));XCTAssertEqual(try String(contentsOf:src),"original");XCTAssertEqual(try String(contentsOf:existing),"existing")
        let moved=try FileServices.transfer(src,to:dest,move:true,promisedName:"receipt 2.txt");XCTAssertEqual(moved.lastPathComponent,"receipt 2.txt");XCTAssertFalse(FileManager.default.fileExists(atPath:src.path))
    }
}
