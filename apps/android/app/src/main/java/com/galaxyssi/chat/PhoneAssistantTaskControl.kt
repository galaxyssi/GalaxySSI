package com.galaxyssi.chat

import android.os.Looper
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantLock
import java.util.concurrent.TimeUnit

/** One physical display is shared by all conversations, not one per model or window. */
internal object PhoneAssistantTaskControl {
    private val requests = ConcurrentHashMap<String, ScreenAssistantAnalysisRequest>()
    private val screenLock = ReentrantLock(true)
    fun bind(turnId: String, request: ScreenAssistantAnalysisRequest) { requests[turnId] = request }
    fun finish(turnId: String) { requests.remove(turnId)?.cancel() }
    fun isBound(turnId: String): Boolean = requests.containsKey(turnId)
    fun isAutomation(turnId: String): Boolean = requests[turnId]?.let { it.automation && !it.isCancelled } == true
    fun isReadOnly(turnId: String): Boolean = requests[turnId]?.automation == false
    fun reasoningRequirements(turnId: String, goal: String): AgentTaskRequirements {
        val requirements = AgentTaskRequirementAnalyzer.analyze(goal)
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
