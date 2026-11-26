import CoreAudio

/// The host clock every timestamp is expressed in: the captured sound, the sound played back and the
/// frame on screen. Everything that has to line up is measured on it.
public enum HostClock {
    public static var now: UInt64 { AudioGetCurrentHostTime() }

    public static func seconds(_ hostTime: UInt64) -> Double {
        Double(AudioConvertHostTimeToNanos(hostTime)) / 1e9
    }

    public static func hostTime(seconds: Double) -> UInt64 {
        AudioConvertNanosToHostTime(UInt64(max(seconds, 0) * 1e9))
    }
}
