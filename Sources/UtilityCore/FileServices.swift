import Foundation
import CryptoKit

public final class AccessLease {
    private var active: [URL] = []
    public init(urls: [URL]) {
        for url in Set(urls) where url.startAccessingSecurityScopedResource() { active.append(url) }
    }
    deinit { active.forEach { $0.stopAccessingSecurityScopedResource() } }
}

public enum FileServices {
    private static let outputLock = NSLock()
    public static func bytes(_ url: URL) -> Int64 { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
    public static func sizeLabel(_ url: URL) -> String { ByteCountFormatter.string(fromByteCount: bytes(url), countStyle: .file) }

    /// The move into the destination is serialized with collision-free name selection.
    public static func commit(_ temporary: URL, to directory: URL, baseName: String, exact: Bool = false, collisionSeparator:String="_") throws -> URL {
        outputLock.lock(); defer { outputLock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fm = FileManager.default
        var staged = temporary
        var stagingFolder: URL?
        let a = (try? temporary.resourceValues(forKeys:[.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        let b = (try? directory.resourceValues(forKeys:[.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        if a == nil || b == nil || !a!.isEqual(b!) {
            let folder=directory.appendingPathComponent(".utility-commit-"+UUID().uuidString)
            try fm.createDirectory(at:folder,withIntermediateDirectories:false);stagingFolder=folder
            staged=folder.appendingPathComponent(temporary.lastPathComponent)
            do { try fm.copyItem(at:temporary,to:staged) } catch { try? fm.removeItem(at:folder);throw error }
        }
        defer { if let stagingFolder { try? fm.removeItem(at:stagingFolder) } }
        let ext = temporary.pathExtension
        let safeBase = baseName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var index = 1
        while index < 100000 {
            let name = safeBase + (index == 1 ? "" : "\(collisionSeparator)\(index)")
            let stem = directory.appendingPathComponent(name)
            let target = ext.isEmpty ? stem : stem.appendingPathExtension(ext)
            if exact && FileManager.default.fileExists(atPath: target.path) { throw UtilityError.message("A file with that name already exists") }
            if !FileManager.default.fileExists(atPath: target.path) {
                do { try FileManager.default.moveItem(at: staged, to: target); if stagingFolder != nil { try? fm.removeItem(at:temporary) }; return target }
                catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { if exact {throw error};index += 1; continue }
            }
            index += 1
        }
        throw UtilityError.message("Could not reserve a unique output filename")
    }

    private static func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { try Task.checkCancellation(); hash.update(data: block) }
        return hash.finalize()
    }

    public static func transfer(_ source: URL, to directory: URL, move: Bool, promisedName: String? = nil) throws -> URL {
        guard promisedName != nil || source.standardizedFileURL.deletingLastPathComponent() != directory.standardizedFileURL else {
            throw UtilityError.message("This file is already in the selected folder")
        }
        try Task.checkCancellation()
        guard (try source.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { throw UtilityError.message("Copy and move currently support regular files only") }
        let fm = FileManager.default
        let work = directory.appendingPathComponent(".utility-transfer-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let temp = work.appendingPathComponent(source.lastPathComponent)
        try fm.copyItem(at: source, to: temp)
        try Task.checkCancellation()
        guard bytes(source) == bytes(temp), try digest(source) == digest(temp) else { throw UtilityError.message("Copied file size does not match the source") }
        let output = try commit(temp, to: directory, baseName: promisedName.map { URL(fileURLWithPath:$0).deletingPathExtension().lastPathComponent } ?? source.deletingPathExtension().lastPathComponent, exact: promisedName != nil,collisionSeparator:" ")
        if move {
            do { try fm.removeItem(at: source) }
            catch { throw UtilityError.message("Copied to \(output.path), but could not remove the original: \(error.localizedDescription)") }
        }
        return output
    }
}

public enum ProcessingEngine {
    public static func run(input: URL, workflow: WorkflowDefinition, outputDirectory: URL, progress: @escaping (Double) -> Void = { _ in },naming:OutputNaming=OutputNaming()) async throws -> URL {
        try workflow.validate(for: AssetKind(url: input))
        guard FileManager.default.isReadableFile(atPath: input.path) else { throw UtilityError.message("The input is missing or cannot be read") }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("utility-job-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var current = input
        for (index, step) in workflow.steps.enumerated() {
            try Task.checkCancellation()
            let fraction = Double(index) / Double(workflow.steps.count)
            let stageProgress: (Double) -> Void = { progress(fraction + $0 / Double(workflow.steps.count)) }
            switch step.kind {
            case .documentMarkdown:
                let out = work.appendingPathComponent("step-\(index).md")
                try DocumentEngine.markdown(from: current,progress:stageProgress).write(to: out, atomically: true, encoding: .utf8)
                current = out
            case .exportPDF:
                let out=work.appendingPathComponent("step-\(index).pdf")
                try PDFAssembly.write(PDFAssembly.load([current]),to:out);current=out
            case .muteVideo,.speedVideo:
                let out=work.appendingPathComponent("step-\(index).mp4")
                try await VideoEngine.adjust(current,to:out,speed:step.kind == .speedVideo ? step.amount:1,muted:step.kind == .muteVideo,progress:stageProgress);current=out
            case .compressVideo:
                let out = work.appendingPathComponent("step-\(index).mp4")
                try await VideoEngine.compress(current, to: out, maximumBytes: Int64(step.amount * 1_000_000), progress: stageProgress)
                current = out
            default:
                current = try ImageEngine.apply(step, input: current, directory: work, name: "step-\(index)")
            }
            stageProgress(1)
        }
        try Task.checkCancellation()
        var dimensions:CGSize?
        if workflow.steps.last?.kind == .resizeImage,let image=try? ImageEngine.load(current) {dimensions=CGSize(width:image.width,height:image.height)}
        return try FileServices.commit(current,to:outputDirectory,baseName:naming.basename(input:input,workflow:workflow,dimensions:dimensions))
    }
}
