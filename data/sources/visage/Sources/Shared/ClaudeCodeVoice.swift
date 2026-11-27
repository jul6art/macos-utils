/// What Visage shares with its voice for Claude Code, `visage-voice` (spec, § 4.4): Claude Code's plugin runs
/// that helper, which reads the end of each reply aloud with the Mac's voice; Visage taps its sound as it
/// taps an app's. The helper reads a few of Visage's settings, in Visage's domain.
public enum ClaudeCodeVoice {
    /// The helper's bundle ID, embedded in its executable: Core Audio names its sound by it.
    public static let bundleID = "com.devinthehood.visage.voice"
    /// The helper, inside Visage.app.
    public static let helperPath = "Contents/Helpers/visage-voice"
    /// Visage's settings domain.
    public static let visageDomain = "com.devinthehood.visage"
    /// The saved source, and Claude Code's value there: the helper speaks only while Visage listens to it.
    public static let sourceKey = "app"
    public static let sourceID = "claudecode"
    /// The face shown: the helper picks a voice that suits it.
    public static let faceKey = "face"
    /// When the plugin last ran, in seconds since 1970: Visage then knows it is installed.
    public static let pluginSeenKey = "claudeCodePluginSeen"
}
