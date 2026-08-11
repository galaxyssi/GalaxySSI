import UIKit

/// Automatic global-Agent work is foreground-only, matching Android's disabled background policy.
enum SignalASIGlobalAgentBackgroundPolicy {
  static var allowsAutomaticCycles: Bool {
    UIApplication.shared.applicationState == .active
  }
}
