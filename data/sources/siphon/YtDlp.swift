import Foundation

/// The formats Siphon offers. Each one maps to a fixed set of yt-dlp options, so what
/// you pick in the window is exactly what runs — see `YtDlp.arguments`.
enum OutputFormat: String, CaseIterable, Identifiable {
    case mp3
    case m4a
    case mp4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .mp4: return "MP4 video"
        }
    }

    var help: String {
        switch self {
        case .mp3: return "MP3 audio at 320 kbps, with cover art and tags"
        case .m4a: return "The original AAC audio, not re-encoded, with cover art and tags"
        case .mp4: return "MP4 video with its sound"
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case p720
    case p1080
    case best

    var id: String { rawValue }

    var title: String {
        switch self {
        case .p720: return "720p"
        case .p1080: return "1080p"
        case .best: return "Best (4K…)"
        }
    }

    /// yt-dlp format sorting (`-S`). Up to 1080p, H.264 wins over VP9 and AV1 so the
    /// file plays in QuickTime and imports anywhere. Past 1080p YouTube only serves VP9
    /// and AV1, so "best" lets the resolution win and prefers AV1 among equals — VP9
    /// in an MP4 does not play in QuickTime at all.
    var sort: String {
        switch self {
        case .p720: return "vcodec:h264,res:720,acodec:aac"
        case .p1080: return "vcodec:h264,res:1080,acodec:aac"
        case .best: return "res,vcodec:av01,acodec:aac"
        }
    }
}

struct DownloadOptions: Equatable {
    var format: OutputFormat
    var videoQuality: VideoQuality
    var wholePlaylist: Bool
}

/// The command line tools Siphon drives, as found on this Mac.
struct Tools: Equatable {
    var ytdlp: URL?
    var ffmpeg: URL?
    var deno: URL?

    static func locate() -> Tools {
        Tools(
            ytdlp: YtDlp.locate("yt-dlp"),
            ffmpeg: YtDlp.locate("ffmpeg"),
            deno: YtDlp.locate("deno")
        )
    }
}

/// One line of yt-dlp output, reduced to what the window shows.
enum OutputLine: Equatable {
    case progress(Progress)
    case processing
    case file(String)
    case error(String)
    case other

    struct Progress: Equatable {
        var fraction: Double?
        var speed: String?
        var eta: String?
        var playlistIndex: Int?
        var playlistCount: Int?
        var title: String
    }
}

enum YtDlp {
    /// An app launched from the Finder gets launchd's PATH — /usr/bin:/bin:/usr/sbin:/sbin —
    /// not your shell's, and Homebrew is not on it. So the tools are looked up in the
    /// usual prefixes by hand.
    static let searchDirectories: [String] = [
        "/opt/homebrew/bin",                // Homebrew, Apple silicon
        "/usr/local/bin",                   // Homebrew, Intel — and manual installs
        NSHomeDirectory() + "/.local/bin",  // pipx, pip --user
    ]

    static func locate(_ tool: String) -> URL? {
        for directory in searchDirectories {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// yt-dlp is told where ffmpeg is with --ffmpeg-location, but it only finds deno —
    /// which YouTube extraction needs — through PATH. Without this, a download started
    /// from the Finder warns "No supported JavaScript runtime" and loses formats.
    static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let inherited = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (searchDirectories + [inherited]).joined(separator: ":")
        // Titles become file names and travel through a pipe: force UTF-8 whatever
        // locale launchd handed over.
        environment["PYTHONUTF8"] = "1"
        return environment
    }

    static let progressTag = "[siphon] "
    static let fileTag = "[siphon-file] "

    /// Title last: a title can contain the separator, a percentage cannot.
    static let progressTemplate = "download:" + progressTag
        + "%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"
        + "|%(info.playlist_index)s|%(info.n_entries)s|%(info.title)s"

    static func arguments(
        for url: String,
        options: DownloadOptions,
        destination: URL,
        ffmpeg: URL?
    ) -> [String] {
        var arguments = [
            // A personal ~/.config/yt-dlp/config could change the output Siphon reads.
            "--ignore-config",
            "--newline",
            "--no-colors",
            // The file date is the download date, not the upload date.
            "--no-mtime",
            "--paths", destination.path,
            "--output", options.wholePlaylist
                // "Playlist title/3 - Title.mp3", and "./Title.mp3" for a lone video.
                // The slash has to stay outside the field: yt-dlp neutralises one
                // inside a replacement (it becomes "⧸"). And the "." default is not
                // cosmetic — with an empty default a lone video becomes "/Title.mp3",
                // an absolute path at the root of the disk.
                ? "%(playlist_title|.)s/%(playlist_index&{} - |)s%(title)s.%(ext)s"
                : "%(title)s.%(ext)s",
            options.wholePlaylist ? "--yes-playlist" : "--no-playlist",
            "--progress-template", progressTemplate,
            "--print", "after_move:" + fileTag + "%(filepath)s",
            // --print implies --quiet, which would also hide the progress lines.
            "--no-quiet",
        ]

        if let ffmpeg {
            // The directory, not the binary, so yt-dlp finds ffprobe next to it.
            arguments += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
        }

        switch options.format {
        case .mp3:
            arguments += ["--extract-audio", "--audio-format", "mp3", "--audio-quality", "320K"]
        case .m4a:
            // Take the AAC stream as it is: extracting to m4a from m4a is a plain copy.
            arguments += ["--format", "ba[ext=m4a]/ba", "--extract-audio", "--audio-format", "m4a"]
        case .mp4:
            arguments += ["--format-sort", options.videoQuality.sort, "--merge-output-format", "mp4"]
        }

        arguments += ["--embed-thumbnail", "--embed-metadata"]

        // "--" first: whatever was pasted, it is never read as an option.
        arguments += ["--", url]
        return arguments
    }

    static func parse(_ line: String) -> OutputLine {
        if line.hasPrefix(progressTag) {
            return .progress(parseProgress(String(line.dropFirst(progressTag.count))))
        }
        if line.hasPrefix(fileTag) {
            return .file(String(line.dropFirst(fileTag.count)))
        }
        if line.hasPrefix("ERROR: ") {
            return .error(String(line.dropFirst("ERROR: ".count)))
        }
        // ffmpeg's turn: conversion, merging audio and video, cover art, tags.
        let postProcessors = [
            "[ExtractAudio]", "[Merger]", "[EmbedThumbnail]", "[Metadata]",
            "[VideoConvertor]", "[FixupM3u8]", "[FixupM4a]",
        ]
        if postProcessors.contains(where: { line.hasPrefix($0) }) {
            return .processing
        }
        return .other
    }

    private static func parseProgress(_ payload: String) -> OutputLine.Progress {
        let fields = payload.split(separator: "|", maxSplits: 5, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func field(_ index: Int) -> String? {
            guard index < fields.count else { return nil }
            let value = fields[index]
            // yt-dlp writes NA for a missing field and "Unknown" for what it cannot
            // estimate yet.
            if value.isEmpty || value == "NA" || value.hasPrefix("Unknown") {
                return nil
            }
            return value
        }

        let percent = field(0).flatMap { Double($0.replacingOccurrences(of: "%", with: "")) }
        return OutputLine.Progress(
            fraction: percent.map { min(max($0 / 100, 0), 1) },
            speed: field(1),
            eta: field(2),
            playlistIndex: field(3).flatMap { Int($0) },
            playlistCount: field(4).flatMap { Int($0) },
            title: fields.count > 5 ? fields[5] : ""
        )
    }

    /// Every http(s) link in a block of pasted text, in order, without duplicates.
    static func links(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        var seen = Set<String>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            .map(\.absoluteString)
            .filter { seen.insert($0).inserted }
    }

    /// yt-dlp's errors are precise but terse; two of them deserve a hint in plain words.
    static func explain(_ message: String) -> String {
        if message.contains("CERTIFICATE_VERIFY_FAILED") {
            return message + " — a proxy is probably intercepting HTTPS (company network)."
        }
        if message.contains("ffmpeg not found") || message.contains("ffprobe and ffmpeg not found") {
            return message + " — install ffmpeg: brew install ffmpeg"
        }
        return message
    }

    /// `yt-dlp --version`, off the main thread: a cold Python start takes a moment.
    static func version(of tool: URL) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = tool
                process.arguments = ["--version"]
                process.environment = environment
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
        }
    }
}
