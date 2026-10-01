import Foundation
import Combine

/// One link, one yt-dlp process.
@MainActor
final class DownloadJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case queued
        case starting       // yt-dlp is reading the page, nothing downloads yet
        case downloading
        case processing     // ffmpeg's turn: conversion, merge, cover art
        case finished
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let url: String
    let options: DownloadOptions
    let destination: URL

    @Published private(set) var state: State = .queued
    @Published private(set) var title: String?
    @Published private(set) var fraction: Double?
    @Published private(set) var detail: String?
    @Published private(set) var position: String?
    @Published private(set) var files: [URL] = []
    @Published private(set) var isCancelling = false

    private var process: Process?
    private var onExit: (() -> Void)?
    private var lastError: String?
    private var exitStatus: Int32?
    private var outputClosed = false

    init(url: String, options: DownloadOptions, destination: URL) {
        self.url = url
        self.options = options
        self.destination = destination
    }

    var isActive: Bool {
        state == .starting || state == .downloading || state == .processing
    }

    var isOver: Bool {
        switch state {
        case .finished, .failed, .cancelled: return true
        case .queued, .starting, .downloading, .processing: return false
        }
    }

    var displayTitle: String {
        title ?? files.last?.deletingPathExtension().lastPathComponent ?? url
    }

    /// Returns false when yt-dlp could not even be launched; the job is then failed.
    @discardableResult
    func start(with tools: Tools, onExit: @escaping () -> Void) -> Bool {
        guard state == .queued, let ytdlp = tools.ytdlp else { return false }

        let process = Process()
        process.executableURL = ytdlp
        process.arguments = YtDlp.arguments(
            for: url,
            options: options,
            destination: destination,
            ffmpeg: tools.ffmpeg
        )
        process.environment = YtDlp.environment
        process.standardInput = FileHandle.nullDevice

        // One pipe for both streams keeps errors in order with the rest.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        Self.attach(pipe, process, to: self)

        do {
            try process.run()
        } catch {
            state = .failed("Impossible de lancer yt-dlp : \(error.localizedDescription)")
            return false
        }

        self.process = process
        self.onExit = onExit
        state = .starting
        return true
    }

    func cancel() {
        switch state {
        case .queued:
            state = .cancelled
        case .starting, .downloading, .processing:
            guard let process, !isCancelling else { return }
            isCancelling = true
            // SIGINT, the way Ctrl-C stops it in a terminal: yt-dlp winds down on its
            // own and keeps the .part file, so the same link resumes where it stopped.
            process.interrupt()
            // A process that ignores it gets a SIGTERM three seconds later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak process] in
                if let process, process.isRunning {
                    process.terminate()
                }
            }
        case .finished, .failed, .cancelled:
            break
        }
    }

    /// Built outside the main actor on purpose: these closures run on Foundation's
    /// background threads, and a closure written inside a @MainActor method would
    /// inherit that isolation — and trap the moment it is called off the main thread.
    /// Lines hop to the main queue one by one, which keeps them in order.
    nonisolated private static func attach(_ pipe: Pipe, _ process: Process, to job: DownloadJob) {
        let reader = LineReader()

        pipe.fileHandleForReading.readabilityHandler = { [weak job] handle in
            let data = handle.availableData
            let closed = data.isEmpty
            let lines = closed ? reader.flush() : reader.append(data)
            if closed {
                handle.readabilityHandler = nil
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let job else { return }
                    lines.forEach { job.receive($0) }
                    if closed {
                        job.outputDidClose()
                    }
                }
            }
        }

        process.terminationHandler = { [weak job] process in
            let status = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    job?.processDidExit(status)
                }
            }
        }
    }

    private func receive(_ line: String) {
        switch YtDlp.parse(line) {
        case .progress(let progress):
            if !isCancelling {
                state = .downloading
            }
            if !progress.title.isEmpty {
                title = progress.title
            }
            fraction = progress.fraction
            let parts = [progress.speed, progress.eta.map { "reste \($0)" }].compactMap { $0 }
            detail = parts.isEmpty ? nil : parts.joined(separator: " · ")
            if let index = progress.playlistIndex, let count = progress.playlistCount {
                position = "\(index)/\(count)"
            }
        case .processing:
            if !isCancelling {
                state = .processing
            }
            fraction = nil
            detail = nil
        case .file(let path):
            files.append(URL(fileURLWithPath: path))
        case .error(let message):
            lastError = message
        case .other:
            break
        }
    }

    private func processDidExit(_ status: Int32) {
        exitStatus = status
        if outputClosed {
            complete()
            return
        }
        // Normally the pipe closes right after the exit. After a cancel, an ffmpeg
        // child can hold it open a moment longer: do not wait for it forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.complete()
        }
    }

    private func outputDidClose() {
        outputClosed = true
        if exitStatus != nil {
            complete()
        }
    }

    private func complete() {
        guard let status = exitStatus, process != nil else { return }
        process = nil

        if isCancelling {
            state = .cancelled
        } else if status == 0 {
            state = .finished
            fraction = 1
        } else {
            state = .failed(lastError.map(YtDlp.explain) ?? "yt-dlp s'est arrêté (code \(status)).")
        }
        detail = nil
        isCancelling = false

        let onExit = self.onExit
        self.onExit = nil
        onExit?()
    }
}

/// Splits the raw bytes of a pipe into lines. Bytes arrive cut anywhere — mid-line,
/// even mid-character — so whatever follows the last newline waits for the next chunk.
final class LineReader {
    private var pending = Data()

    func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let end = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = pending[pending.startIndex..<end]
            pending.removeSubrange(pending.startIndex...end)
            if !line.isEmpty {
                lines.append(String(decoding: line, as: UTF8.self))
            }
        }
        return lines
    }

    func flush() -> [String] {
        defer { pending.removeAll() }
        return pending.isEmpty ? [] : [String(decoding: pending, as: UTF8.self)]
    }
}
