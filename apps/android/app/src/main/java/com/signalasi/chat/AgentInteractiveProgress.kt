package com.signalasi.chat

import java.util.Locale

internal enum class AgentInteractiveProgressStepState {
    PENDING,
    ACTIVE,
    COMPLETED,
    SUPERSEDED,
    FAILED
}

internal data class AgentInteractiveProgressStep(
    val text: String,
    val state: AgentInteractiveProgressStepState,
    val actionId: String = "",
    val planRevision: Int = 1
)

internal data class AgentInteractiveProgressBatch(
    val planRevision: Int,
    val steps: List<AgentInteractiveProgressStep>,
    val current: Boolean
)

internal data class AgentInteractiveProgressPresentation(
    val visible: Boolean,
    val summary: String,
    val steps: List<AgentInteractiveProgressStep>,
    val batches: List<AgentInteractiveProgressBatch>,
    val currentStep: Int,
    val totalSteps: Int,
    val completedSteps: Int,
    val planRevision: Int,
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
            batches = emptyList(),
            currentStep = 0,
            totalSteps = 0,
            completedSteps = 0,
            planRevision = 1,
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
        completed: Boolean
    ): AgentInteractiveProgressPresentation {
        val declaredPlan = processTexts.singleOrNull()
            ?.let(::splitPlanText)
            ?.takeIf { lines -> lines.size >= 2 }
        val narration = processTexts
            .flatMap(::splitPlanText)
            .map(String::trim)
            .filter(String::isNotBlank)
            .distinctBy(::normalizedIdentity)
        val currentActionIds = plan?.actions.orEmpty().mapTo(hashSetOf(), AgentAction::id)
        val planActions = plan?.let { current ->
            AgentProjectHistoryRetentionPolicy.latestSnapshots(current.actionHistory + current.actions)
        }.orEmpty()
            .filterNot(AgentAction::isTaskCompleteMarker)
            .filter { action -> action.description.isNotBlank() }
        val actionDescriptions = planActions
            .map(AgentAction::description)
            .distinctBy(::normalizedIdentity)
        val plannedDescriptions = when {
            actionDescriptions.size >= 2 -> actionDescriptions
            narration.size >= 2 -> narration
            else -> (actionDescriptions + narration).distinctBy(::normalizedIdentity)
        }
        if (!isComplex(goal, plan, narration.size)) {
            return AgentInteractiveProgressPresentation.HIDDEN
        }
        val visibleDescriptions = plannedDescriptions
        if (visibleDescriptions.isEmpty()) return AgentInteractiveProgressPresentation.HIDDEN

        val terminal = completed || phase in TERMINAL_PHASES
        val checkpointRevisions = plan?.checkpoints.orEmpty()
            .associate { checkpoint -> checkpoint.actionId to checkpoint.planRevision }
        val steps = when {
            planActions.isNotEmpty() -> {
                var carriedRevision = 1
                planActions.map { action ->
                    val revision = when {
                        action.id in currentActionIds -> plan?.revision ?: carriedRevision
                        else -> action.planRevision(checkpointRevisions, carriedRevision)
                    }.coerceIn(1, plan?.revision?.coerceAtLeast(1) ?: Int.MAX_VALUE)
                    carriedRevision = maxOf(carriedRevision, revision)
                    val superseded = revision < (plan?.revision ?: revision)
                    AgentInteractiveProgressStep(
                        text = action.description.trim(),
                        state = action.status.toProgressStepState(superseded),
                        actionId = action.id,
                        planRevision = revision
                    )
                }
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
                    ),
                    planRevision = 1
                )
            }
        }
        if (steps.isEmpty()) return AgentInteractiveProgressPresentation.HIDDEN

        val batches = steps
            .groupByTo(linkedMapOf(), AgentInteractiveProgressStep::planRevision)
            .map { (revision, batchSteps) ->
                AgentInteractiveProgressBatch(
                    planRevision = revision,
                    steps = batchSteps,
                    current = revision == (plan?.revision ?: revision)
                )
            }
        val currentBatch = batches.firstOrNull(AgentInteractiveProgressBatch::current)
            ?: batches.last()
        val currentBatchSteps = currentBatch.steps

        val activeIndex = currentBatchSteps.indexOfFirst { step ->
            step.state == AgentInteractiveProgressStepState.ACTIVE
        }
        val failedIndex = currentBatchSteps.indexOfFirst { step ->
            step.state == AgentInteractiveProgressStepState.FAILED
        }
        val pendingIndex = currentBatchSteps.indexOfFirst { step ->
            step.state == AgentInteractiveProgressStepState.PENDING
        }
        val currentIndex = when {
            activeIndex >= 0 -> activeIndex
            failedIndex >= 0 -> failedIndex
            pendingIndex >= 0 -> pendingIndex
            else -> currentBatchSteps.lastIndex
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
                if (declaredPlan != null && !terminal) {
                    currentBatchSteps[currentIndex].text
                } else {
                    narration.lastOrNull().orEmpty()
                }
            }
            .ifBlank { nextAction?.description.orEmpty() }
            .ifBlank { currentBatchSteps[currentIndex].text }
        val agentLabel = plan?.route?.targetTitle
            .orEmpty()
            .ifBlank { plan?.selectedAgentOrModel.orEmpty() }
        return AgentInteractiveProgressPresentation(
            visible = true,
            summary = summary,
            steps = steps,
            batches = batches,
            currentStep = currentIndex + 1,
            totalSteps = currentBatchSteps.size,
            completedSteps = steps.count { step ->
                step.state == AgentInteractiveProgressStepState.COMPLETED
            },
            planRevision = plan?.revision?.coerceAtLeast(1) ?: currentBatch.planRevision,
            running = !terminal,
            agentLabel = agentLabel,
            recentActivity = narration.takeLast(2)
        )
    }

    private fun isComplex(
        goal: String,
        plan: AgentPlan?,
        narrationCount: Int
    ): Boolean {
        val requirements = AgentTaskRequirementAnalyzer.analyze(goal)
        val intent = AgentTaskIntentClassifier.classify(goal).intent
        val actionCount = plan?.actions.orEmpty().count { action ->
            !action.isTaskCompleteMarker() && action.description.isNotBlank()
        }
        return plan?.isSupervisedProjectPlan() == true ||
            actionCount >= 2 ||
            requirements.complexReasoning ||
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

    private fun AgentActionStatus.toProgressStepState(
        superseded: Boolean
    ): AgentInteractiveProgressStepState = when (this) {
        AgentActionStatus.COMPLETED -> AgentInteractiveProgressStepState.COMPLETED
        AgentActionStatus.RUNNING,
        AgentActionStatus.WAITING_RESPONSE -> AgentInteractiveProgressStepState.ACTIVE
        AgentActionStatus.FAILED,
        AgentActionStatus.BLOCKED,
        AgentActionStatus.ROLLED_BACK -> if (superseded) {
            AgentInteractiveProgressStepState.SUPERSEDED
        } else {
            AgentInteractiveProgressStepState.FAILED
        }
        AgentActionStatus.PROPOSED,
        AgentActionStatus.PENDING_CONFIRMATION -> AgentInteractiveProgressStepState.PENDING
    }

    private fun AgentAction.planRevision(
        checkpointRevisions: Map<String, Int>,
        fallback: Int
    ): Int = parameters[PLAN_REVISION_PARAMETER]
        ?.toIntOrNull()
        ?: checkpointRevisions[id]
        ?: ACTION_REVISION_PREFIX.find(id)?.groupValues?.getOrNull(1)?.toIntOrNull()
        ?: SUPERVISED_REVISION_ID.find(id)?.groupValues?.getOrNull(1)?.toIntOrNull()
        ?: fallback

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
    private val ACTION_REVISION_PREFIX = Regex("^(?:r|sp)(\\d+)-")
    private val SUPERVISED_REVISION_ID = Regex(
        "^supervise-phone-project-(?:recovery|format|progress|completion)-(\\d+)-"
    )
    private const val PLAN_REVISION_PARAMETER = "plan_revision"
    private val COMPLEX_INTENTS = setOf(
        AgentTaskIntent.CODE,
        AgentTaskIntent.PHONE_CONTROL,
        AgentTaskIntent.DESKTOP_CONTROL,
        AgentTaskIntent.RESEARCH,
        AgentTaskIntent.FILE,
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
