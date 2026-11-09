import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageEngine {
    public static var writableFormats: [String] {
        let types = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        return [("jpg", UTType.jpeg), ("png", .png), ("heic", .heic)].filter { types.contains($0.1.identifier) }.map(\.0)
    }
    public static func load(_ input: URL, maximumSide: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(source) > 0 else { throw UtilityError.message("This image couldn’t be opened") }
        guard CGImageSourceGetCount(source) == 1 else { throw UtilityError.message("Choose a still image instead of an animation") }
        let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard w > 0, h > 0, Double(w)*Double(h) <= 120_000_000 else { throw UtilityError.message("This image exceeds 120 megapixels") }
        let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:min(max(w,h),maximumSide ?? max(w,h)),kCGImageSourceShouldCacheImmediately:true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else { throw UtilityError.message("This image couldn’t be decoded") }
        return image
    }
    public static func transformed(_ step: ActionStep, image: CGImage) throws -> CGImage {
        try step.validate(); try Task.checkCancellation()
        switch step.kind {
        case .cropImage:
            let r = step.crop!
            let x=max(0,min(image.width-1,Int((r.x*Double(image.width)).rounded()))), y=max(0,min(image.height-1,Int((r.y*Double(image.height)).rounded())))
            let rect = CGRect(x:x,y:y,width:min(image.width-x,max(1,Int((r.width*Double(image.width)).rounded()))),height:min(image.height-y,max(1,Int((r.height*Double(image.height)).rounded()))))
            guard let result = image.cropping(to:rect), result.width > 0, result.height > 0 else { throw UtilityError.message("Choose a larger crop") }; return result
        case .resizeImage:
            let w: Int, h: Int
            if let width = step.width, let height = step.height { if step.aspectLocked == true { let scale = min(Double(width)/Double(image.width),Double(height)/Double(image.height));w = max(1,Int((Double(image.width)*scale).rounded()));h = max(1,Int((Double(image.height)*scale).rounded())) } else { w = width; h = height } }
            else { let scale = min(1,step.amount/Double(max(image.width,image.height))); w = max(1,Int((Double(image.width)*scale).rounded())); h = max(1,Int((Double(image.height)*scale).rounded())) }
            return try canvas(width:w,height:h) { $0.draw(image,in:CGRect(x:0,y:0,width:w,height:h)) }
        case .rotateImage:
            let angle = step.amount * .pi / 180
            let w = max(1,Int(ceil(abs(Double(image.width)*cos(angle))+abs(Double(image.height)*sin(angle))-0.000001)))
            let h = max(1,Int(ceil(abs(Double(image.width)*sin(angle))+abs(Double(image.height)*cos(angle))-0.000001)))
            guard Double(w)*Double(h) <= 120_000_000 else { throw UtilityError.message("The rotated canvas is too large") }
            return try canvas(width:w,height:h) { c in c.translateBy(x:CGFloat(w)/2,y:CGFloat(h)/2); c.rotate(by:-angle); c.draw(image,in:CGRect(x:-CGFloat(image.width)/2,y:-CGFloat(image.height)/2,width:CGFloat(image.width),height:CGFloat(image.height))) }
        case .flipHorizontal,.flipVertical:
            return try canvas(width:image.width,height:image.height) { c in
                if step.kind == .flipHorizontal { c.translateBy(x:CGFloat(image.width),y:0); c.scaleBy(x:-1,y:1) }
                else { c.translateBy(x:0,y:CGFloat(image.height)); c.scaleBy(x:1,y:-1) }
                c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            }
        default: return image
        }
    }
    public static func apply(_ step: ActionStep, input: URL, directory: URL, name: String) throws -> URL {
        let source = CGImageSourceCreateWithURL(input as CFURL,nil)
        var metadata = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0,0,nil) as? [CFString:Any] } ?? [:]
        var image = try transformed(step,image:load(input))
        let original = input.pathExtension.lowercased()
        var ext = ["jpg","jpeg","png","heic","heif"].contains(original) ? original : "png"
        if ext == "jpeg" { ext = "jpg" }; if ext == "heif" { ext = "heic" }
        if step.kind == .convertImage { ext = step.format }
        guard writableFormats.contains(ext) else { throw UtilityError.message("\(ext.uppercased()) export isn’t available on this Mac") }
        if step.kind == .compressImage && ext == "png" && step.amount < 100 { image = try quantized(image,quality:step.amount) }
        if ext == "jpg" { image = try flattenForJPEG(image) }
        let type: UTType = ext == "jpg" ? .jpeg : ext == "heic" ? .heic : .png
        let output = directory.appendingPathComponent(name).appendingPathExtension(ext)
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL,type.identifier as CFString,1,nil) else { throw UtilityError.message("Couldn’t create the output") }
        metadata[kCGImagePropertyOrientation] = 1
        if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString:Any] { tiff[kCGImagePropertyTIFFOrientation] = 1; metadata[kCGImagePropertyTIFFDictionary] = tiff }
        metadata[kCGImagePropertyPixelWidth] = image.width; metadata[kCGImagePropertyPixelHeight] = image.height
        metadata[kCGImageDestinationLossyCompressionQuality] = step.kind == .compressImage ? step.amount/100 : 0.9
        CGImageDestinationAddImage(dest,image,metadata as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { try? FileManager.default.removeItem(at:output); throw UtilityError.message("Couldn’t finish exporting the image") }
        return output
    }
    public static func flattenForJPEG(_ image:CGImage) throws -> CGImage {
        try canvas(width:image.width,height:image.height) { c in c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:0,y:0,width:image.width,height:image.height));c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height)) }
    }
    private static func quantized(_ image: CGImage, quality: Double) throws -> CGImage {
        let levels = Double((1 << Int((2+quality*0.06).rounded())) - 1)
        return try canvas(width:image.width,height:image.height) { c in
            c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            let p = c.data!.assumingMemoryBound(to:UInt8.self)
            for y in 0..<image.height { try Task.checkCancellation(); for x in 0..<image.width { let i = y*c.bytesPerRow+x*4; let a = Double(p[i+3]); if a == 0 { continue }; for channel in 0..<3 { let straight = Double(p[i+channel])/a; p[i+channel] = UInt8(max(0,min(a,(straight*levels).rounded()/levels*a))) } } }
        }
    }
    private static func canvas(width: Int,height: Int,draw: (CGContext)throws->Void) throws -> CGImage {
        guard let ctx = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw UtilityError.message("Couldn’t allocate the image canvas") }
        ctx.interpolationQuality = .high; try draw(ctx)
        guard let image = ctx.makeImage() else { throw UtilityError.message("Couldn’t render the image") }; return image
    }
}
