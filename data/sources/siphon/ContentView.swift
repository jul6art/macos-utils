import SwiftUI
import AppKit

/// The window's own state. It would be three `@State` properties, but since the
/// macOS 27 SDK `@State` is a macro whose compiler plugin ships with Xcode only:
/// with the Command Line Tools alone it does not compile. `@StateObject` is still a
/// plain property wrapper.
final class InputState: ObservableObject {
    @Published var text = ""
    @Published var clipStart = ""
    @Published var clipEnd = ""
    @Published var notice: String?
    @Published var isDropTargeted = false
}

struct ContentView: View {
    @ObservedObject var queue: DownloadQueue
    @StateObject private var state = InputState()

    var body: some View {
        VStack(spacing: 0) {
            if queue.tools.ytdlp == nil || queue.tools.ffmpeg == nil {
                MissingToolsBanner(queue: queue)
                Divider()
            }

            controls
                .padding(16)

            Divider()

            jobList

            Divider()

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 580, minHeight: 400)
        .dropDestination(for: URL.self) { urls, _ in
            let links = urls.filter { !$0.isFileURL }.map(\.absoluteString)
            return !links.isEmpty && enqueue(links.joined(separator: "\n"))
        } isTargeted: { state.isDropTargeted = $0 }
        .overlay {
            if state.isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Input and settings

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                TextField("Paste one or more links (YouTube, SoundCloud, Vimeo…)", text: $state.text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                    .onChange(of: state.text) { _ in state.notice = nil }

                Button("Paste", action: pasteAndSubmit)
                    .help("Adds the links on the clipboard")

                Button("Download", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let notice = state.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 16) {
                Picker("Format", selection: $queue.format) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help(queue.format.help)

                if queue.format == .mp4 {
                    Picker("Quality", selection: $queue.videoQuality) {
                        ForEach(VideoQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    .fixedSize()
                    .help(queue.videoQuality == .best
                        ? "Past 1080p, YouTube only serves AV1 or VP9: QuickTime may not play them."
                        : "H.264: plays everywhere, QuickTime included")
                }

                Toggle("Whole playlist", isOn: $queue.wholePlaylist)
                    .help("For a link to a video that belongs to a playlist. Off: only that video is downloaded. "
                        + "On: the whole playlist, in a subfolder named after it.")

                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "scissors")
                    .foregroundStyle(.secondary)
                Text("From")
                TextField("start", text: $state.clipStart)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .onSubmit(submit)
                Text("to")
                TextField("end", text: $state.clipEnd)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .onSubmit(submit)
                Text("e.g. 9:45 or 1:02:03 — empty: the whole file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .help("Keeps only this part of the next links added. Cleared once they are in the queue.")
            .onChange(of: state.clipStart) { _ in state.notice = nil }
            .onChange(of: state.clipEnd) { _ in state.notice = nil }

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(displayPath(queue.destination))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(queue.destination.path)
                Spacer()
                Button("Choose…", action: chooseFolder)
                Button {
                    NSWorkspace.shared.open(queue.destination)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Open the folder in the Finder")
            }
        }
    }

    private func submit() {
        guard !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if enqueue(state.text) {
            state.text = ""
        }
    }

    /// Queues the links in `text`, cut to the times typed in the window if any.
    /// When nothing is added, the notice says why.
    private func enqueue(_ text: String) -> Bool {
        let clip: Clip?
        do {
            clip = try Clip.parse(start: state.clipStart, end: state.clipEnd)
        } catch {
            state.notice = error.localizedDescription
            return false
        }
        guard queue.add(text, clip: clip) > 0 else {
            state.notice = "No new link found: paste an address that starts with http(s)://"
            return false
        }
        // Times belong to the video they were typed for: the next link starts whole.
        state.clipStart = ""
        state.clipEnd = ""
        return true
    }

    private func pasteAndSubmit() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            state.notice = "The clipboard holds no text."
            return
        }
        state.text = text
        submit()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = queue.destination
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            queue.destination = url
        }
    }

    private func displayPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    // MARK: - Queue

    @ViewBuilder
    private var jobList: some View {
        if queue.jobs.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Paste a link, or drag it here from your browser")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(queue.jobs) { job in
                    JobRow(job: job, queue: queue)
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            ToolStatus(name: "yt-dlp", isPresent: queue.tools.ytdlp != nil, version: queue.ytdlpVersion)
            ToolStatus(name: "ffmpeg", isPresent: queue.tools.ffmpeg != nil)
            ToolStatus(name: "deno", isPresent: queue.tools.deno != nil)
                .help(queue.tools.deno == nil
                    ? "Without deno, YouTube withholds part of the formats: brew install deno"
                    : "The JavaScript runtime yt-dlp uses for YouTube")
            Spacer()
            Button("Clear finished") {
                queue.clearFinished()
            }
            .disabled(!queue.jobs.contains(where: \.isOver))
        }
        .font(.caption)
    }
}

struct JobRow: View {
    @ObservedObject var job: DownloadJob
    let queue: DownloadQueue

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(job.displayTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }

                if job.isActive {
                    if job.state == .downloading, let fraction = job.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }

                Text(status)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            actions
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            switch job.state {
            case .queued, .starting, .downloading, .processing:
                Button {
                    queue.cancel(job)
                } label: {
                    Image(systemName: "stop.circle")
                }
                .help("Stop")
                .disabled(job.isCancelling)
            case .finished:
                Button(action: reveal) {
                    Image(systemName: "magnifyingglass")
                }
                .help("Show in Finder")
                removeButton
            case .failed, .cancelled:
                Button {
                    queue.retry(job)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Retry")
                removeButton
            }
        }
        .buttonStyle(.borderless)
    }

    private var removeButton: some View {
        Button {
            queue.remove(job)
        } label: {
            Image(systemName: "xmark")
        }
        .help("Remove from the list (the file stays on disk)")
    }

    private func reveal() {
        let existing = job.files.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.isEmpty {
            NSWorkspace.shared.open(job.destination)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(existing)
        }
    }

    /// "1080p", "MP3 · 9:45–12:03".
    private var badge: String {
        let options = job.options
        let format = options.format == .mp4 ? options.videoQuality.title : options.format.title
        return options.clip.map { format + " · " + $0.title } ?? format
    }

    private var status: String {
        let position = job.position.map { " · \($0)" } ?? ""
        if job.isCancelling {
            return "Stopping…"
        }
        switch job.state {
        case .queued:
            return "Waiting"
        case .starting:
            return "Reading the link…"
        case .downloading:
            let percent = job.fraction.map { "\(Int(($0 * 100).rounded()))%" }
            let parts = ["Downloading", percent, job.detail].compactMap { $0 }
            return parts.joined(separator: " · ") + position
        case .processing:
            return "Converting…" + position
        case .finished:
            return job.files.count > 1 ? "Done · \(job.files.count) files" : "Done"
        case .failed(let message):
            return message
        case .cancelled:
            return "Stopped"
        }
    }

    private var icon: String {
        switch job.state {
        case .queued: return "clock"
        case .starting, .downloading: return "arrow.down.circle"
        case .processing: return "gearshape"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "stop.circle"
        }
    }

    private var iconColor: Color {
        switch job.state {
        case .finished: return .green
        case .failed: return .orange
        case .starting, .downloading, .processing: return .accentColor
        case .queued, .cancelled: return .secondary
        }
    }

    private var statusColor: Color {
        if case .failed = job.state {
            return .orange
        }
        return .secondary
    }
}

struct SettingsView: View {
    @ObservedObject var queue: DownloadQueue

    /// "2 s, 5 s" for three attempts: the waits between them, as DownloadJob does them.
    private var waits: String {
        let delays = DownloadJob.retryDelays
        return (1..<max(queue.attempts, 2))
            .map { "\(Int(delays[min($0, delays.count) - 1])) s" }
            .joined(separator: ", ")
    }

    var body: some View {
        Form {
            Stepper(value: $queue.attempts, in: DownloadQueue.attemptRange) {
                Text("Attempts when the site refuses: \(queue.attempts)")
            }
            Text((queue.attempts == 1
                ? "A refusal (HTTP 403) shows at once."
                : "After a refusal (HTTP 403), waits \(waits) between attempts, then shows it.")
                + " Default: \(DownloadQueue.defaultAttempts).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct ToolStatus: View {
    let name: String
    let isPresent: Bool
    var version: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isPresent ? Color.green : Color.orange)
            Text(version.map { "\(name) \($0)" } ?? name)
                .foregroundStyle(.secondary)
        }
    }
}

struct MissingToolsBanner: View {
    @ObservedObject var queue: DownloadQueue

    private let command = "brew install yt-dlp ffmpeg"

    private var missing: String {
        let names = [
            queue.tools.ytdlp == nil ? "yt-dlp" : nil,
            queue.tools.ffmpeg == nil ? "ffmpeg" : nil,
        ].compactMap { $0 }
        return names.joined(separator: " and ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(missing) not found")
                    .bold()
                Text("Install it with Homebrew, then click “Check again”:")
                    .font(.caption)
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            Button("Check again") {
                queue.refreshTools()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }
}
