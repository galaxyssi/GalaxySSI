package com.signalasi.chat

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Stable, conversation-scoped identity shared by file tools and the Linux runtime. */
object AgentWorkspaceScope {
    fun id(conversationId: String, sessionId: String = ""): String {
        val owner = conversationId.trim().ifBlank { sessionId.trim() }.ifBlank { "default" }
        return UUID.nameUUIDFromBytes("signalasi-workspace:$owner".toByteArray(Charsets.UTF_8)).toString()
    }

    fun bindToolInput(
        toolId: String,
        input: AgentNativeJsonObject,
        workspaceId: String
    ): AgentNativeJsonObject {
        return LinkedHashMap(input).apply {
            canonicalizeCommonModelArguments(toolId)
            if (WORKSPACE_TOOL_PREFIXES.any(toolId::startsWith)) {
                put("workspace_id", workspaceId)
            }
        }
    }

    fun <T> withLock(workspaceId: String, block: () -> T): T =
        locks.computeIfAbsent(workspaceId) { ReentrantLock() }.withLock(block)

    private val WORKSPACE_TOOL_PREFIXES = listOf("signalasi.workspace.", "signalasi.project.")
    private val REPOSITORY_URL_ALIASES = listOf("url", "repo_url", "repository")
    private val RUNTIME_SOURCE_ALIASES = listOf("command", "script", "code")
    private val locks = ConcurrentHashMap<String, ReentrantLock>()

    private fun MutableMap<String, Any?>.canonicalizeCommonModelArguments(toolId: String) {
        when (toolId) {
            AgentMobileProjectNativeTools.CLONE -> {
                if (containsKey("repository_url")) return
                val alias = REPOSITORY_URL_ALIASES.firstOrNull { key ->
                    this[key]?.toString()?.trim().orEmpty().isNotBlank()
                } ?: return
                put("repository_url", remove(alias))
                REPOSITORY_URL_ALIASES.forEach(::remove)
            }
            AgentOnDeviceRuntimeTools.EXECUTE -> canonicalizeRuntimeExecutionArguments()
        }
    }

    private fun MutableMap<String, Any?>.canonicalizeRuntimeExecutionArguments() {
        if (this["source"]?.toString()?.trim().orEmpty().isBlank()) {
            RUNTIME_SOURCE_ALIASES.firstOrNull { alias ->
                this[alias]?.toString()?.trim().orEmpty().isNotBlank()
            }?.let { alias -> put("source", remove(alias)) }
        }
        RUNTIME_SOURCE_ALIASES.forEach(::remove)
        remove("workspace_id")
        val language = this["language"]?.toString()?.trim()?.lowercase().orEmpty()
        this["language"] = when (language) {
            "bash", "sh", "zsh" -> AgentRuntimeLanguage.SHELL.wireValue
            "python3", "py" -> AgentRuntimeLanguage.PYTHON.wireValue
            "js", "node", "nodejs" -> AgentRuntimeLanguage.JAVASCRIPT.wireValue
            "ts" -> AgentRuntimeLanguage.TYPESCRIPT.wireValue
            "c++", "cxx" -> AgentRuntimeLanguage.CPP.wireValue
            else -> language
        }
    }
}
