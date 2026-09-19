package com.galaxyssi.chat

internal object AgentRemoteSilencePolicy {
    const val PROBE_INTERVAL = 30_000L
    const val SILENCE_LIMIT = 5 * 60_000L
    const val MIN_PROBES = 3

    fun expired(startedAt: Long, lastResponseAt: Long, misses: Int, now: Long): Boolean {
        val anchor = maxOf(startedAt, lastResponseAt)
        return anchor > 0 && now >= anchor && now - anchor >= SILENCE_LIMIT && misses >= MIN_PROBES
    }

    fun permitsReplay(action: AgentAction?, goal: String): Boolean {
        if (action == null || action.risk != AgentRisk.LOW) return false
        val instruction = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal).lowercase()
        // Risk heuristics alone are not proof that a full Desktop executor is read-only.
        val mutationTerms = listOf("delete", "remove", "send", "publish", "buy", "pay", "install", "upload",
            "修改", "删除", "发送", "提交", "发布", "购买", "付款", "安装", "上传", "写入", "保存", "转账")
        if (mutationTerms.any(instruction::contains)) return false
        val question = instruction.contains('?') || instruction.contains('？') ||
            listOf("what", "why", "how", "explain", "tell me", "什么", "为什么", "如何", "解释", "天气", "新闻", "查询", "查找")
                .any(instruction::contains)
        if (!question && action.parameters["read_only"] != "true") return false
        val requirements = AgentTaskRequirementAnalyzer.analyze(goal)
        val readCapabilities = setOf(AgentCapability.CHAT, AgentCapability.REASONING,
            AgentCapability.LIVE_DATA, AgentCapability.RESEARCH, AgentCapability.KNOWLEDGE_SEARCH)
        return requirements.executionHorizon == AgentExecutionHorizon.INTERACTIVE &&
            requirements.capabilities.all { it in readCapabilities }
    }
}
