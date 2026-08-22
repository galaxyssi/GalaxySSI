package com.signalasi.chat

internal object AgentSessionPersistencePolicy {
    const val MAX_SESSION_JSON_CHARACTERS = 96 * 1024
    internal const val MAX_ENCRYPTED_SESSION_CHARACTERS = 192 * 1024
    internal const val MAX_GENERAL_TEXT_CHARACTERS = 8 * 1024
    internal const val MAX_ACTION_TEXT_CHARACTERS = 4 * 1024
    internal const val MAX_AUDIT_TEXT_CHARACTERS = 1 * 1024
    internal const val MAX_METADATA_ENTRIES = 24
    internal const val MAX_METADATA_VALUE_CHARACTERS = 2 * 1024
    internal const val MAX_SCREEN_LABEL_CHARACTERS = 512

    private val RECOVERABLE_ACTION_STATUSES = setOf(
        AgentActionStatus.PROPOSED,
        AgentActionStatus.PENDING_CONFIRMATION,
        AgentActionStatus.RUNNING,
        AgentActionStatus.WAITING_RESPONSE,
        AgentActionStatus.FAILED,
        AgentActionStatus.BLOCKED
    )

    fun actionHistory(plan: AgentPlan): List<AgentAction> =
        if (plan.isSupervisedProjectPlan()) {
            AgentProjectHistoryRetentionPolicy.retainForPersistence(plan.actionHistory)
        } else {
            plan.actionHistory.takeLast(MAX_NON_PROJECT_ACTION_HISTORY)
        }

    fun shouldDiscardEncodedValue(encodedLength: Int): Boolean =
        encodedLength > MAX_ENCRYPTED_SESSION_CHARACTERS

    fun compactText(value: String): String = value.take(MAX_GENERAL_TEXT_CHARACTERS)

    fun compactActionText(value: String): String = value.take(MAX_ACTION_TEXT_CHARACTERS)

    fun compactAuditText(value: String): String = value.take(MAX_AUDIT_TEXT_CHARACTERS)

    fun compactMetadata(metadata: Map<String, String>): Map<String, String> = metadata.entries
        .sortedBy { (key, _) -> if (key in RECOVERY_METADATA_KEYS) 0 else 1 }
        .take(MAX_METADATA_ENTRIES)
        .associate { (key, value) ->
            key.take(128) to value.take(MAX_METADATA_VALUE_CHARACTERS)
        }

    private val RECOVERY_METADATA_KEYS = setOf(
        "delivery_failed",
        "source_message_id",
        "awaiting_response",
        "contact_id",
        "resource_id",
        "failure_domain",
        "resource_started_at",
        "handoff_recovery_attempt",
        "depends_on",
        "use_outputs_from",
        "tool_id",
        "workspace_id",
        "repository_url",
        "working_directory",
        "command"
    )

    private const val MAX_NON_PROJECT_ACTION_HISTORY = 24

    fun compactRecoveryPlan(
        plan: AgentPlan,
        lastActionId: String,
        minimal: Boolean = false
    ): AgentPlan {
        val actionLimit = if (minimal) MINIMAL_RECOVERY_ACTIONS else MAX_RECOVERY_ACTIONS
        val anchorIds = linkedSetOf<String>().apply {
            fun addWithinLimit(id: String?) {
                id?.takeIf(String::isNotBlank)?.let { value -> if (size < actionLimit) add(value) }
            }
            addWithinLimit(lastActionId)
            addWithinLimit(plan.actions.firstOrNull { it.status == AgentActionStatus.RUNNING }?.id)
            addWithinLimit(plan.actions.firstOrNull { it.status == AgentActionStatus.WAITING_RESPONSE }?.id)
            toList().forEach { id ->
                plan.actions.firstOrNull { it.id == id }
                    ?.let(::recoveryDependencyIds)
                    .orEmpty()
                    .forEach(::addWithinLimit)
            }
            addWithinLimit(plan.actions.firstOrNull { it.status == AgentActionStatus.FAILED }?.id)
            addWithinLimit(plan.actions.firstOrNull { it.status == AgentActionStatus.BLOCKED }?.id)
            addWithinLimit(plan.actions.firstOrNull { it.status == AgentActionStatus.PENDING_CONFIRMATION }?.id)
        }
        val selectedIds = linkedSetOf<String>().apply {
            addAll(anchorIds)
            plan.actions.asSequence()
                .filter { it.status in RECOVERABLE_ACTION_STATUSES }
                .map(AgentAction::id)
                .forEach { id -> if (size < actionLimit) add(id) }
            plan.actions.asReversed().asSequence()
                .filter { it.status == AgentActionStatus.COMPLETED || it.status == AgentActionStatus.ROLLED_BACK }
                .map(AgentAction::id)
                .forEach { id -> if (size < actionLimit) add(id) }
        }
        val selectedActions = selectedIds
            .take(actionLimit)
            .mapNotNull { selectedId -> plan.actions.firstOrNull { it.id == selectedId } }
            .ifEmpty { plan.actions.take(1) }
            .map { compactRecoveryAction(it, minimal) }
        val retainedActionIds = selectedActions.mapTo(linkedSetOf(), AgentAction::id)
        val historyLimit = if (minimal) MINIMAL_RECOVERY_HISTORY else MAX_RECOVERY_HISTORY
        val selectedHistory = buildList {
            plan.actionHistory.filter { it.id in anchorIds }.forEach(::add)
            plan.actionHistory.takeLast(historyLimit).forEach(::add)
        }.distinctBy { action -> listOf(action.id, action.status.name, action.result) }
            .takeLast(historyLimit)
            .map { compactRecoveryAction(it, minimal) }
        val verificationLimit = if (minimal) 1 else MAX_RECOVERY_VERIFICATIONS
        val selectedVerifications = buildList {
            plan.verificationResults.filter { it.actionId in retainedActionIds }.forEach(::add)
            plan.verificationResults.takeLast(verificationLimit).forEach(::add)
        }.distinctBy { result -> result.actionId to result.timestampMillis }
            .takeLast(verificationLimit)
            .map { result ->
                result.copy(
                    observedApp = result.observedApp.take(256),
                    observedTitle = result.observedTitle.take(256),
                    evidence = result.evidence.take(if (minimal) 256 else MAX_RECOVERY_RESULT_CHARACTERS)
                )
            }
        val checkpointLimit = if (minimal) 1 else MAX_RECOVERY_CHECKPOINTS
        val selectedCheckpoints = buildList {
            plan.checkpoints.filter {
                it.status == AgentCheckpointStatus.ACTIVE || it.actionId in retainedActionIds
            }.forEach(::add)
            plan.checkpoints.takeLast(checkpointLimit).forEach(::add)
        }.distinctBy(AgentExecutionCheckpoint::id)
            .takeLast(checkpointLimit)
            .map { checkpoint ->
                checkpoint.copy(
                    id = checkpoint.id.take(256),
                    actionId = checkpoint.actionId.take(512),
                    foregroundApp = checkpoint.foregroundApp.take(256),
                    activityName = checkpoint.activityName.take(256),
                    pageTitle = checkpoint.pageTitle.take(256),
                    screenDigest = checkpoint.screenDigest.take(512),
                    rollbackAction = checkpoint.rollbackAction?.let { compactRecoveryAction(it, minimal) }
                )
            }
        val artifacts = AgentRuntimeArtifactUi.mergeArtifactOutputs(plan.artifactRichOutputJson)
            .takeIf { it.length <= MAX_RECOVERY_ARTIFACT_CHARACTERS }
            .orEmpty()
        return plan.copy(
            goal = plan.goal.take(if (minimal) 1_024 else 4_096),
            screen = compactScreen(plan.screen),
            steps = plan.steps.take(MAX_RECOVERY_STEPS),
            actions = selectedActions,
            planId = plan.planId.take(512),
            selectedAgentOrModel = plan.selectedAgentOrModel.take(512),
            requiredPermissions = plan.requiredPermissions.take(if (minimal) 4 else 12).map { permission ->
                permission.copy(id = permission.id.take(256), title = permission.title.take(512))
            },
            rollbackStrategy = plan.rollbackStrategy.take(if (minimal) 256 else 1_024),
            expectedResult = plan.expectedResult.take(if (minimal) 512 else 2_048),
            plannerProfile = plan.plannerProfile.take(256),
            contextDigest = plan.contextDigest.take(if (minimal) 512 else 2_048),
            routeRationale = plan.routeRationale.take(if (minimal) 512 else 2_048),
            route = plan.route.copy(
                routeId = plan.route.routeId.take(256),
                targetId = plan.route.targetId.take(256),
                targetTitle = plan.route.targetTitle.take(512),
                deliveryMode = plan.route.deliveryMode.take(128),
                capabilities = plan.route.capabilities.distinct().take(16),
                executionDeviceId = plan.route.executionDeviceId.take(256),
                executionDeviceName = plan.route.executionDeviceName.take(256)
            ),
            validation = plan.validation.copy(
                issues = plan.validation.issues.take(if (minimal) 2 else 8).map { it.take(512) }
            ),
            verificationResults = selectedVerifications,
            safetyReview = plan.safetyReview.copy(
                deniedPermissions = plan.safetyReview.deniedPermissions.take(8).map { it.take(256) },
                warnings = plan.safetyReview.warnings.take(if (minimal) 2 else 8).map { it.take(512) },
                reason = plan.safetyReview.reason.take(if (minimal) 256 else 1_024)
            ),
            actionHistory = selectedHistory,
            checkpoints = selectedCheckpoints,
            artifactRichOutputJson = artifacts
        )
    }

    fun compactExecutionLoop(
        snapshot: AgentExecutionLoopSnapshot,
        minimal: Boolean = false
    ): AgentExecutionLoopSnapshot = snapshot.copy(
        taskId = snapshot.taskId.take(512),
        lastActionId = snapshot.lastActionId.take(512),
        lastReason = snapshot.lastReason.take(if (minimal) 256 else 1_024),
        budgetFailure = snapshot.budgetFailure.take(if (minimal) 256 else 1_024),
        taskIntentSignals = snapshot.taskIntentSignals.take(if (minimal) 2 else 8).map { it.take(256) },
        failureCounts = snapshot.failureCounts.entries.take(if (minimal) 4 else 16).associate { (key, value) ->
            key.take(256) to value
        }
    )

    private fun compactRecoveryAction(action: AgentAction, minimal: Boolean): AgentAction = action.copy(
        id = action.id.take(512),
        target = action.target.take(512),
        description = action.description.take(if (minimal) 256 else 1_024),
        parameters = compactMetadata(action.parameters).entries
            .take(if (minimal) 8 else MAX_RECOVERY_METADATA_ENTRIES)
            .associate { (key, value) -> key to value.take(if (minimal) 256 else 1_024) },
        result = action.result.take(if (minimal) 256 else MAX_RECOVERY_RESULT_CHARACTERS),
        evidence = action.evidence.take(if (minimal) 256 else MAX_RECOVERY_RESULT_CHARACTERS)
    )

    private fun recoveryDependencyIds(action: AgentAction): List<String> = listOf(
        action.parameters["depends_on"],
        action.parameters["use_outputs_from"]
    ).filterNotNull()
        .flatMap { value -> value.split(',', ';', '\n') }
        .map(String::trim)
        .filter(String::isNotBlank)
        .distinct()
        .take(4)

    private const val MAX_RECOVERY_ACTIONS = 16
    private const val MINIMAL_RECOVERY_ACTIONS = 4
    private const val MAX_RECOVERY_HISTORY = 8
    private const val MINIMAL_RECOVERY_HISTORY = 2
    private const val MAX_RECOVERY_STEPS = 12
    private const val MAX_RECOVERY_VERIFICATIONS = 4
    private const val MAX_RECOVERY_CHECKPOINTS = 4
    private const val MAX_RECOVERY_METADATA_ENTRIES = 16
    private const val MAX_RECOVERY_RESULT_CHARACTERS = 1_024
    private const val MAX_RECOVERY_ARTIFACT_CHARACTERS = 16 * 1_024

    fun compactScreen(screen: ScreenContext): ScreenContext = screen.copy(
        foregroundApp = screen.foregroundApp.take(256),
        activityName = screen.activityName.take(256),
        pageTitle = screen.pageTitle.take(256),
        visibleTexts = emptyList(),
        selectedText = screen.selectedText.take(MAX_SCREEN_LABEL_CHARACTERS),
        focusedInputField = screen.focusedInputField?.copy(
            label = screen.focusedInputField.label.take(MAX_SCREEN_LABEL_CHARACTERS),
            viewId = screen.focusedInputField.viewId.take(256),
            className = screen.focusedInputField.className.take(256),
            bounds = screen.focusedInputField.bounds.take(128)
        ),
        clickableElements = emptyList(),
        inputFields = emptyList(),
        scrollableRegions = emptyList(),
        sensitiveFlags = screen.sensitiveFlags.take(8).map { it.take(128) },
        visualScene = screen.visualScene.copy(
            modelProfile = screen.visualScene.modelProfile.take(128),
            elements = emptyList()
        ),
        clipboard = ClipboardContext(),
        notifications = AgentNotificationContext(
            hasAccess = screen.notifications.hasAccess,
            totalCount = screen.notifications.totalCount
        ),
        installedApps = emptyList(),
        deviceStatus = screen.deviceStatus.copy(network = screen.deviceStatus.network.take(64))
    )
}
