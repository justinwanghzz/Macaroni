import AppKit
import Foundation

public struct ClipboardEntry:Codable,Identifiable {
    public var id=UUID()
    public var text:String
    public var pinned=false
    public var png:Data?
    public var files:[FileReference]?
    public init(text:String,png:Data?=nil,files:[FileReference]?=nil) {self.text=text;self.png=png;self.files=files}
    public var isFiles:Bool { !(files ?? []).isEmpty }
    public var unavailableFiles:[FileReference] { (files ?? []).filter {!FileManager.default.fileExists(atPath:$0.url.path)} }
    public var storedBytes:Int {text.utf8.count+(png?.count ?? 0)+(files ?? []).reduce(0) {$0+$1.path.utf8.count+($1.bookmark?.count ?? 0)}}
    public func sameContent(as other:Self)->Bool {
        if isFiles || other.isFiles {return isFiles && other.isFiles && files!.map(\.path)==other.files!.map(\.path)}
        return text==other.text && png==other.png
    }
    public static func capture(from pb:NSPasteboard)->Self? {
        let count=pb.changeCount
        let urls=pb.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []
        let entry:Self?
        if !urls.isEmpty,urls.count<=1000 {
            let files=urls.map {FileReference(url:$0)}
            entry=Self(text:urls.map(\.lastPathComponent).joined(separator:", "),files:files)
        } else if let raw=pb.data(forType:.png) ?? pb.data(forType:.tiff),raw.count<=20_000_000,let bitmap=NSBitmapImageRep(data:raw),let data=bitmap.representation(using:.png,properties:[:]),data.count<=20_000_000 {
            entry=Self(text:"Image",png:data)
        } else if let text=pb.string(forType:.string),!text.isEmpty,text.utf8.count<=1_000_000 {entry=Self(text:text)}
        else {entry=nil}
        return count==pb.changeCount ? entry:nil
    }
    /// Validate before replacing the clipboard. Keep the returned lease alive for destination reads.
    @discardableResult public func restore(to pb:NSPasteboard)throws->AccessLease {
        if isFiles {
            let refs=files!,urls=refs.map(\.url),lease=AccessLease(urls:urls)
            let missing=urls.filter {!FileManager.default.fileExists(atPath:$0.path)}
            guard missing.isEmpty else {throw UtilityError.message("Files unavailable: "+missing.prefix(3).map(\.lastPathComponent).joined(separator:", "))}
            pb.clearContents()
            guard pb.writeObjects(urls.map {$0 as NSURL}) else {throw UtilityError.message("Couldn’t copy these file references")}
            return lease
        }
        let item=NSPasteboardItem()
        if let png {
            guard let bitmap=NSBitmapImageRep(data:png) else {throw UtilityError.message("This image could not be restored")}
            item.setData(png,forType:.png)
            if let tiff=bitmap.tiffRepresentation {item.setData(tiff,forType:.tiff)}
        } else {item.setString(text,forType:.string)}
        pb.clearContents()
        guard pb.writeObjects([item]) else {throw UtilityError.message("Couldn’t restore this clipboard entry")}
        return AccessLease(urls:[])
    }
}
