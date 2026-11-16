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
    private static let transferLock = NSLock()
    public static func bytes(_ url: URL) -> Int64 { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
    public static func sizeLabel(_ url: URL) -> String { ByteCountFormatter.string(fromByteCount: bytes(url), countStyle: .file) }

    /// The move into the destination is serialized with collision-free name selection.
    public static func commit(_ temporary: URL, to directory: URL, baseName: String, exact: Bool = false, collisionSeparator:String="_") throws -> URL {
        let safeBase = baseName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return try commitNamed(temporary, to: directory, baseName: safeBase, extension: temporary.pathExtension,
                               exact: exact, collisionSeparator: collisionSeparator)
    }

    private static func commitNamed(_ temporary: URL, to directory: URL, baseName: String, extension ext: String,
                                    exact: Bool, collisionSeparator: String) throws -> URL {
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
        var index = 1
        while index < 100000 {
            let name = baseName + (index == 1 ? "" : "\(collisionSeparator)\(index)")
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
        transferLock.lock()
        defer { transferLock.unlock() }
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL
        let destinationPath = directory.resolvingSymlinksInPath().standardizedFileURL
        guard promisedName != nil || sourcePath.deletingLastPathComponent().path != destinationPath.path else {
            throw UtilityError.message("This item is already in the selected folder")
        }
        try Task.checkCancellation()
        let fm = FileManager.default
        let kind = try source.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        let isFolder = kind.isDirectory == true
        guard kind.isSymbolicLink != true, isFolder || kind.isRegularFile == true else {
            throw UtilityError.message("Choose a regular file or folder")
        }
        if isFolder {
            // Check the nearest existing directory, including aliases through symlinks and case variants.
            var ancestor = destinationPath
            while ancestor.path != "/", !fm.fileExists(atPath: ancestor.path) {
                ancestor.deleteLastPathComponent()
            }
            var relationship = FileManager.URLRelationship.other
            try fm.getRelationship(&relationship, ofDirectoryAt: sourcePath, toItemAt: ancestor.resolvingSymlinksInPath())
            guard relationship == .other else {
                throw UtilityError.message("A folder cannot be copied or moved into itself")
            }
        }
        let name = promisedName ?? source.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw UtilityError.message("Invalid destination name")
        }
        let work = directory.appendingPathComponent(".utility-transfer-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let temp = work.appendingPathComponent(name, isDirectory: isFolder)
        try fm.copyItem(at: source, to: temp)
        guard try matchesCopy(source, temp) else {
            throw UtilityError.message("The copied contents do not match the source")
        }
        try Task.checkCancellation()
        let baseName = isFolder ? name : temp.deletingPathExtension().lastPathComponent
        let output = try commitNamed(temp, to: directory, baseName: baseName, extension: isFolder ? "" : temp.pathExtension,
                                     exact: promisedName != nil, collisionSeparator: " ")
        if move {
            do { try fm.removeItem(at: source) }
            catch { throw UtilityError.message("Copied to \(output.path), but could not remove the original: \(error.localizedDescription)") }
        }
        return output
    }

    private static func matchesCopy(_ source: URL, _ copy: URL) throws -> Bool {
        try Task.checkCancellation()
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let original = try source.resourceValues(forKeys: keys)
        let duplicate = try copy.resourceValues(forKeys: keys)
        if original.isSymbolicLink == true {
            guard duplicate.isSymbolicLink == true else { return false }
            return try fm.destinationOfSymbolicLink(atPath: source.path) == fm.destinationOfSymbolicLink(atPath: copy.path)
        }
        guard duplicate.isSymbolicLink != true else { return false }
        if original.isDirectory == true {
            guard duplicate.isDirectory == true else { return false }
            let names = try fm.contentsOfDirectory(atPath: source.path)
            guard Set(names) == Set(try fm.contentsOfDirectory(atPath: copy.path)) else { return false }
            return try names.allSatisfy {
                try matchesCopy(source.appendingPathComponent($0), copy.appendingPathComponent($0))
            }
        }
        guard original.isRegularFile == true, duplicate.isRegularFile == true, bytes(source) == bytes(copy) else {
            return false
        }
        return try digest(source) == digest(copy)
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
