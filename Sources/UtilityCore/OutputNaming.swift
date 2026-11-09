import Foundation

public struct OutputNaming:Codable,Equatable,Sendable {
    public var compressed="compressed",cropped="cropped",rotated="rotated",flipped="flipped",edited="edited",muted="muted"
    public var resizePattern="{width}x{height}"
    public var speedPattern="{speed}x"
    public var workflowPattern="{workflow}"
    public var combinedImages="Combined_images",combinedDocuments="Combined_documents",combinedPages="Combined_pages"
    public init() {}
    public static func clean(_ value:String)->String {
        let forbidden=CharacterSet(charactersIn:"/:\\").union(.controlCharacters)
        let words=value.components(separatedBy:forbidden).joined(separator:"_").split(whereSeparator:{$0.isWhitespace}).joined(separator:"_")
        return words.trimmingCharacters(in:CharacterSet(charactersIn:"_ ."))
    }
    public func basename(input:URL,workflow:WorkflowDefinition,dimensions:CGSize?=nil)->String {
        let base=input.deletingPathExtension().lastPathComponent
        let suffix:String
        if workflow.steps.count>1 || workflow.isPreset == true {suffix=workflowPattern.replacingOccurrences(of:"{workflow}",with:Self.clean(workflow.name))}
        else if let step=workflow.steps.first {
            switch step.kind {
            case .compressImage,.compressVideo:suffix=compressed
            case .cropImage:suffix=cropped
            case .rotateImage:suffix=rotated
            case .flipHorizontal,.flipVertical:suffix=flipped
            case .muteVideo:suffix=muted
            case .speedVideo:suffix=speedPattern.replacingOccurrences(of:"{speed}",with:Self.number(step.amount))
            case .resizeImage:
                suffix=resizePattern.replacingOccurrences(of:"{width}",with:String(Int(dimensions?.width ?? CGFloat(step.width ?? Int(step.amount))))).replacingOccurrences(of:"{height}",with:String(Int(dimensions?.height ?? CGFloat(step.height ?? Int(step.amount)))))
            default:suffix=""
            }
        } else {suffix=""}
        return Self.appending(base,suffix:Self.clean(suffix))
    }
    public static func number(_ value:Double)->String {String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value).replacingOccurrences(of:"0+$",with:"",options:.regularExpression).replacingOccurrences(of:"\\.$",with:"",options:.regularExpression)}
    public static func appending(_ base:String,suffix:String)->String {
        guard !suffix.isEmpty else {return base}
        var stem=base
        if let range=stem.range(of:"_(?:[2-9]|[1-9][0-9]+)$",options:.regularExpression) {
            let candidate=String(stem[..<range.lowerBound]);if candidate.hasSuffix("_"+suffix) {stem=candidate}
        }
        return stem.hasSuffix("_"+suffix) ? stem:stem+"_"+suffix
    }
    public func pdfName(inputs:[URL])->String {
        guard let first=inputs.first else {return combinedPages+".pdf"}
        if inputs.count==1 {return (AssetKind(url:first) == .pdf ? Self.appending(first.deletingPathExtension().lastPathComponent,suffix:Self.clean(edited)):first.deletingPathExtension().lastPathComponent)+".pdf"}
        let kinds=Set(inputs.map {AssetKind(url:$0)})
        return Self.clean(kinds == [.image] ? combinedImages:kinds == [.pdf] ? combinedDocuments:combinedPages)+".pdf"
    }
}
