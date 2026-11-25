import Foundation

/// Opt-in tracing for window behaviour.
///
/// Window bugs — a panel that drifts off screen, an event monitor that is installed
/// twice and removed once — are invisible in a screenshot and awkward to reproduce by
/// hand. This lets a run of the real app narrate what its windows are doing:
///
///     ZSTATS_WINDOW_LOG=1 open -a ZStats.app   # or run the binary directly
///
/// Off by default and reduced to a single boolean check when disabled, so it costs
/// nothing in a normal session.
enum WindowLog {
    static let isEnabled = ProcessInfo.processInfo.environment["ZSTATS_WINDOW_LOG"] == "1"

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        FileHandle.standardError.write(Data("[zstats.window] \(message())\n".utf8))
    }
}
