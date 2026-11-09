import XCTest
import AVFoundation
@testable import UtilityCore
final class VideoTests: XCTestCase {
    func testVideoTargetKeepsDurationAndAudio() async throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("Fixtures/Color-motion.mp4")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
        defer { try? FileManager.default.removeItem(at:out) }
        try await VideoEngine.compress(source,to:out,maximumBytes:250_000,progress:{ _ in })
        XCTAssertLessThanOrEqual(FileServices.bytes(out),250_000)
        let a = AVURLAsset(url:out); let duration = try await a.load(.duration)
        XCTAssertEqual(duration.seconds,4,accuracy:0.2)
        let audio = try await a.loadTracks(withMediaType:.audio); XCTAssertEqual(audio.count,1)
        let generator = AVAssetImageGenerator(asset:a)
        let first = try await generator.image(at:.zero); let last = try await generator.image(at:CMTime(seconds:3.5,preferredTimescale:600))
        XCTAssertGreaterThan(first.image.width,0); XCTAssertGreaterThan(last.image.width,0)
    }
    func testCancellationCleansVideoOutput() async throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
        let task = Task { try await VideoEngine.compress(root.appendingPathComponent("Fixtures/Color-motion.mp4"),to:out,maximumBytes:250_000,progress:{ _ in }) }
        try await Task.sleep(nanoseconds:20_000_000); task.cancel()
        do { try await task.value; XCTFail("Expected cancellation during encoding") } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath:out.path))
    }
    func testImpossibleTargetFails() async throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
        do { try await VideoEngine.compress(root.appendingPathComponent("Fixtures/Color-motion.mp4"),to:out,maximumBytes:10_000,progress:{ _ in }); XCTFail("Should reject impossibly low bitrate") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath:out.path))
    }
}
