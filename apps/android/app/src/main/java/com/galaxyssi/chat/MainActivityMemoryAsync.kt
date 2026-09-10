package com.galaxyssi.chat

import android.view.View
import android.widget.Toast
import java.util.concurrent.Executors

internal object AgentMemoryUiWork {
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "galaxyssi-memory-ui-io").apply { isDaemon = true }
    }
    fun execute(action: () -> Unit) = executor.execute { action() }
}

internal data class AgentMemoryPageContent(
    val page: AgentMemoryBrowsePage,
    val captureEnabled: Boolean,
    val request: AgentMemoryBrowseRequest
)

internal fun MainActivity.showMemoryControlCenterAsync() {
    val title = getString(R.string.cc_memory_title)
    showFeaturePage(title)
    featureContent.addView(featureValueRow(getString(R.string.navigation_content_loading), "", R.drawable.ic_agent_memory, ""))
    val generation = navigationContentGate.begin()
    AgentMemoryUiWork.execute {
        if (!navigationContentGate.isCurrent(generation)) return@execute
        val result = runCatching { buildControlCenterMemoryPage() }
        handler.post {
            if (isFinishing || isDestroyed || !navigationContentGate.isCurrent(generation) ||
                featurePage.visibility != View.VISIBLE || featureTitle.text.toString() != title) return@post
            featureContent.removeAllViews()
            result.onSuccess { controlCenterRenderer.render(featureContent, it, ::handleControlCenterAction) }.onFailure { error ->
                featureContent.addView(featureValueRow(getString(R.string.agent_observation_action_failed),
                    memoryFailureReason(error), R.drawable.ic_agent_memory, ""))
            }
        }
    }
}

internal fun MainActivity.showAgentMemoryPage(filterKinds: Set<AgentMemoryKind> = emptySet(),
    request: AgentMemoryBrowseRequest = AgentMemoryBrowseRequest(kinds = filterKinds)) {
    val title = getString(R.string.agent_memory_title)
    showFeaturePage(title)
    featureContent.addView(featureValueRow(getString(R.string.navigation_content_loading), "", R.drawable.ic_agent_node, ""))
    val generation = navigationContentGate.begin()
    AgentMemoryUiWork.execute {
        if (!navigationContentGate.isCurrent(generation)) return@execute
        val result = runCatching {
            val scoped = request.copy(kinds = filterKinds)
            AgentMemoryPageContent(mobileNativeAgent.memoryStore.browse(scoped),
                mobileNativeAgent.safetySettings().memoryCapture, scoped)
        }
        handler.post {
            if (isFinishing || isDestroyed || !navigationContentGate.isCurrent(generation) ||
                featurePage.visibility != View.VISIBLE || featureTitle.text.toString() != title) return@post
            featureContent.removeAllViews()
            result.onSuccess { renderAgentMemoryPage(it, filterKinds) }.onFailure { error ->
                if (error is AgentMemoryPageChanged && request.cursor != null) {
                    showAgentMemoryPage(filterKinds, request.copy(cursor = null, backwards = false))
                    return@onFailure
                }
                featureContent.addView(featureValueRow(getString(R.string.agent_observation_action_failed),
                    memoryFailureReason(error), R.drawable.ic_agent_node, ""))
            }
        }
    }
}

internal fun MainActivity.addAgentMemorySummaryRow() {
    fun row(value: String) = featureValueRow(getString(R.string.agent_memory_title),
        getString(R.string.agent_memory_management_subtitle), R.drawable.ic_agent_node, value).apply {
        setOnClickListener {
            showAgentMemoryPage()
            setFeatureBackAction { showOnDeviceAgentFeaturePage() }
        }
    }
    val placeholder = row("")
    featureContent.addView(placeholder)
    val generation = navigationContentGate.begin()
    AgentMemoryUiWork.execute {
        if (!navigationContentGate.isCurrent(generation)) return@execute
        val result = runCatching { mobileNativeAgent.memoryStore.browseCounts() }
        handler.post {
            if (isFinishing || isDestroyed || !navigationContentGate.isCurrent(generation) ||
                featurePage.visibility != View.VISIBLE || placeholder.parent !== featureContent) return@post
            val position = featureContent.indexOfChild(placeholder)
            val text = result.fold({ getString(R.string.agent_memory_value, it.active, it.conflicts) },
                { getString(R.string.agent_observation_action_failed) })
            featureContent.removeView(placeholder)
            featureContent.addView(row(text), position)
        }
    }
}

internal fun <T> MainActivity.runAgentMemoryMutation(action: () -> T, completed: (T) -> Unit) {
    val generation = navigationContentGate.begin()
    val title = featureTitle.text.toString()
    AgentMemoryUiWork.execute {
        val result = runCatching(action)
        handler.post {
            if (isFinishing || isDestroyed || !navigationContentGate.isCurrent(generation) ||
                featurePage.visibility != View.VISIBLE || featureTitle.text.toString() != title) return@post
            result.onSuccess(completed).onFailure { error ->
                Toast.makeText(this, getString(R.string.agent_observation_action_failed) + ": " + memoryFailureReason(error),
                    Toast.LENGTH_LONG).show()
            }
        }
    }
}

private fun memoryFailureReason(error: Throwable): String = error.message?.takeIf { it.isNotBlank() }?.take(240)
    ?: error.javaClass.simpleName
