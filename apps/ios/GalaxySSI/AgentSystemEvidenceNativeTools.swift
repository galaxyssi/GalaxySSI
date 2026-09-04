import Foundation
import UIKit

enum AgentSystemEvidenceNativeToolCatalog {
  static let deviceInfo = "galaxyssi.system.device.info"
  static let appInfo = "galaxyssi.system.app.info"
  static let localTime = "galaxyssi.system.time.local"
  static let jsonValidate = "galaxyssi.data.json.validate"
  static let executorId = "galaxyssi.ios.system_evidence"

  static let toolIds: Set<String> = [deviceInfo, appInfo, localTime, jsonValidate]

  static func definitions() -> [AgentPhoneNativeToolDefinition] {
    [
      definition(deviceInfo, "Read device and iOS version", "Returns app-visible device and iOS version facts."),
      definition(appInfo, "Read GalaxySSI application version", "Returns this installed GalaxySSI build identity and version."),
      definition(localTime, "Read local date and time zone", "Returns the current local ISO timestamp, time zone, and UTC offset."),
      definition(
        jsonValidate,
        "Validate a JSON value",
        "Parses a bounded JSON object or array and returns its canonical shape and digest.",
        inputSchema: [
          "type": .string("object"),
          "properties": .object(["json": .object([
            "type": .string("string"),
            "minLength": .int(1),
            "maxLength": .int(65_536)
          ])]),
          "required": .array([.string("json")]),
          "additionalProperties": .bool(false)
        ]
      )
    ]
  }

  static func executableDefinitions(
    nowMillis: @escaping () -> Int64 = AgentEvalClock.nowMillis
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentSystemEvidenceNativeToolExecutor(nowMillis: nowMillis)
    return definitions().map(executor.executableDefinition)
  }

  private static func definition(
    _ id: String,
    _ title: String,
    _ description: String,
    inputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema()
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: title,
      description: description,
      location: .application,
      inputSchema: inputSchema,
      risk: .low,
      capabilities: ["system.evidence.read"],
      idempotency: .idempotent,
      concurrency: .parallelReadOnly
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: ["platform": "ios", "evidence_policy": "app-visible-v1"]
    )
  }
}

struct AgentSystemEvidenceNativeToolExecutor {
  var nowMillis: () -> Int64

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(definition: definition) { invocation in
      try invocation.checkpoint()
      return execute(invocation)
    }
  }

  private func execute(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let observedAt = max(0, nowMillis())
    switch invocation.descriptor.id {
    case AgentSystemEvidenceNativeToolCatalog.deviceInfo:
      return .success(output: [
        "device_family": .string(UIDevice.current.model),
        "localized_model": .string(UIDevice.current.localizedModel),
        "system_name": .string(UIDevice.current.systemName),
        "system_version": .string(UIDevice.current.systemVersion),
        "observed_at_epoch_ms": .int(observedAt)
      ])
    case AgentSystemEvidenceNativeToolCatalog.appInfo:
      let info = Bundle.main.infoDictionary ?? [:]
      return .success(output: [
        "bundle_identifier": .string(Bundle.main.bundleIdentifier ?? ""),
        "version_name": .string(info["CFBundleShortVersionString"] as? String ?? ""),
        "build_number": .string(info["CFBundleVersion"] as? String ?? ""),
        "observed_at_epoch_ms": .int(observedAt)
      ])
    case AgentSystemEvidenceNativeToolCatalog.localTime:
      let date = Date(timeIntervalSince1970: TimeInterval(observedAt) / 1_000)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let zone = TimeZone.current
      return .success(output: [
        "local_iso_8601": .string(formatter.string(from: date)),
        "timezone_id": .string(zone.identifier),
        "utc_offset_seconds": .int(Int64(zone.secondsFromGMT(for: date))),
        "observed_at_epoch_ms": .int(observedAt)
      ])
    case AgentSystemEvidenceNativeToolCatalog.jsonValidate:
      return validateJSON(invocation.input["json"]?.strictStringValue ?? "")
    default:
      return .failure(code: "unsupported_system_evidence_tool", message: "Unsupported system evidence tool")
    }
  }

  private func validateJSON(_ raw: String) -> AgentNativeToolExecutionResult {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = clean.data(using: .utf8), data.count <= 65_536,
          let value = try? JSONSerialization.jsonObject(with: data),
          value is [String: Any] || value is [Any],
          let canonicalData = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let canonical = String(data: canonicalData, encoding: .utf8) else {
      return .failure(code: "invalid_json", message: "Only a valid JSON object or array is accepted")
    }
    return .success(output: [
      "valid": .bool(true),
      "kind": .string(value is [String: Any] ? "object" : "array"),
      "canonical_json": .string(canonical),
      "sha256": .string(AgentMcpJSONCodec.sha256(["canonical_json": .string(canonical)]))
    ])
  }
}
