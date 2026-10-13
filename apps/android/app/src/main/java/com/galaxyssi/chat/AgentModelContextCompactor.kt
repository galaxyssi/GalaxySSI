package com.galaxyssi.chat

import java.util.IdentityHashMap

data class CompactedAgentModelContext(
    val messages: List<AgentModelMessage>,
    val originalEstimatedTokens: Int,
    val compactedEstimatedTokens: Int,
    val compacted: Boolean
)

internal class AgentModelContextCompactionSession(
    private val messageEstimator: (AgentModelMessage) -> Int = AgentModelContextCompactor::estimateMessage
) {
    private val estimates = IdentityHashMap<AgentModelMessage, Int>()

    fun compact(
        messages: List<AgentModelMessage>,
        budget: ConversationContextBudget
    ): CompactedAgentModelContext = AgentModelContextCompactor.compact(
        messages = messages,
        budget = budget,
        messageEstimator = ::estimateMessage
    )

    internal val cachedMessageCount: Int
        get() = estimates.size

    private fun estimateMessage(message: AgentModelMessage): Int =
        estimates[message] ?: messageEstimator(message).also { estimates[message] = it }
}

/**
 * Prunes model tool-loop history by token pressure while preserving protocol
 * structure. An assistant tool call and its matching tool results always move
 * together; older completed blocks become a reference-only system summary.
 */
object AgentModelContextCompactor {
    private const val SUMMARY_HEADER = "[EARLIER TOOL ACTIVITY - REFERENCE ONLY]"

    fun compact(
        messages: List<AgentModelMessage>,
        budget: ConversationContextBudget
    ): CompactedAgentModelContext = compact(
        messages = messages,
        budget = budget,
        messageEstimator = ::estimateMessage
    )

    internal fun compact(
        messages: List<AgentModelMessage>,
        budget: ConversationContextBudget,
        messageEstimator: (AgentModelMessage) -> Int
    ): CompactedAgentModelContext {
        val originalTokens = estimate(messages, messageEstimator)
        val trigger = (budget.inputBudgetTokens * budget.triggerRatio).toInt()
        if (originalTokens <= trigger) {
            return CompactedAgentModelContext(messages, originalTokens, originalTokens, false)
        }

        val systemMessages = messages.filter { it.role == AgentModelMessageRole.SYSTEM }
        val blocks = protocolBlocks(messages.filterNot { it.role == AgentModelMessageRole.SYSTEM })
        val targetTokens = (budget.inputBudgetTokens * budget.targetRatio).toInt()
        val summaryAllowance = minOf(
            budget.maximumSummaryTokens,
            (budget.inputBudgetTokens * 0.15).toInt()
        )
        val fixedTokens = estimate(systemMessages, messageEstimator)
        val tailAllowance = (targetTokens - fixedTokens - summaryAllowance).coerceAtLeast(512)
        val retainedKeys = linkedSetOf<Int>()
        val latestFailure = blocks.lastOrNull { block -> block.messages.any { it.toolResult?.failedObservation() == true } }
        var retainedTokens = 0
        var retainedBlocks = 0
        blocks.asReversed().forEach { block ->
            val blockTokens = estimate(block.messages, messageEstimator)
            val mustKeep = block.unresolvedToolCalls ||
                retainedBlocks < budget.minimumRecentGroups ||
                block.containsOriginalOrLatestUserRequest || block === latestFailure ||
                block.messages.any { message -> message.toolResult?.let { result ->
                    result.error?.code == "effect_outcome_unknown" || AgentToolContextObservation.isLive(result)
                } == true }
            if (mustKeep || retainedTokens + blockTokens <= tailAllowance) {
                retainedKeys += block.index
                retainedTokens += blockTokens
                retainedBlocks += 1
            }
        }
        if (retainedKeys.isEmpty() && blocks.isNotEmpty()) {
            retainedKeys += blocks.last().index
        }

        val olderBlocks = blocks.filterNot { it.index in retainedKeys }
        val recent = blocks.filter { it.index in retainedKeys }.flatMap(ToolProtocolBlock::messages)
        val summary = toolSummary(olderBlocks, summaryAllowance)
        val assembled = buildList {
            addAll(systemMessages)
            if (summary.isNotBlank()) add(AgentModelMessage.system(summary))
            addAll(recent)
        }
        val bounded = if (estimate(assembled, messageEstimator) <= budget.inputBudgetTokens) {
            assembled
        } else {
            shrinkOversizedMessages(assembled, budget.inputBudgetTokens, messageEstimator)
        }
        return CompactedAgentModelContext(
            messages = bounded,
            originalEstimatedTokens = originalTokens,
            compactedEstimatedTokens = estimate(bounded, messageEstimator),
            compacted = olderBlocks.isNotEmpty() || bounded != messages
        )
    }

    private fun protocolBlocks(messages: List<AgentModelMessage>): List<ToolProtocolBlock> {
        if (messages.isEmpty()) return emptyList()
        val latestUserIndex = messages.indexOfLast { it.role == AgentModelMessageRole.USER }
        val originalUserIndex = messages.indexOfFirst { it.role == AgentModelMessageRole.USER }
        val blocks = mutableListOf<ToolProtocolBlock>()
        var index = 0
        while (index < messages.size) {
            val message = messages[index]
            if (message.role == AgentModelMessageRole.ASSISTANT && message.toolCalls.isNotEmpty()) {
                val expected = message.toolCalls.mapTo(linkedSetOf(), AgentModelToolCall::callId)
                val blockMessages = mutableListOf(message)
                var cursor = index + 1
                val resolved = linkedSetOf<String>()
                while (cursor < messages.size && messages[cursor].role == AgentModelMessageRole.TOOL) {
                    val result = requireNotNull(messages[cursor].toolResult)
                    if (result.callId !in expected) break
                    blockMessages += messages[cursor]
                    resolved += result.callId
                    cursor += 1
                }
                blocks += ToolProtocolBlock(
                    index = blocks.size,
                    messages = blockMessages,
                    unresolvedToolCalls = resolved != expected,
                    containsOriginalOrLatestUserRequest = latestUserIndex in index until cursor ||
                        originalUserIndex in index until cursor
                )
                index = cursor
            } else {
                blocks += ToolProtocolBlock(
                    index = blocks.size,
                    messages = listOf(message),
                    unresolvedToolCalls = false,
                    containsOriginalOrLatestUserRequest = index == latestUserIndex || index == originalUserIndex
                )
                index += 1
            }
        }
        return blocks
    }

    private fun toolSummary(blocks: List<ToolProtocolBlock>, maximumTokens: Int): String {
        if (blocks.isEmpty() || maximumTokens <= 0) return ""
        // Only host-derived counters belong in SYSTEM; page/log/error text stays in TOOL.
        val candidates = blocks.asSequence()
            .flatMap { block -> block.messages.asSequence() }
            .mapNotNull(AgentModelMessage::toolResult)
            .groupBy { it.toolId.takeIf { id -> id.matches(Regex("[a-z0-9_.]{1,160}")) } ?: "invalid_tool_id" }
            .map { (tool, results) ->
                "Tool $tool: observations=${results.size}, failed_or_rejected=${results.count { it.failedObservation() }}."
            }
        val lines = mutableListOf<String>()
        var usedTokens = 0
        candidates.asReversed().forEach { candidate ->
            val tokens = ConversationContextCompactor.estimateTokens(candidate) + 2
            if (lines.isEmpty() || usedTokens + tokens <= maximumTokens) {
                lines += candidate
                usedTokens += tokens
            }
        }
        lines.reverse()
        if (lines.isEmpty()) return ""
        return ConversationContextCompactor.fitTextToTokenBudget(
            buildString {
                append(SUMMARY_HEADER).append('\n')
                append("Earlier observations are not proof of goal completion. Details omitted; inspect retained receipts or current state before repeating operations.\n")
                lines.forEach { append("- ").append(it).append('\n') }
            }.trim(),
            maximumTokens
        )
    }

    private fun shrinkOversizedMessages(
        messages: List<AgentModelMessage>,
        maximumTokens: Int,
        messageEstimator: (AgentModelMessage) -> Int
    ): List<AgentModelMessage> {
        var current = messages
        var estimate = estimate(current, messageEstimator)
        if (estimate <= maximumTokens) return current
        val reducible = current.indices.filter { index ->
            current[index].role == AgentModelMessageRole.TOOL ||
                current[index].role == AgentModelMessageRole.ASSISTANT
        }
        val resolvedCallIds = messages.mapNotNull { it.toolResult?.callId }.toSet()
        for (index in reducible) {
            val message = current[index]
            val replacement = when (message.role) {
                AgentModelMessageRole.TOOL -> {
                    message.copy(toolResult = AgentToolContextObservation.compact(requireNotNull(message.toolResult)))
                }
                AgentModelMessageRole.ASSISTANT -> message.copy(
                    text = ConversationContextCompactor.fitTextToTokenBudget(message.text, 256),
                    toolCalls = message.toolCalls.map { call ->
                        if (call.callId !in resolvedCallIds) call
                        else call.copy(arguments = compactObject(call.arguments, 80))
                    }
                )
                else -> message
            }
            current = current.toMutableList().also { it[index] = replacement }
            estimate = estimate(current, messageEstimator)
            if (estimate <= maximumTokens) return current
        }
        return current
    }

    private fun estimate(
        messages: List<AgentModelMessage>,
        messageEstimator: (AgentModelMessage) -> Int
    ): Int = messages.sumOf(messageEstimator)

    internal fun estimateMessage(message: AgentModelMessage): Int = with(message) {
        var tokens = ConversationContextCompactor.estimateTokens(message.text) + 6
        message.toolCalls.forEach { call ->
            tokens += ConversationContextCompactor.estimateTokens(call.toolId)
            tokens += ConversationContextCompactor.estimateTokens(
                runCatching { AgentNativeJsonCodec.stringify(call.arguments) }.getOrDefault("")
            )
        }
        message.toolResult?.let { result ->
            tokens += ConversationContextCompactor.estimateTokens(
                runCatching { AgentNativeJsonCodec.stringify(result.toJsonValue()) }
                    .getOrDefault(result.message)
            )
        }
        tokens
    }

    private fun compactObject(value: AgentNativeJsonObject, tokenLimit: Int): AgentNativeJsonObject =
        value.mapValuesTo(linkedMapOf()) { (_, item) -> compactValue(item, tokenLimit) }

    private fun compactValue(value: Any?, tokenLimit: Int): Any? = when (value) {
        is String -> ConversationContextCompactor.fitTextToTokenBudget(value, tokenLimit)
        is Map<*, *> -> value.entries.associateTo(linkedMapOf()) { entry ->
            entry.key.toString() to compactValue(entry.value, tokenLimit)
        }
        is List<*> -> value.take(12).map { compactValue(it, tokenLimit) }
        else -> value
    }

    private fun AgentModelToolResultContent.failedObservation(): Boolean =
        error != null || status in setOf("failed", "rejected", "cancelled")

    private data class ToolProtocolBlock(
        val index: Int,
        val messages: List<AgentModelMessage>,
        val unresolvedToolCalls: Boolean,
        val containsOriginalOrLatestUserRequest: Boolean
    )
}
