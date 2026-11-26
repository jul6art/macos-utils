import CoreAudio
import Darwin
import Foundation

/// A process Core Audio knows about: every process that has opened an audio connection.
struct AudioProcess: Hashable, Sendable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let executable: String
    let isRunningOutput: Bool
    let isRunningInput: Bool

    var executableName: String { (executable as NSString).lastPathComponent }

    var summary: String {
        let flags = (isRunningOutput ? "OUT" : "   ") + (isRunningInput ? " IN" : "   ")
        let bundle = bundleID.isEmpty ? "-" : bundleID
        return "\(String(pid).padding(toLength: 6, withPad: " ", startingAt: 0)) \(flags)  \(bundle)  \(executableName)"
    }
}

enum ProcessCatalog {
    static func all() -> [AudioProcess] {
        let objects = (try? readArrayProperty(systemObject, kAudioHardwarePropertyProcessObjectList, filler: AudioObjectID(0))) ?? []
        return objects.compactMap { object in
            guard let pid = try? readProperty(object, kAudioProcessPropertyPID, initial: pid_t(0)) else { return nil }
            let output = (try? readProperty(object, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0
            let input = (try? readProperty(object, kAudioProcessPropertyIsRunningInput, initial: UInt32(0))) ?? 0
            return AudioProcess(
                objectID: object,
                pid: pid,
                bundleID: (try? readStringProperty(object, kAudioProcessPropertyBundleID)) ?? "",
                executable: executablePath(of: pid),
                isRunningOutput: output != 0,
                isRunningInput: input != 0
            )
        }
    }

    /// A process matches when its bundle ID starts with `target` (an Electron app plays its sound from a
    /// helper whose bundle ID extends the app's), or when its executable is named `target`.
    static func matching(_ target: String, in processes: [AudioProcess]) -> [AudioProcess] {
        guard !target.isEmpty else { return [] }
        return processes.filter { $0.bundleID.hasPrefix(target) || $0.executableName == target }
    }

    private static func executablePath(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// The process taps that exist on the system. A private tap is visible to its owner only.
enum TapCatalog {
    static func uids() -> [String] {
        let taps = (try? readArrayProperty(systemObject, kAudioHardwarePropertyTapList, filler: AudioObjectID(0))) ?? []
        return taps.map { (try? readStringProperty($0, kAudioTapPropertyUID)) ?? "?" }
    }

    /// Destroys a public tap, whoever created it. Returns a process exit code.
    static func destroy(uid: String) -> Int32 {
        let taps = (try? readArrayProperty(systemObject, kAudioHardwarePropertyTapList, filler: AudioObjectID(0))) ?? []
        for tap in taps where (try? readStringProperty(tap, kAudioTapPropertyUID)) == uid {
            let status = AudioHardwareDestroyProcessTap(tap)
            print(status == noErr ? "destroyed \(uid)" : "could not destroy \(uid): \(fourCharacterCode(status))")
            return status == noErr ? 0 : 1
        }
        print("no public tap \(uid)")
        return 1
    }
}
