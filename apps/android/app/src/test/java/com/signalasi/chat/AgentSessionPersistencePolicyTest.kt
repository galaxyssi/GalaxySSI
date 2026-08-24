package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.json.JSONObject
import org.junit.Test

class AgentSessionPersistencePolicyTest {
    @Test
    fun recoveryMetadataSurvivesEntryCompaction() {
        val metadata = buildMap {
            repeat(AgentSessionPersistencePolicy.MAX_METADATA_ENTRIES + 12) { index ->
                put("ordinary_$index", "value-$index")
            }
            put("delivery_failed", "true")
            put("source_message_id", "1450")
            put("failure_domain", "desktop")
        }

        val compact = AgentSessionPersistencePolicy.compactMetadata(metadata)

        assertEquals(AgentSessionPersistencePolicy.MAX_METADATA_ENTRIES, compact.size)
        assertEquals("true", compact["delivery_failed"])
        assertEquals("1450", compact["source_message_id"])
        assertEquals("desktop", compact["failure_domain"])
    }

    @Test
    fun oversizedLegacyCheckpointIsRejectedBeforeDecryption() {
        assertFalse(AgentSessionPersistencePolicy.shouldDiscardEncodedValue(128 * 1024))
        assertTrue(AgentSessionPersistencePolicy.shouldDiscardEncodedValue(256 * 1024))
    }

    @Test
    fun screenCheckpointKeepsSummaryAndDropsTransientPayloads() {
        val screen = ScreenContext(
            foregroundApp = "SignalASI",
            activityName = "MainActivity",
            pageTitle = "Agent",
            visibleTextCount = 400,
            clickableNodeCount = 80,
            visibleTexts = List(400) { "visible-$it" },
            selectedText = "selected",
            clickableElements = List(80) {
                ScreenElement("button-$it", "id-$it", "Button", "0,0,1,1")
            },
            inputFields = listOf(ScreenElement("message", "input", "EditText", "0,0,1,1")),
            scrollableRegions = listOf(ScreenElement("list", "list", "List", "0,0,1,1")),
            clipboard = ClipboardContext(hasText = true, textLength = 50, preview = "private"),
            notifications = AgentNotificationContext(
                hasAccess = true,
                items = listOf(AgentNotificationItem(title = "private")),
                totalCount = 12
            ),
            installedApps = List(300) { InstalledAppInfo("App $it", "app.$it") }
        )

        val compact = AgentSessionPersistencePolicy.compactScreen(screen)

        assertEquals("SignalASI", compact.foregroundApp)
        assertEquals(400, compact.visibleTextCount)
        assertEquals(80, compact.clickableNodeCount)
        assertEquals("selected", compact.selectedText)
        assertTrue(compact.visibleTexts.isEmpty())
        assertTrue(compact.clickableElements.isEmpty())
        assertTrue(compact.inputFields.isEmpty())
        assertTrue(compact.scrollableRegions.isEmpty())
        assertTrue(compact.installedApps.isEmpty())
        assertFalse(compact.clipboard.hasText)
        assertTrue(compact.notifications.hasAccess)
        assertEquals(12, compact.notifications.totalCount)
        assertTrue(compact.notifications.items.isEmpty())
    }

    @Test
    fun oversizedSessionRetainsAResumableCurrentPlan() {
        val storage = MemoryCheckpointStorage()
        val store = SharedPreferencesAgentSessionStore(storage)
        val snapshot = oversizedSnapshot()

        store.save(snapshot)

        val raw = storage.value.orEmpty()
        val persisted = JSONObject(raw)
        val restored = store.load()
        val plan = restored?.currentPlan
        assertTrue(raw.length <= AgentSessionPersistencePolicy.MAX_SESSION_JSON_CHARACTERS)
        assertTrue(persisted.getString("persistence_mode").endsWith("recovery"))
        assertNotNull(plan)
        assertEquals("plan-large", plan?.planId)
        assertEquals(17, plan?.revision)
        assertEquals(5, plan?.replanCount)
        assertEquals("phone-linux", plan?.route?.targetId)
        assertEquals(AgentExecutionLocationKind.PHONE, plan?.route?.executionLocationKind)
        assertTrue(plan?.actions.orEmpty().any {
            it.id == "action-40" && it.status == AgentActionStatus.WAITING_RESPONSE
        })
        assertEquals("action-40", restored?.executionLoopSnapshot?.lastActionId)
        assertEquals("action-40", restored?.lastActionResult?.actionId)
    }

    @Test
    fun obviouslyOversizedProjectUsesRecoveryEncodingBeforeBuildingTheFullPayload() {
        val store = SharedPreferencesAgentSessionStore(MemoryCheckpointStorage())

        val payload = store.encodePayload(oversizedSnapshot())

        assertEquals(AgentSessionPayloadEncodingMode.PREFLIGHT_RECOVERY, payload.mode)
        assertTrue(JSONObject(payload.value).getString("persistence_mode").endsWith("recovery"))
    }

    @Test
    fun normalSessionKeepsTheFullPersistenceFormat() {
        val store = SharedPreferencesAgentSessionStore(MemoryCheckpointStorage())
        val snapshot = AgentSessionSnapshot(
            sessionId = "session-small",
            phase = AgentPhase.OBSERVING,
            currentGoal = "Answer a short question",
            currentScreen = ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent"),
            currentPlan = null,
            auditTrail = emptyList(),
            lastActionResult = null,
            updatedAtMillis = 1_000L
        )

        val payload = store.encodePayload(snapshot)

        assertEquals(AgentSessionPayloadEncodingMode.FULL, payload.mode)
        assertFalse(JSONObject(payload.value).has("persistence_mode"))
    }

    @Test
    fun minimalRecoveryCheckpointStillKeepsActiveActionAndDependencies() {
        val storage = MemoryCheckpointStorage()
        val store = SharedPreferencesAgentSessionStore(storage)

        store.save(oversizedSnapshot())

        val raw = storage.value.orEmpty()
        val persisted = JSONObject(raw)
        val restored = store.load()
        val active = restored?.currentPlan?.actions.orEmpty().firstOrNull { it.id == "action-40" }
        assertEquals("minimal_recovery", persisted.getString("persistence_mode"))
        assertNotNull(active)
        assertEquals("action-39", active?.parameters?.get("depends_on"))
        assertTrue(restored?.currentPlan?.actions.orEmpty().any { it.id == "action-39" })
        assertTrue(active?.description.orEmpty().length <= 256)
        assertTrue(active?.evidence.orEmpty().length <= 256)
        assertTrue(restored?.currentPlan?.actions.orEmpty().size <= 4)
    }

    @Test
    fun compactRecoveryPlanPreservesFailureAndCheckpointEvidence() {
        val plan = oversizedSnapshot().currentPlan!!

        val compact = AgentSessionPersistencePolicy.compactRecoveryPlan(plan, "action-40")

        assertTrue(compact.actions.any { it.id == "action-40" })
        assertTrue(compact.actions.any { it.id == "action-41" && it.status == AgentActionStatus.FAILED })
        assertTrue(compact.verificationResults.any { it.actionId == "action-40" })
        assertTrue(compact.checkpoints.any { it.actionId == "action-40" })
        assertEquals("phone-linux", compact.route.targetId)
        assertEquals("", compact.artifactRichOutputJson)
    }

    private fun oversizedSnapshot(): AgentSessionSnapshot {
        val large = "x".repeat(12_000)
        val actions = List(80) { index ->
            AgentAction(
                id = "action-$index",
                kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = "phone-linux",
                risk = AgentRisk.LOW,
                status = when (index) {
                    40 -> AgentActionStatus.WAITING_RESPONSE
                    41 -> AgentActionStatus.FAILED
                    in 42..50 -> AgentActionStatus.PENDING_CONFIRMATION
                    else -> AgentActionStatus.COMPLETED
                },
                description = "action-$index:$large",
                parameters = buildMap {
                    put("depends_on", "action-${(index - 1).coerceAtLeast(0)}")
                    repeat(30) { metadataIndex -> put("metadata-$metadataIndex", large) }
                },
                requiresConfirmation = false,
                result = large,
                evidence = large
            )
        }
        val plan = AgentPlan(
            goal = "Develop SignalASI on the phone",
            screen = ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent"),
            steps = listOf(
                AgentStep(1, AgentStepKind.ANALYZE_GOAL, AgentStepStatus.DONE),
                AgentStep(2, AgentStepKind.CONFIRM_AND_ACT, AgentStepStatus.CURRENT),
                AgentStep(3, AgentStepKind.OBSERVE_SCREEN, AgentStepStatus.WAITING)
            ),
            actions = actions,
            planId = "plan-large",
            selectedAgentOrModel = "Codex",
            expectedResult = large,
            rollbackStrategy = large,
            contextDigest = large,
            routeRationale = large,
            route = AgentRoute(
                routeId = "route-phone",
                kind = AgentRouteKind.LOCAL_SYSTEM,
                targetId = "phone-linux",
                targetTitle = "Phone Linux",
                status = AgentConnectorStatus.AVAILABLE,
                executionLocationKind = AgentExecutionLocationKind.PHONE,
                executionRuntimeKind = AgentExecutionRuntimeKind.PHONE_LINUX
            ),
            revision = 17,
            replanCount = 5,
            actionHistory = actions + actions,
            verificationResults = listOf(
                AgentVerificationResult(
                    actionId = "action-40",
                    success = false,
                    observedApp = "SignalASI",
                    observedTitle = "Agent",
                    visibleTextCount = 1,
                    clickableNodeCount = 1,
                    evidence = large
                )
            ),
            checkpoints = listOf(
                AgentExecutionCheckpoint(
                    id = "checkpoint-40",
                    actionId = "action-40",
                    planRevision = 17,
                    foregroundApp = "SignalASI",
                    activityName = "MainActivity",
                    pageTitle = "Agent",
                    screenDigest = large
                )
            ),
            artifactRichOutputJson = large
        )
        val now = System.currentTimeMillis()
        return AgentSessionSnapshot(
            sessionId = "session-large",
            phase = AgentPhase.WAITING_RESPONSE,
            currentGoal = plan.goal,
            currentScreen = plan.screen,
            currentPlan = plan,
            auditTrail = List(40) { AgentAuditEntry(AgentAuditEvent.ACTION_EXECUTED, large, now + it) },
            lastActionResult = AgentActionResult(
                actionId = "action-40",
                success = false,
                message = large,
                metadata = mapOf("depends_on" to "action-39", "native_tool_output" to large)
            ),
            executionLoopSnapshot = AgentExecutionLoopSnapshot(
                taskId = "task-large",
                phase = AgentExecutionLoopPhase.WAITING_RESPONSE,
                budget = AgentExecutionLoopBudget(enforceCountLimits = false),
                usage = AgentExecutionLoopUsage(),
                resumePhase = AgentExecutionLoopPhase.ACT,
                lastActionId = "action-40",
                lastReason = large,
                taskIntentSignals = List(40) { "$it:$large" },
                lastProgressAtMillis = now,
                failureCounts = (0 until 40).associate { "$it:$large" to it },
                startedAtMillis = now,
                updatedAtMillis = now
            ),
            processInstanceId = "process-old",
            updatedAtMillis = now
        )
    }

    private class MemoryCheckpointStorage : AgentSessionCheckpointStorage {
        var value: String? = null

        override fun encodedValueLength(key: String): Int = value?.length ?: 0
        override fun readString(key: String, defaultValue: String): String = value ?: defaultValue
        override fun writeString(key: String, value: String) {
            this.value = value
        }
        override fun remove(key: String) {
            value = null
        }
    }
}
