package com.galaxyssi.chat

import android.content.Context
import java.util.UUID

/** Reuses the normal phone Agent, scoped tool gate, task journal and connector delivery path. */
internal object HealthCareResearchRuntime {
    fun preview(context: Context, concernId: String): HealthCareDiscussionPreview {
        val conversation = HealthCareDiscussion.open(context, concernId)
        return HealthCareDiscussion.prepare(context, conversation, context.getString(R.string.health_research_question), context(context))
    }

    private fun context(app: Context): AgentRuntimeContext {
        val screen = ScreenContext(app.packageName, pageTitle = "Health research")
        val tools = AgentPhoneNativeToolCatalog.defaultRegistry(app, { screen }).descriptors()
            .filter { it.id in HealthCareDiscussionPolicy.discussionTools }
        return AgentRuntimeContext(UUID.randomUUID().toString(), "", screen, PermissionMode.OBSERVE_ONLY, true, false,
            emptyList(), nativeTools = tools, callableTargets = emptyList(), memories = emptyList(), knowledgeItems = emptyList(),
            knowledgeStats = AgentKnowledgeStats())
    }

    fun authorize(context: Context, preview: HealthCareDiscussionPreview, expectedId: String?) {
        val grant = preview.grant
        val fingerprint = HealthCareDiscussion.configurationFingerprint(context, grant.conversationId, grant.targetId)
        check(AgentModelSelectionSettings.selection(context, grant.conversationId) == preview.selection &&
            AgentModelSelectionSettings.configurationForTarget(context, grant.conversationId, grant.targetId) == preview.configuration)
        val authorization = HealthCareResearchAuthorization(UUID.randomUUID().toString(), grant, fingerprint)
        check(bindingCurrent(context, authorization)) { context.getString(R.string.health_care_changed) }
        HealthCareStore(context).use { it.authorizeResearch(authorization, expectedId) }
        HealthCareResearchWork.changed(context)
    }

    fun bindingCurrent(context: Context, value: HealthCareResearchAuthorization): Boolean {
        val scope = value.scope
        val privacy = HealthPrivacyStore(context).use { it.policy() }
        val conversation = AgentTranscriptStore(context).conversation(scope.conversationId)
        return value.active && privacy.metrics && privacy.profile && privacy.version == scope.privacyVersion &&
            (scope.targetId == "local-llm" || privacy.online) && conversation?.status == AgentConversationStatus.ACTIVE &&
            conversation.privateMode && conversation.trackingPaused &&
            value.configuration == HealthCareDiscussion.configurationFingerprint(context, scope.conversationId, scope.targetId) &&
            runCatching { HealthCareDiscussion.destination(context, scope.targetId, scope.modelId) == scope.destination }.getOrDefault(false)
    }

    fun prepare(context: Context, job: HealthCareResearchJob, authorization: HealthCareResearchAuthorization): HealthCareDiscussionPreview {
        val preview = HealthCareDiscussion.prepare(context, job.conversationId, context.getString(R.string.health_research_question),
            context(context), authorization, job.turnId)
        val existing = HealthCareStore(context).use { it.discussionGrant(job.turnId) }
        if (existing == null) return preview
        check(existing.copy(approvedAt = preview.grant.approvedAt) == preview.grant &&
            System.currentTimeMillis() - existing.approvedAt in 0 until HealthCareDiscussionPolicy.MAX_APPROVAL_AGE) {
            context.getString(R.string.health_care_discussion_expired)
        }
        return preview.copy(grant = existing)
    }

    suspend fun launch(context: Context, job: HealthCareResearchJob, preview: HealthCareDiscussionPreview) {
        HealthCareDiscussion.approve(context, preview)
        val transcripts = AgentTranscriptStore(context)
        val history = transcripts.context(job.conversationId, excludeTurnId = job.turnId)
        check(history.conversationId == job.conversationId && history.privateMode && history.trackingPaused)
        val goal = HealthCareDiscussionPolicy.prompt(preview.question, preview.snapshot)
        transcripts.append(AgentTranscriptRole.USER, context.getString(R.string.health_research_requested),
            dedupeKey = "health-research:${job.turnId}", conversationId = job.conversationId, turnId = job.turnId, taskId = job.turnId)
        val supervisor = AgentTaskRuntime.supervisor(context)
        val workspace = AgentWorkspace(job.turnId, job.turnId, job.conversationId, job.turnId,
            goal = goal, agentId = preview.grant.targetId, deviceId = AppStore.localDeviceRouteId(context))
        val handle = supervisor.submit(workspace, AgentTaskLane.READ_REASONING, AgentTaskPriority.BACKGROUND) {
            HealthCareStore(context).use { store ->
                val current = store.researchJob(job.turnId) ?: throw HealthCareConflict()
                check(!current.terminal && HealthCareDiscussion.rejection(context, job.conversationId, job.turnId) == null)
                store.updateResearchJob(current, HealthCareResearchState.DISPATCHED)
            }
            val runtime = MobileNativeAgent(context, planner = AgentSelectedNativeActionPlanner(preview.action),
                sessionStore = SharedPreferencesAgentSessionStore(context, "task:${job.turnId}"), screenObservationOverride = false,
                executionLoopEventSink = AgentExecutionLoopEventSink { persistExecutionLoop(it) })
            var state = try {
                var next = runtime.submitGoal(goal, history, job.turnId)
                while (next.pendingAction != null && next.phase != AgentPhase.WAITING_RESPONSE) {
                    cancellationSource.throwIfCancellationRequested()
                    next = runtime.approveNextAction(highRiskConfirmed = true)
                }
                next
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (failure: Exception) { runtime.failSubmission(failure.message ?: "Health research execution failed") }
            state = finalizeAgentExecution(runtime, job.turnId, state, AgentExecutionRunRecorder(context, runtime)::recordAgentRunFromState)
            runtime.persistSession()
            val metadata = state.lastActionResult?.metadata.orEmpty()
            metadata["source_message_id"]?.toLongOrNull()?.takeIf { it > 0 }?.let { source ->
                AgentPendingDeliveryStore.put(context, AgentPendingDelivery(source, job.conversationId, job.turnId,
                    metadata["remote_task_id"].orEmpty().ifBlank { job.turnId }, metadata["contact_id"].orEmpty()))
                AndroidAgentRecoveryWake.request(context)
            }
            checkpoint(AgentRecoveryTranscript.CHECKPOINT_ID, stateJson = AgentRecoveryTranscript.pendingCheckpoint(workspace(),
                checkNotNull(SharedPreferencesAgentSessionStore(context, "task:${job.turnId}").load())))
            AgentRecoveryTranscript.project(context, workspace(), state, transcripts)
            context.persistAgentWorkspaceSnapshot(job.turnId, state, runtime, required = true)
            checkpoint(AgentRecoveryTranscript.CHECKPOINT_ID, stateJson = "{\"pending\":false}")
            when (state.phase) {
                AgentPhase.WAITING_RESPONSE -> waitForResponse(state.lastActionResult?.message.orEmpty())
                AgentPhase.WAITING_CONFIRMATION -> waitForConfirmation(state.pendingAction?.description.orEmpty())
                AgentPhase.PAUSED -> pause(state.lastActionResult?.message.orEmpty())
                AgentPhase.BLOCKED -> blockTask(AgentBlockedStatePolicy.reason(state))
                AgentPhase.FAILED -> transition(AgentWorkspaceStatus.FAILED, AgentTaskEventKinds.FAILED, state.lastActionResult?.message.orEmpty())
                AgentPhase.CANCELLED -> transition(AgentWorkspaceStatus.CANCELLED, AgentTaskEventKinds.CANCELLED, "Health research cancelled")
                AgentPhase.COMPLETED -> Unit
                else -> pause("Health research checkpoint retained for recovery")
            }
        }
        handle.join()
        val finished = supervisor.findWorkspace(job.turnId)
        if (finished?.status?.isTerminal == true) HealthCareStore(context).use { care ->
            care.researchJob(job.turnId)?.takeUnless { it.terminal }?.let {
                val status = if (finished.status == AgentWorkspaceStatus.COMPLETED && it.state == HealthCareResearchState.DISPATCHED)
                    HealthCareResearchState.COMPLETED else HealthCareResearchState.FAILED
                care.updateResearchJob(it, status, finished.errorMessage.ifBlank {
                    if (status == HealthCareResearchState.FAILED) context.getString(R.string.health_research_interrupted) else ""
                })
            }
        }
    }
}
