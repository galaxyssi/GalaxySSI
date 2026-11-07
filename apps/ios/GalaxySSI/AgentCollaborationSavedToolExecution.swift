import Foundation

enum AgentCollaborationSavedToolExecution {
  static let contract = "galaxyssi.collaboration-tool-test/1"
  static let requestType = "collaboration_tool_test_request"
  static let responseType = "collaboration_tool_test_result"
  static let processID = UUID().uuidString

  struct PreflightRejected: Error {
    let input: AgentMcpJSONObject
    let code: String
  }

  static func permitsDirectRuntime(source: String, key: String) -> Bool {
    let toolId = AgentIOSOnDeviceRuntimeNativeToolCatalog.execute
    let action = AgentAction(id: key, kind: .callNativeTool, target: toolId, risk: .medium,
      status: .proposed, description: "Run a saved collaboration test",
      parameters: ["tool_id": toolId, "source": source], requiresConfirmation: false)
    return AgentConfirmationPolicy.tier(for: action) == .direct
  }

  struct Request {
    enum Mode: String { case start, status, cancel }
    let mode: Mode
    let executionID: String
    let plan: AgentCollaborationResearchReference?
    let release: AgentCollaborationResearchReference?
    let channel: AgentCollaborationResearchReference?
    let parameters: AgentMcpJSONObject?
    let timeoutMillis: Int64?
    let inputHash: String

    init?(phase: String, input: AgentMcpJSONObject) {
      guard let mode = Mode(rawValue: phase), input["mode"] == .string(phase),
            let id = input["execution_id"]?.strictStringValue,
            id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#,
              options: .regularExpression) != nil, !id.contains(where: \.isNewline) else { return nil }
      self.mode = mode
      executionID = id
      switch mode {
      case .start:
        guard case .int(let timeout)? = input["timeout_ms"],
              (100...AgentIOSOnDeviceRuntimeNativeToolCatalog.maxTimeoutMillis).contains(timeout) else { return nil }
        if Set(input.keys) == ["mode", "execution_id", "tool_test_plan", "timeout_ms"],
           let reference = AgentCollaborationSavedToolTest.reference(input["tool_test_plan"]),
           reference.revision <= Int64(Int32.max) {
          plan = reference
          release = nil
          channel = nil
          parameters = nil
        } else {
          let selectors = Set(input.keys).intersection(["tool_release", "capability_channel"])
          guard selectors.count == 1, let selector = selectors.first,
                Set(input.keys) == ["mode", "execution_id", selector, "parameters", "timeout_ms"],
                let reference = AgentCollaborationSavedToolTest.reference(input[selector]),
                reference.revision <= Int64(Int32.max), let values = input["parameters"]?.objectValue,
                AgentMcpJSONCodec.stringify(values).utf8.count <= 64 * 1_024 else { return nil }
          plan = nil
          release = selector == "tool_release" ? reference : nil
          channel = selector == "capability_channel" ? reference : nil
          parameters = values
        }
        timeoutMillis = timeout
      case .status, .cancel:
        guard Set(input.keys) == ["mode", "execution_id"] else { return nil }
        plan = nil
        release = nil
        channel = nil
        parameters = nil
        timeoutMillis = nil
      }
      inputHash = AgentMcpJSONCodec.sha256(input)
    }
  }

  struct Scope: Codable, Equatable {
    let assignment: AgentCollaborationToolEvidenceScope
    let profileFingerprint: String
    let desktopID: String
    let desktopFingerprint: String
    let routeID: String
    let generation: Int64

    var isValid: Bool {
      !profileFingerprint.isBlank && !desktopID.isBlank && !desktopFingerprint.isBlank && !routeID.isBlank &&
        AgentRemoteOutcomePolicy.validGeneration(generation)
    }

    func key(_ executionID: String) -> String {
      // A replacement route or generation cannot create a new execution for this ID.
      "saved-tool-test:" + AgentMcpJSONCodec.sha256([
        "assignment": .string(assignment.ownershipDigest), "execution": .string(executionID)
      ])
    }
  }

  struct Record: Codable, Equatable {
    enum State: String, Codable {
      case queued, running, cancelling, cancelled, interrupted, finished
      var active: Bool { self == .queued || self == .running || self == .cancelling }
    }

    let scope: Scope
    let executionID: String
    let inputHash: String
    let plan: AgentCollaborationResearchReference?
    var release: AgentCollaborationResearchReference? = nil
    var channel: AgentCollaborationResearchReference? = nil
    var parameters: AgentMcpJSONObject? = nil
    let timeoutMillis: Int64
    let ownerProcess: String
    var state: State
    var updatedAt: Int64
    var result: AgentMcpJSONObject?

    var response: AgentMcpJSONObject {
      ["success": .bool(true), "status": .string(state.rawValue), "execution_id": .string(executionID),
        "input_sha256": .string(inputHash), "updated_at": .int(updatedAt), "result": result.map(AgentMcpJSONValue.object) ?? .null,
        "retry_after_ms": state.active ? .int(2_000) : .null, "automatically_reexecuted": .bool(false),
        "reason": .string(state == .interrupted
          ? "Execution ended without a confirmed result. Recover original evidence before choosing another execution ID."
          : "")]
    }
  }

  enum Operation {
    case request(Request)
    case running(executionID: String)
    case interrupt(executionID: String)
    case finish(executionID: String, result: AgentMcpJSONObject)

    var id: String {
      switch self {
      case .request(let request): return request.executionID
      case .running(let id), .interrupt(let id), .finish(let id, _): return id
      }
    }
  }

  struct Outcome {
    let record: Record?
    var shouldLaunch = false
    var shouldCancel = false
    var didStart = false
    var busy = false

    var response: AgentMcpJSONObject {
      if busy { return ["success": .bool(true), "status": .string("busy"), "retry_after_ms": .int(2_000)] }
      return record?.response ?? ["success": .bool(true), "status": .string("not_recorded")]
    }
  }

  static func apply(_ operation: Operation, scope: Scope, existing: Record?, process: String,
                    now: Int64, allowAdmission: Bool = true) throws -> Outcome {
    guard scope.isValid, !process.isBlank, now >= 0,
          existing.map({ $0.scope == scope && $0.executionID == operation.id }) ?? true else {
      throw AgentTeamHistoryDatabase.Failure.stale
    }
    var current = existing
    if var record = current, record.state.active, record.ownerProcess != process {
      record.state = .interrupted
      record.updatedAt = max(record.updatedAt, now)
      current = record
    }
    switch operation {
    case .request(let request):
      switch request.mode {
      case .start:
        guard request.plan != nil || ((request.release != nil || request.channel != nil) && request.parameters != nil),
              let timeoutMillis = request.timeoutMillis else {
          throw AgentTeamHistoryDatabase.Failure.corrupt
        }
        if let record = current {
          guard record.inputHash == request.inputHash else { throw AgentTeamHistoryDatabase.Failure.stale }
          return Outcome(record: record)
        }
        guard allowAdmission else { return Outcome(record: nil, busy: true) }
        return Outcome(record: Record(scope: scope, executionID: request.executionID, inputHash: request.inputHash,
          plan: request.plan, release: request.release, channel: request.channel, parameters: request.parameters,
          timeoutMillis: timeoutMillis, ownerProcess: process, state: .queued, updatedAt: now), shouldLaunch: true)
      case .status:
        return Outcome(record: current)
      case .cancel:
        guard var record = current, record.state.active else { return Outcome(record: current) }
        let running = record.state != .queued
        record.state = running ? .cancelling : .cancelled
        record.updatedAt = max(record.updatedAt, now)
        return Outcome(record: record, shouldCancel: running)
      }
    case .running:
      guard var record = current, record.state == .queued else { return Outcome(record: current) }
      record.state = .running
      record.updatedAt = max(record.updatedAt, now)
      return Outcome(record: record, didStart: true)
    case .interrupt:
      guard var record = current, record.state.active else { return Outcome(record: current) }
      record.state = .interrupted
      record.updatedAt = max(record.updatedAt, now)
      return Outcome(record: record)
    case .finish(_, let result):
      guard AgentMcpJSONCodec.stringify(result).utf8.count <= 16 * 1_024 else {
        throw AgentTeamHistoryDatabase.Failure.corrupt
      }
      guard var record = current, record.state == .running || record.state == .cancelling else {
        return Outcome(record: current)
      }
      let code = result["error"]?.objectValue?["code"]?.stringValue
      switch code {
      case "runtime_execution_cancelled", "cancelled":
        record.state = .cancelled
      case "runtime_cancellation_unconfirmed", "runtime_execution_outcome_unknown", "effect_outcome_unknown":
        record.state = .interrupted
      default:
        record.state = .finished
      }
      record.updatedAt = max(record.updatedAt, now)
      record.result = result
      return Outcome(record: record)
    }
  }
}
