import Foundation
import CoreGraphics

public struct ImagePDFPage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public var quarterTurns: Int
    public init(url: URL, id: UUID = UUID(), quarterTurns: Int = 0) {
        self.id=id;self.url=url;self.quarterTurns=quarterTurns
    }
    public static func moving(_ pages:[Self], ids:Set<UUID>, before destination:Int)->[Self] {
        let index=max(0,min(destination,pages.count))
        let moving=pages.filter { ids.contains($0.id) }
        let insertion=pages.prefix(index).filter { !ids.contains($0.id) }.count
        var remaining=pages.filter { !ids.contains($0.id) }
        remaining.insert(contentsOf:moving,at:insertion)
        return remaining
    }
}

public enum ImagePDF {
    /// Each image is a page, preserving its aspect ratio and the user's chosen order.
    /// The output is replaced only after every page has been successfully written.
    public static func write(_ pages:[ImagePDFPage], to output:URL, overwrite:Bool=false) throws {
        guard !pages.isEmpty else { throw UtilityError.message("Add at least one image") }
        let fm=FileManager.default
        guard !pages.contains(where: { $0.url.standardizedFileURL == output.standardizedFileURL }) else { throw UtilityError.message("Choose a different output filename") }
        let lease=AccessLease(urls:pages.map(\.url)+[output.deletingLastPathComponent()]);defer { _=lease }
        let temporary=output.deletingLastPathComponent().appendingPathComponent(".utility-pdf-\(UUID().uuidString).pdf")
        defer { try? fm.removeItem(at:temporary) }
        guard let consumer=CGDataConsumer(url:temporary as CFURL),let context=CGContext(consumer:consumer,mediaBox:nil,nil) else { throw UtilityError.message("Could not create the PDF") }
        var closed=false
        defer { if !closed { context.closePDF() } }
        for page in pages {
            try Task.checkCancellation()
            let original=try ImageEngine.load(page.url)
            let turns=((page.quarterTurns%4)+4)%4
            let image=turns==0 ? original : try ImageEngine.transformed(.init(kind:.rotateImage,amount:Double(turns*90)),image:original)
            let scale=min(1,720/CGFloat(max(image.width,image.height)))
            let bounds=CGRect(x:0,y:0,width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
            let box=withUnsafeBytes(of:bounds) { Data($0) }
            context.beginPDFPage([kCGPDFContextMediaBox as String:box] as CFDictionary)
            context.setFillColor(CGColor(gray:1,alpha:1));context.fill(bounds)
            context.draw(image,in:bounds);context.endPDFPage()
        }
        context.closePDF();closed=true
        try Task.checkCancellation()
        if fm.fileExists(atPath:output.path) {
            guard overwrite else { throw UtilityError.message("A file already exists at this location") }
            _=try fm.replaceItemAt(output,withItemAt:temporary)
        } else { try fm.moveItem(at:temporary,to:output) }
    }
}
