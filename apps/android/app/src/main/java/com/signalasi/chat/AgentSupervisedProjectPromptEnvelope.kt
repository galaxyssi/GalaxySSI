package com.signalasi.chat

internal data class AgentSupervisedProjectPromptEnvelope(
    val systemPrompt: String,
    val userPrompt: String
) {
    companion object {
        fun split(prompt: String): AgentSupervisedProjectPromptEnvelope? {
            val boundary = prompt.indexOf(AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER)
            if (boundary <= 0) return null
            val systemPrompt = prompt.substring(0, boundary).trimEnd()
            val userPrompt = prompt.substring(boundary).trim()
            if (systemPrompt.isBlank() || userPrompt.isBlank()) return null
            return AgentSupervisedProjectPromptEnvelope(systemPrompt, userPrompt)
        }
    }
}
