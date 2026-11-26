import CoreAudio
import Darwin
import Foundation

/// A process Core Audio knows about: every process that has opened an audio connection.
public struct AudioProcess: Hashable, Sendable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String
    public let executable: String
    public let isRunningOutput: Bool

    public init(objectID: AudioObjectID, pid: pid_t, bundleID: String, executable: String, isRunningOutput: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.executable = executable
        self.isRunningOutput = isRunningOutput
    }

    public var executableName: String { (executable as NSString).lastPathComponent }
}

public enum AudioProcesses {
    public static func all() -> [AudioProcess] {
        let objects =
            (try? readArrayProperty(systemObject, kAudioHardwarePropertyProcessObjectList, filler: AudioObjectID(0)))
            ?? []
        return objects.compactMap { object in
            guard let pid = try? readProperty(object, kAudioProcessPropertyPID, initial: pid_t(0)) else { return nil }
            let output = (try? readProperty(object, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0
            return AudioProcess(
                objectID: object,
                pid: pid,
                bundleID: (try? readStringProperty(object, kAudioProcessPropertyBundleID)) ?? "",
                executable: executablePath(of: pid),
                isRunningOutput: output != 0
            )
        }
    }

    /// The processes of an app: its bundle ID, and the helpers whose bundle IDs extend it (an Electron
    /// app plays its sound from a helper, `com.example.app.helper`). An executable name matches too, for
    /// command-line stand-ins such as `afplay`.
    public static func matching(_ target: String, in processes: [AudioProcess]) -> [AudioProcess] {
        guard !target.isEmpty else { return [] }
        return processes.filter {
            $0.bundleID == target || $0.bundleID.hasPrefix(target + ".") || $0.executableName == target
        }
    }

    private static func executablePath(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// The public process taps on the system. Visage's own taps are private; a public one named "Visage" can
/// only be a leftover from a version that crashed (a public tap outlives its process: pilot, § 2.2).
public enum ProcessTaps {
    public static let name = "Visage"

    /// Destroys the public taps named "Visage". Returns how many went.
    @discardableResult
    public static func destroyLeftovers() -> Int {
        let taps = (try? readArrayProperty(systemObject, kAudioHardwarePropertyTapList, filler: AudioObjectID(0))) ?? []
        var destroyed = 0
        for tap in taps {
            guard
                let description = try? readProperty(
                    tap, kAudioTapPropertyDescription, initial: Unmanaged<CATapDescription>?.none),
                description.takeRetainedValue().name == name
            else { continue }
            if AudioHardwareDestroyProcessTap(tap) == noErr { destroyed += 1 }
        }
        return destroyed
    }
}
