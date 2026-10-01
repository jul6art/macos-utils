import SwiftUI
import AppKit

/// The window's own state. It would be three `@State` properties, but since the
/// macOS 27 SDK `@State` is a macro whose compiler plugin ships with Xcode only:
/// with the Command Line Tools alone it does not compile. `@StateObject` is still a
/// plain property wrapper.
final class InputState: ObservableObject {
    @Published var text = ""
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
            return queue.add(links.joined(separator: "\n")) > 0
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
                TextField("Colle un ou plusieurs liens (YouTube, SoundCloud, Vimeo…)", text: $state.text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                    .onChange(of: state.text) { _ in state.notice = nil }

                Button("Coller", action: pasteAndSubmit)
                    .help("Ajoute les liens du presse-papiers")

                Button("Télécharger", action: submit)
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
                    Picker("Qualité", selection: $queue.videoQuality) {
                        ForEach(VideoQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    .fixedSize()
                    .help(queue.videoQuality == .best
                        ? "Au-delà de 1080p, YouTube ne fournit que de l'AV1 ou du VP9 : QuickTime peut ne pas les lire."
                        : "H.264 : lisible partout, QuickTime compris")
                }

                Toggle("Playlist entière", isOn: $queue.wholePlaylist)
                    .help("Pour un lien vers une vidéo d'une playlist. Décoché : seule la vidéo est téléchargée. "
                        + "Coché : toute la playlist, dans un sous-dossier à son nom.")

                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(displayPath(queue.destination))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(queue.destination.path)
                Spacer()
                Button("Choisir…", action: chooseFolder)
                Button {
                    NSWorkspace.shared.open(queue.destination)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Ouvrir le dossier dans le Finder")
            }
        }
    }

    private func submit() {
        guard !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if queue.add(state.text) > 0 {
            state.text = ""
        } else {
            state.notice = "Aucun nouveau lien reconnu : colle une adresse qui commence par http(s)://"
        }
    }

    private func pasteAndSubmit() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            state.notice = "Le presse-papiers ne contient pas de texte."
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
        panel.prompt = "Choisir"
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
                Text("Colle un lien, ou glisse-le ici depuis ton navigateur")
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
                    ? "Sans deno, YouTube refuse une partie des formats : brew install deno"
                    : "Moteur JavaScript utilisé par yt-dlp pour YouTube")
            Spacer()
            Button("Effacer les terminés") {
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
                    Text(job.options.format == .mp4 ? job.options.videoQuality.title : job.options.format.title)
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
                .help("Arrêter")
                .disabled(job.isCancelling)
            case .finished:
                Button(action: reveal) {
                    Image(systemName: "magnifyingglass")
                }
                .help("Afficher dans le Finder")
                removeButton
            case .failed, .cancelled:
                Button {
                    queue.retry(job)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Réessayer")
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
        .help("Retirer de la liste (le fichier reste sur le disque)")
    }

    private func reveal() {
        let existing = job.files.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.isEmpty {
            NSWorkspace.shared.open(job.destination)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(existing)
        }
    }

    private var status: String {
        let position = job.position.map { " · \($0)" } ?? ""
        if job.isCancelling {
            return "Arrêt…"
        }
        switch job.state {
        case .queued:
            return "En attente"
        case .starting:
            return "Lecture du lien…"
        case .downloading:
            let percent = job.fraction.map { "\(Int(($0 * 100).rounded()))\u{00A0}%" }
            let parts = ["Téléchargement", percent, job.detail].compactMap { $0 }
            return parts.joined(separator: " · ") + position
        case .processing:
            return "Conversion…" + position
        case .finished:
            return job.files.count > 1 ? "Terminé · \(job.files.count) fichiers" : "Terminé"
        case .failed(let message):
            return message
        case .cancelled:
            return "Arrêté"
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
        return names.joined(separator: " et ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(missing) introuvable")
                    .bold()
                Text("Installe-le avec Homebrew, puis clique sur « Vérifier à nouveau » :")
                    .font(.caption)
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Copier") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            Button("Vérifier à nouveau") {
                queue.refreshTools()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }
}
