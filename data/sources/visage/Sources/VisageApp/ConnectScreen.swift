import AppKit
import AudioSource
import SwiftUI

/// « Connect my AI » (spec, § 4.2): one card per known app, another app that plays sound, and a status
/// line that says what to do next.
struct ConnectScreen: View {
    let model: AppModel
    /// Inside the welcome: no header of its own, and the face waits for « Start ».
    var welcoming = false

    var body: some View {
        ConnectView(
            state: model.connection.state,
            connectedApp: model.connection.app,
            listening: model.connection.appListening,
            claudeCodePluginSeen: model.claudeCodePluginSeen,
            apps: model.apps.map { AppCardInfo(app: $0) },
            otherApps: model.otherApps(),
            connect: { model.connect(to: $0, showingFace: !welcoming) },
            showFace: { model.showFace() },
            header: !welcoming
        )
    }
}

struct AppCardInfo: Identifiable {
    let app: AIApp
    let isInstalled: Bool
    let isRunning: Bool

    var id: String { app.id }

    @MainActor
    init(app: AIApp) {
        self.app = app
        isInstalled = app.installation != nil
        isRunning = app.isRunning
    }

    init(app: AIApp, isInstalled: Bool, isRunning: Bool) {
        self.app = app
        self.isInstalled = isInstalled
        self.isRunning = isRunning
    }
}

/// The screen itself, fed with plain values so it can be rendered for checking (`--snapshot`).
struct ConnectView: View {
    let state: Connection.State
    let connectedApp: AIApp?
    var listening = false
    /// Whether Claude Code's plugin has run: until then, connecting to Claude Code says how to install it.
    var claudeCodePluginSeen = false
    let apps: [AppCardInfo]
    let otherApps: [AIApp]
    let connect: (AIApp) -> Void
    let showFace: () -> Void
    var header = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if header {
                HStack(alignment: .top, spacing: 16) {
                    MarkView(size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connect my AI").font(.title2.weight(.semibold))
                        Text(
                            "Visage gives a face to the voice of the AI app you already use. It only hears that app's sound, and nothing leaves your Mac."
                        )
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Three in a row; four, Siri shown, in two rows.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: apps.count == 4 ? 2 : apps.count),
                spacing: 12
            ) {
                ForEach(apps) { info in
                    AppCard(info: info, isConnected: connectedApp?.id == info.app.id, connect: connect)
                }
            }

            if !otherApps.isEmpty {
                DisclosureGroup("Another app") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(otherApps) { app in
                            HStack {
                                Text(app.name)
                                Text(app.bundleIDs.first ?? "").foregroundStyle(.secondary).font(.caption)
                                Spacer()
                                Button("Connect") { connect(app) }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }

            StatusLine(
                state: state, app: connectedApp, listening: listening, pluginSeen: claudeCodePluginSeen,
                showFace: showFace)
        }
        .padding(header ? 24 : 0)
        .frame(width: header ? 560 : nil, alignment: .leading)
    }
}

private struct AppCard: View {
    let info: AppCardInfo
    let isConnected: Bool
    let connect: (AIApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(info.app.name).font(.headline)
            Text(status).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if info.isInstalled {
                Button(isConnected ? String(localized: "Reconnect") : String(localized: "Connect")) {
                    connect(info.app)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.braise)
                .foregroundStyle(Color(nsColor: Palette.charbon))
            } else if let url = info.app.downloadURL {
                // Claude Code installs from a command, which its page gives.
                Link(
                    info.app.kind == .claudeCode ? String(localized: "How to install") : String(localized: "Download"),
                    destination: url)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                isConnected ? Palette.braise : Color(nsColor: .separatorColor), lineWidth: isConnected ? 2 : 1))
    }

    private var status: String {
        if isConnected { return String(localized: "Connected") }
        if info.isRunning { return String(localized: "Open") }
        return info.isInstalled ? String(localized: "Installed") : String(localized: "Not installed")
    }
}

private struct StatusLine: View {
    let state: Connection.State
    let app: AIApp?
    let listening: Bool
    let pluginSeen: Bool
    let showFace: () -> Void

    /// Installs Visage's plugin in Claude Code, in one step (Claude Code 2.1.275 and later).
    static let pluginCommand = "/plugin install visage --marketplace jul6art/macos-utils"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            line
            // Claude Code without its plugin: the command, on a line of its own, to copy into Claude Code.
            if case .connected = state, app?.kind == .claudeCode, !pluginSeen, !listening {
                HStack(spacing: 8) {
                    Text(Self.pluginCommand).font(.caption.monospaced()).fixedSize().textSelection(.enabled)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.pluginCommand, forType: .string)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var line: some View {
        let name = app?.name ?? ""
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            switch state {
            case .idle:
                Text("Pick the app you talk to.").foregroundStyle(.secondary)
            case .notInstalled:
                Text("\(name) is not installed on this Mac.")
            case .starting:
                ProgressView().controlSize(.small)
                Text("Connecting…")
            case .waitingForPermission:
                ProgressView().controlSize(.small)
                Text("macOS asks whether Visage may record system audio: allow it.")
            case .permissionMissing:
                Text(
                    "Visage cannot hear \(name) yet. Allow it in System Settings, under Privacy & Security, Screen & System Audio Recording."
                )
                .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .waitingForApp where app?.kind == .siri:
                Text("Ask Siri something: Visage connects at its first spoken answer.")
            case .waitingForApp where app?.kind == .claudeCode:
                Text("Talk to Claude Code: Visage connects with your next request.")
            case .waitingForApp:
                Text("Start voice mode in \(name): Visage connects as soon as it speaks.")
            case .connected:
                if listening {
                    Text("Connected to \(name), which is listening: talk to it.")
                } else if app?.kind == .siri {
                    Text(
                        "Connected to Siri. Ask it something: it answers aloud when its voice responses are on, in System Settings, under Siri."
                    )
                    .fixedSize(horizontal: false, vertical: true)
                } else if app?.kind == .claudeCode, !pluginSeen {
                    Text("Connected to Claude Code. Install Visage's plugin in it, once:")
                        .fixedSize(horizontal: false, vertical: true)
                } else if app?.kind == .claudeCode {
                    // Its dictation is the microphone: Claude Code answers aloud through the plugin.
                    Text("Connected to Claude Code. Turn on its dictation with /voice, and talk: it answers aloud.")
                        .fixedSize(horizontal: false, vertical: true)
                } else if app?.id == AIApp.claude.id {
                    // Not dictation (the microphone): the sound-wave button opens the spoken conversation.
                    Text(
                        "Connected to Claude. Start its voice mode: the sound-wave button, at the bottom right of its window."
                    )
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Connected to \(name). Start voice mode and talk.")
                }
                Spacer()
                Button("Show the face", action: showFace)
            case .failed(let message):
                Text("The connection failed: \(message)").foregroundStyle(.red)
            }
        }
        .font(.callout)
        .frame(minHeight: 28)
    }
}

/// The charter's mark, drawn once from the shared geometry (logo state).
struct MarkView: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            MarkDrawing.draw(in: &context, size: canvasSize)
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.22).fill(Color(nsColor: Palette.charbon)))
    }
}
