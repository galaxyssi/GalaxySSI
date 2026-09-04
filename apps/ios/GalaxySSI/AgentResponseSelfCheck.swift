import CryptoKit
import Foundation

enum AgentResponseSelfCheckStatus: String, Codable, CaseIterable, Identifiable {
  case passed = "PASSED"
  case repair = "REPAIR"
  case rejected = "REJECTED"

  var id: String { rawValue }
}

struct AgentResponseSelfCheckResult: Codable, Equatable {
  var status: AgentResponseSelfCheckStatus
  var reasons: [String]
  var requestDigest: String
  var responseDigest: String
  var actionableRequest: Bool
  var hasAttachments: Bool

  var accepted: Bool {
    status == .passed
  }

  var diagnostic: String {
    if accepted {
      return "Final response addresses the latest user request."
    }
    let detail = reasons.isEmpty ? "response_not_verified" : reasons.joined(separator: ", ")
    return "Final response did not pass latest-request self-check: \(detail)"
  }
}

enum AgentResponseSelfCheck {
  static func evaluate(
    latestRequest: String,
    response: String,
    hasAttachments: Bool = false,
    hasOutputArtifacts: Bool = false,
    expectedIdentity: [String: String] = [:],
    responseIdentity: [String: String] = [:]
  ) -> AgentResponseSelfCheckResult {
    let request = String(latestRequest.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxRequestLength))
    let reply = String(response.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxResponseLength))
    let actionable = isActionable(request, hasAttachments: hasAttachments)
    var reasons: [String] = []
    let status: AgentResponseSelfCheckStatus

    if !identityMatches(expected: expectedIdentity, actual: responseIdentity) {
      reasons.append("identity_mismatch")
      status = .rejected
    } else if reply.isEmpty && !hasOutputArtifacts {
      reasons.append("empty_response")
      status = .repair
    } else {
      if hasAttachments && regexContains(missingAttachmentPattern, in: reply, caseInsensitive: true) {
        reasons.append("available_attachment_ignored")
      }
      if actionable && regexContains(askForTaskAgainPattern, in: reply, caseInsensitive: true) {
        reasons.append("latest_request_ignored")
      }
      if !hasOutputArtifacts &&
        acknowledgementOnly(reply) &&
        !acknowledgementRequests.contains(normalized(request)) &&
        !explicitlyRequestsShortReply(request, response: reply) {
        reasons.append("acknowledgement_only")
      }
      if actionable && normalized(reply) == normalized(request) {
        reasons.append("request_echo")
      }
      status = reasons.isEmpty ? .passed : .repair
    }

    return AgentResponseSelfCheckResult(
      status: status,
      reasons: reasons,
      requestDigest: digest(request),
      responseDigest: digest(reply),
      actionableRequest: actionable,
      hasAttachments: hasAttachments
    )
  }

  private static func isActionable(_ request: String, hasAttachments: Bool) -> Bool {
    let clean = normalized(request)
    if clean.isEmpty || genericRequests.contains(clean) {
      return false
    }
    return regexContains(actionTermsPattern, in: request, caseInsensitive: true) ||
      (hasAttachments && clean.split(separator: " ").filter { !$0.isEmpty }.count >= 2)
  }

  private static func acknowledgementOnly(_ response: String) -> Bool {
    let stripped = response.map { char -> String in
      "`*_>#[]()".contains(char) ? " " : String(char)
    }.joined()
    let clean = replaceRegex(pattern: #"\s+"#, in: stripped, with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if ackExact.contains(clean) {
      return true
    }
    if clean.count > 400 || clean.split(separator: " ").count > 60 {
      return false
    }
    return regexContains(ackStartPattern, in: clean, caseInsensitive: true) &&
      regexContains(futureOnlyPattern, in: clean, caseInsensitive: true)
  }

  private static func explicitlyRequestsShortReply(_ request: String, response: String) -> Bool {
    let requested = normalized(request)
    let reply = normalized(response)
    guard !reply.isEmpty,
          ackExact.contains(where: { normalized($0) == reply }) else {
      return false
    }

    let englishPatterns = [
      "reply only \(reply)",
      "reply with only \(reply)",
      "respond only \(reply)",
      "respond with only \(reply)",
      "answer only \(reply)",
      "answer with only \(reply)",
      "only reply \(reply)",
      "only respond \(reply)",
      "only answer \(reply)"
    ]
    if englishPatterns.contains(where: { requested.contains($0) }) {
      return true
    }

    let compactRequest = requested.replacingOccurrences(of: " ", with: "")
    let compactReply = reply.replacingOccurrences(of: " ", with: "")
    return [
      "\u{53ea}\u{56de}\u{590d}\(compactReply)",
      "\u{53ea}\u{56de}\u{7b54}\(compactReply)",
      "\u{56de}\u{590d}\(compactReply)\u{5373}\u{53ef}",
      "\u{56de}\u{7b54}\(compactReply)\u{5373}\u{53ef}"
    ].contains(where: { compactRequest.contains($0) })
  }

  private static func identityMatches(
    expected: [String: String],
    actual: [String: String]
  ) -> Bool {
    if expected.isEmpty {
      return true
    }
    if actual.isEmpty {
      return false
    }
    for (key, value) in expected {
      if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        continue
      }
      if actual[key] ?? "" != value {
        return false
      }
    }
    return true
  }

  private static func normalized(_ value: String) -> String {
    replaceRegex(pattern: #"[^\p{L}\p{N}_]+"#, in: value.lowercased(), with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func digest(_ value: String) -> String {
    let hash = Data(SHA256.hash(data: Data(value.utf8)))
    return Data(hash.prefix(8)).hexString()
  }

  private static func regexContains(_ pattern: String, in value: String, caseInsensitive: Bool = false) -> Bool {
    var options: NSRegularExpression.Options = []
    if caseInsensitive {
      options.insert(.caseInsensitive)
    }
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return false
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.firstMatch(in: value, options: [], range: range) != nil
  }

  private static func replaceRegex(pattern: String, in value: String, with replacement: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return value
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: replacement)
  }

  private static let maxRequestLength = 16_000
  private static let maxResponseLength = 32_000
  private static let genericRequests: Set<String> = ["attached files", "attached file", "attachment", "file"]
  private static let actionTermsPattern =
    #"\b(?:analy[sz]e|build|calculate|check|compare|convert|create|debug|delete|download|edit|explain|export|extract|find|fix|generate|install|list|make|modify|open|prepare|read|repair|research|review|run|save|search|send|set|show|start|stop|summari[sz]e|test|translate|update|verify|write)\b|"# +
    "(?:\u{5206}\u{6790}|\u{8ba1}\u{7b97}|\u{521b}\u{5efa}|\u{6253}\u{5f00}|\u{5173}\u{95ed}|\u{4fee}\u{590d}|\u{68c0}\u{67e5}|\u{67e5}\u{627e}|\u{641c}\u{7d22}|\u{603b}\u{7ed3}|\u{7ffb}\u{8bd1}|\u{8fd0}\u{884c}|\u{6d4b}\u{8bd5}|\u{5b89}\u{88c5}|\u{751f}\u{6210}|\u{5236}\u{4f5c}|\u{4fee}\u{6539}|\u{7f16}\u{8f91}|\u{5bfc}\u{51fa}|\u{4fdd}\u{5b58}|\u{53d1}\u{9001}|\u{8bbe}\u{7f6e}|\u{8bfb}\u{53d6}|\u{67e5}\u{770b}|\u{5bf9}\u{6bd4}|\u{9a8c}\u{8bc1})"
  private static let ackExact: Set<String> = [
    "got it", "got it.", "ok", "okay", "sure", "understood", "done", "completed",
    "working on it", "i will handle this", "i'll handle this",
    "\u{597d}\u{7684}", "\u{6536}\u{5230}", "\u{660e}\u{767d}",
    "\u{5df2}\u{5b8c}\u{6210}", "\u{5904}\u{7406}\u{597d}\u{4e86}"
  ]
  private static let acknowledgementRequests: Set<String> = [
    "ok", "okay", "thanks", "thank you", "got it",
    "\u{597d}\u{7684}", "\u{8c22}\u{8c22}", "\u{6536}\u{5230}", "\u{660e}\u{767d}"
  ]
  private static let ackStartPattern =
    #"^(?:got it|okay|sure|understood|i(?:'ll| will| am going to)|working on it|starting now|"# +
    "\u{597d}\u{7684}|\u{6536}\u{5230}|\u{660e}\u{767d}|\u{6211}\u{4f1a}|\u{6211}\u{5c06}|\u{9a6c}\u{4e0a}|\u{6b63}\u{5728}|\u{5f00}\u{59cb}\u{5904}\u{7406})"
  private static let futureOnlyPattern =
    #"\b(?:will|going to|working on|starting|handle this|do that)\b|"# +
    "(?:\u{5c06}\u{4f1a}|\u{6211}\u{4f1a}|\u{9a6c}\u{4e0a}|\u{6b63}\u{5728}|\u{5f00}\u{59cb}\u{5904}\u{7406})"
  private static let missingAttachmentPattern =
    #"(?:no|without)\s+(?:an?\s+|any\s+)?(?:attachment|image|file)|"# +
    #"(?:cannot|can't|could not|couldn't)\s+(?:see|find|access)\s+(?:the\s+|an?\s+|any\s+)?(?:attachment|image|file)|"# +
    #"(?:please\s+)?(?:upload|attach|send)\s+(?:the\s+|an?\s+)?(?:attachment|image|file)|"# +
    "(?:\u{6ca1}\u{6709}|\u{672a})\u{6536}\u{5230}(?:\u{9644}\u{4ef6}|\u{56fe}\u{7247}|\u{6587}\u{4ef6})|(?:\u{770b}\u{4e0d}\u{5230}|\u{627e}\u{4e0d}\u{5230})(?:\u{9644}\u{4ef6}|\u{56fe}\u{7247}|\u{6587}\u{4ef6})|\u{8bf7}(?:\u{4e0a}\u{4f20}|\u{53d1}\u{9001})(?:\u{9644}\u{4ef6}|\u{56fe}\u{7247}|\u{6587}\u{4ef6})"
  private static let askForTaskAgainPattern =
    #"(?:what|which)\s+(?:task|thing)\s+(?:should|would)\s+i|"# +
    #"what\s+would\s+you\s+like\s+me\s+to\s+do|"# +
    #"please\s+(?:provide|tell\s+me)\s+(?:the\s+)?(?:task|request|goal)|"# +
    "(?:\u{8bf7}\u{544a}\u{8bc9}\u{6211}|\u{4f60}\u{60f3}\u{8ba9}\u{6211}|\u{9700}\u{8981}\u{6211})(?:\u{505a}\u{4ec0}\u{4e48}|\u{5b8c}\u{6210}\u{4ec0}\u{4e48}|\u{5904}\u{7406}\u{4ec0}\u{4e48})"
}
