import AppKit
import PDFKit

public struct AssemblyPage:Identifiable,Equatable,Sendable {
    public var id=UUID()
    public let documentID:UUID
    public let url:URL
    public let pageIndex:Int?
    public var quarterTurns=0
    public init(url:URL,documentID:UUID=UUID(),pageIndex:Int?=nil) {self.url=url;self.documentID=documentID;self.pageIndex=pageIndex}
    public var caption:String {pageIndex.map {"\(url.lastPathComponent) · \($0+1)"} ?? url.lastPathComponent}
    public static func moving(_ pages:[Self],ids:Set<UUID>,before position:Int)->[Self] {
        let index=max(0,min(position,pages.count)),group=pages.filter {ids.contains($0.id)}
        let insertion=pages.prefix(index).filter {!ids.contains($0.id)}.count
        var result=pages.filter {!ids.contains($0.id)};result.insert(contentsOf:group,at:insertion);return result
    }
}
public enum ImagePageSize:String,CaseIterable,Identifiable,Sendable {
    case image,letter,a4
    public var id:String {rawValue}
    public var title:String {switch self {case .image:return "Image size";case .letter:return "US Letter";case .a4:return "A4"}}
    public var size:CGSize? {switch self {case .image:return nil;case .letter:return CGSize(width:612,height:792);case .a4:return CGSize(width:595.28,height:841.89)}}
}
public enum PDFAssembly {
    public static func load(_ urls:[URL])throws->[AssemblyPage] {
        var pages:[AssemblyPage]=[]
        let lease=AccessLease(urls:urls);defer {_=lease}
        for url in urls {
            try Task.checkCancellation();let id=UUID()
            if AssetKind(url:url) == .image {pages.append(AssemblyPage(url:url,documentID:id))}
            else if AssetKind(url:url) == .pdf {
                guard let document=PDFDocument(url:url),!document.isLocked else {throw UtilityError.message("Can’t open \(url.lastPathComponent). It may be locked or damaged")}
                guard document.allowsDocumentAssembly else {throw UtilityError.message("\(url.lastPathComponent) does not permit page changes")}
                guard document.pageCount<=500-pages.count else {throw UtilityError.message("Choose up to 500 pages")}
                pages += (0..<document.pageCount).map {AssemblyPage(url:url,documentID:id,pageIndex:$0)}
            }
            guard pages.count<=500 else {throw UtilityError.message("Choose up to 500 pages")}
        }
        guard !pages.isEmpty else {throw UtilityError.message("Add images or PDF documents")};return pages
    }
    public static func page(_ item:AssemblyPage,size:ImagePageSize = .image,margin:Double=0,maximumImageSide:Int?=nil)throws->PDFPage {
        let lease=AccessLease(urls:[item.url]);defer {_=lease}
        let page:PDFPage
        if let index=item.pageIndex {
            guard let document=PDFDocument(url:item.url),!document.isLocked,document.allowsDocumentAssembly,let source=document.page(at:index),let copied=source.copy() as? PDFPage else {throw UtilityError.message("Could not load \(item.caption)")}
            page=copied
        } else {
            let image=try ImageEngine.load(item.url,maximumSide:maximumImageSide)
            let turns=((item.quarterTurns%4)+4)%4
            let rotated=turns==0 ? image:try ImageEngine.transformed(.init(kind:.rotateImage,amount:Double(turns*90)),image:image)
            let fit=min(1,720/CGFloat(max(rotated.width,rotated.height)))
            let canvas=size.size ?? CGSize(width:CGFloat(rotated.width)*fit,height:CGFloat(rotated.height)*fit)
            let inset=size == .image ? 0:max(0,min(72,margin))
            let available=CGRect(origin:.zero,size:canvas).insetBy(dx:inset,dy:inset)
            let scale=min(available.width/CGFloat(rotated.width),available.height/CGFloat(rotated.height))
            let drawing=CGRect(x:(canvas.width-CGFloat(rotated.width)*scale)/2,y:(canvas.height-CGFloat(rotated.height)*scale)/2,width:CGFloat(rotated.width)*scale,height:CGFloat(rotated.height)*scale)
            let data=NSMutableData();var box=CGRect(origin:.zero,size:canvas)
            guard let consumer=CGDataConsumer(data:data),let context=CGContext(consumer:consumer,mediaBox:&box,nil) else {throw UtilityError.message("Could not create the image page")}
            context.beginPDFPage(nil);context.setFillColor(CGColor(gray:1,alpha:1));context.fill(box);context.draw(rotated,in:drawing);context.endPDFPage();context.closePDF()
            guard let rendered=PDFDocument(data:data as Data)?.page(at:0)?.copy() as? PDFPage else {throw UtilityError.message("Could not render the image page")};page=rendered
        }
        if item.pageIndex != nil {page.rotation=(page.rotation+item.quarterTurns*90+1440)%360}
        return page
    }
    public static func write(_ pages:[AssemblyPage],to output:URL,size:ImagePageSize = .image,margin:Double=0,overwrite:Bool=false)throws {
        guard !pages.isEmpty,pages.count<=500 else {throw UtilityError.message("Export between 1 and 500 pages")}
        guard !pages.contains(where:{$0.url.resolvingSymlinksInPath().standardizedFileURL==output.resolvingSymlinksInPath().standardizedFileURL}) else {throw UtilityError.message("Choose a new filename to preserve the source")}
        let lease=AccessLease(urls:pages.map(\.url)+[output.deletingLastPathComponent()]);defer {_=lease}
        let document=PDFDocument()
        for item in pages {try Task.checkCancellation();document.insert(try page(item,size:size,margin:margin),at:document.pageCount)}
        guard let data=document.dataRepresentation() else {throw UtilityError.message("Could not encode the PDF")}
        try Task.checkCancellation()
        let temporary=output.deletingLastPathComponent().appendingPathComponent(".utility-assembly-\(UUID().uuidString).pdf")
        defer {try? FileManager.default.removeItem(at:temporary)}
        try data.write(to:temporary,options:.atomic)
        if FileManager.default.fileExists(atPath:output.path) {
            guard overwrite else {throw UtilityError.message("A file already exists at this location")}
            _=try FileManager.default.replaceItemAt(output,withItemAt:temporary)
        } else {try FileManager.default.moveItem(at:temporary,to:output)}
    }
}
