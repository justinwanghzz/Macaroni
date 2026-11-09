import Foundation
import Vision
import PDFKit
import AppKit

public enum OCREngine {
    public static func markdown(image url:URL)throws->String {
        let text=try recognize(ImageEngine.load(url,maximumSide:5000))
        guard !text.isEmpty else {throw UtilityError.message("No readable text was found in this image")}
        return text+"\n"
    }
    public static func recognize(_ image:CGImage)throws->String {
        try Task.checkCancellation()
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
        request.usesLanguageCorrection=true;request.automaticallyDetectsLanguage=true
        let supported=try request.supportedRecognitionLanguages()
        request.recognitionLanguages=["en-US","zh-Hans","zh-Hant"].filter {supported.contains($0)}
        try VNImageRequestHandler(cgImage:image).perform([request])
        try Task.checkCancellation()
        let observations=(request.results ?? []).sorted { a,b in
            let tolerance=min(a.boundingBox.height,b.boundingBox.height)*0.45
            if abs(a.boundingBox.midY-b.boundingBox.midY)<tolerance {return a.boundingBox.minX<b.boundingBox.minX}
            return a.boundingBox.midY>b.boundingBox.midY
        }
        var result="",previous:CGRect?
        for observation in observations {
            guard var line=observation.topCandidates(1).first?.string.trimmingCharacters(in:.whitespacesAndNewlines),!line.isEmpty else {continue}
            if line.hasPrefix("• ") {line="- "+line.dropFirst(2)}
            if let prior=previous {
                let gap=prior.minY-observation.boundingBox.maxY
                result += gap>max(prior.height,observation.boundingBox.height)*0.85 ? "\n\n":"\n"
            }
            result+=line;previous=observation.boundingBox
        }
        return result
    }
    public static func recognize(page:PDFPage)throws->String {try recognize(render(page:page))}
    public static func render(page:PDFPage)throws->CGImage {
        let rect=page.bounds(for:.mediaBox)
        guard rect.width>0,rect.height>0 else {throw UtilityError.message("This PDF page has invalid dimensions")}
        // Draw directly into a bounded bitmap. PDFKit thumbnails can render at the
        // screen backing scale again, making OCR needlessly process huge images.
        guard let pageRef=page.pageRef else {throw UtilityError.message("Could not read this PDF page")}
        let rotated=abs(page.rotation)%180 != 0
        let size=rotated ? CGSize(width:rect.height,height:rect.width):rect.size
        let factor=min(2.5,2600/max(size.width,size.height))
        let width=max(1,Int(ceil(size.width*factor))),height=max(1,Int(ceil(size.height*factor)))
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {throw UtilityError.message("Could not allocate an OCR preview")}
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
        context.concatenate(pageRef.getDrawingTransform(.mediaBox,rect:CGRect(x:0,y:0,width:width,height:height),rotate:0,preserveAspectRatio:true))
        context.drawPDFPage(pageRef)
        guard let image=context.makeImage() else {throw UtilityError.message("Could not render this PDF page for OCR")}
        return image
    }
}
