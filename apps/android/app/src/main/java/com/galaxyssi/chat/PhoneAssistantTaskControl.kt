package com.galaxyssi.chat

import android.os.Looper
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantLock
import java.util.concurrent.TimeUnit

/** One physical display is shared by all conversations, not one per model or window. */
internal object PhoneAssistantTaskControl {
    const val SCREEN_ANALYSIS_REQUEST_KIND = "screen_analysis"
    private val requests = ConcurrentHashMap<String, ScreenAssistantAnalysisRequest>()
    private data class AnalysisScope(val question: String, val followUp: Boolean)
    private val analysisScopes = ConcurrentHashMap<String, AnalysisScope>()
    private val screenLock = ReentrantLock(true)
    fun bind(turnId: String, request: ScreenAssistantAnalysisRequest) {
        requests[turnId] = request
        if (!request.automation) analysisScopes[turnId] = AnalysisScope(request.displayQuestion, request.followUp)
        else analysisScopes.remove(turnId)
    }
    fun finish(turnId: String) { analysisScopes.remove(turnId); requests.remove(turnId)?.cancel() }
    fun cancel(turnId: String) { requests[turnId]?.cancel() }
    fun release(turnId: String, request: ScreenAssistantAnalysisRequest) {
        if (requests.remove(turnId, request)) analysisScopes.remove(turnId)
    }
    fun pageCapture(turnId: String): String = requests[turnId]?.pageCaptureId.orEmpty()
    fun isBound(turnId: String): Boolean = requests.containsKey(turnId)
    fun isAutomation(turnId: String): Boolean = requests[turnId]?.let { it.automation && !it.isCancelled } == true
    fun isReadOnly(turnId: String): Boolean = requests[turnId]?.automation == false
    fun requestKind(turnId: String): String = if (isReadOnly(turnId)) SCREEN_ANALYSIS_REQUEST_KIND else ""
    fun isReadOnlyRequest(turnId: String, action: AgentAction): Boolean =
        isReadOnly(turnId) || action.parameters["request_kind"] == SCREEN_ANALYSIS_REQUEST_KIND
    fun bindReadOnlyScope(action: AgentAction, turnId: String): AgentAction {
        if (!isReadOnly(turnId)) return action
        return action.copy(parameters = action.parameters + buildMap {
            put("request_kind", SCREEN_ANALYSIS_REQUEST_KIND)
            val scope = analysisScopes[turnId]
            put("screen_analysis_context", if (scope?.followUp == true) "follow_up" else "current")
            scope?.question?.takeIf(String::isNotBlank)?.let { put("screen_analysis_question", it) }
        })
    }
    fun isIndependentReadOnlyRequest(action: AgentAction): Boolean =
        action.parameters["request_kind"] == SCREEN_ANALYSIS_REQUEST_KIND &&
            action.parameters["screen_analysis_context"] != "follow_up"
    fun reasoningRequirements(turnId: String, goal: String): AgentTaskRequirements {
        val scope = analysisScopes[turnId]
        val instruction = scope?.question?.takeIf(String::isNotBlank) ?: goal
        val requirements = AgentTaskRequirementAnalyzer.analyze(instruction)
        if (scope != null) {
            // Reading supplied evidence does not require a separate knowledge-store connector.
            return requirements.copy(
                capabilities = requirements.capabilities - AgentCapability.KNOWLEDGE_SEARCH,
                estimatedInputTokens = maxOf(requirements.estimatedInputTokens, goal.length / 3)
            )
        }
        // The provider plans; authorized local tools supply navigation capabilities.
        return if (isAutomation(turnId)) requirements.copy(capabilities = setOf(AgentCapability.CHAT))
            else requirements
    }
    fun authorizeMutation(turnId: String) {
        check(isAutomation(turnId)) { "Start an explicit floating phone task before changing the phone UI" }
    }
    fun confirm(turnId: String, description: String, checkpoint: () -> Unit) {
        authorizeMutation(turnId)
        requireNotNull(requests[turnId])
            .requireApproval(description, checkpoint)
    }
    fun hasActiveTask(): Boolean = requests.values.any { !it.isCancelled }
    fun checkpoint(turnId: String, cancelled: () -> Boolean = { false }) {
        if (cancelled()) throw AgentNativeToolCancelledException()
        requests[turnId]?.awaitRunnable {
            if (cancelled()) throw AgentNativeToolCancelledException()
        }
    }
    fun <T> screenOperation(turnId: String, cancelled: () -> Boolean = { false }, operation: () -> T): T {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Phone operations must run off the main thread" }
        while (true) {
            checkpoint(turnId, cancelled)
            if (!screenLock.tryLock(200L, TimeUnit.MILLISECONDS)) continue
            try {
                if (requests[turnId]?.isPaused == true) continue
                if (cancelled() || requests[turnId]?.isCancelled == true) throw AgentNativeToolCancelledException()
                return operation()
            } finally { screenLock.unlock() }
        }
    }
    fun executor(turnId: String, delegate: AgentActionExecutor): AgentActionExecutor {
        val boundRequest = requests[turnId]
        return object : AgentActionExecutor {
        override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
            boundRequest?.awaitRunnable()
            if (boundRequest != null) check(requests[turnId] === boundRequest) { "Phone task authorization ended" }
            checkpoint(turnId)
            if (isBound(turnId) && action.kind.mayChangeScreen()) {
                authorizeMutation(turnId)
                check(action.kind !in setOf(AgentActionKind.TAP, AgentActionKind.LONG_PRESS, AgentActionKind.SWIPE,
                    AgentActionKind.TYPE_TEXT, AgentActionKind.DELETE_TEXT, AgentActionKind.PASTE_TEXT)) {
                    "Use galaxyssi.phone.ui.act with a fresh window revision and node path, not stale coordinates"
                }
            }
            return if (requests.containsKey(turnId) && action.kind.mayChangeScreen()) screenOperation(turnId) { delegate.execute(action, screen) }
                else delegate.execute(action, screen)
        }
        }
    }
}
