import Foundation

/// ~/Library/Logs/VisagePilot: `pilot.log` (one JSON event per line) and `status.json` (rewritten
/// every second), so the measurements can be read back after a run.
@MainActor
final class PilotLog {
    private let directory: URL
    private let events: URL
    private let statusFile: URL

    init() {
        directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/VisagePilot")
        events = directory.appending(path: "pilot.log")
        statusFile = directory.appending(path: "status.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func event(_ name: String, _ fields: [String: Any]) {
        var record = fields
        record["event"] = name
        record["time"] = Self.timestamp()
        guard var line = Self.json(record, pretty: false) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: events) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: events)
        }
    }

    func status(_ fields: [String: Any]) {
        var record = fields
        record["time"] = Self.timestamp()
        try? Self.json(record, pretty: true)?.write(to: statusFile, options: .atomic)
    }

    private static func timestamp() -> String {
        Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
    }

    private static func json(_ object: [String: Any], pretty: Bool) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys])
    }
}
