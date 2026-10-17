package com.galaxyssi.chat

import java.util.Locale

internal enum class AgentInteractiveProgressStepState {
    PENDING,
    ACTIVE,
    WAITING,
    PAUSED,
    STOPPED,
    NOT_EXECUTED,
    RECORDED,
    COMPLETED,
    SUPERSEDED,
    FAILED
}

internal enum class AgentInteractiveProgressStatus {
    RUNNING, WAITING_RESPONSE, WAITING_CONFIRMATION, PAUSED, BLOCKED,
    FAILED, CANCELLED, COMPLETED, UNKNOWN;

    val animating: Boolean
        get() = this == RUNNING || this == WAITING_RESPONSE

    companion object {
        fun from(phase: AgentPhase?, completed: Boolean): AgentInteractiveProgressStatus = when (phase) {
            AgentPhase.OBSERVING, AgentPhase.PLANNING, AgentPhase.EXECUTING,
            AgentPhase.VERIFYING -> RUNNING
            AgentPhase.WAITING_RESPONSE -> WAITING_RESPONSE
            AgentPhase.WAITING_CONFIRMATION -> WAITING_CONFIRMATION
            AgentPhase.PAUSED -> PAUSED
            AgentPhase.BLOCKED -> BLOCKED
            AgentPhase.FAILED -> FAILED
            AgentPhase.CANCELLED -> CANCELLED
            AgentPhase.COMPLETED -> COMPLETED
            null -> if (completed) COMPLETED else UNKNOWN
        }
    }
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
    val status: AgentInteractiveProgressStatus,
    val agentLabel: String,
    val recentActivity: List<String>
) {
    val running: Boolean
        get() = status.animating

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
            status = AgentInteractiveProgressStatus.UNKNOWN,
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
        fallbackPhase: AgentPhase? = null
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

        // An owned runtime phase takes precedence over an older completion hint.
        val resolvedPhase = phase ?: fallbackPhase?.takeUnless {
            completed && AgentInteractiveProgressStatus.from(it, false).animating
        }
        val status = AgentInteractiveProgressStatus.from(resolvedPhase, completed)
        val checkpointRevisions = plan?.checkpoints.orEmpty()
            .associate { checkpoint -> checkpoint.actionId to checkpoint.planRevision }
        val steps = when {
            planActions.isNotEmpty() -> {
                var carriedRevision = 1
                planActions.map { action ->
                    val explicitRevision = action.planRevisionOrNull(checkpointRevisions)
                    val revision = when {
                        explicitRevision != null -> explicitRevision
                        action.id in currentActionIds -> plan?.revision ?: carriedRevision
                        else -> carriedRevision
                    }.coerceIn(1, plan?.revision?.coerceAtLeast(1) ?: Int.MAX_VALUE)
                    carriedRevision = maxOf(carriedRevision, revision)
                    val superseded = revision < (plan?.revision ?: revision)
                    AgentInteractiveProgressStep(
                        text = action.description.trim(),
                        state = action.status.toProgressStepState(superseded, status),
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
                        status = status,
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
            step.state in CURRENT_STEP_STATES
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
        val activeAction = currentBatchSteps.firstOrNull { it.state in CURRENT_STEP_STATES }
            ?.takeIf { status.animating }
        val nextAction = currentBatchSteps.firstOrNull { it.state == AgentInteractiveProgressStepState.PENDING }
        val summary = activeAction?.text
            .orEmpty()
            .ifBlank {
                if (declaredPlan != null && status.animating) {
                    currentBatchSteps[currentIndex].text
                } else {
                    narration.lastOrNull().orEmpty()
                }
            }
            .ifBlank { nextAction?.text.orEmpty() }
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
            status = status,
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
        superseded: Boolean,
        status: AgentInteractiveProgressStatus
    ): AgentInteractiveProgressStepState = when (this) {
        AgentActionStatus.COMPLETED -> AgentInteractiveProgressStepState.COMPLETED
        AgentActionStatus.RUNNING,
        AgentActionStatus.WAITING_RESPONSE -> if (superseded) {
            AgentInteractiveProgressStepState.SUPERSEDED
        } else when (status) {
            AgentInteractiveProgressStatus.RUNNING -> if (this == AgentActionStatus.WAITING_RESPONSE) {
                AgentInteractiveProgressStepState.WAITING
            } else AgentInteractiveProgressStepState.ACTIVE
            AgentInteractiveProgressStatus.WAITING_RESPONSE,
            AgentInteractiveProgressStatus.WAITING_CONFIRMATION,
            AgentInteractiveProgressStatus.BLOCKED -> AgentInteractiveProgressStepState.WAITING
            AgentInteractiveProgressStatus.PAUSED -> AgentInteractiveProgressStepState.PAUSED
            AgentInteractiveProgressStatus.FAILED,
            AgentInteractiveProgressStatus.CANCELLED -> AgentInteractiveProgressStepState.STOPPED
            AgentInteractiveProgressStatus.COMPLETED,
            AgentInteractiveProgressStatus.UNKNOWN -> AgentInteractiveProgressStepState.RECORDED
        }
        AgentActionStatus.FAILED,
        AgentActionStatus.BLOCKED,
        AgentActionStatus.ROLLED_BACK -> if (superseded) {
            AgentInteractiveProgressStepState.SUPERSEDED
        } else {
            AgentInteractiveProgressStepState.FAILED
        }
        AgentActionStatus.PROPOSED,
        AgentActionStatus.PENDING_CONFIRMATION -> if (status in FINISHED_STATUSES) {
            AgentInteractiveProgressStepState.NOT_EXECUTED
        } else AgentInteractiveProgressStepState.PENDING
    }

    private fun AgentAction.planRevisionOrNull(
        checkpointRevisions: Map<String, Int>
    ): Int? = parameters[PLAN_REVISION_PARAMETER]
        ?.toIntOrNull()
        ?: checkpointRevisions[id]
        ?: ACTION_REVISION_PREFIX.find(id)?.groupValues?.getOrNull(1)?.toIntOrNull()
        ?: SUPERVISED_REVISION_ID.find(id)?.groupValues?.getOrNull(1)?.toIntOrNull()

    private fun narrationStepState(
        index: Int,
        lastIndex: Int,
        status: AgentInteractiveProgressStatus,
        declaredPlan: Boolean
    ): AgentInteractiveProgressStepState = when {
        declaredPlan && index > 0 -> AgentActionStatus.PROPOSED.toProgressStepState(false, status)
        !declaredPlan && index < lastIndex -> AgentInteractiveProgressStepState.RECORDED
        else -> AgentActionStatus.RUNNING.toProgressStepState(false, status)
    }

    private val PLAN_LINE_PREFIX = Regex(
        "^(?:[-*\\u2022]|\\d+[.)])\\s+(.+)$"
    )
    private val ACTION_REVISION_PREFIX = Regex("^(?:r|sp)(\\d+)-")
    private val SUPERVISED_REVISION_ID = Regex(
        "^supervise-phone-project-(?:recovery|format|progress|completion)-(\\d+)-"
    )
    private val COMPLEX_INTENTS = setOf(
        AgentTaskIntent.CODE,
        AgentTaskIntent.PHONE_CONTROL,
        AgentTaskIntent.DESKTOP_CONTROL,
        AgentTaskIntent.RESEARCH,
        AgentTaskIntent.FILE,
        AgentTaskIntent.AUTOMATION
    )
    private val CURRENT_STEP_STATES = setOf(
        AgentInteractiveProgressStepState.ACTIVE,
        AgentInteractiveProgressStepState.WAITING,
        AgentInteractiveProgressStepState.PAUSED,
        AgentInteractiveProgressStepState.STOPPED
    )
    private val FINISHED_STATUSES = setOf(
        AgentInteractiveProgressStatus.COMPLETED,
        AgentInteractiveProgressStatus.CANCELLED,
        AgentInteractiveProgressStatus.FAILED
    )
}
