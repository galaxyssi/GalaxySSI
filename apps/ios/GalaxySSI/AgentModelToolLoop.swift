import Foundation

final class AgentModelToolLoop {
  private let modelAdapter: AgentModelAdapter
  private let toolRegistry: AgentNativeToolRegistry
  private let clock: AgentModelToolLoopClock
  private let idFactory: AgentModelToolLoopIdFactory
  private let approvalLock = NSLock()
  private var pendingApprovals: [String: PendingApproval] = [:]

  init(
    modelAdapter: AgentModelAdapter,
    toolRegistry: AgentNativeToolRegistry,
    clock: AgentModelToolLoopClock = .system,
    idFactory: AgentModelToolLoopIdFactory = .uuids
  ) {
    self.modelAdapter = modelAdapter
    self.toolRegistry = toolRegistry
    self.clock = clock
    self.idFactory = idFactory
  }

  func run(_ request: AgentModelToolLoopRequest) async -> AgentModelToolLoopOutcome {
    let startedAt = clock.nowEpochMillis()
    let manifestJson = toolRegistry.catalogJson()
    let state = LoopState(
      request: request,
      messages: request.messages,
      manifestJson: manifestJson,
      manifestSha256: AgentModelToolProtocolJSON.sha256(manifestJson),
      startedAtEpochMillis: startedAt,
      deadlineEpochMillis: AgentModelToolLoopValidation.safeAdd(startedAt, request.budget.maxDurationMillis)
    )
    emit(state, .loopStarted)
    return await advance(state, initialCalls: [])
  }

  func resume(
    _ handle: AgentModelToolApprovalHandle,
    decision: AgentModelToolApprovalDecision
  ) async throws -> AgentModelToolLoopOutcome {
    approvalLock.lock()
    guard let pending = pendingApprovals[handle.confirmationId],
          pending.handle.nonce == handle.nonce else {
      approvalLock.unlock()
      throw AgentModelToolLoopError(
        code: "unknown_approval",
        message: "Approval handle is unknown, expired, or already used"
      )
    }
    pendingApprovals.removeValue(forKey: handle.confirmationId)
    approvalLock.unlock()

    let state = pending.state
    if let terminal = terminalGuard(state) {
      return terminal
    }
    let effectiveDecision: AgentModelToolApprovalDecision =
      decision == .approved && clock.nowEpochMillis() >= handle.expiresAtEpochMillis
        ? .expired
        : decision
    emit(
      state,
      .approvalDecided,
      call: pending.call,
      details: [
        "confirmation_id": .string(handle.confirmationId),
        "decision": .string(effectiveDecision.rawValue),
        "arguments_sha256": .string(handle.argumentsSha256)
      ]
    )
    emit(state, .loopResumed, call: pending.call)

    let resumed: ProcessResult
    if effectiveDecision == .approved {
      resumed = executeCall(
        state: state,
        call: pending.call,
        descriptor: pending.descriptor,
        approvedConsentIds: handle.requiredConsentIds,
        confirmationId: handle.confirmationId
      )
    } else {
      let code = effectiveDecision == .expired ? "approval_expired" : "approval_rejected"
      appendSyntheticToolResult(
        state,
        pending.call,
        code: code,
        message: effectiveDecision == .expired
          ? "The phone approval expired before the tool call could run"
          : "The user rejected the phone tool call"
      )
      resumed = .continue
    }
    if case .terminal(let outcome) = resumed {
      return outcome
    }
    return await advance(state, initialCalls: pending.remainingCalls)
  }

  private func advance(
    _ state: LoopState,
    initialCalls: [AgentModelToolCall]
  ) async -> AgentModelToolLoopOutcome {
    var calls = initialCalls
    while true {
      if let terminal = terminalGuard(state) {
        return terminal
      }
      if !calls.isEmpty {
        switch await processCalls(state, calls: calls) {
        case .continue:
          break
        case .terminal(let outcome):
          return outcome
        }
        calls = []
      }

      if let terminal = terminalGuard(state) {
        return terminal
      }
      if state.rounds >= state.request.budget.maxRounds {
        return budgetExceeded(state, code: "max_rounds", message: "The model round budget was exhausted")
      }

      state.rounds += 1
      emit(state, .modelRequested)
      let modelRequest = AgentModelRequest(
        sessionId: state.request.sessionId,
        conversationId: state.request.conversationId,
        turnId: state.request.turnId,
        taskId: state.request.taskId,
        workspaceId: state.request.workspaceId,
        round: state.rounds,
        messages: state.messages,
        toolManifestJson: state.manifestJson,
        toolManifestSha256: state.manifestSha256,
        remainingToolCalls: max(0, state.request.budget.maxToolCalls - state.toolCallAttempts),
        remainingTokens: max(0, state.request.budget.maxTokens - state.totalTokens()),
        remainingTimeMillis: remainingTime(state),
        maxDepth: state.request.budget.maxDepth,
        cancellationToken: state.request.cancellationToken
      )

      let response: AgentModelResponse
      do {
        response = try await modelAdapter.complete(modelRequest)
      } catch {
        if state.request.cancellationToken.isCancellationRequested {
          return cancelled(state)
        }
        return modelFailed(state, error: error)
      }
      if state.request.cancellationToken.isCancellationRequested {
        return cancelled(state)
      }

      state.inputTokens = AgentModelToolLoopValidation.safeTokenSum(state.inputTokens, response.usage.inputTokens)
      state.outputTokens = AgentModelToolLoopValidation.safeTokenSum(state.outputTokens, response.usage.outputTokens)
      state.lastAssistantText = response.assistantText
      state.messages.append(.assistant(response.assistantText, toolCalls: response.toolCalls))
      emit(
        state,
        .modelResponded,
        details: [
          "tool_call_count": .int(Int64(response.toolCalls.count)),
          "input_tokens": .int(response.usage.inputTokens),
          "output_tokens": .int(response.usage.outputTokens)
        ]
      )

      if let terminal = terminalGuard(state) {
        return terminal
      }
      if state.totalTokens() > state.request.budget.maxTokens {
        return budgetExceeded(state, code: "max_tokens", message: "The model token budget was exhausted")
      }
      if response.toolCalls.isEmpty {
        return completed(state, assistantText: response.assistantText)
      }

      let fingerprint = responseFingerprint(response)
      if state.seenResponseFingerprints.contains(fingerprint) {
        return loopDetected(
          state,
          code: "repeated_model_response",
          message: "The model repeated an identical tool-calling response"
        )
      }
      state.seenResponseFingerprints.insert(fingerprint)
      calls = response.toolCalls
    }
  }

  private func processCalls(
    _ state: LoopState,
    calls: [AgentModelToolCall]
  ) async -> ProcessResult {
    var parallelCalls: [PreparedCall] = []
    var parallelPlans: [AgentNativeResourceLockPlan] = []
    var parallelWorkload: AgentConcurrencyWorkload?

    func flushParallelCalls() -> ProcessResult {
      guard !parallelCalls.isEmpty, let workload = parallelWorkload else { return .continue }
      let prepared = parallelCalls
      parallelCalls.removeAll()
      parallelPlans.removeAll()
      parallelWorkload = nil
      return prepared.count == 1
        ? executePreparedCall(state, prepared: prepared[0])
        : executeParallelCalls(state, preparedCalls: prepared, workload: workload)
    }

    for index in calls.indices {
      if let terminal = terminalGuard(state) { return .terminal(terminal) }
      let proposed = calls[index]
      let candidate = parallelCandidate(state, proposedCall: proposed)
      let canJoinBatch = candidate.map { candidate in
        (parallelWorkload == nil || parallelWorkload == candidate.workload) &&
          !parallelPlans.contains(where: { $0.conflicts(with: candidate.resourcePlan) })
      } ?? false
      if !parallelCalls.isEmpty && !canJoinBatch {
        let flushed = flushParallelCalls()
        if case .terminal = flushed { return flushed }
      }
      let remaining = Array(calls.dropFirst(index + 1))
      switch prepareCall(state, proposedCall: proposed, remainingCalls: remaining) {
      case .continue:
        continue
      case .terminal(let outcome):
        return .terminal(outcome)
      case .ready(let prepared):
        if let candidate {
          parallelCalls.append(prepared)
          parallelPlans.append(candidate.resourcePlan)
          parallelWorkload = candidate.workload
        } else {
          let flushed = flushParallelCalls()
          if case .terminal = flushed { return flushed }
          let executed = executePreparedCall(state, prepared: prepared)
          if case .terminal = executed { return executed }
        }
      }
    }
    return flushParallelCalls()
  }

  private func parallelCandidate(
    _ state: LoopState,
    proposedCall: AgentModelToolCall
  ) -> ParallelCandidate? {
    guard state.toolCallAttempts < state.request.budget.maxToolCalls else { return nil }
    let call = boundWorkspaceCall(proposedCall, workspaceId: state.request.workspaceId)
    guard basicCallError(call) == nil,
          call.depth <= state.request.budget.maxDepth,
          let descriptor = toolRegistry.lookup(call.toolId)?.descriptor,
          call.toolVersion == nil || call.toolVersion == descriptor.version,
          toolRegistry.validateInput(call.toolId, input: call.arguments).isValid else {
      return nil
    }
    let identity = callIdentity(call, version: descriptor.version)
    guard state.callIds[call.callId] == nil,
          (state.callSignatures[identity] ?? 0) < state.request.budget.maxRepeatedCallSignatures else {
      return nil
    }
    let missingConsents = descriptor.requiredConsents.contains {
      $0.required && !state.request.grantedConsents.contains($0.id)
    }
    guard !missingConsents else { return nil }
    let resourcePlan = AgentNativeToolResourcePolicy.resolve(
      descriptor: descriptor,
      input: call.arguments,
      fallbackWorkspaceId: state.request.workspaceId
    )
    if descriptor.concurrency == .parallelReadOnly {
      return ParallelCandidate(workload: .nativeReadIO, resourcePlan: resourcePlan)
    }
    guard descriptor.concurrency == .serial, resourcePlan.resourceScoped else { return nil }
    return ParallelCandidate(workload: .nativeMutation, resourcePlan: resourcePlan)
  }

  private func prepareCall(
    _ state: LoopState,
    proposedCall: AgentModelToolCall,
    remainingCalls: [AgentModelToolCall]
  ) -> PreparationResult {
    let call = boundWorkspaceCall(proposedCall, workspaceId: state.request.workspaceId)
    emit(state, .toolCallProposed, call: call)
    guard consumeToolCallAttempt(state) else {
      return .terminal(budgetExceeded(
        state,
        code: "max_tool_calls",
        message: "The phone tool-call budget was exhausted"
      ))
    }

    if let basicError = basicCallError(call) {
      appendSyntheticToolResult(state, call, code: basicError.code, message: basicError.message)
      return .continue
    }

    let argumentsSha256 = AgentMcpJSONCodec.sha256(call.arguments)
    let resolvedVersion = toolRegistry.lookup(call.toolId)?.descriptor.version ?? call.toolVersion ?? ""
    let callIdentity = "\(call.toolId)|\(resolvedVersion)|\(argumentsSha256)|\(call.depth)"
    if let previousIdentity = state.callIds[call.callId] {
      return .terminal(loopDetected(
        state,
        code: previousIdentity == callIdentity ? "repeated_tool_call_id" : "tool_call_id_reused",
        message: "The model reused a tool call id",
        call: call
      ))
    }
    state.callIds[call.callId] = callIdentity

    let signatureCount = (state.callSignatures[callIdentity] ?? 0) + 1
    state.callSignatures[callIdentity] = signatureCount
    if signatureCount > state.request.budget.maxRepeatedCallSignatures {
      return .terminal(loopDetected(
        state,
        code: "repeated_tool_call",
        message: "The model repeated the same tool call beyond the configured limit",
        call: call
      ))
    }

    let inputValidation = toolRegistry.validateInput(call.toolId, input: call.arguments)
    if !inputValidation.isValid {
      appendSyntheticToolResult(
        state,
        call,
        code: inputValidation.issues.first?.code ?? "invalid_input",
        message: "The phone rejected the proposed tool input",
        details: [
          "issues": .array(inputValidation.issues.map {
            .object([
              "path": .string($0.path),
              "code": .string($0.code),
              "message": .string($0.message)
            ])
          })
        ]
      )
      return .continue
    }

    guard let descriptor = toolRegistry.lookup(call.toolId)?.descriptor else {
      appendSyntheticToolResult(
        state,
        call,
        code: "unknown_tool",
        message: "No native tool is registered with id \(call.toolId)"
      )
      return .continue
    }
    if let toolVersion = call.toolVersion, toolVersion != descriptor.version {
      appendSyntheticToolResult(
        state,
        call,
        code: "tool_version_mismatch",
        message: "The proposed tool version does not match the phone manifest",
        details: ["expected": .string(descriptor.version), "received": .string(toolVersion)]
      )
      return .continue
    }
    if call.depth > state.request.budget.maxDepth {
      appendSyntheticToolResult(
        state,
        call,
        code: "max_depth_exceeded",
        message: "The proposed tool call exceeds the configured graph depth",
        details: ["depth": .int(Int64(call.depth)), "max_depth": .int(Int64(state.request.budget.maxDepth))]
      )
      return .continue
    }

    let missingConsents = Set(descriptor.requiredConsents
      .filter { $0.required && !state.request.grantedConsents.contains($0.id) }
      .map(\.id))
    if !missingConsents.isEmpty {
      let now = clock.nowEpochMillis()
      let handle = AgentModelToolApprovalHandle(
        confirmationId: checkedId("confirmation"),
        sessionId: state.request.sessionId,
        turnId: state.request.turnId,
        taskId: state.request.taskId,
        toolCallId: call.callId,
        toolId: descriptor.id,
        toolVersion: descriptor.version,
        argumentsSha256: argumentsSha256,
        toolManifestSha256: state.manifestSha256,
        requiredConsentIds: missingConsents,
        targetSummary: descriptor.title,
        expiresAtEpochMillis: min(
          state.deadlineEpochMillis,
          AgentModelToolLoopValidation.safeAdd(now, state.request.budget.approvalTtlMillis)
        ),
        nonce: checkedId("approval_nonce")
      )
      approvalLock.lock()
      pendingApprovals[handle.confirmationId] = PendingApproval(
        state: state,
        call: call,
        remainingCalls: remainingCalls,
        descriptor: descriptor,
        handle: handle
      )
      approvalLock.unlock()
      emit(
        state,
        .approvalRequired,
        call: call,
        details: [
          "confirmation_id": .string(handle.confirmationId),
          "consent_ids": .array(missingConsents.sorted().map(AgentMcpJSONValue.string)),
          "arguments_sha256": .string(argumentsSha256),
          "expires_at_epoch_ms": .int(handle.expiresAtEpochMillis)
        ]
      )
      return .terminal(outcome(state, status: .waitingForApproval, approval: handle))
    }

    return .ready(PreparedCall(call: call, descriptor: descriptor, approvedConsentIds: []))
  }

  private func callIdentity(_ call: AgentModelToolCall, version: String) -> String {
    "\(call.toolId)|\(version)|\(AgentMcpJSONCodec.sha256(call.arguments))|\(call.depth)"
  }

  private func executePreparedCall(_ state: LoopState, prepared: PreparedCall) -> ProcessResult {
    executeCall(
      state: state,
      call: prepared.call,
      descriptor: prepared.descriptor,
      approvedConsentIds: prepared.approvedConsentIds
    )
  }

  private func executeParallelCalls(
    _ state: LoopState,
    preparedCalls: [PreparedCall],
    workload: AgentConcurrencyWorkload
  ) -> ProcessResult {
    precondition(preparedCalls.count > 1)
    if let terminal = terminalGuard(state) { return .terminal(terminal) }
    let attempts = preparedCalls.map { beginInvocation(state, prepared: $0, attempt: 1) }
    let results = AgentNativeToolBatchExecutor.executeOrdered(
      inputs: attempts,
      limitProvider: { AgentAdaptiveConcurrencyRuntime.currentLimit(workload) },
      operation: { self.invokeNativeTool(state, attempt: $0) }
    )
    for (attempt, result) in zip(attempts, results) {
      finishInvocation(state, attempt: attempt, result: result)
    }
    if results.contains(where: { $0.status == .cancelled }) ||
        state.request.cancellationToken.isCancellationRequested {
      for (attempt, result) in zip(attempts, results) {
        appendToolResult(state, attempt.prepared.call, result: result, retryCount: 0)
      }
      return .terminal(cancelled(state))
    }

    for index in attempts.indices {
      let attempt = attempts[index]
      let result = results[index]
      let descriptor = attempt.prepared.descriptor
      let mayRetry = !result.isSuccess &&
        result.error?.retryable == true &&
        descriptor.idempotency != .nonIdempotent &&
        state.request.budget.maxRetriesPerCall > 0
      if !mayRetry {
        appendToolResult(state, attempt.prepared.call, result: result, retryCount: 0)
        continue
      }
      guard consumeToolCallAttempt(state) else {
        for remainingIndex in index..<attempts.count {
          appendToolResult(
            state,
            attempts[remainingIndex].prepared.call,
            result: results[remainingIndex],
            retryCount: 0
          )
        }
        return .terminal(budgetExceeded(
          state,
          code: "max_tool_calls",
          message: "A safe tool retry would exceed the call budget"
        ))
      }
      state.retries += 1
      emit(
        state,
        .toolRetryScheduled,
        call: attempt.prepared.call,
        invocationId: attempt.invocationId,
        details: [
          "next_attempt": .int(2),
          "error_code": .string(result.error?.code ?? ""),
          "idempotency": .string(descriptor.idempotency.rawValue)
        ]
      )
      let retried = executeCall(
        state: state,
        call: attempt.prepared.call,
        descriptor: descriptor,
        approvedConsentIds: attempt.prepared.approvedConsentIds,
        startingAttempt: 1
      )
      if case .terminal = retried { return retried }
    }
    return .continue
  }

  private func beginInvocation(
    _ state: LoopState,
    prepared: PreparedCall,
    attempt: Int
  ) -> NativeInvocationAttempt {
    let idempotencyKey: String?
    switch prepared.descriptor.idempotency {
    case .nonIdempotent:
      idempotencyKey = prepared.call.idempotencyKey
    case .idempotent, .idempotencyKeyRequired:
      idempotencyKey = prepared.call.idempotencyKey ?? derivedIdempotencyKey(state, call: prepared.call)
    }
    let invocationId = checkedId("invocation")
    emit(
      state,
      .toolStarted,
      call: prepared.call,
      invocationId: invocationId,
      details: ["attempt": .int(Int64(attempt)), "tool_version": .string(prepared.descriptor.version)]
    )
    let context = invocationContext(
      state,
      call: prepared.call,
      invocationId: invocationId,
      idempotencyKey: idempotencyKey,
      approvedConsentIds: prepared.approvedConsentIds,
      confirmationId: nil,
      attempt: attempt
    )
    return NativeInvocationAttempt(
      prepared: prepared,
      invocationId: invocationId,
      context: context,
      attempt: attempt
    )
  }

  private func invokeNativeTool(
    _ state: LoopState,
    attempt: NativeInvocationAttempt
  ) -> AgentNativeToolResult {
    toolRegistry.invoke(
      attempt.prepared.call.toolId,
      input: attempt.prepared.call.arguments,
      context: attempt.context,
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: clock.nowEpochMillis,
        cancellationRequested: { state.request.cancellationToken.isCancellationRequested }
      )
    )
  }

  private func finishInvocation(
    _ state: LoopState,
    attempt: NativeInvocationAttempt,
    result: AgentNativeToolResult
  ) {
    var details: AgentMcpJSONObject = [
      "status": .string(result.status.rawValue),
      "retryable": .bool(result.error?.retryable == true),
      "attempt": .int(Int64(attempt.attempt))
    ]
    if let code = result.error?.code { details["error_code"] = .string(code) }
    emit(
      state,
      .toolFinished,
      call: attempt.prepared.call,
      invocationId: attempt.invocationId,
      details: details
    )
  }

  private func invocationContext(
    _ state: LoopState,
    call: AgentModelToolCall,
    invocationId: String,
    idempotencyKey: String?,
    approvedConsentIds: Set<String>,
    confirmationId: String?,
    attempt: Int
  ) -> AgentNativeToolInvocationContext {
    var attributes: [String: String] = [
      "task_id": state.request.taskId,
      "workspace_id": state.request.workspaceId,
      "tool_call_id": call.callId,
      "tool_manifest_sha256": state.manifestSha256,
      "model_round": String(state.rounds),
      "tool_depth": String(call.depth),
      "retry_attempt": String(max(attempt - 1, 0)),
      "response_language": LanguagePolicySettings.resolve(state.request.responseLanguage)
    ]
    if let confirmationId {
      attributes["confirmation_id"] = confirmationId
      attributes["explicit_user_approval"] = "true"
    }
    return AgentNativeToolInvocationContext(
      invocationId: invocationId,
      sessionId: state.request.sessionId,
      conversationId: state.request.conversationId,
      turnId: state.request.turnId,
      callerId: state.request.callerId,
      requestedAtEpochMillis: clock.nowEpochMillis(),
      deadlineEpochMillis: state.deadlineEpochMillis,
      idempotencyKey: idempotencyKey,
      grantedPermissions: state.request.grantedPermissions,
      grantedConsents: state.request.grantedConsents.union(approvedConsentIds),
      attributes: attributes
    )
  }

  private func executeCall(
    state: LoopState,
    call: AgentModelToolCall,
    descriptor: AgentNativeToolDescriptor,
    approvedConsentIds: Set<String> = [],
    confirmationId: String? = nil,
    startingAttempt: Int = 0
  ) -> ProcessResult {
    let idempotencyKey: String?
    switch descriptor.idempotency {
    case .nonIdempotent:
      idempotencyKey = call.idempotencyKey
    case .idempotent, .idempotencyKeyRequired:
      idempotencyKey = call.idempotencyKey ?? derivedIdempotencyKey(state, call: call)
    }

    var attempt = max(startingAttempt, 0)
    while true {
      if let terminal = terminalGuard(state) {
        return .terminal(terminal)
      }
      attempt += 1
      let invocationId = checkedId("invocation")
      emit(
        state,
        .toolStarted,
        call: call,
        invocationId: invocationId,
        details: ["attempt": .int(Int64(attempt)), "tool_version": .string(descriptor.version)]
      )
      var attributes: [String: String] = [
        "task_id": state.request.taskId,
        "workspace_id": state.request.workspaceId,
        "tool_call_id": call.callId,
        "tool_manifest_sha256": state.manifestSha256,
        "model_round": String(state.rounds),
        "tool_depth": String(call.depth),
        "retry_attempt": String(attempt - 1),
        "response_language": LanguagePolicySettings.resolve(state.request.responseLanguage)
      ]
      if let confirmationId {
        attributes["confirmation_id"] = confirmationId
        attributes["explicit_user_approval"] = "true"
      }
      let context = AgentNativeToolInvocationContext(
        invocationId: invocationId,
        sessionId: state.request.sessionId,
        conversationId: state.request.conversationId,
        turnId: state.request.turnId,
        callerId: state.request.callerId,
        requestedAtEpochMillis: clock.nowEpochMillis(),
        deadlineEpochMillis: state.deadlineEpochMillis,
        idempotencyKey: idempotencyKey,
        grantedPermissions: state.request.grantedPermissions,
        grantedConsents: state.request.grantedConsents.union(approvedConsentIds),
        attributes: attributes
      )
      let result = toolRegistry.invoke(
        call.toolId,
        input: call.arguments,
        context: context,
        hooks: AgentNativeToolInvocationHooks(
          nowMillis: clock.nowEpochMillis,
          cancellationRequested: { state.request.cancellationToken.isCancellationRequested }
        )
      )
      var details: AgentMcpJSONObject = [
        "status": .string(result.status.rawValue),
        "retryable": .bool(result.error?.retryable == true),
        "attempt": .int(Int64(attempt))
      ]
      if let code = result.error?.code {
        details["error_code"] = .string(code)
      }
      emit(state, .toolFinished, call: call, invocationId: invocationId, details: details)

      if result.status == .cancelled || state.request.cancellationToken.isCancellationRequested {
        appendToolResult(state, call, result: result, retryCount: attempt - 1)
        return .terminal(cancelled(state))
      }

      let mayRetry = !result.isSuccess &&
        result.error?.retryable == true &&
        descriptor.idempotency != .nonIdempotent &&
        attempt <= state.request.budget.maxRetriesPerCall
      if !mayRetry {
        appendToolResult(state, call, result: result, retryCount: attempt - 1)
        return .continue
      }
      guard consumeToolCallAttempt(state) else {
        appendToolResult(state, call, result: result, retryCount: attempt - 1)
        return .terminal(budgetExceeded(
          state,
          code: "max_tool_calls",
          message: "A safe tool retry would exceed the call budget"
        ))
      }
      state.retries += 1
      emit(
        state,
        .toolRetryScheduled,
        call: call,
        invocationId: invocationId,
        details: [
          "next_attempt": .int(Int64(attempt + 1)),
          "error_code": .string(result.error?.code ?? ""),
          "idempotency": .string(descriptor.idempotency.rawValue)
        ]
      )
    }
  }

  private func appendToolResult(
    _ state: LoopState,
    _ call: AgentModelToolCall,
    result: AgentNativeToolResult,
    retryCount: Int
  ) {
    state.messages.append(.tool(AgentModelToolResultContent(
      callId: call.callId,
      toolId: call.toolId,
      status: result.status.rawValue,
      output: result.output,
      message: result.message,
      error: result.error,
      invocationId: result.receipt.invocationId,
      retryCount: retryCount,
      receipt: result.receipt,
      nativeResult: result
    )))
  }

  private func appendSyntheticToolResult(
    _ state: LoopState,
    _ call: AgentModelToolCall,
    code: String,
    message: String,
    details: AgentMcpJSONObject = [:]
  ) {
    let error = AgentNativeToolError(code: code, message: message, retryable: false, details: details)
    state.messages.append(.tool(AgentModelToolResultContent(
      callId: call.callId,
      toolId: call.toolId,
      status: AgentNativeToolResultStatus.rejected.rawValue,
      message: message,
      error: error
    )))
    var eventDetails: AgentMcpJSONObject = ["code": .string(code), "message": .string(message)]
    for (key, value) in details {
      eventDetails[key] = value
    }
    emit(state, .toolCallRejected, call: call, details: eventDetails)
  }

  private func basicCallError(_ call: AgentModelToolCall) -> (code: String, message: String)? {
    if call.callId.isBlank {
      return ("invalid_tool_call_id", "Tool call id must not be blank")
    }
    if call.callId.count > AgentModelToolLoopValidation.maximumIdCharacters {
      return ("invalid_tool_call_id", "Tool call id is too long")
    }
    if call.toolId.isBlank {
      return ("invalid_tool_id", "Tool id must not be blank")
    }
    if call.depth <= 0 {
      return ("invalid_tool_depth", "Tool call depth must be positive")
    }
    if !AgentModelToolLoopValidation.jsonCompatible(.object(call.arguments)) {
      return ("invalid_json_arguments", "Tool arguments must be JSON-compatible")
    }
    return nil
  }

  private func terminalGuard(_ state: LoopState) -> AgentModelToolLoopOutcome? {
    if state.request.cancellationToken.isCancellationRequested {
      return cancelled(state)
    }
    if clock.nowEpochMillis() >= state.deadlineEpochMillis {
      return budgetExceeded(state, code: "max_duration", message: "The model tool loop exceeded its time budget")
    }
    return nil
  }

  private func completed(_ state: LoopState, assistantText: String) -> AgentModelToolLoopOutcome {
    emit(
      state,
      .loopCompleted,
      details: ["assistant_text_present": .bool(!assistantText.isBlank)]
    )
    return outcome(state, status: .completed)
  }

  private func cancelled(_ state: LoopState) -> AgentModelToolLoopOutcome {
    if state.events.last?.type != .loopCancelled {
      emit(state, .loopCancelled)
    }
    return outcome(
      state,
      status: .cancelled,
      error: AgentModelToolLoopError(
        code: "cancelled",
        message: "The phone-owned model tool loop was cancelled"
      )
    )
  }

  private func budgetExceeded(_ state: LoopState, code: String, message: String) -> AgentModelToolLoopOutcome {
    emit(state, .budgetExceeded, details: ["code": .string(code)])
    return outcome(
      state,
      status: .budgetExceeded,
      error: AgentModelToolLoopError(code: code, message: message)
    )
  }

  private func loopDetected(
    _ state: LoopState,
    code: String,
    message: String,
    call: AgentModelToolCall? = nil
  ) -> AgentModelToolLoopOutcome {
    emit(state, .loopDetected, call: call, details: ["code": .string(code)])
    return outcome(
      state,
      status: .loopDetected,
      error: AgentModelToolLoopError(code: code, message: message)
    )
  }

  private func modelFailed(_ state: LoopState, error: Error) -> AgentModelToolLoopOutcome {
    let message = String(String(describing: error).prefix(500)).ifBlank("Error")
    emit(state, .loopFailed, details: ["code": .string("model_failed")])
    return outcome(
      state,
      status: .modelFailed,
      error: AgentModelToolLoopError(code: "model_failed", message: message)
    )
  }

  private func outcome(
    _ state: LoopState,
    status: AgentModelToolLoopStatus,
    approval: AgentModelToolApprovalHandle? = nil,
    error: AgentModelToolLoopError? = nil
  ) -> AgentModelToolLoopOutcome {
    AgentModelToolLoopOutcome(
      status: status,
      assistantText: state.lastAssistantText,
      messages: state.messages,
      events: state.events,
      usage: AgentModelToolLoopUsage(
        rounds: state.rounds,
        toolCallAttempts: state.toolCallAttempts,
        retries: state.retries,
        inputTokens: state.inputTokens,
        outputTokens: state.outputTokens,
        durationMillis: max(0, clock.nowEpochMillis() - state.startedAtEpochMillis)
      ),
      toolManifestJson: state.manifestJson,
      toolManifestSha256: state.manifestSha256,
      approval: approval,
      error: error
    )
  }

  private func emit(
    _ state: LoopState,
    _ type: AgentModelToolLoopEventType,
    call: AgentModelToolCall? = nil,
    invocationId: String? = nil,
    details: AgentMcpJSONObject = [:]
  ) {
    state.eventSequence += 1
    let event = AgentModelToolLoopEvent(
      sequence: state.eventSequence,
      type: type,
      occurredAtEpochMillis: clock.nowEpochMillis(),
      sessionId: state.request.sessionId,
      turnId: state.request.turnId,
      taskId: state.request.taskId,
      toolManifestSha256: state.manifestSha256,
      round: state.rounds,
      toolCallId: call?.callId,
      invocationId: invocationId,
      details: details
    )
    state.events.append(event)
    state.request.eventSink.onEvent(event)
  }

  private func consumeToolCallAttempt(_ state: LoopState) -> Bool {
    guard state.toolCallAttempts < state.request.budget.maxToolCalls else {
      return false
    }
    state.toolCallAttempts += 1
    return true
  }

  private func remainingTime(_ state: LoopState) -> Int64 {
    max(0, state.deadlineEpochMillis - clock.nowEpochMillis())
  }

  private func derivedIdempotencyKey(_ state: LoopState, call: AgentModelToolCall) -> String {
    AgentModelToolProtocolJSON.sha256([
      state.request.sessionId,
      state.request.turnId,
      call.callId,
      call.toolId,
      AgentMcpJSONCodec.sha256(call.arguments)
    ].joined(separator: "|"))
  }

  private func responseFingerprint(_ response: AgentModelResponse) -> String {
    AgentMcpJSONCodec.sha256([
      "assistant_text": .string(response.assistantText),
      "tool_calls": .array(response.toolCalls.map { call in
        .object([
          "call_id": .string(call.callId),
          "tool_id": .string(call.toolId),
          "tool_version": call.toolVersion.map(AgentMcpJSONValue.string) ?? .null,
          "arguments": .object(call.arguments),
          "depth": .int(Int64(call.depth))
        ])
      })
    ])
  }

  private func checkedId(_ purpose: String) -> String {
    let value = idFactory.newId(purpose)
    AgentModelToolLoopValidation.validateBoundId(purpose.replacingOccurrences(of: "_", with: " "), value)
    return value
  }

  private func boundWorkspaceCall(_ call: AgentModelToolCall, workspaceId: String) -> AgentModelToolCall {
    guard call.toolId.hasPrefix("galaxyssi.workspace.") ||
            call.toolId.hasPrefix("galaxyssi.project.") else {
      return call
    }
    var arguments = call.arguments
    arguments["workspace_id"] = .string(workspaceId)
    return AgentModelToolCall(
      callId: call.callId,
      toolId: call.toolId,
      arguments: arguments,
      toolVersion: call.toolVersion,
      idempotencyKey: call.idempotencyKey,
      depth: call.depth
    )
  }

  private struct PendingApproval {
    var state: LoopState
    var call: AgentModelToolCall
    var remainingCalls: [AgentModelToolCall]
    var descriptor: AgentNativeToolDescriptor
    var handle: AgentModelToolApprovalHandle
  }

  private struct PreparedCall {
    var call: AgentModelToolCall
    var descriptor: AgentNativeToolDescriptor
    var approvedConsentIds: Set<String>
  }

  private struct ParallelCandidate {
    var workload: AgentConcurrencyWorkload
    var resourcePlan: AgentNativeResourceLockPlan
  }

  private struct NativeInvocationAttempt {
    var prepared: PreparedCall
    var invocationId: String
    var context: AgentNativeToolInvocationContext
    var attempt: Int
  }

  private final class LoopState {
    var request: AgentModelToolLoopRequest
    var messages: [AgentModelMessage]
    var events: [AgentModelToolLoopEvent] = []
    var manifestJson: String
    var manifestSha256: String
    var startedAtEpochMillis: Int64
    var deadlineEpochMillis: Int64
    var callIds: [String: String] = [:]
    var callSignatures: [String: Int] = [:]
    var seenResponseFingerprints: Set<String> = []
    var rounds = 0
    var toolCallAttempts = 0
    var retries = 0
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var lastAssistantText = ""
    var eventSequence: Int64 = 0

    init(
      request: AgentModelToolLoopRequest,
      messages: [AgentModelMessage],
      manifestJson: String,
      manifestSha256: String,
      startedAtEpochMillis: Int64,
      deadlineEpochMillis: Int64
    ) {
      self.request = request
      self.messages = messages
      self.manifestJson = manifestJson
      self.manifestSha256 = manifestSha256
      self.startedAtEpochMillis = startedAtEpochMillis
      self.deadlineEpochMillis = deadlineEpochMillis
    }

    func totalTokens() -> Int64 {
      AgentModelToolLoopValidation.safeTokenSum(inputTokens, outputTokens)
    }
  }

  private enum ProcessResult {
    case `continue`
    case terminal(AgentModelToolLoopOutcome)
  }

  private enum PreparationResult {
    case `continue`
    case ready(PreparedCall)
    case terminal(AgentModelToolLoopOutcome)
  }
}
