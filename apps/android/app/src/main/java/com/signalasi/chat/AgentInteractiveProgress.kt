package com.signalasi.chat

import java.util.Locale

internal enum class AgentInteractiveProgressStepState {
    PENDING,
    ACTIVE,
    COMPLETED,
    FAILED
}

internal data class AgentInteractiveProgressStep(
    val text: String,
    val state: AgentInteractiveProgressStepState
)

internal data class AgentInteractiveProgressPresentation(
    val visible: Boolean,
    val summary: String,
    val steps: List<AgentInteractiveProgressStep>,
    val currentStep: Int,
    val totalSteps: Int,
    val completedSteps: Int,
    val running: Boolean,
    val agentLabel: String,
    val recentActivity: List<String>
) {
    val counter: String
        get() = "$currentStep/$totalSteps"

    companion object {
        val HIDDEN = AgentInteractiveProgressPresentation(
            visible = false,
            summary = "",
            steps = emptyList(),
            currentStep = 0,
            totalSteps = 0,
            completedSteps = 0,
            running = false,
            agentLabel = "",
            recentActivity = emptyList()
        )
    }
}

internal object AgentInteractiveProgressPolicy {
    fun project(
        goal: String,
        plan: AgentPlan?,
        phase: AgentPhase?,
        processTexts: List<String>,
        completed: Boolean,
        fallbackSteps: List<String> = emptyList()
    ): AgentInteractiveProgressPresentation {
        val declaredPlan = processTexts.singleOrNull()
            ?.let(::splitPlanText)
            ?.takeIf { lines -> lines.size >= 2 }
        val narration = processTexts
            .flatMap(::splitPlanText)
            .map(String::trim)
            .filter(String::isNotBlank)
            .distinctBy(::normalizedIdentity)
        val planActions = plan?.actions.orEmpty()
            .filterNot(AgentAction::isTaskCompleteMarker)
            .filter { action -> action.description.isNotBlank() }
        val actionDescriptions = planActions
            .map(AgentAction::description)
            .distinctBy(::normalizedIdentity)
        val plannedDescriptions = when {
            actionDescriptions.size >= 2 -> actionDescriptions
            narration.size >= 2 -> narration
            fallbackSteps.isNotEmpty() -> emptyList()
            else -> (actionDescriptions + narration).distinctBy(::normalizedIdentity)
        }
        if (!isComplex(goal, plan, narration.size, fallbackSteps.isNotEmpty())) {
            return AgentInteractiveProgressPresentation.HIDDEN
        }
        val usingFallback = plannedDescriptions.isEmpty()
        val visibleDescriptions = plannedDescriptions.ifEmpty {
            fallbackSteps.map(String::trim).filter(String::isNotBlank)
        }
        if (visibleDescriptions.isEmpty()) return AgentInteractiveProgressPresentation.HIDDEN

        val terminal = completed || phase in TERMINAL_PHASES
        val steps = when {
            actionDescriptions.size >= 2 -> planActions
                .distinctBy { action -> normalizedIdentity(action.description) }
                .map { action ->
                    AgentInteractiveProgressStep(
                        text = action.description.trim(),
                        state = action.status.toProgressStepState()
                    )
                }
            usingFallback -> visibleDescriptions.mapIndexed { index, text ->
                AgentInteractiveProgressStep(
                    text = text,
                    state = when {
                        terminal -> AgentInteractiveProgressStepState.COMPLETED
                        index == 0 -> AgentInteractiveProgressStepState.ACTIVE
                        else -> AgentInteractiveProgressStepState.PENDING
                    }
                )
            }
            else -> visibleDescriptions.mapIndexed { index, text ->
                AgentInteractiveProgressStep(
                    text = text,
                    state = narrationStepState(
                        index = index,
                        lastIndex = visibleDescriptions.lastIndex,
                        terminal = terminal,
                        failed = phase in FAILED_PHASES,
                        declaredPlan = declaredPlan != null
                    )
                )
            }
        }
        if (steps.isEmpty()) return AgentInteractiveProgressPresentation.HIDDEN

        val activeIndex = steps.indexOfFirst { step ->
            step.state == AgentInteractiveProgressStepState.ACTIVE
        }
        val failedIndex = steps.indexOfFirst { step ->
            step.state == AgentInteractiveProgressStepState.FAILED
        }
        val pendingIndex = steps.indexOfFirst { step ->
            step.state == AgentInteractiveProgressStepState.PENDING
        }
        val currentIndex = when {
            activeIndex >= 0 -> activeIndex
            failedIndex >= 0 -> failedIndex
            pendingIndex >= 0 -> pendingIndex
            else -> steps.lastIndex
        }
        val activeAction = planActions.firstOrNull { action ->
            action.status in ACTIVE_ACTION_STATUSES
        }
        val nextAction = planActions.firstOrNull { action ->
            action.status in PENDING_ACTION_STATUSES
        }
        val summary = activeAction?.description
            .orEmpty()
            .ifBlank {
                if ((declaredPlan != null || usingFallback) && !terminal) {
                    steps[currentIndex].text
                } else {
                    narration.lastOrNull().orEmpty()
                }
            }
            .ifBlank { nextAction?.description.orEmpty() }
            .ifBlank { steps[currentIndex].text }
        val agentLabel = plan?.route?.targetTitle
            .orEmpty()
            .ifBlank { plan?.selectedAgentOrModel.orEmpty() }
        return AgentInteractiveProgressPresentation(
            visible = true,
            summary = summary,
            steps = steps,
            currentStep = currentIndex + 1,
            totalSteps = steps.size,
            completedSteps = steps.count { step ->
                step.state == AgentInteractiveProgressStepState.COMPLETED
            },
            running = !terminal,
            agentLabel = agentLabel,
            recentActivity = narration.takeLast(2)
        )
    }

    private fun isComplex(
        goal: String,
        plan: AgentPlan?,
        narrationCount: Int,
        fallbackStepsAvailable: Boolean
    ): Boolean {
        val requirements = AgentTaskRequirementAnalyzer.analyze(goal)
        val intent = AgentTaskIntentClassifier.classify(goal).intent
        val actionCount = plan?.actions.orEmpty().count { action ->
            !action.isTaskCompleteMarker() && action.description.isNotBlank()
        }
        return plan?.isSupervisedProjectPlan() == true ||
            actionCount >= 2 ||
            requirements.complexReasoning ||
            (intent in IMMEDIATE_COMPLEX_INTENTS && fallbackStepsAvailable) ||
            (intent in COMPLEX_INTENTS && (plan != null || narrationCount >= 2)) ||
            narrationCount >= 3
    }

    private fun splitPlanText(value: String): List<String> {
        val lines = value.lineSequence()
            .map(String::trim)
            .filter(String::isNotBlank)
            .toList()
        val listed = lines.mapNotNull { line ->
            PLAN_LINE_PREFIX.matchEntire(line)?.groupValues?.getOrNull(1)?.trim()
        }
        return if (listed.size >= 2) listed else listOf(value.trim())
    }

    private fun normalizedIdentity(value: String): String = value
        .trim()
        .replace(Regex("\\s+"), " ")
        .lowercase(Locale.ROOT)

    private fun AgentActionStatus.toProgressStepState(): AgentInteractiveProgressStepState = when (this) {
        AgentActionStatus.COMPLETED -> AgentInteractiveProgressStepState.COMPLETED
        AgentActionStatus.RUNNING,
        AgentActionStatus.WAITING_RESPONSE -> AgentInteractiveProgressStepState.ACTIVE
        AgentActionStatus.FAILED,
        AgentActionStatus.BLOCKED,
        AgentActionStatus.ROLLED_BACK -> AgentInteractiveProgressStepState.FAILED
        AgentActionStatus.PROPOSED,
        AgentActionStatus.PENDING_CONFIRMATION -> AgentInteractiveProgressStepState.PENDING
    }

    private fun narrationStepState(
        index: Int,
        lastIndex: Int,
        terminal: Boolean,
        failed: Boolean,
        declaredPlan: Boolean
    ): AgentInteractiveProgressStepState = when {
        terminal && failed && index == lastIndex -> AgentInteractiveProgressStepState.FAILED
        terminal -> AgentInteractiveProgressStepState.COMPLETED
        declaredPlan && index == 0 -> AgentInteractiveProgressStepState.ACTIVE
        declaredPlan -> AgentInteractiveProgressStepState.PENDING
        index < lastIndex -> AgentInteractiveProgressStepState.COMPLETED
        index == lastIndex -> AgentInteractiveProgressStepState.ACTIVE
        else -> AgentInteractiveProgressStepState.PENDING
    }

    private val PLAN_LINE_PREFIX = Regex(
        "^(?:[-*\\u2022]|\\d+[.)])\\s+(.+)$"
    )
    private val COMPLEX_INTENTS = setOf(
        AgentTaskIntent.CODE,
        AgentTaskIntent.PHONE_CONTROL,
        AgentTaskIntent.DESKTOP_CONTROL,
        AgentTaskIntent.RESEARCH,
        AgentTaskIntent.FILE,
        AgentTaskIntent.AUTOMATION
    )
    private val IMMEDIATE_COMPLEX_INTENTS = setOf(
        AgentTaskIntent.CODE,
        AgentTaskIntent.DESKTOP_CONTROL,
        AgentTaskIntent.AUTOMATION
    )
    private val ACTIVE_ACTION_STATUSES = setOf(
        AgentActionStatus.RUNNING,
        AgentActionStatus.WAITING_RESPONSE
    )
    private val PENDING_ACTION_STATUSES = setOf(
        AgentActionStatus.PROPOSED,
        AgentActionStatus.PENDING_CONFIRMATION
    )
    private val TERMINAL_PHASES = setOf(
        AgentPhase.COMPLETED,
        AgentPhase.FAILED,
        AgentPhase.CANCELLED,
        AgentPhase.BLOCKED
    )
    private val FAILED_PHASES = setOf(
        AgentPhase.FAILED,
        AgentPhase.CANCELLED,
        AgentPhase.BLOCKED
    )
}
