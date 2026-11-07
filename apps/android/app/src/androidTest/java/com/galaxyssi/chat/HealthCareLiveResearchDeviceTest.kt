package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in paid probe: real paired reasoning and phone HTTPS, isolated synthetic care databases.
 * Reuses production prompts, parser, observation compaction and tools, not the Activity consent UI.
 */
class HealthCareLiveResearchDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val report = JSONArray()
    private val reportFile get() = File(context.filesDir, "health-care-live-research.json")

    @Test fun pairedModelResearchesAndAnswersFollowupWithoutConfirmingPlan(): Unit = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_live_research") == "true")
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it) }.firstOrNull {
            !it.optBoolean("deleted") && AppStore.agentIdForContact(context, it.optString("id")) == "codex" &&
                !AppStore.isDesktopDeviceContact(context, it.optString("id")) &&
                GalaxySSILinkProtocol.serverLink(context, it.optString("desktop_id"))?.paired == true
        } ?: error("No paired Codex contact; preserve pairing and credentials")
        GalaxySSIMqttClient.connect(context)
        withTimeout(30_000) { while (!GalaxySSIMqttClient.isRequestReplyReady()) delay(100) }
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val conversation = UUID.randomUUID().toString()
        val history = mutableListOf<AgentTranscriptEntry>()
        try {
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
            HealthCareStore(context, names.care).use { it.configure(true, it.settings().version) }
            HealthCareEngine.evaluate(context, names)
            HealthCareStore(context, names.care).use { store ->
                val found = store.forMetric(HealthMetric.GLUCOSE)!!
                val concern = store.bindDiscussion(found.id, found.revision, conversation)
                val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
                val selected = AgentModelSelectionSettings.configurationForTarget(context, conversation, contact.getString("id"))
                val grant = HealthCareDiscussionGrant(conversation, UUID.randomUUID().toString(), concern.id,
                    concern.revision, store.settings().version, privacy.version,
                    HealthCareDiscussion.desktopDestination(context, contact.getString("id")), System.currentTimeMillis(),
                    contact.getString("id"), selected?.modelId.orEmpty(), selected?.reasoningEffort?.wireValue.orEmpty())
                store.approveDiscussion(grant)
                val firstQuestion = "\u8fd9\u662f\u5408\u6210\u6d4b\u8bd5\uff0c\u4e0d\u662f\u6211\u7684\u5065\u5eb7\u6570\u636e\u3002" +
                    "\u62a5\u544a\u53c2\u8003\u8303\u56f4\u662f4-6\uff0c\u8840\u7cd6\u662f6.3 mmol/L\uff0c\u68c0\u6d4b\u6761\u4ef6\u8fd8\u6ca1\u6838\u5bf9\u3002" +
                    "\u8bf7\u5148\u9605\u8bfb https://medlineplus.gov/lab-tests/how-to-understand-your-lab-results/ " +
                    "\u89e3\u91ca\u4e3a\u4ec0\u4e48\u4e0d\u80fd\u7528\u8303\u56f4\u4e2d\u70b9\u4f5c\u4e3a\u6700\u4f73\u503c\uff0c" +
                    "\u63d0\u51fa\u6838\u5bf9\u6761\u4ef6\u548c\u4e0e\u533b\u751f\u8ba8\u8bba\u7684\u5f85\u786e\u8ba4\u8349\u6848\u3002\u4e0d\u8981\u786e\u8bca\u6216\u8bbe\u63d0\u9192\u3002" +
                    "\u8bf7\u7528\u624b\u673a\u5de5\u5177\u771f\u5b9e\u8bfb\u53d6\u6765\u6e90\uff0c\u5e76\u4fdd\u5b58\u4e3a\u5f85\u786e\u8ba4\u8ba1\u5212\uff0c\u4e0d\u662f\u53ea\u5728\u56de\u590d\u4e2d\u5217\u51fa\u8349\u6848\u3002"
                val first = runTurn(store, concern, grant, contact, firstQuestion, history)
                assertTrue(first.isNotBlank())
                val plan = store.plan(grant.turnId) ?: error("Real model did not submit a source-grounded draft")
                assertEquals(HealthCarePlanState.PENDING, plan.state)
                assertTrue(plan.sources.all { it.evidence != null && it.quote.isNotBlank() })
                assertTrue(store.concern(concern.id)!!.actions.isEmpty()); assertNull(store.nextDue())
                history += entry(AgentTranscriptRole.USER, firstQuestion, grant)
                history += entry(AgentTranscriptRole.ASSISTANT, first, grant)
                val next = grant.copy(turnId = UUID.randomUUID().toString(), approvedAt = System.currentTimeMillis())
                store.approveDiscussion(next)
                val answer = runTurn(store, concern, next, contact,
                    "\u5148\u4e0d\u786e\u8ba4\u8ba1\u5212\u3002\u4e0d\u7528\u518d\u67e5\u7f51\u9875\uff0c\u4e5f\u4e0d\u8981\u65b0\u5efa\u8349\u6848\u3002" +
                        "\u8bf7\u590d\u8ff0\u521a\u624d\u7684\u6570\u503c\u3001\u5355\u4f4d\u548c\u8fd8\u672a\u6838\u5bf9\u7684\u4fe1\u606f\uff0c\u5e76\u8bf4\u660e\u8ba1\u5212\u6709\u6ca1\u6709\u6267\u884c\u3002", history)
                assertTrue("Follow-up lost the measurement", answer.contains("6.3"))
                assertTrue("Follow-up lost units", answer.contains("mmol", true) || answer.contains("\u6beb\u6469"))
                assertEquals(plan, store.plan(grant.turnId)); assertNull(store.plan(next.turnId))
                assertTrue(store.concern(concern.id)!!.actions.isEmpty()); assertNull(store.nextDue())
                println("HEALTH_LIVE research_and_followup=true pending_only=true real_provider=true")
            }
        } finally {
            reportFile.writeText(report.toString(2))
            listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase)
        }
    }

    private suspend fun runTurn(store: HealthCareStore, concern: HealthCareConcern, grant: HealthCareDiscussionGrant,
        contact: JSONObject, question: String, turns: List<AgentTranscriptEntry>): String {
        val web = AgentBoundedWebService(AgentPinnedOkHttpWebTransport())
        val service = AgentWebIntelligenceService(AgentBoundedWebIntelligenceFetcher(web), AgentInMemoryWebIntelligenceStore())
        val registry = AgentNativeToolRegistry()
        HealthCareWebEvidence.wrap(AgentWebIntelligenceNativeTools.definitions(service, web.availability)
            .filter { it.descriptor.id == AgentWebIntelligenceNativeTools.FETCH }) { invocation, output ->
            check(invocation.conversationId == grant.conversationId && invocation.turnId == grant.turnId)
            val proofs = HealthCareEvidencePolicy.read(output, grant, invocation.invocationId, System.currentTimeMillis())
            store.recordEvidence(proofs)
            output + ("health_evidence" to proofs.map { it.output() })
        }.forEach(registry::register)
        registry.register(AgentToolInspectionTools.definition())
        registry.register(HealthCarePlanTool.definition { invocation, input ->
            check(invocation.conversationId == grant.conversationId && invocation.turnId == grant.turnId)
            store.proposePlan(HealthCarePlanPolicy.parse(input, grant, concern, System.currentTimeMillis()))
        })
        val screen = ScreenContext("Synthetic health acceptance", pageTitle = "Synthetic health concern")
        val goal = HealthCareDiscussionPolicy.prompt(question, HealthCareDiscussionPolicy.snapshot(concern))
        val runtime = AgentRuntimeContextBuilder.build(sessionId = grant.conversationId, goal = goal, screen = screen,
            permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
            callableTargets = emptyList(), memories = emptyList(), nativeTools = registry.availableCatalog().descriptors)
        val observations = mutableListOf<AgentAction>()
        val seed = AgentRequest(goal, screen, emptyList(), memories = emptyList(), runtimeContext = runtime,
            conversationContext = AgentConversationContext(grant.conversationId, "", turns, true, trackingPaused = true),
            executionTurnId = grant.turnId)
        var repair = ""
        // Bound this paid acceptance probe only; no production task budget is changed.
        return withTimeout(600_000L) {
            repeat(12) { round ->
                val request = seed.copy(executionHistory = observations.toList(),
                    replanReason = if (round == 0) "" else PHONE_SUPERVISED_PROJECT_REPLAN_REASON)
                val prompt = repair.ifBlank { if (round == 0) AgentSupervisedProjectLoop.planningPrompt(request)
                    else AgentSupervisedProjectLoop.continuationPrompt(request) }
                val raw = exchange(contact, grant, prompt)
                report.put(JSONObject().put("turn", grant.turnId).put("round", round).put("response", raw))
                reportFile.writeText(report.toString(2))
                AgentSupervisedProjectDirectResponseCodec.parse(raw)?.let { return@withTimeout it }
                val normalized = AgentSupervisedProjectControlPayload.normalize(raw, observations)
                val parsed = AgentModelPlanParser.parseWithDiagnostics(request, normalized,
                    AgentSupervisedProjectLoop.plannerSettings(AgentModelPlannerSettings()), allowInitialCompletion = true)
                if (parsed.plan == null) {
                    repair = AgentSupervisedProjectLoop.formatRepairPrompt(request, raw, parsed.rejection?.toJson().orEmpty())
                    println("HEALTH_LIVE round=$round parse=${parsed.rejection?.code}")
                    return@repeat
                }
                repair = ""
                val actions = parsed.plan.actions
                if (actions.singleOrNull()?.isTaskCompleteMarker() == true) return@withTimeout actions.single().description
                actions.forEach { action ->
                    require(action.kind == AgentActionKind.CALL_NATIVE_TOOL) { "Only scoped phone tools allowed" }
                    val id = action.parameters.getValue("tool_id")
                    require(registry.lookup(id) != null)
                    val input = jsonObject(JSONObject(action.parameters.getValue("input_json")))
                    val result = registry.invoke(id, input, AgentNativeToolInvocationContext(
                        conversationId = grant.conversationId, turnId = grant.turnId,
                        deadlineEpochMillis = System.currentTimeMillis() + 60_000))
                    val encoded = AgentNativeJsonCodec.stringify(result.output)
                    val evidence = AgentWebObservation.compact(encoded, 16_000, preserveReceipt = true) ?: result.toJson()
                    observations += action.copy(id = "round-$round-${action.id}",
                        status = if (result.isSuccess) AgentActionStatus.COMPLETED else AgentActionStatus.FAILED,
                        result = result.message, evidence = evidence)
                    report.put(JSONObject().put("tool", id).put("status", result.status.wireValue).put("observation", evidence))
                    println("HEALTH_LIVE round=$round tool=$id status=${result.status.wireValue}")
                }
            }
            error("Live health probe exhausted its test-only 12-round allowance")
        }
    }

    private suspend fun exchange(contact: JSONObject, grant: HealthCareDiscussionGrant, prompt: String): String {
        val source = System.currentTimeMillis()
        val task = "health-live-${UUID.randomUUID()}"
        val id = contact.getString("id")
        val pending = CompletableDeferred<AgentConnectorResponse>()
        val listener = object : GalaxySSIMqttClient.Listener {
            override fun onMessage(payload: String) {
                val json = runCatching { JSONObject(payload) }.getOrNull() ?: return
                if (json.optLong("source_message_id") != source || json.optString("contact_id") != id ||
                    json.optString("conversation_id") != grant.conversationId || json.optString("turn_id") != grant.turnId ||
                    json.optString("task_id") != task || json.optString("type") != "text") return
                val result = AgentRemoteOutcomeCodec.decode(json, AgentRemoteOutcomeCodec.content(context, json)) ?: return
                GalaxySSIMqttClient.completeIncomingDelivery(context, payload)
                pending.complete(result)
            }
        }
        GalaxySSIMqttClient.addListener(listener)
        var received = false
        try {
            assertTrue(GalaxySSIMqttClient.publishUserMessage(prompt, contactId = id, clientMessageId = source,
                conversationId = grant.conversationId, turnId = grant.turnId, taskId = task,
                executionMode = AgentTaskExecutionMode.PLAN_ONLY, connectorTaskMode = PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                agentModelId = grant.modelId, agentReasoningEffort = AgentModelReasoningEffort.fromWireValue(grant.effort)))
            val response = withTimeout(180_000) { pending.await() }
            received = true
            assertTrue("Paired provider failed: ${AgentObservationRedaction.redact(response.content).take(300)}", response.success)
            return response.content
        } finally {
            if (!received) GalaxySSIMqttClient.publishAgentTaskCancel(task, id, source, grant.conversationId, grant.turnId)
            GalaxySSIMqttClient.removeListener(listener)
        }
    }

    private fun entry(role: AgentTranscriptRole, text: String, grant: HealthCareDiscussionGrant) =
        AgentTranscriptEntry(UUID.randomUUID().toString(), role, text, System.currentTimeMillis(),
            conversationId = grant.conversationId, turnId = grant.turnId)

    private fun jsonValue(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> jsonObject(value)
        is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
        else -> value
    }

    private fun jsonObject(value: JSONObject): AgentNativeJsonObject =
        value.keys().asSequence().associateWith { jsonValue(value.get(it)) }
}
