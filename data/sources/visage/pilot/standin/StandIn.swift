import AppKit
import AVFoundation

/// A stand-in for an AI app: a real bundle ID, no window, and a voice that loops until the app is quit.
/// The pilot taps it by bundle ID, and quits and relaunches it to see the tap follow.
///
///   open -n VoiceStandIn.app --args /path/to/voice.aiff
@main
enum StandIn {
    @MainActor
    static func main() {
        guard let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }),
              let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else {
            FileHandle.standardError.write(Data("usage: VoiceStandIn <audio file>\n".utf8))
            exit(1)
        }
        player.numberOfLoops = -1
        player.play()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(player) {
            app.run()
        }
    }
}
