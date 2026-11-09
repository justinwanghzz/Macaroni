import Foundation
import UniformTypeIdentifiers

public enum UtilityError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public enum AssetKind: String, Codable, CaseIterable {
    case image, video, pdf, word, presentation, spreadsheet, markdown, text, other
    public init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "webp", "bmp": self = .image
        case "mov", "mp4", "m4v", "avi", "mkv": self = .video
        case "pdf": self = .pdf
        case "docx": self = .word
        case "pptx": self = .presentation
        case "xlsx": self = .spreadsheet
        case "md", "markdown": self = .markdown
        case "txt", "csv", "json", "tex": self = .text
        default:
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .image) == true { self = .image }
            else if type?.conforms(to: .movie) == true { self = .video }
            else { self = .other }
        }
    }
}

public enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case convertImage, compressImage, resizeImage, rotateImage, cropImage, flipHorizontal, flipVertical, documentMarkdown, compressVideo, muteVideo, speedVideo, exportPDF
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .convertImage: return "Convert image"
        case .compressImage: return "Compress"
        case .resizeImage: return "Resize"
        case .rotateImage: return "Rotate"
        case .cropImage: return "Crop"
        case .flipHorizontal: return "Flip horizontally"
        case .flipVertical: return "Flip vertically"
        case .documentMarkdown: return "Convert to Markdown"
        case .compressVideo: return "Compress video"
        case .muteVideo:return "Mute video"
        case .speedVideo:return "Video speed"
        case .exportPDF:return "Export to PDF"
        }
    }
    public var symbol: String {
        switch self {
        case .convertImage: return "arrow.triangle.2.circlepath"
        case .compressImage, .compressVideo: return "arrow.down.right.and.arrow.up.left"
        case .resizeImage: return "arrow.up.left.and.arrow.down.right"
        case .rotateImage: return "rotate.right"
        case .cropImage: return "crop"
        case .flipHorizontal, .flipVertical: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .documentMarkdown: return "doc.text"
        case .muteVideo:return "speaker.slash"
        case .speedVideo:return "speedometer"
        case .exportPDF:return "doc.richtext"
        }
    }
    public func accepts(_ kind: AssetKind) -> Bool {
        switch self {
        case .documentMarkdown: return [.image, .pdf, .word, .presentation, .text, .markdown].contains(kind)
        case .compressVideo,.muteVideo,.speedVideo: return kind == .video
        default: return kind == .image
        }
    }
    public func outputKind(for input: AssetKind) -> AssetKind { self == .documentMarkdown ? .markdown:self == .exportPDF ? .pdf:input }
    public static var imageSteps:[Self] {[.convertImage,.compressImage,.resizeImage,.rotateImage,.cropImage,.flipHorizontal,.flipVertical,.exportPDF]}
}

public struct CropRegion: Codable, Equatable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var isValid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.000001 && y + height <= 1.000001 }
}

public struct ActionStep: Codable, Identifiable, Equatable {
    public var id: UUID
    public var kind: ActionKind
    public var amount: Double
    public var format: String
    public var width: Int?
    public var height: Int?
    public var crop: CropRegion?
    public var aspectLocked: Bool?
    public init(kind: ActionKind, amount: Double? = nil, format: String = "jpg", id: UUID = UUID()) {
        self.id = id; self.kind = kind; self.format = format
        self.amount = amount ?? (kind == .resizeImage ? 1600 : kind == .compressVideo ? 25 : kind == .rotateImage ? 90 : kind == .speedVideo ? 1:70)
    }
    public func validate() throws {
        guard amount.isFinite else { throw UtilityError.message("Enter a finite number") }
        switch kind {
        case .convertImage:
            guard ["jpg", "png", "heic"].contains(format) else { throw UtilityError.message("Unsupported image output format") }
        case .compressImage:
            guard (1...100).contains(amount) else { throw UtilityError.message("Image quality must be between 1 and 100") }
        case .resizeImage:
            if let width, let height { guard (1...16000).contains(width), (1...16000).contains(height), Double(width) * Double(height) <= 120_000_000 else { throw UtilityError.message("Choose dimensions up to 16000 px per edge and 120 megapixels") }; return }
            guard (1...16000).contains(amount) else { throw UtilityError.message("Longest edge must be between 1 and 16000 pixels") }
        case .compressVideo:
            guard amount >= 0.01, amount <= 10000 else { throw UtilityError.message("Video target must be between 0.01 and 10000 MB") }
        case .speedVideo:guard (0.25...3).contains(amount) else {throw UtilityError.message("Choose a speed from 0.25× to 3×")}
        case .rotateImage:
            guard (-360...360).contains(amount) else { throw UtilityError.message("Choose an angle between −360° and 360°") }
        case .cropImage:
            guard let crop, crop.isValid else { throw UtilityError.message("Choose a crop inside the image") }
        default: break
        }
    }
}

public struct WorkflowDefinition: Codable, Identifiable, Equatable {
    public var schemaVersion = 1
    public var id: UUID
    public var name: String
    public var steps: [ActionStep]
    public var pinned:Bool?
    public var isPreset:Bool?
    public init(name: String, steps: [ActionStep], id: UUID = UUID()) { self.name = name; self.steps = steps; self.id = id }
    public func validate(for input: AssetKind) throws {
        guard schemaVersion == 1 else { throw UtilityError.message("This workflow was created by an unsupported version") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw UtilityError.message("Give the workflow a name") }
        guard !steps.isEmpty, steps.count <= 12 else { throw UtilityError.message("A workflow needs between 1 and 12 steps") }
        var current = input
        for step in steps {
            try step.validate()
            guard step.kind.accepts(current) else { throw UtilityError.message("\(step.kind.title) cannot process \(current.rawValue) content") }
            current = step.kind.outputKind(for: current)
        }
    }
    public static var examples: [Self] {
        [.init(name: "Images for sharing", steps: [.init(kind: .convertImage), .init(kind: .resizeImage), .init(kind: .compressImage)])]
    }
}

public struct FileReference: Codable, Identifiable, Equatable {
    public var id: UUID
    public var path: String
    public var bookmark: Data?
    public init(url: URL, id: UUID = UUID()) {
        self.id = id; self.path = url.standardizedFileURL.path
        bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    public var url: URL {
        if let bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) { return resolved }
        }
        return URL(fileURLWithPath: path)
    }
}

public enum ItemStatus: String, Codable { case succeeded, failed, skipped, cancelled }
public struct ItemResult: Codable, Identifiable {
    public var id = UUID()
    public var input: String
    public var output: String?
    public var status: ItemStatus
    public var message: String
    public init(input: String, output: String? = nil, status: ItemStatus, message: String) {
        self.input = input; self.output = output; self.status = status; self.message = message
    }
}

public enum JSONStore {
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
