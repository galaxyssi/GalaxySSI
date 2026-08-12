/// Automatic global-Agent work is disabled, matching Android's disabled background policy.
enum SignalASIGlobalAgentBackgroundPolicy {
  /// Explicit actions from the Global Agent control page remain available.
  static let allowsAutomaticCycles = false
}
