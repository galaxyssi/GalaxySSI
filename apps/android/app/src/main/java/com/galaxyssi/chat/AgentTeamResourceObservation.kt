package com.galaxyssi.chat

import org.json.JSONObject

/** Host facts only. This observation neither grants resources nor replaces admission enforcement. */
class AgentTeamResourceObservation private constructor(
    private val owner: List<String>,
    private val unit: Unit,
    private val limit: Long,
    private val reserved: Long,
    private val observedAtMillis: Long,
    private val remainingWindowMillis: Long?,
    private val window: Window,
    private val closed: Boolean
) {
    internal enum class Unit(val wire: String) {
        PHONE_DISPATCH("phone_delegate_admissions_not_provider_requests"),
        HTTP_REQUEST("cloud_http_request_admissions_not_completed_requests")
    }
    internal enum class Window(val wire: String) {
        EXECUTION("parent_execution_window"), ADMISSION("new_admission_window")
    }

    internal fun json(execution: AgentTeamMemberExecutionContext): JSONObject {
        check(owner == owner(execution)) { "Resource observation belongs to another assignment" }
        return JSONObject().put("format", "galaxyssi.execution-resources.v1")
            .put("scope", "shared_parent_run_pool").put("observed_at_unix_ms", observedAtMillis)
            .put("window_scope", window.wire).put("remaining_window_ms_at_observation", remainingWindowMillis ?: JSONObject.NULL)
            .put("admission_unit", unit.wire).put("admission_limit", limit)
            .put("admissions_reserved", reserved).put("admissions_remaining_at_observation", limit - reserved)
            .put("current_dispatch_included", false).put("admission_closed", closed)
            .put("billed_cost", JSONObject.NULL).put("provider_request_count", JSONObject.NULL)
            .put("remaining_token_budget", JSONObject.NULL)
    }

    internal fun prompt(execution: AgentTeamMemberExecutionContext): String =
        "[Host resource observation]\n${json(execution)}\n$INSTRUCTIONS\n"

    companion object {
        internal fun capture(execution: AgentTeamMemberExecutionContext, unit: Unit, limit: Long, reserved: Long,
                             observedAtMillis: Long, remainingWindowMillis: Long?, closed: Boolean = false,
                             window: Window = Window.EXECUTION): AgentTeamResourceObservation {
            require(limit > 0 && reserved in 0..limit && observedAtMillis >= 0)
            require(remainingWindowMillis == null || remainingWindowMillis >= 0)
            return AgentTeamResourceObservation(owner(execution), unit, limit, reserved, observedAtMillis, remainingWindowMillis, window, closed)
        }

        private fun owner(execution: AgentTeamMemberExecutionContext) = execution.request.let {
            listOf(it.conversationId, it.messageId, it.taskId, it.parentRunId, it.runId, it.idempotencyKey,
                execution.member.memberId, execution.member.context["collaboration_group_id"].orEmpty(),
                execution.member.context[CollaborationResearchWorkflow.PERSON].orEmpty(),
                AgentNativeJsonCodec.sha256(it.goal), AgentNativeJsonCodec.sha256(execution.member.objective))
        }

        private const val INSTRUCTIONS =
            "These are host facts sampled before this dispatch, not a live reservation or a fresh budget for each member. " +
            "Other members share the pool and may consume it after this observation. The current dispatch is not included yet. " +
            "Time decreases after observation; null means unknown, not free or unlimited. Phone dispatches are not provider calls or token usage. " +
            "window_scope distinguishes an execution window from a new-admission window; the latter does not cancel already admitted work. " +
            "Choose work for its expected contribution to the goal: resolving a consequential uncertainty, improving an artifact, or verifying a result. " +
            "When resources are scarce, preserve usable artifacts and unresolved evidence, and adapt the division of work instead of repeating low-value checks. " +
            "A closed or exhausted envelope does not satisfy the goal. Do not weaken acceptance criteria, invent completion, or assume new spending or access permission. " +
            "Existing host admission and user control remain authoritative."
    }
}
