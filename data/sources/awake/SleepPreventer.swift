import Foundation
import IOKit.pwr_mgt

final class SleepPreventer {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    /// Two very different guarantees:
    ///
    /// - `PreventUserIdleDisplaySleep` keeps the screen on, and as a side effect
    ///   the machine cannot idle-sleep either. This is `caffeinate -d`.
    /// - `PreventUserIdleSystemSleep` only keeps the machine running. The display
    ///   still dims, turns off and locks on its own schedule. This is
    ///   `caffeinate -i`.
    ///
    /// A menu bar coffee cup is expected to do the former, so that is the default.
    func start(keepDisplayAwake: Bool) {
        guard !isActive else { return }

        let type = keepDisplayAwake
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep

        let reason = keepDisplayAwake
            ? "Awake - keep the display awake"
            : "Awake - prevent idle system sleep"

        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isActive = true
        }
    }

    func stop() {
        guard isActive else { return }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit {
        stop()
    }
}
