import Foundation

enum AgentIOSPr2627To2633Oracle: String, CaseIterable {
  case parallelReader = "parallel_reader"
  case completionPolicy = "completion_policy"
  case pairingIdentity = "pairing_id"
  case urlExtraction = "url_extract"
  case urlContext = "url_context"
  case cacheService = "cache_service"
  case singleFlight = "singleflight"
  case evidencePack = "evidence_pack"
  case canonicalURL = "canonical_url"
  case boundedPack = "bounded_pack"
  case untrustedBoundary = "untrusted_boundary"
  case dynamicHeaders = "dynamic_headers"
  case articleParser = "article_parse"
  case dynamicFetch = "dynamic_fetch"
  case cognitionPlan = "cognition_plan"
  case cognitionDelay = "cognition_delay"
  case privacyKnowledge = "privacy_knowledge"
  case privacyMetadata = "privacy_metadata"
  case transcriptRedaction = "transcript_redaction"
  case toolCatalog = "tool_catalog"
  case toolProtocol = "tool_protocol"
  case citationValidation = "citation_validation"
}

struct AgentIOSPr2627To2633Suite: Equatable {
  var pullRequest: Int
  var id: String
  var oracle: AgentIOSPr2627To2633Oracle
  var layer: String
}

struct AgentIOSPr2627To2633Case: Equatable {
  var id: String
  var ordinal: Int
  var riskID: String
  var conversationID: String
  var pullRequest: Int
  var suiteID: String
  var oracle: AgentIOSPr2627To2633Oracle
  var layer: String
  var profileID: String
  var variantIndex: Int
}

enum AgentIOSPr2627To2633RegressionCorpus {
  static let profiles = [
    "fresh-start", "warm-state", "duplicate-input", "reordered-input", "single-failure",
    "partial-failure", "late-timeout", "early-timeout", "cancel-before", "cancel-during",
    "offline", "same-host-redirect", "cross-host-redirect", "unicode-content", "percent-encoded",
    "empty-optional", "maximum-bound", "untrusted-instruction", "process-restart", "concurrent-callers"
  ]

  static let suites: [AgentIOSPr2627To2633Suite] = [
    suite(2627, "parallel-result-order", .parallelReader, "integration"),
    suite(2627, "per-host-cap", .parallelReader, "integration"),
    suite(2627, "mixed-host-fairness", .parallelReader, "integration"),
    suite(2627, "shared-deadline", .parallelReader, "integration"),
    suite(2627, "early-completion", .completionPolicy, "unit"),
    suite(2627, "partial-source-failure", .parallelReader, "integration"),
    suite(2627, "duplicate-candidate-collapse", .parallelReader, "integration"),
    suite(2627, "cancellation-propagation", .parallelReader, "integration"),
    suite(2628, "pairing-replay-dedup", .pairingIdentity, "unit"),
    suite(2628, "supplied-message-id", .pairingIdentity, "unit"),
    suite(2628, "route-isolation", .pairingIdentity, "unit"),
    suite(2628, "desktop-isolation", .pairingIdentity, "unit"),
    suite(2628, "system-notice-idempotence", .pairingIdentity, "device"),
    suite(2629, "explicit-url-dedup", .urlExtraction, "unit"),
    suite(2629, "max-url-bound", .urlExtraction, "unit"),
    suite(2629, "history-continuation", .urlContext, "unit"),
    suite(2629, "cache-hit", .cacheService, "integration"),
    suite(2629, "cache-expiry", .cacheService, "integration"),
    suite(2629, "concurrent-singleflight", .singleFlight, "integration"),
    suite(2629, "failure-not-poison-cache", .cacheService, "integration"),
    suite(2629, "redirect-request-alias", .cacheService, "device"),
    suite(2630, "canonical-citation", .evidencePack, "unit"),
    suite(2630, "manifest-integrity", .evidencePack, "unit"),
    suite(2630, "duplicate-content-correlation", .evidencePack, "unit"),
    suite(2630, "numeric-conflict", .evidencePack, "unit"),
    suite(2630, "cross-client-url-normalization", .canonicalURL, "unit"),
    suite(2630, "bounded-pack-json", .boundedPack, "unit"),
    suite(2630, "untrusted-evidence-boundary", .untrustedBoundary, "unit"),
    suite(2631, "wechat-mobile-headers", .dynamicHeaders, "device"),
    suite(2631, "generic-host-no-special-header", .dynamicHeaders, "unit"),
    suite(2631, "structured-wechat-parse", .articleParser, "device"),
    suite(2631, "generic-jsonld-parse", .articleParser, "unit"),
    suite(2631, "challenge-detection", .dynamicFetch, "integration"),
    suite(2631, "static-success-no-render", .dynamicFetch, "integration"),
    suite(2631, "renderer-failure-isolation", .dynamicFetch, "integration"),
    suite(2632, "background-event-lightweight", .cognitionPlan, "unit"),
    suite(2632, "scheduled-bounded-cycle", .cognitionPlan, "unit"),
    suite(2632, "idle-four-hour-cap", .cognitionDelay, "unit"),
    suite(2632, "active-ten-minute-cadence", .cognitionDelay, "unit"),
    suite(2632, "secret-knowledge-block", .privacyKnowledge, "unit"),
    suite(2632, "safe-knowledge-project", .privacyKnowledge, "unit"),
    suite(2632, "metadata-token-block", .privacyMetadata, "unit"),
    suite(2632, "transcript-redaction", .transcriptRedaction, "unit"),
    suite(2633, "model-semantic-tool-policy", .toolCatalog, "unit"),
    suite(2633, "dsml-tool-call-parse", .toolProtocol, "unit"),
    suite(2633, "normal-text-preservation", .toolProtocol, "unit"),
    suite(2633, "citation-required", .citationValidation, "unit"),
    suite(2633, "foreign-citation-rejected", .citationValidation, "unit"),
    suite(2633, "tampered-citation-id", .evidencePack, "unit"),
    suite(2633, "one-repair-only", .citationValidation, "integration")
  ]

  static let cases: [AgentIOSPr2627To2633Case] = suites.enumerated().flatMap { suiteIndex, suite in
    profiles.enumerated().map { profileIndex, profileID in
      let ordinal = suiteIndex * profiles.count + profileIndex + 1
      let paddedOrdinal = String(format: "%04d", ordinal)
      return AgentIOSPr2627To2633Case(
        id: "PR\(suite.pullRequest)-\(suite.id.uppercased())-\(String(format: "%02d", profileIndex + 1))",
        ordinal: ordinal,
        riskID: "RISK-\(paddedOrdinal)",
        conversationID: "regression-pr2627-pr2633-\(paddedOrdinal)",
        pullRequest: suite.pullRequest,
        suiteID: suite.id,
        oracle: suite.oracle,
        layer: suite.layer,
        profileID: profileID,
        variantIndex: profileIndex
      )
    }
  }

  private static func suite(
    _ pullRequest: Int,
    _ id: String,
    _ oracle: AgentIOSPr2627To2633Oracle,
    _ layer: String
  ) -> AgentIOSPr2627To2633Suite {
    AgentIOSPr2627To2633Suite(pullRequest: pullRequest, id: id, oracle: oracle, layer: layer)
  }
}
