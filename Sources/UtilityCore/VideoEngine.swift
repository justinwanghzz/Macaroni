import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import AudioToolbox

public enum VideoEngine {
    public static func compress(_ input: URL, to output: URL, maximumBytes: Int64, progress: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw UtilityError.message("Video duration is invalid") }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw UtilityError.message("No video track was found") }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let sourceRect = CGRect(origin: .zero, size: size).applying(transform)
        guard sourceRect.width.isFinite, sourceRect.height.isFinite, sourceRect.width > 0, sourceRect.height > 0 else { throw UtilityError.message("Video dimensions are invalid") }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioRate = audioTracks.isEmpty ? 0 : 96000
        let availableRate = Double(maximumBytes) * 8 * 0.92 / seconds - Double(audioRate)
        guard maximumBytes >= 10000, availableRate >= 32000 else { throw UtilityError.message("That target is too small for this clip's duration. Choose a larger size") }
        for attempt in 0..<3 {
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: output)
            let bitrate = max(32000, Int(min(50_000_000, availableRate * pow(0.82, Double(attempt)))))
            let maxSide: CGFloat = bitrate < 250000 ? 480 : bitrate < 700000 ? 720 : bitrate < 1800000 ? 1280 : 1920
            let scale = min(1, maxSide / max(sourceRect.width, sourceRect.height))
            let width = max(2, Int(sourceRect.width * scale) / 2 * 2)
            let height = max(2, Int(sourceRect.height * scale) / 2 * 2)
            try await encode(asset: asset, track: track, audio: audioTracks.first, output: output, duration: duration, rect: sourceRect, transform: transform, width: width, height: height, bitrate: bitrate, audioRate: audioRate) { p in progress((Double(attempt) + p) / 3) }
            try Task.checkCancellation()
            let written = FileServices.bytes(output)
            let check = AVURLAsset(url: output)
            let exportedDuration = try await check.load(.duration).seconds
            guard abs(exportedDuration - seconds) < max(0.25, seconds * 0.005) else { throw UtilityError.message("The exported clip did not preserve the complete duration") }
            if written > 0 && written <= maximumBytes { progress(1); return }
        }
        try? FileManager.default.removeItem(at: output)
        throw UtilityError.message("Could not meet that size target after three attempts. Choose a larger target")
    }

    /// Retimes the full composition, including audio. Spectral time stretching preserves pitch.
    public static func adjust(_ input:URL,to output:URL,speed:Double=1,muted:Bool=false,progress:@escaping(Double)->Void={_ in}) async throws {
        guard !FileManager.default.fileExists(atPath:output.path) else {throw UtilityError.message("A file already exists at the export destination")}
        var finished=false
        defer {if !finished {try? FileManager.default.removeItem(at:output)}}
        try Task.checkCancellation()
        progress(0)
        guard speed.isFinite,(0.25...3).contains(speed) else {throw UtilityError.message("Choose a speed between 0.25× and 3×")}
        let asset=AVURLAsset(url:input), composition=AVMutableComposition()
        let duration=try await asset.load(.duration)
        guard duration.seconds.isFinite,duration.seconds>0 else {throw UtilityError.message("Video duration is invalid")}
        for type in [AVMediaType.video,.audio] where type != .audio || !muted {
            for source in try await asset.loadTracks(withMediaType:type) {
                guard let track=composition.addMutableTrack(withMediaType:type,preferredTrackID:kCMPersistentTrackID_Invalid) else {throw UtilityError.message("Cannot create a video track")}
                try track.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:source,at:.zero)
                if type == .video {track.preferredTransform=try await source.load(.preferredTransform)}
            }
        }
        guard !(try await composition.loadTracks(withMediaType:.video)).isEmpty else {throw UtilityError.message("No video track was found")}
        composition.scaleTimeRange(CMTimeRange(start:.zero,duration:duration),toDuration:CMTimeMultiplyByFloat64(duration,multiplier:1/speed))
        guard let session=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality) else {throw UtilityError.message("Video export is unavailable")}
        session.outputURL=output;session.outputFileType = .mp4;session.audioTimePitchAlgorithm = .spectral
        session.timeRange=CMTimeRange(start:.zero,duration:CMTimeMultiplyByFloat64(duration,multiplier:1/speed))
        try await withTaskCancellationHandler(operation: {
            await session.export()
            try Task.checkCancellation()
            guard session.status == .completed else {throw session.error ?? UtilityError.message("Could not export the video")}
        },onCancel:{session.cancelExport()})
        let expected=duration.seconds/speed,actual=try await AVURLAsset(url:output).load(.duration).seconds
        guard actual.isFinite,abs(actual-expected)<=max(0.1,expected*0.01) else {throw UtilityError.message("The exported video did not preserve the requested duration")}
        finished=true;progress(1)
    }

    private static func encode(asset: AVAsset, track: AVAssetTrack, audio: AVAssetTrack?, output: URL, duration: CMTime, rect: CGRect, transform: CGAffineTransform, width: Int, height: Int, bitrate: Int, audioRate: Int, progress: @escaping (Double) -> Void) async throws {
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: width, height: height)
        let nominal = try await track.load(.nominalFrameRate)
        let fps = nominal.isFinite ? min(30, max(1, Int(min(240, nominal).rounded()))) : 30
        composition.frameDuration = CMTime(value: 1, timescale: Int32(fps))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let adjusted = transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY)).concatenating(CGAffineTransform(scaleX: CGFloat(width) / rect.width, y: CGFloat(height) / rect.height))
        layer.setTransform(adjusted, at: .zero)
        instruction.layerInstructions = [layer]; composition.instructions = [instruction]
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw UtilityError.message("This video cannot be decoded") }; reader.add(videoOutput)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel]])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw UtilityError.message("H.264 encoding is unavailable for these settings") }; writer.add(videoInput)
        var pipes: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(videoOutput, videoInput)]
        if let audio {
            let out = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            let inp = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: audioRate])
            guard reader.canAdd(out), writer.canAdd(inp) else { throw UtilityError.message("This audio track cannot be converted") }
            reader.add(out); writer.add(inp); pipes.append((out, inp))
        }
        guard writer.startWriting(), reader.startReading() else { throw UtilityError.message(reader.error?.localizedDescription ?? writer.error?.localizedDescription ?? "Could not begin video conversion") }
        writer.startSession(atSourceTime: .zero)
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, pipe) in pipes.enumerated() {
                    group.addTask {
                        var lastProgress = -1.0
                        while true {
                            try Task.checkCancellation()
                            if reader.status == .failed || writer.status == .failed || writer.status == .cancelled {
                                throw UtilityError.message(reader.error?.localizedDescription ?? writer.error?.localizedDescription ?? "Video conversion interrupted")
                            }
                            guard pipe.1.isReadyForMoreMediaData else {
                                try await Task.sleep(nanoseconds: 2_000_000); continue
                            }
                            guard let sample = pipe.0.copyNextSampleBuffer() else {
                                if reader.status == .failed { throw UtilityError.message(reader.error?.localizedDescription ?? "Could not decode the complete clip") }
                                pipe.1.markAsFinished(); return
                            }
                            guard pipe.1.append(sample) else { throw UtilityError.message(writer.error?.localizedDescription ?? "Could not write a video sample") }
                            if index == 0 {
                                let p = CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration.seconds
                                if p - lastProgress > 0.02 { lastProgress = p; progress(min(1, max(0,p))) }
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }
            try Task.checkCancellation()
            await writer.finishWriting()
            guard writer.status == .completed else { throw UtilityError.message(writer.error?.localizedDescription ?? "Could not finish the video") }
        } catch {
            reader.cancelReading(); writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
