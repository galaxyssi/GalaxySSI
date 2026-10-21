package com.galaxyssi.chat

internal object AgentRemoteSilencePolicy {
    const val PROBE_INTERVAL = 30_000L
    const val SILENCE_LIMIT = AgentCodexSilenceRecovery.MAX_SILENCE_MILLIS
    const val MIN_PROBES = 3
    const val TERMINAL_DELIVERY_LIMIT = 15 * 60_000L

    fun terminalDeliveryExpired(completedAt: Long, now: Long): Boolean =
        completedAt > 0 && now >= completedAt && now - completedAt >= TERMINAL_DELIVERY_LIMIT

    fun expired(startedAt: Long, lastResponseAt: Long, misses: Int, now: Long): Boolean {
        val anchor = maxOf(startedAt, lastResponseAt)
        return anchor > 0 && now >= anchor && now - anchor >= SILENCE_LIMIT && misses >= MIN_PROBES
    }

    fun permitsReplay(action: AgentAction?, goal: String): Boolean {
        if (action?.isSupervisedProjectConnector() == true) return true
        if (action == null || action.risk != AgentRisk.LOW) return false
        val instruction = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal).lowercase()
        // Risk heuristics alone are not proof that a full Desktop executor is read-only.
        val mutationTerms = listOf("delete", "remove", "send", "publish", "buy", "pay", "install", "upload",
            "修改", "删除", "发送", "提交", "发布", "购买", "付款", "安装", "上传", "写入", "保存", "转账")
        if (mutationTerms.any(instruction::contains)) return false
        val requirements = AgentTaskRequirementAnalyzer.analyze(goal)
        val readCapabilities = setOf(AgentCapability.CHAT, AgentCapability.REASONING,
            AgentCapability.LIVE_DATA, AgentCapability.RESEARCH, AgentCapability.KNOWLEDGE_SEARCH)
        return requirements.executionHorizon == AgentExecutionHorizon.INTERACTIVE &&
            requirements.capabilities.all { it in readCapabilities }
    }
}
