import AppKit
import Combine

@MainActor
final class DownloadQueue: ObservableObject {
    private enum Key {
        static let format = "siphon.format"
        static let videoQuality = "siphon.videoQuality"
        static let wholePlaylist = "siphon.wholePlaylist"
        static let destination = "siphon.destination"
        static let attempts = "siphon.attempts"
    }

    /// Two at a time: enough to overlap one download with the conversion of another,
    /// few enough not to get throttled by the site.
    static let maxConcurrent = 2

    /// How many times in all a download the site refuses (HTTP 403) is tried. Three:
    /// a passing refusal rarely comes twice in a row, and past three it is usually a
    /// real block — more attempts would only redo the download to show it later.
    static let defaultAttempts = 3
    static let attemptRange = 1...10

    @Published var format: OutputFormat {
        didSet { defaults.set(format.rawValue, forKey: Key.format) }
    }
    @Published var videoQuality: VideoQuality {
        didSet { defaults.set(videoQuality.rawValue, forKey: Key.videoQuality) }
    }
    @Published var wholePlaylist: Bool {
        didSet { defaults.set(wholePlaylist, forKey: Key.wholePlaylist) }
    }
    @Published var destination: URL {
        didSet { defaults.set(destination.path, forKey: Key.destination) }
    }
    /// Read when a download starts: a change applies to the ones not started yet.
    @Published var attempts: Int {
        didSet { defaults.set(attempts, forKey: Key.attempts) }
    }

    @Published private(set) var jobs: [DownloadJob] = []
    @Published private(set) var tools = Tools.locate()
    @Published private(set) var ytdlpVersion: String?

    private let defaults = UserDefaults.standard

    init() {
        let saved = UserDefaults.standard
        format = saved.string(forKey: Key.format).flatMap(OutputFormat.init(rawValue:)) ?? .mp3
        videoQuality = saved.string(forKey: Key.videoQuality).flatMap(VideoQuality.init(rawValue:)) ?? .p1080
        wholePlaylist = saved.bool(forKey: Key.wholePlaylist)
        destination = saved.string(forKey: Key.destination).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        // 0 when never set, and a value typed with `defaults write` may be anything.
        let savedAttempts = saved.integer(forKey: Key.attempts)
        attempts = Self.attemptRange.contains(savedAttempts) ? savedAttempts : Self.defaultAttempts
        loadVersion()
    }

    var options: DownloadOptions {
        DownloadOptions(format: format, videoQuality: videoQuality, wholePlaylist: wholePlaylist)
    }

    var activeCount: Int {
        jobs.filter(\.isActive).count
    }

    /// Queues every link found in `text` with the current settings, cut to `clip` if
    /// there is one. A link already waiting or downloading with the same clip is
    /// skipped — another clip of it is another file. Returns how many were added.
    @discardableResult
    func add(_ text: String, clip: Clip? = nil) -> Int {
        let pending = Set(jobs.filter { !$0.isOver && $0.options.clip == clip }.map(\.url))
        let links = YtDlp.links(in: text).filter { !pending.contains($0) }
        var options = self.options
        options.clip = clip
        for link in links {
            jobs.append(DownloadJob(url: link, options: options, destination: destination))
        }
        schedule()
        return links.count
    }

    func cancel(_ job: DownloadJob) {
        job.cancel()
        schedule()
    }

    func cancelAll() {
        jobs.forEach { $0.cancel() }
    }

    /// Same link, same settings as the first attempt — not the ones changed since.
    func retry(_ job: DownloadJob) {
        guard job.isOver, let index = jobs.firstIndex(where: { $0 === job }) else { return }
        jobs[index] = DownloadJob(url: job.url, options: job.options, destination: job.destination)
        schedule()
    }

    func remove(_ job: DownloadJob) {
        guard job.isOver else { return }
        jobs.removeAll { $0 === job }
    }

    func clearFinished() {
        jobs.removeAll(where: \.isOver)
    }

    /// For the "Check again" button, once yt-dlp or ffmpeg has been installed.
    func refreshTools() {
        tools = Tools.locate()
        loadVersion()
        schedule()
    }

    private func loadVersion() {
        ytdlpVersion = nil
        guard let ytdlp = tools.ytdlp else { return }
        Task {
            ytdlpVersion = await YtDlp.version(of: ytdlp)
        }
    }

    private func schedule() {
        // Without yt-dlp the links simply wait; the banner says what to install.
        if tools.ytdlp != nil {
            var running = activeCount
            for job in jobs where job.state == .queued && running < Self.maxConcurrent {
                if job.start(with: tools, attempts: attempts, onExit: { [weak self] in self?.schedule() }) {
                    running += 1
                }
            }
        }

        let pending = jobs.filter { !$0.isOver }.count
        NSApp?.dockTile.badgeLabel = pending > 0 ? "\(pending)" : nil
    }
}
