import AVFoundation
import CoreImage
import FaceAnimation
import Foundation
import HoloRenderer
import ImageIO
import UniformTypeIdentifiers
import VoiceAnalysis

/// `Visage --render <audio file> <video.mov> [<frames directory>] [--face <id>] [--realism <0-100>|<a-b>]
/// [--mute]`:
/// the offline render
/// of the spec (§ 11.2). The face speaks the file at 60 frames a second, its mouth read 60 ms ahead of the
/// sound, then the file's own sound is laid under the picture — unless `--mute`, for watching in an open
/// office. With a frames directory, a PNG every half second too.
enum VideoRender {
    static let size = (width: 720, height: 900)
    static let fps = 60
    static let anticipation = 0.06

    static func run(
        input: URL, output: URL, frames directory: URL?, face: String, realism: ClosedRange<Float>, mute: Bool
    )
        -> Int32
    {
        do {
            let analysis = try AudioFileAnalysis.analyse(input)
            guard let renderer = HoloRenderer(model: FaceLibrary.model(id: face)) else {
                throw CocoaError(.featureUnsupported)
            }
            let silent = output.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: silent) }
            try writeVideo(analysis: analysis, renderer: renderer, realism: realism, to: silent, frames: directory)
            if mute {
                try? FileManager.default.removeItem(at: output)
                try FileManager.default.copyItem(at: silent, to: output)
            } else {
                try addSound(video: silent, audio: input, to: output)
            }
            print("\(output.path): \(String(format: "%.2f", analysis.duration)) s, \(fps) fps")
            return 0
        } catch {
            FileHandle.standardError.write(Data("visage: \(error)\n".utf8))
            return 1
        }
    }

    private static func writeVideo(
        analysis: AudioFileAnalysis.Result, renderer: HoloRenderer, realism: ClosedRange<Float>, to url: URL,
        frames directory: URL?
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
            ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }

        var settings = HoloSettings()
        settings.background = HoloSettings.charbon
        let animator = FaceAnimator(seed: 1)
        let frameCount = Int(analysis.duration * Double(fps)) + fps / 2
        for index in 0..<frameCount {
            let time = Double(index) / Double(fps)
            // The gauge slides across the clip when the realism is a range.
            let progress = Float(index) / Float(max(frameCount - 1, 1))
            settings.realism = realism.lowerBound + (realism.upperBound - realism.lowerBound) * progress
            let hop = Int(((time + anticipation) * 100).rounded(.down))
            let voice = hop >= 0 && hop < analysis.frames.count ? analysis.frames[hop] : nil
            let moment: ConversationMoment = voice.map { $0.sound != .silence } == true ? .speaking : .waiting
            let pose = animator.update(dt: 1 / Double(fps), voice: voice, moment: moment)
            guard
                let pixels = renderer.renderPixels(
                    pose: pose, time: time, settings: settings, width: size.width, height: size.height)
            else { throw CocoaError(.fileWriteUnknown) }

            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            let base = CVPixelBufferGetBaseAddress(buffer)!
            pixels.withUnsafeBytes { source in
                for row in 0..<size.height {
                    memcpy(base + row * rowBytes, source.baseAddress! + row * size.width * 4, size.width * 4)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))

            if let directory, index % (fps / 2) == 0,
                let image = renderer.image(
                    pose: pose, time: time, settings: settings, width: size.width, height: size.height)
            {
                savePNG(image, to: directory.appending(path: String(format: "frame-%05.2fs.png", time)))
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    /// The picture, with the file's own sound under it.
    private static func addSound(video: URL, audio: URL, to output: URL) throws {
        try? FileManager.default.removeItem(at: output)
        let done = DispatchSemaphore(value: 0)
        let failure = ErrorBox()
        Task.detached {
            do {
                let composition = AVMutableComposition()
                let picture = AVURLAsset(url: video)
                let sound = AVURLAsset(url: audio)
                let duration = try await picture.load(.duration)
                if let track = try await picture.loadTracks(withMediaType: .video).first,
                    let target = composition.addMutableTrack(
                        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                {
                    try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
                }
                let soundDuration = try await sound.load(.duration)
                if let track = try await sound.loadTracks(withMediaType: .audio).first,
                    let target = composition.addMutableTrack(
                        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                {
                    try target.insertTimeRange(
                        CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, soundDuration)), of: track,
                        at: .zero)
                }
                guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
                else { throw CocoaError(.fileWriteUnknown) }
                try await session.export(to: output, as: .mov)
            } catch {
                failure.error = error
            }
            done.signal()
        }
        done.wait()
        if let error = failure.error { throw error }
    }

    private final class ErrorBox: @unchecked Sendable {
        var error: Error?
    }

    static func savePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
