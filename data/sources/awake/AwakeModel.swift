import Foundation
import Combine

enum AwakeDuration: String, CaseIterable, Identifiable {
    case thirtyMinutes
    case oneHour
    case twoHours
    case unlimited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 heure"
        case .twoHours: return "2 heures"
        case .unlimited: return "Illimité"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .unlimited: return nil
        }
    }
}

@MainActor
final class AwakeModel: ObservableObject {
    private enum Key {
        static let isPreventing = "awake.isPreventingSleep"
        static let duration = "awake.duration"
        static let endDate = "awake.endDate"
        static let keepDisplayAwake = "awake.keepDisplayAwake"
    }

    @Published private(set) var isPreventingSleep = false
    @Published private(set) var remainingText: String?
    @Published var duration: AwakeDuration = .unlimited
    @Published var launchAtLogin = false
    @Published private(set) var keepDisplayAwake = true

    private let defaults = UserDefaults.standard
    private let preventer = SleepPreventer()
    private var timer: Timer?
    private var endDate: Date?

    init() {
        // Keeping the display on is what a coffee cup in the menu bar is expected
        // to do, so it is the default when nothing has been saved yet.
        defaults.register(defaults: [Key.keepDisplayAwake: true])
        launchAtLogin = LaunchAtLogin.isEnabled
        keepDisplayAwake = defaults.bool(forKey: Key.keepDisplayAwake)
        restore()
    }

    func setPreventingSleep(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func setDuration(_ newDuration: AwakeDuration) {
        duration = newDuration
        defaults.set(newDuration.rawValue, forKey: Key.duration)
        guard isPreventingSleep else { return }
        configureTimer()
    }

    func setKeepDisplayAwake(_ enabled: Bool) {
        keepDisplayAwake = enabled
        defaults.set(enabled, forKey: Key.keepDisplayAwake)
        defaults.synchronize()

        // The assertion type is fixed at creation time, so swap it out live.
        guard isPreventingSleep else { return }
        preventer.stop()
        preventer.start(keepDisplayAwake: enabled)
        if !preventer.isActive { stop() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLogin = enabled
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    /// Restores the state saved by a previous run. Without this, relaunching the
    /// app (update, quit, login) silently drops the assertion while the menu bar
    /// icon still suggests the app is doing its job.
    private func restore() {
        if let raw = defaults.string(forKey: Key.duration),
           let saved = AwakeDuration(rawValue: raw) {
            duration = saved
        }

        guard defaults.bool(forKey: Key.isPreventing) else { return }

        guard duration.seconds != nil else {
            start()
            return
        }

        // A finite duration only resumes if its deadline is still ahead of us.
        guard let saved = defaults.object(forKey: Key.endDate) as? Date,
              saved.timeIntervalSinceNow > 0 else {
            persist(preventing: false, endDate: nil)
            return
        }

        preventer.start(keepDisplayAwake: keepDisplayAwake)
        guard preventer.isActive else { return }

        isPreventingSleep = true
        configureTimer(until: saved)
    }

    private func start() {
        preventer.start(keepDisplayAwake: keepDisplayAwake)
        guard preventer.isActive else { return }
        isPreventingSleep = true
        configureTimer()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remainingText = nil
        preventer.stop()
        isPreventingSleep = false
        persist(preventing: false, endDate: nil)
    }

    private func configureTimer(until resumedEnd: Date? = nil) {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remainingText = nil

        guard let seconds = duration.seconds else {
            persist(preventing: true, endDate: nil)
            return
        }

        let deadline = resumedEnd ?? Date().addingTimeInterval(seconds)
        endDate = deadline
        persist(preventing: true, endDate: deadline)
        updateRemaining()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRemaining()
            }
        }

        // Keep counting down while the menu bar popover is open, otherwise the
        // run loop switches to event tracking mode and the timer stalls.
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func persist(preventing: Bool, endDate: Date?) {
        defaults.set(preventing, forKey: Key.isPreventing)
        defaults.set(duration.rawValue, forKey: Key.duration)
        if let endDate {
            defaults.set(endDate, forKey: Key.endDate)
        } else {
            defaults.removeObject(forKey: Key.endDate)
        }
        // Menu bar utilities get killed abruptly — replaced by an update, force
        // quit, logout. Buffered writes are lost when that happens, so flush now
        // rather than trusting the periodic one.
        defaults.synchronize()
    }

    private func updateRemaining() {
        guard let endDate else { return }

        let remaining = endDate.timeIntervalSinceNow
        guard remaining > 0 else {
            stop()
            return
        }

        let total = Int(remaining)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            remainingText = String(format: "%dh %02dm", hours, minutes)
        } else {
            remainingText = String(format: "%02dm %02ds", minutes, seconds)
        }
    }
}
