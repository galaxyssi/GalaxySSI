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
        return LinkedHashMap(input).apply { put("workspace_id", workspaceId) }
    }

    fun <T> withLock(workspaceId: String, block: () -> T): T =
        locks.computeIfAbsent(workspaceId) { ReentrantLock() }.withLock(block)

    private val WORKSPACE_TOOL_PREFIXES = listOf("signalasi.workspace.", "signalasi.project.")
    private val locks = ConcurrentHashMap<String, ReentrantLock>()
}
