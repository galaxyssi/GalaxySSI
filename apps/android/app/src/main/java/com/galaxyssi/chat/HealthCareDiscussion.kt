package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject
import java.util.UUID

internal data class HealthCareDiscussionPreview(val concern: HealthCareConcern, val grant: HealthCareDiscussionGrant,
    val target: AgentCallableTarget, val snapshot: String, val question: String, val action: AgentAction,
    val selection: AgentModelSelection, val configuration: AgentTargetConfiguration?)

/** A discussion grants one provider one turn, not access to the user's complete health archive. */
internal object HealthCareDiscussion {
    fun open(context: Context, concernId: String, names: HealthOverviewDatabases = HealthOverviewDatabases()): String = synchronized(this) {
        HealthCareStore(context, names.care).use { care ->
            val concern = care.concern(concernId) ?: throw HealthCareConflict()
            val transcripts = AgentTranscriptStore(context)
            if (concern.conversationId.isNotBlank() && care.discussion(concern.conversationId) == concernId) {
                transcripts.conversation(concern.conversationId)?.takeIf { HealthCareAgentScope.concernId(it) == concernId }
                    ?.let { return@synchronized it.id }
            }
            val conversation = transcripts.createAgentConversation(context.getString(R.string.health_care_discussion_title,
                context.getString(concern.metric.titleResource())), globalTopicKey = HealthCareDiscussionPolicy.TOPIC_PREFIX + concernId,
                privateMode = true, trackingPaused = true)
            care.bindDiscussion(concernId, concern.revision, conversation.id)
            conversation.id
        }
    }

    fun bound(context: Context, conversationId: String): Boolean {
        if (conversationId.isBlank()) return false
        if (context.getDatabasePath(HealthCareStore.DEFAULT_DB).exists() &&
            HealthCareStore(context).use { it.discussion(conversationId) != null }) return true
        return AgentTranscriptStore(context).conversation(conversationId)?.globalTopicKey
            ?.startsWith(HealthCareDiscussionPolicy.TOPIC_PREFIX) == true
    }

    fun prepare(context: Context, conversationId: String, question: String, runtime: AgentRuntimeContext,
        research: HealthCareResearchAuthorization? = null, turnId: String = UUID.randomUUID().toString(),
        feedbackHistoryShared: Boolean = false, instructionId: String? = null,
        visitFollowUpScope: HealthCareVisitFollowUpScope? = null): HealthCareDiscussionPreview {
        require(instructionId == null || research == null && HealthProfilePolicy.uuid(instructionId))
        require(visitFollowUpScope == null || instructionId == null && research == null)
        HealthCareEngine.evaluate(context)
        val privacy = HealthPrivacyStore(context).use { it.policy() }
        check(privacy.metrics && privacy.profile) { context.getString(R.string.health_care_discussion_permissions) }
        return HealthCareStore(context).use { care ->
            val id = care.discussion(conversationId) ?: error(context.getString(R.string.health_care_profile_discussion_changed))
            val concern = care.concern(id) ?: throw HealthCareConflict()
            val journal = visitFollowUpScope?.let { HealthCareVisitFollowUpTool.selected(care, id, it) }
            val instruction = instructionId?.let { selected ->
                val value = care.instruction(selected) ?: throw HealthCareConflict()
                HealthCareInstructionTool.selected(context, care, id, HealthCareInstructionScope.of(value))
            }
            check(care.settings().enabled && concern.stage !in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED) &&
                HealthCareSignal.SOURCE_REMOVED !in concern.assessment.signals) { context.getString(R.string.health_care_discussion_inactive) }
            val registry = AppStoreAgentConnectorRegistry(context)
            val targets = registry.availableTargets()
            val selection = AgentModelSelectionSettings.selection(context, conversationId)
            val selected = AgentModelSelectionPolicy.selectedTarget(selection, targets)
            if (research != null) check(research.active && research.scope.concernId == id && research.scope.conversationId == conversationId &&
                research.configuration == configurationFingerprint(context, conversationId, research.scope.targetId) &&
                care.researchAuthorization(id) == research) { context.getString(R.string.health_care_changed) }
            val target = if (research != null) targets.firstOrNull { it.id == research.scope.targetId }
            else if (selection.mode == AgentModelSelectionMode.MANUAL) selected else {
                AgentStableAutoRoutePolicy.select(targets, AgentResourceRouter(context).route(question, targets))?.target
            }
            check(target != null && target.status == AgentConnectorStatus.AVAILABLE && target.kind != AgentConnectorKind.DEVICE) {
                context.getString(R.string.health_care_discussion_no_model)
            }
            check(target.id == "local-llm" || privacy.online) { context.getString(R.string.health_care_discussion_online) }
            val config = AgentModelSelectionSettings.configurationForTarget(context, conversationId, target.id)
            val requestedModel = research?.scope?.modelId ?: config?.modelId?.takeIf(String::isNotBlank) ?: target.invocationProfile.defaultModelId
            val model = if (AppStore.isCloudApiContact(context, target.id)) {
                val contact = AppStore.selectedCloudModelContact(context, target.id) ?: error("Cloud model unavailable")
                CloudModelRequestRoutingPolicy.resolve(contact, requestedModel, false).getString("cloud_model")
            } else requestedModel
            val effort = research?.scope?.effort?.let(AgentModelReasoningEffort::fromWireValue) ?: config?.reasoningEffort ?: AgentModelReasoningEffort.AUTO
            val destination = destination(context, target.id, model)
            val grant = HealthCareDiscussionGrant(conversationId, turnId, id, concern.revision,
                care.settings().version, privacy.version, destination, System.currentTimeMillis(), target.id, model, effort.wireValue,
                research?.id.orEmpty(), concern.profileLink, questionsShared = instruction == null && journal == null && (research?.scope?.questionsShared ?: true),
                userInputDigest = if (research == null) AgentNativeJsonCodec.sha256(question.trim()) else "",
                feedbackHistoryShared = instruction == null && journal == null && (research?.scope?.feedbackHistoryShared ?: feedbackHistoryShared),
                instruction = instruction?.let(HealthCareInstructionScope::of), visitFollowUp = visitFollowUpScope)
            check(HealthCareDiscussionPolicy.questionScopeCurrent(grant, concern)) { context.getString(R.string.health_care_changed) }
            if (research != null) check(research.permits(grant) && care.researchGrantCurrent(grant)) {
                context.getString(R.string.health_care_changed)
            }
            val followUp = if (research == null) null else {
                val job = checkNotNull(care.researchJob(turnId))
                val previous = care.previousCompletedResearch(job)
                HealthCareResearchHandoff.snapshot(concern, job, previous,
                    previous?.let { care.revision(concern.id, it.revision) }, care.priorResearchEvidence(job, grant),
                    care.hasRecordedPlan(concern.id, job.createdAt))
            }
            val profile = concern.profileLink?.takeIf { instruction == null && journal == null }?.let { link ->
                try { HealthCareProfileAccess.capture(context, link) }
                catch (_: HealthProfileConflict) { error(context.getString(R.string.health_care_profile_changed)) }
            }
            val snapshot = if (instruction != null) HealthCareInstructionTool.snapshot(instruction)
            else if (journal != null) HealthCareVisitFollowUpTool.snapshot(journal, care.encounter(journal.encounterId)!!, concern.revision)
            else HealthCareDiscussionPolicy.snapshot(concern, followUp, profile,
                if (grant.questionsShared) care.questions(concern, limit = 8) else null, grant.feedbackHistoryShared)
            val goal = HealthCareDiscussionPolicy.prompt(question, snapshot)
            val history = HealthCareDiscussionPolicy.historyForGrant(AgentTranscriptStore(context).context(conversationId),
                grant, care::discussionGrant)
            check(history.conversationId == conversationId && history.privateMode && history.trackingPaused) {
                context.getString(R.string.health_care_discussion_permissions)
            }
            val screen = ScreenContext(context.packageName, pageTitle = "Health discussion")
            val safeRuntime = runtime.copy(goal = goal, screen = screen, memoryCapture = false, memories = emptyList(),
                knowledgeItems = emptyList(), systemTools = emptyList(), callableTargets = listOf(target),
                nativeTools = runtime.nativeTools.filter { it.id in HealthCareDiscussionPolicy.tools(grant) })
            val request = AgentRequest(goal, screen, listOf(target), memories = emptyList(), runtimeContext = safeRuntime,
                conversationContext = history, executionTurnId = grant.turnId)
            val base = RuleBasedAgentPlanner(context).supervisedProjectActions(request)?.singleOrNull() ?: error("No health discussion route")
            val action = base.copy(parameters = base.parameters + mapOf("connector_id" to target.id,
                AgentInvocationBinding.TARGET to target.id, "manual_target_locked" to "true", "auto_reroute_on_failure" to "false",
                "routing_fallback_ids" to "", "manual_model_id" to model, "agent_model_id" to model,
                "agent_reasoning_effort" to effort.wireValue, "connector_adapter_type" to target.adapterType,
                INTERNAL_CONVERSATION_ID to conversationId, INTERNAL_TURN_ID to grant.turnId,
                INTERNAL_LONG_TERM_WRITE_ALLOWED to "false"))
            HealthCareDiscussionPreview(concern, grant, target, snapshot, question, action, selection, config)
        }
    }

    fun approve(context: Context, preview: HealthCareDiscussionPreview) {
        val grant = preview.grant
        check(AgentModelSelectionSettings.selection(context, grant.conversationId) == preview.selection &&
            AgentModelSelectionSettings.configurationForTarget(context, grant.conversationId, grant.targetId) == preview.configuration) {
            context.getString(R.string.health_care_changed)
        }
        check(destination(context, grant.targetId, grant.modelId) == grant.destination) { context.getString(R.string.health_care_changed) }
        check(HealthCareProfileAccess.current(context, grant.profileLink)) { context.getString(R.string.health_care_profile_changed) }
        HealthPrivacyStore(context).use { privacy ->
            val policy = privacy.policy()
            check(policy.version == grant.privacyVersion && policy.metrics && policy.profile &&
                (grant.targetId == "local-llm" || policy.online)) { context.getString(R.string.health_care_changed) }
        }
        HealthCareStore(context).use {
            grant.instruction?.let { scope -> HealthCareInstructionTool.selected(context, it, grant.concernId, scope) }
            grant.visitFollowUp?.let { scope -> HealthCareVisitFollowUpTool.selected(it, grant.concernId, scope) }
            it.approveDiscussion(grant)
        }
    }

    fun cloudDestination(contact: JSONObject): String = AgentNativeJsonCodec.sha256(JSONObject()
        .put("kind", "cloud").put("id", contact.optString("id").ifBlank { contact.optString("galaxyssi_id") })
        .put("endpoint", contact.optString("cloud_endpoint")).put("model", contact.optString("cloud_model"))
        .put("style", contact.optString("cloud_api_style", "openai")).toString())

    fun desktopDestination(context: Context, contactId: String): String {
        val contact = AppStore.contactById(context, contactId) ?: error("Health discussion destination unavailable")
        return AgentNativeJsonCodec.sha256(JSONObject().put("kind", "desktop").put("id", contactId)
            .put("desktop", contact.optString("desktop_id")).put("link", contact.optString("link_secret"))
            .put("fingerprint", contact.optString("identity_fingerprint")).toString())
    }

    internal fun configurationFingerprint(context: Context, conversationId: String, targetId: String): String {
        val selection = AgentModelSelectionSettings.selection(context, conversationId)
        val config = AgentModelSelectionSettings.configurationForTarget(context, conversationId, targetId)
        return AgentNativeJsonCodec.sha256(JSONObject().put("mode", selection.mode.name).put("target", selection.targetId)
            .put("model", selection.modelId).put("effort", selection.reasoningEffort.wireValue)
            .put("target_model", config?.modelId ?: JSONObject.NULL).put("target_effort", config?.reasoningEffort?.wireValue ?: JSONObject.NULL).toString())
    }

    internal fun destination(context: Context, targetId: String, model: String): String {
        if (targetId == "local-llm") return AgentNativeJsonCodec.sha256("local-llm:$model")
        if (AppStore.isCloudApiContact(context, targetId)) {
            val contact = AppStore.selectedCloudModelContact(context, targetId) ?: error("Cloud model unavailable")
            return cloudDestination(CloudModelRequestRoutingPolicy.resolve(contact, model, false))
        }
        val contact = AgentConnectorContactSnapshot.from(AppStore.contacts(context)).preferredMatchingContactId(targetId) {
            AppStore.outgoingTopicForContact(context, it) != null
        }
            ?: error("Paired model unavailable")
        return desktopDestination(context, contact)
    }

    fun rejection(context: Context, conversationId: String, turnId: String, actualDestination: String? = null): String? {
        if (!bound(context, conversationId)) return null
        val allowed = runCatching {
            val conversation = AgentTranscriptStore(context).conversation(conversationId)
            if (conversation?.privateMode != true || !conversation.trackingPaused ||
                conversation.status != AgentConversationStatus.ACTIVE) return@runCatching false
            HealthCareStore(context).use { care ->
                val grant = care.discussionGrant(turnId) ?: return@use false
                val concern = care.discussion(conversationId)?.let(care::concern)
                val privacy = HealthPrivacyStore(context).use { it.policy() }
                val settings = care.settings()
                val sourceCurrent = concern?.let { issue -> HealthRecordStore(context).use {
                    issue.inputVersion == HealthCareEngine.inputVersion(settings.version, privacy.version, it.metricVersion(issue.metric))
                } } == true
                grant.instruction?.let { HealthCareInstructionTool.selected(context, care, grant.concernId, it) }
                grant.visitFollowUp?.let { HealthCareVisitFollowUpTool.selected(care, grant.concernId, it) }
                HealthCareDiscussionPolicy.permitted(grant, conversationId, turnId, concern, settings, privacy,
                    actualDestination ?: destination(context, grant.targetId, grant.modelId), System.currentTimeMillis()) &&
                    sourceCurrent && HealthCareProfileAccess.current(context, grant.profileLink) &&
                    (grant.targetId == "local-llm" || privacy.online) && care.researchGrantCurrent(grant) &&
                    (grant.researchAuthorizationId.isEmpty() || care.researchAuthorization(grant.concernId)?.let {
                        it.configuration == configurationFingerprint(context, conversationId, grant.targetId)
                    } == true)
            }
        }.getOrDefault(false)
        return if (allowed) null else context.getString(R.string.health_care_discussion_expired)
    }

    fun actionRejection(context: Context, action: AgentAction): String? {
        val conversation = action.parameters[INTERNAL_CONVERSATION_ID].orEmpty()
        if (!bound(context, conversation)) return null
        val turn = action.parameters[INTERNAL_TURN_ID].orEmpty()
        rejection(context, conversation, turn)?.let { return it }
        val granted = HealthCareStore(context).use { it.discussionGrant(turn) } ?: return context.getString(R.string.health_care_discussion_expired)
        val allowed = when (action.kind) {
            AgentActionKind.DRAFT_PLAN -> true
            AgentActionKind.CALL_NATIVE_TOOL -> action.parameters["tool_id"] in HealthCareDiscussionPolicy.tools(granted)
            AgentActionKind.CALL_CONNECTOR -> action.parameters["connector_id"] == granted.targetId &&
                action.parameters["agent_model_id"].orEmpty() == granted.modelId &&
                action.parameters["agent_reasoning_effort"].orEmpty() == granted.effort &&
                action.parameters["routing_fallback_ids"].isNullOrBlank()
            else -> false
        }
        return if (allowed) null else context.getString(R.string.health_care_discussion_scope)
    }

    fun toolRejection(context: Context, tool: AgentNativeToolDescriptor, invocation: AgentNativeToolInvocationContext): String? {
        if (!bound(context, invocation.conversationId)) return null
        return rejection(context, invocation.conversationId, invocation.turnId)
            ?: if (!HealthCareStore(context).use {
                it.discussionGrant(invocation.turnId)?.let { grant -> tool.id in HealthCareDiscussionPolicy.tools(grant) } == true
            }) context.getString(R.string.health_care_discussion_scope)
            else if (tool.id !in setOf(AgentToolDiscoveryTools.ID, AgentToolInspectionTools.DESCRIBE, AgentConversationRecallTool.ID,
                    HealthCarePlanTool.ID, HealthCareHistoryTool.ID, HealthCareFeedbackTool.ID, HealthCareInstructionTool.ID,
                    HealthCareVisitFollowUpTool.ID) && tool.id !in HealthCareQuestionTools.ids &&
                !HealthPrivacyStore(context).use { it.policy().online }) context.getString(R.string.health_care_discussion_online)
            else null
    }
}
