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
        if (WORKSPACE_TOOL_PREFIXES.none(toolId::startsWith)) return input
        return LinkedHashMap(input).apply {
            canonicalizeCommonModelArguments(toolId)
            put("workspace_id", workspaceId)
        }
    }

    fun <T> withLock(workspaceId: String, block: () -> T): T =
        locks.computeIfAbsent(workspaceId) { ReentrantLock() }.withLock(block)

    private val WORKSPACE_TOOL_PREFIXES = listOf("signalasi.workspace.", "signalasi.project.")
    private val REPOSITORY_URL_ALIASES = listOf("url", "repo_url", "repository")
    private val locks = ConcurrentHashMap<String, ReentrantLock>()

    private fun MutableMap<String, Any?>.canonicalizeCommonModelArguments(toolId: String) {
        if (toolId != AgentMobileProjectNativeTools.CLONE || containsKey("repository_url")) return
        val alias = REPOSITORY_URL_ALIASES.firstOrNull { key ->
            this[key]?.toString()?.trim().orEmpty().isNotBlank()
        } ?: return
        put("repository_url", remove(alias))
        REPOSITORY_URL_ALIASES.forEach(::remove)
    }
}
