package com.galaxyssi.chat

/** Reuse the supervised phone loop without replaying a shortcut whose effect is uncertain. */
internal object AgentUnverifiedOutcomeRecovery {
    const val ORIGIN_ACTION = "goal_recovery_origin_action"
    const val PHONE_CONTROL = "goal_recovery_phone_control"
    private const val PHONE_REVIEW_REASON = "inspect_unverified_phone_outcome"

    fun needsReview(plan: AgentPlan, action: AgentAction, result: AgentActionResult?): Boolean {
        if (plan.isSupervisedProjectPlan() || plan.executionMode == AgentTaskExecutionMode.PLAN_ONLY ||
            action.kind != AgentActionKind.CALL_NATIVE_TOOL || result?.actionId != action.id ||
            result.success != true || result.metadata["awaiting_response"] == "true" ||
            AgentGoalEvidence.permitsSuccess(result) || !AgentSupervisedProjectLoop.needsRunnableReviewer(plan)) return false
        val observed = plan.actions.lastOrNull { it.id == action.id } ?: return false
        return observed.status == AgentActionStatus.COMPLETED &&
            AgentGoalEvidence.pendingReceipt(listOf(observed))?.canInspect == true
    }

    fun create(plan: AgentPlan, action: AgentAction, result: AgentActionResult?, request: AgentRequest,
        provider: AgentAction?): AgentPlan? {
        if (!needsReview(plan, action, result) || provider?.kind != AgentActionKind.CALL_CONNECTOR ||
            provider.parameters["connector_id"].isNullOrBlank() ||
            provider.parameters["connector_id"] == UNAVAILABLE_REASONING_CONNECTOR_ID ||
            AgentTaskRequirementAnalyzer.analyze(request.goal).localOnly) return null
        val scope = AgentPlanContinuationScope.resolve(plan, request.conversationContext.conversationId,
            request.executionTurnId, request.runtimeContext.sessionId) ?: return null
        val revision = plan.revision + 1
        val history = plan.historyForNextRevision(revision).filter(scope::owns)
        val observed = history.lastOrNull { it.id == action.id } ?: return null
        val phoneControl = PhoneAssistantToolPolicy.allowsRemotePhoneTool(action.parameters["tool_id"].orEmpty())
        val marker = provider.copy(parameters = provider.parameters + mapOf(
            ORIGIN_ACTION to action.id, PHONE_CONTROL to phoneControl.toString()))
        val scoped = request.copy(conversationContext = scope.context(request.conversationContext), memories = emptyList(),
            executionTurnId = scope.turnId, executionHistory = history,
            replanReason = if (phoneControl) PHONE_REVIEW_REASON else "inspect_unverified_outcome",
            planningRevision = revision, completionRequirements = plan.completionRequirements)
        val initial = AgentPhoneReasoningProviderPlanner(marker).plan(scoped)
        val connector = scope.bind(initial.actions.single().copy(
            id = "review-outcome-r$revision-${action.id.take(40)}",
            description = "Inspect the unverified phone outcome before deciding the next step",
            parameters = initial.actions.single().parameters + mapOf(
                "supervised_iteration" to "1",
                "prompt" to AgentSupervisedProjectLoop.recoveryPrompt(scoped, observed,
                    "The shortcut's business outcome is unverified. First return read-only observations of the affected state; " +
                        "do not repeat the effect, include a mutation in that batch, or claim completion before inspecting. " +
                        "Then repair only missing work and verify an identity-bound postcondition.")
            ))).withPlanRevision(revision)
        val candidate = initial.copy(planId = plan.planId, executionMode = plan.executionMode,
            actions = listOf(connector), revision = revision, replanCount = plan.replanCount + 1,
            actionHistory = history, checkpoints = plan.checkpoints, verificationResults = plan.verificationResults,
            artifactRichOutputJson = plan.artifactRichOutputJson, completionRequirements = plan.completionRequirements,
            expectedResult = plan.expectedResult, rollbackStrategy = plan.rollbackStrategy)
        return candidate.copy(validation = AgentPlanValidator.validate(candidate)).takeIf { it.validation.valid }
    }

    fun isPhoneControl(request: AgentRequest): Boolean = request.replanReason == PHONE_REVIEW_REASON ||
        request.executionHistory.any {
            it.parameters[PHONE_CONTROL] == "true" && !it.parameters[ORIGIN_ACTION].isNullOrBlank()
        }

    fun observationViolation(connector: AgentAction, history: List<AgentAction>, proposed: List<AgentAction>,
        descriptorFor: (String) -> AgentNativeToolDescriptor?): String? {
        val origin = connector.parameters[ORIGIN_ACTION].orEmpty()
        if (origin.isBlank()) return null
        val originIndex = history.indexOfLast { it.id == origin }
        fun readOnly(action: AgentAction): Boolean = action.kind == AgentActionKind.CALL_NATIVE_TOOL &&
            descriptorFor(action.parameters["tool_id"].orEmpty())?.requiresEffectClaim == false
        val inspected = originIndex >= 0 && history.drop(originIndex + 1).any {
            it.status == AgentActionStatus.COMPLETED && it.evidence.isNotBlank() && readOnly(it) &&
                it.parameters["tool_id"] !in AgentToolInspectionTools.toolIds &&
                !AgentSupervisedProjectRecoveryPolicy.hasUnknownOutcome(it)
        }
        if (inspected) return null
        return if (proposed.isNotEmpty() && proposed.all(::readOnly)) null
        else "unverified_outcome_requires_observation: first inspect the affected state with read-only native tools. " +
            "A schema lookup alone is not state evidence. Do not repeat or combine mutations, or declare completion before observation."
    }
}

internal fun MobileNativeAgent.continueUnverifiedOutcome(
    plan: AgentPlan, action: AgentAction, result: AgentActionResult?
): AgentPlan {
    if (!AgentUnverifiedOutcomeRecovery.needsReview(plan, action, result) || planningWasStopped() ||
        safetySettingsStore.load().executionPaused || !safetySettingsStore.load().connectorCallsAllowed ||
        AgentTaskRequirementAnalyzer.analyze(currentGoal).localOnly) return plan
    val request = supervisedProjectRequest(plan, continuation = true)
    val provider = RuleBasedAgentPlanner(appContext).informationQueryAction(request)
    val recovered = AgentUnverifiedOutcomeRecovery.create(plan, action, result, request, provider) ?: return plan
    val reviewed = AgentActionRiskHardener.enforce(appContext, recovered).let {
        it.withSafetyReview(safetyPolicy.review(it, sessionId))
    }
    if (planningWasStopped()) return plan
    recordAudit(AgentAuditEvent.PLAN_REPLANNED,
        "unverified_outcome_review:action=${action.id}; revision=${reviewed.revision}")
    return reviewed
}
