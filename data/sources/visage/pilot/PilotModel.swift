import AppKit
import CoreAudio
import Foundation
import Observation

/// Drives the pilot: finds the target, holds the capture session, reconnects when the target's
/// audio processes change, and writes what happens to the log.
@MainActor
@Observable
final class PilotModel {
    var target: String
    var mode: TapTargetMode
    /// Bundle mode only: tap the target's bundle ID alone, without its helpers'.
    var exactBundle: Bool
    var privateTap: Bool
    var delayMilliseconds: Int { didSet { session?.setDelay(milliseconds: delayMilliseconds) } }
    var anticipationMilliseconds: Int
    var extraLatencyMilliseconds = 0

    private(set) var isConnected = false
    private(set) var status = "Not connected"
    private(set) var lastError: String?
    private(set) var details = ""

    @ObservationIgnored private var session: TapSession?
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var connectedObjects: Set<AudioObjectID> = []
    @ObservationIgnored private var opening = 0.0
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private let log = PilotLog()
    @ObservationIgnored private var timer: Timer?

    init(arguments: [String]) {
        let options = LaunchOptions(arguments)
        target = options.target
        mode = options.mode
        exactBundle = options.exactBundle
        privateTap = options.privateTap
        delayMilliseconds = options.delayMilliseconds
        anticipationMilliseconds = options.anticipationMilliseconds
        log.event("launch", ["arguments": Array(arguments.dropFirst())])

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.disconnect(reason: "quit") }
        }
        if options.connectAtLaunch {
            connect()
        }
    }

    // MARK: - Connection

    func connect() {
        wantsConnection = true
        lastError = nil
        reconnect(reason: "connect")
    }

    func disconnect(reason: String) {
        wantsConnection = false
        stopSession(reason: reason)
        status = "Not connected"
    }

    /// Simulates a crash: the process dies without stopping anything. The target must play again.
    func crash() {
        log.event("crash", [:])
        kill(getpid(), SIGKILL)
    }

    private func reconnect(reason: String) {
        stopSession(reason: reason)
        let matches = ProcessCatalog.matching(target, in: ProcessCatalog.all())

        var tapTarget = TapTarget()
        switch mode {
        case .processes:
            guard !matches.isEmpty else {
                status = "Waiting: no audio process matches “\(target)” yet"
                return
            }
            tapTarget.processObjects = matches.map(\.objectID)
        case .bundleIDs:
            tapTarget.bundleIDs = exactBundle
                ? [target]
                : Array(Set(matches.map(\.bundleID).filter { !$0.isEmpty } + [target])).sorted()
        }

        let session = TapSession()
        do {
            try session.start(target: tapTarget, privateTap: privateTap, delayMilliseconds: delayMilliseconds)
        } catch {
            lastError = "\(error)"
            status = "Connection failed"
            log.event("error", ["message": "\(error)"])
            return
        }
        self.session = session
        connectedObjects = Set(matches.map(\.objectID))
        isConnected = true
        status = "Connected to “\(target)” — \(mode.label)"
        log.event("connected", [
            "reason": reason,
            "mode": mode.rawValue,
            "privateTap": privateTap,
            "processes": matches.map(\.summary),
            "bundleIDs": tapTarget.bundleIDs,
            "tapUID": session.tapUID,
            "tapFormat": Self.describe(session.tapFormat),
            "sampleRate": session.sampleRate,
            "bufferFrames": session.bufferFrames,
            "output": session.outputDeviceName,
            "outputLatencyFrames": session.outputLatencyFrames,
        ])
    }

    private func stopSession(reason: String) {
        guard let session else { return }
        session.stop()
        self.session = nil
        isConnected = false
        connectedObjects = []
        log.event("disconnected", ["reason": reason])
    }

    // MARK: - Every half second

    private func tick() {
        ticks += 1
        let all = ProcessCatalog.all()
        let matches = ProcessCatalog.matching(target, in: all)

        // Process mode follows the target's audio processes by hand; bundle mode leaves it to Core Audio.
        if wantsConnection, mode == .processes, !matches.isEmpty, Set(matches.map(\.objectID)) != connectedObjects {
            reconnect(reason: "processes changed")
        }

        var lines: [String] = []
        if let session {
            let now = HostClock.now
            let lookahead = session.lookahead(at: now, extraLatency: extraLatency).map { String(format: "%.0f ms", $0 * 1000) } ?? "-"
            lines += [
                "tap      \(session.tapUID.prefix(8))…  \(privateTap ? "private" : "public")  \(Self.describe(session.tapFormat))",
                "output   \(session.outputDeviceName)  \(Int(session.sampleRate)) Hz  buffer \(session.bufferFrames)  latency \(session.outputLatencyFrames) frames (\(String(format: "%.1f", Double(session.outputLatencyFrames) / session.sampleRate * 1000)) ms)",
                "io       callbacks \(session.callbacks.load(ordering: .relaxed))  frames/cb \(session.framesPerCallback.load(ordering: .relaxed))  overloads \(session.overloads.load(ordering: .relaxed))  mismatches \(session.frameMismatches.load(ordering: .relaxed))  in \(session.inputLayout.load(ordering: .relaxed))  out \(session.outputLayout.load(ordering: .relaxed))",
                String(format: "level    %.1f dBFS   lookahead %@", session.capturedLevelDecibels, lookahead),
            ]
        }
        lines.append("matching \(matches.isEmpty ? "none" : "")")
        lines += matches.map { "  " + $0.summary }
        lines.append("playing")
        lines += all.filter(\.isRunningOutput).map { "  " + $0.summary }
        details = lines.joined(separator: "\n")

        if ticks % 2 == 0 {
            let lookahead = session?.lookahead(at: HostClock.now, extraLatency: extraLatency) ?? -1
            log.status([
                "connected": isConnected,
                "target": target,
                "mode": mode.rawValue,
                "exactBundle": exactBundle,
                "privateTap": privateTap,
                "tapFormat": session.map { Self.describe($0.tapFormat) } ?? "",
                "sampleRate": session?.sampleRate ?? 0,
                "bufferFrames": session?.bufferFrames ?? 0,
                "outputLatencyMs": session.map { (Double($0.outputLatencyFrames) / $0.sampleRate * 10_000).rounded() / 10 } ?? 0,
                "lookaheadMs": (lookahead * 10_000).rounded() / 10,
                "framesPerCallback": session?.framesPerCallback.load(ordering: .relaxed) ?? 0,
                "frameMismatches": session?.frameMismatches.load(ordering: .relaxed) ?? 0,
                "inputLayout": session?.inputLayout.load(ordering: .relaxed) ?? -1,
                "outputLayout": session?.outputLayout.load(ordering: .relaxed) ?? -1,
                "delayMs": delayMilliseconds,
                "anticipationMs": anticipationMilliseconds,
                "extraLatencyMs": extraLatencyMilliseconds,
                "levelDb": session.map { ($0.capturedLevelDecibels * 10).rounded() / 10 } ?? -120,
                "callbacks": session?.callbacks.load(ordering: .relaxed) ?? 0,
                "overloads": session?.overloads.load(ordering: .relaxed) ?? 0,
                "matching": matches.map(\.summary),
                "playing": all.filter(\.isRunningOutput).map(\.summary),
                "taps": TapCatalog.uids(),
            ])
        }
    }

    // MARK: - The mouth

    private var extraLatency: Double { Double(extraLatencyMilliseconds) / 1000 }

    /// How open the mouth is on the frame being drawn now, from closed (0) to wide open (1).
    func mouthOpening() -> Double {
        guard let session else {
            opening *= 0.85
            return opening
        }
        let frameDuration = 1 / Double(NSScreen.main?.maximumFramesPerSecond ?? 60)
        let displayTime = HostClock.now + HostClock.hostTime(nanoseconds: frameDuration * 1e9)
        let level = session.level(
            heardAt: displayTime,
            anticipation: Double(anticipationMilliseconds) / 1000,
            extraLatency: extraLatency
        )
        let decibels = 20 * log10(max(Double(level), 1e-6))
        let goal = min(max((decibels + 50) / 35, 0), 1)   // −50 dBFS closed, −15 dBFS wide open
        opening += (goal - opening) * (goal > opening ? 0.6 : 0.25)   // opens fast, closes softer
        return opening
    }

    private static func describe(_ format: AudioStreamBasicDescription) -> String {
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        return "\(Int(format.mSampleRate)) Hz \(format.mChannelsPerFrame) ch \(format.mBitsPerChannel) bit \(interleaved ? "interleaved" : "planar")"
    }
}

enum TapTargetMode: String, CaseIterable, Sendable {
    case processes
    case bundleIDs = "bundle"

    var label: String {
        switch self {
        case .processes: "Processes"
        case .bundleIDs: "Bundle IDs"
        }
    }
}

/// `open VisagePilot.app --args --target afplay --mode processes --delay 150 --anticipation 40 --connect`
/// The tap is private unless `--public`: a public tap outlives its process (pilot, R3), a private one is
/// invisible to other processes. `--exact` taps the bundle ID alone, without its helpers'.
struct LaunchOptions {
    var target = "com.anthropic.claudefordesktop"
    var mode = TapTargetMode.processes
    var exactBundle = false
    var privateTap = true
    var delayMilliseconds = 150
    var anticipationMilliseconds = 40
    var connectAtLaunch = false

    init(_ arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--target": target = iterator.next() ?? target
            case "--mode": mode = iterator.next().flatMap(TapTargetMode.init(rawValue:)) ?? mode
            case "--delay": delayMilliseconds = iterator.next().flatMap(Int.init) ?? delayMilliseconds
            case "--anticipation": anticipationMilliseconds = iterator.next().flatMap(Int.init) ?? anticipationMilliseconds
            case "--private": privateTap = true
            case "--public": privateTap = false
            case "--exact": exactBundle = true
            case "--connect": connectAtLaunch = true
            default: break
            }
        }
    }
}
