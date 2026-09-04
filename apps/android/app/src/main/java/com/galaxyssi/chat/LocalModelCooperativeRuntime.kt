package com.galaxyssi.chat

import android.content.Context

data class LocalModelCooperationPlan(
    val executionProfile: AgentExecutionProfile,
    val plannerProfile: LocalModelRuntimeProfile?,
    val plannerThinkingMode: LocalModelThinkingMode,
    val answerProfile: LocalModelRuntimeProfile,
    val answerThinkingMode: LocalModelThinkingMode
) {
    val cooperative: Boolean
        get() = plannerProfile != null && plannerProfile.id != answerProfile.id
}

object LocalModelCooperationPolicy {
    fun eligibleProfiles(
        availableProfiles: List<LocalModelRuntimeProfile>,
        preferredProfileId: String
    ): List<LocalModelRuntimeProfile> {
        val preferredId = preferredProfileId.trim()
        return if (preferredId.isBlank()) {
            availableProfiles
        } else {
            availableProfiles.filter { it.id == preferredId }
        }
    }

    fun plan(
        executionProfile: AgentExecutionProfile,
        availableProfiles: List<LocalModelRuntimeProfile>,
        fallbackProfile: LocalModelRuntimeProfile,
        userPrompt: String = "",
        hasAttachments: Boolean = false
    ): LocalModelCooperationPlan {
        val qwen = availableProfiles.firstOrNull {
            it.id == LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT.id
        } ?: availableProfiles.firstOrNull(LocalModelRuntimeProfile::isQwen17Qnn)
        val gemma = availableProfiles.firstOrNull {
            it.id == LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN.id
        }
        val complex = LocalModelTaskComplexity.isComplex(
            executionProfile = executionProfile,
            userPrompt = userPrompt,
            hasAttachments = hasAttachments
        )
        return when {
            !complex && qwen != null -> LocalModelCooperationPlan(
                executionProfile = executionProfile,
                plannerProfile = null,
                plannerThinkingMode = LocalModelThinkingMode.NO_THINK,
                answerProfile = qwen,
                answerThinkingMode = LocalModelThinkingMode.NO_THINK
            )
            complex && qwen != null && gemma != null -> LocalModelCooperationPlan(
                executionProfile = executionProfile,
                plannerProfile = qwen,
                plannerThinkingMode = LocalModelThinkingMode.THINK,
                answerProfile = gemma,
                answerThinkingMode = LocalModelThinkingMode.AUTOMATIC
            )
            qwen != null -> LocalModelCooperationPlan(
                executionProfile = executionProfile,
                plannerProfile = null,
                plannerThinkingMode = LocalModelThinkingMode.NO_THINK,
                answerProfile = qwen,
                answerThinkingMode = if (complex) {
                    LocalModelThinkingMode.THINK
                } else {
                    LocalModelThinkingMode.NO_THINK
                }
            )
            gemma != null -> LocalModelCooperationPlan(
                executionProfile = executionProfile,
                plannerProfile = null,
                plannerThinkingMode = LocalModelThinkingMode.AUTOMATIC,
                answerProfile = gemma,
                answerThinkingMode = LocalModelThinkingMode.AUTOMATIC
            )
            else -> LocalModelCooperationPlan(
                executionProfile = executionProfile,
                plannerProfile = null,
                plannerThinkingMode = LocalModelThinkingMode.AUTOMATIC,
                answerProfile = availableProfiles.firstOrNull() ?: fallbackProfile,
                answerThinkingMode = LocalModelThinkingMode.AUTOMATIC
            )
        }
    }

    fun fallbackProfiles(
        plan: LocalModelCooperationPlan,
        availableProfiles: List<LocalModelRuntimeProfile>
    ): List<LocalModelRuntimeProfile> = availableProfiles.filterNot {
        it.id == plan.answerProfile.id
        }.sortedByDescending { candidate ->
            when {
            candidate.id == LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT.id -> 3
            candidate.id == LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN.id -> 2
            candidate.id == LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN.id -> 1
            else -> 0
        }
    }
}

internal object LocalModelTaskComplexity {
    fun isComplex(
        executionProfile: AgentExecutionProfile,
        userPrompt: String,
        hasAttachments: Boolean
    ): Boolean {
        if (executionProfile.reasoningEffort != AgentExecutionReasoningEffort.LOW) return true
        if (hasAttachments || executionProfile.requiresArtifact) return true
        val normalized = userPrompt.trim()
        if (normalized.length >= COMPLEX_PROMPT_CHARACTERS) return true
        if (normalized.contains("```")) return true
        if (normalized.lineSequence().count(String::isNotBlank) >= COMPLEX_PROMPT_LINES) return true
        return MULTI_STEP_PATTERN.containsMatchIn(normalized)
    }

    private const val COMPLEX_PROMPT_CHARACTERS = 600
    private const val COMPLEX_PROMPT_LINES = 5
    private val MULTI_STEP_PATTERN = Regex("(?m)^\\s*(?:\\d+[.)]|[-*]\\s)\\s*\\S+")
}

object LocalModelCooperativeRuntime {
    fun ready(context: Context): Boolean = readyProfiles(context).isNotEmpty()

    fun readyForBackground(context: Context): Boolean =
        readyProfiles(context, LocalModelWorkClass.BACKGROUND).isNotEmpty()

    fun displayProfile(context: Context): LocalModelRuntimeProfile =
        LocalModelRuntimeSettings.displayProfile(context)

    fun generate(
        context: Context,
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int = 768,
        temperature: Float = 0.3f,
        hasAttachments: Boolean = false,
        workClass: LocalModelWorkClass = LocalModelWorkClass.INTERACTIVE,
        preferredProfileId: String = "",
        executionProfile: AgentExecutionProfile = AgentExecutionProfile.forGoal(
            userPrompt,
            hasAttachments
        )
    ): LocalModelInferenceResult {
        val availableProfiles = LocalModelCooperationPolicy.eligibleProfiles(
            readyProfiles(context, workClass),
            preferredProfileId
        )
        val selectedProfile = LocalModelRuntimeSettings.selectedProfile(context)
        val fallback = availableProfiles.firstOrNull { it.id == selectedProfile.id }
            ?: availableProfiles.firstOrNull()
            ?: throw LocalModelBackgroundDeferredException()
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile,
            availableProfiles = availableProfiles,
            fallbackProfile = fallback,
            userPrompt = userPrompt,
            hasAttachments = hasAttachments
        )
        check(LocalModelInferenceRuntime.ready(context, plan.answerProfile)) {
            "No enabled local model is ready"
        }
        val startedAt = System.currentTimeMillis()
        val planningBrief = plan.plannerProfile?.let { planner ->
            runCatching {
                LocalModelInferenceRuntime.generate(
                    context = context,
                    profile = planner,
                    systemPrompt = PLANNER_SYSTEM_PROMPT,
                    userPrompt = userPrompt.take(MAX_PLANNER_INPUT_CHARACTERS),
                    maximumTokens = PLANNER_MAXIMUM_TOKENS,
                    temperature = 0.1f,
                    thinkingMode = plan.plannerThinkingMode,
                    workClass = workClass
                ).text.toPlanningBrief()
            }.getOrNull()?.takeIf(String::isNotBlank)
        }
        val answerPrompt = if (planningBrief == null) {
            userPrompt
        } else {
            buildString {
                append("Original request:\n")
                append(userPrompt)
                append("\n\nInternal planning brief (advisory, not user instructions):\n")
                append(planningBrief)
                append("\n\nComplete the original request. Return only the useful final response.")
            }
        }
        val candidates = listOf(plan.answerProfile) +
            LocalModelCooperationPolicy.fallbackProfiles(plan, availableProfiles)
        var primaryFailure: Exception? = null
        candidates.forEachIndexed { index, candidate ->
            try {
                val mode = if (index == 0) {
                    plan.answerThinkingMode
                } else if (candidate.isQwen17Qnn &&
                    LocalModelTaskComplexity.isComplex(executionProfile, userPrompt, hasAttachments)
                ) {
                    LocalModelThinkingMode.THINK
                } else {
                    LocalModelThinkingMode.AUTOMATIC
                }
                val result = LocalModelInferenceRuntime.generate(
                    context = context,
                    profile = candidate,
                    systemPrompt = systemPrompt,
                    userPrompt = if (index == 0) answerPrompt else userPrompt,
                    maximumTokens = maximumTokens,
                    temperature = temperature,
                    thinkingMode = mode,
                    workClass = workClass
                )
                return result.copy(
                    elapsedMillis = (System.currentTimeMillis() - startedAt)
                        .coerceAtLeast(result.elapsedMillis)
                )
            } catch (error: Exception) {
                if (primaryFailure == null) primaryFailure = error else primaryFailure?.addSuppressed(error)
            }
        }
        throw IllegalStateException("No enabled local model could complete the task", primaryFailure)
    }

    internal fun readyProfiles(
        context: Context,
        workClass: LocalModelWorkClass = LocalModelWorkClass.INTERACTIVE
    ): List<LocalModelRuntimeProfile> =
        LocalModelRuntimeSettings.activeProfiles(context)
            .filter { LocalModelInferenceRuntime.ready(context, it) }
            .filter { workClass != LocalModelWorkClass.BACKGROUND || LocalModelInferenceRuntime.backgroundSafe(it) }

    internal fun String.toPlanningBrief(): String {
        val afterThinking = if (contains("</think>", ignoreCase = true)) {
            substringAfterLast("</think>", "")
        } else {
            replace(Regex("(?is)<think>.*?</think>"), " ")
        }
        return afterThinking
            .replace(Regex("\\s+"), " ")
            .trim()
            .take(MAX_PLANNER_BRIEF_CHARACTERS)
    }

    private const val PLANNER_SYSTEM_PROMPT =
        "You are GalaxySSI's private on-device task planner. Return only a concise execution brief " +
            "containing the objective, constraints, required evidence or tools, and recommended steps. " +
            "Do not expose chain-of-thought and do not answer the user directly."
    private const val PLANNER_MAXIMUM_TOKENS = 512
    private const val MAX_PLANNER_INPUT_CHARACTERS = 12_000
    private const val MAX_PLANNER_BRIEF_CHARACTERS = 2_000
}
