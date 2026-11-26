import Foundation
import VoiceAnalysis

/// `Visage --analyse <audio file> <frames.json>`: the file mode of the analysis (spec, § 11.2). Writes
/// every 10 ms frame as JSON and prints a summary: tune the analysis on a recording, no AI needed.
enum AnalysisReport {
    static func run(input: URL, output: URL) -> Int32 {
        do {
            let result = try AudioFileAnalysis.analyse(input)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(result.frames).write(to: output)
            print(summary(of: result))
            return 0
        } catch {
            FileHandle.standardError.write(Data("visage: \(error)\n".utf8))
            return 1
        }
    }

    static func summary(of result: AudioFileAnalysis.Result) -> String {
        let frames = result.frames
        let voiced = frames.filter(\.isVoiced)
        let pitches = voiced.compactMap(\.pitch).sorted()
        var counts: [SoundClass: Int] = [:]
        for frame in frames { counts[frame.sound, default: 0] += 1 }
        let classes = counts.sorted { $0.value > $1.value }.map { "\($0.key.rawValue) \($0.value)" }
        let closures = runs(of: .closure, in: frames)
        let lipClosures = closures.filter { $0.bilabial >= 0.5 }.count
        return """
            \(String(format: "%.2f", result.duration)) s at \(Int(result.sampleRate)) Hz, \(frames.count) frames
            voiced \(percent(voiced.count, frames.count)), pitch median \(pitches.isEmpty ? "-" : String(format: "%.0f Hz", pitches[pitches.count / 2]))
            sounds: \(classes.joined(separator: ", "))
            closures: \(closures.count), of which lips likely: \(lipClosures)
            """
    }

    private static func runs(of sound: SoundClass, in frames: [VoiceFrame]) -> [VoiceFrame] {
        var starts: [VoiceFrame] = []
        var previous: SoundClass?
        for frame in frames {
            if frame.sound == sound, previous != sound { starts.append(frame) }
            previous = frame.sound
        }
        return starts
    }

    private static func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "-" : "\(part * 100 / whole) %"
    }
}
