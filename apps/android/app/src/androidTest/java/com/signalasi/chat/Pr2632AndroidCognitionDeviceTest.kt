package com.signalasi.chat

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkInfo
import androidx.work.WorkManager
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class Pr2632AndroidCognitionDeviceTest {
    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val memoryIds = mutableListOf<String>()

    @After
    fun cleanUp() {
        val memoryStore = EncryptedAgentMemoryStore(context).apply { suppressObservations = true }
        memoryIds.asReversed().forEach(memoryStore::deleteById)
        WorkManager.getInstance(context)
            .cancelUniqueWork(SCHEDULED_WORK)
            .result
            .get(10, TimeUnit.SECONDS)
        AndroidCognitionScheduler.requestImmediate(context)
    }

    @Test
    fun coreMemoryPersistsAcrossInstancesAndSupersedesOldState() {
        val marker = "pr2632-${UUID.randomUUID()}"
        val legacyKey = "corepreference$marker"
        val key = "core:preference:$marker"
        val store = EncryptedAgentMemoryStore(context).apply { suppressObservations = true }
        val first = requireNotNull(store.remember(AgentMemoryItem(
            kind = AgentMemoryKind.PREFERENCE,
            value = "The PR2632 device marker is $marker-initial.",
            source = "pr2632_device_test",
            key = legacyKey,
            important = true,
            confidence = 1.0,
            lastConfirmedAtMillis = System.currentTimeMillis()
        )).item)
        memoryIds += first.id

        val firstPrompt = AndroidCoreMemoryCoordinator(context).compilePrompt()
        val migrated = EncryptedAgentMemoryStore(context).snapshot()
            .activeItems
            .single { it.key == key }
        assertTrue(firstPrompt.contains("$marker-initial"))
        assertTrue(EncryptedAgentMemoryStore(context).snapshot().historyItems.any { it.id == first.id })

        val updated = requireNotNull(store.update(
            migrated.id,
            "The PR2632 device marker is $marker-updated.",
            key
        )?.item)
        memoryIds.clear()
        memoryIds += updated.id

        val restoredPrompt = AndroidCoreMemoryCoordinator(context).compilePrompt()
        val snapshot = EncryptedAgentMemoryStore(context).snapshot()
        assertTrue(restoredPrompt.contains("$marker-updated"))
        assertFalse(restoredPrompt.contains("$marker-initial"))
        assertEquals(updated.id, snapshot.activeItems.single { it.key == key }.id)
        assertTrue(snapshot.historyItems.any { it.id == migrated.id })
    }

    @Test
    fun encryptedCoreMemoryReachesFreshSessionPlannerAndAgentTransport() {
        val marker = "matrix-preference-${UUID.randomUUID()}"
        val coordinator = AndroidCoreMemoryCoordinator(context)
        val stored = coordinator.captureExplicit("我偏好 $marker 的简洁回答方式").single()
        memoryIds += stored.id

        val corePrompt = coordinator.compilePrompt()
        val freshContext = AgentConversationContext(
            conversationId = "fresh-session-${UUID.randomUUID()}",
            summary = "",
            turns = emptyList(),
            privateMode = false,
            globalContext = corePrompt
        )
        val screen = ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")
        val plannerPrompt = AgentModelPlanningPrompt.build(
            request = AgentRequest(
                goal = "What response style do I prefer?",
                screen = screen,
                targets = emptyList(),
                memories = emptyList(),
                runtimeContext = AgentRuntimeContextBuilder.build(
                    sessionId = freshContext.conversationId,
                    goal = "What response style do I prefer?",
                    screen = screen,
                    permissionMode = PermissionMode.AUTO_LOW_RISK,
                    highRiskGuard = true,
                    memoryCapture = true,
                    callableTargets = emptyList(),
                    memories = emptyList(),
                    nativeTools = emptyList()
                ),
                conversationContext = freshContext
            ),
            settings = AgentModelPlannerSettings(),
            requirements = AgentTaskRequirements(
                capabilities = emptySet(),
                mode = AgentRoutingMode.BALANCED,
                liveDataRequired = false,
                localOnly = false,
                complexReasoning = false,
                estimatedInputTokens = 64
            )
        )

        assertTrue(corePrompt.contains(marker))
        assertTrue(plannerPrompt.contains(marker))
        assertTrue(freshContext.asAgentTransportBlock("What response style do I prefer?").contains(marker))
    }

    @Test
    fun explicitExtractorRejectsSecretsBeforeImmediateStorage() {
        assertTrue(AndroidCoreMemoryExtractor.extract(
            "我的名字是测试用户，api_key=sk-pr2632-secret"
        ).isEmpty())
        assertTrue(AndroidCoreMemoryExtractor.extract(
            "My phone is Galaxy Tab Active3 and my access token is private"
        ).isEmpty())
    }

    @Test
    fun scheduledCognitionIsDurablyRegisteredOnDevice() {
        val workManager = WorkManager.getInstance(context)
        workManager.cancelUniqueWork(SCHEDULED_WORK).result.get(10, TimeUnit.SECONDS)
        workManager.pruneWork().result.get(10, TimeUnit.SECONDS)

        AndroidCognitionScheduler.scheduleAt(
            context,
            System.currentTimeMillis() + TimeUnit.MINUTES.toMillis(20)
        )

        val scheduled = workManager.getWorkInfosForUniqueWork(SCHEDULED_WORK)
            .get(10, TimeUnit.SECONDS)
            .firstOrNull { it.state == WorkInfo.State.ENQUEUED }
        assertNotNull(scheduled)
    }

    @Test
    fun obsidianSettingsRoundTripEncryptedAndAreRestoredAfterTest() {
        val store = ObsidianAndroidStateStore(context)
        val original = store.settings()
        val marker = "pr2632-vault-${UUID.randomUUID()}"
        val testSettings = ObsidianAndroidSettings(
            enabled = true,
            treeUri = "content://pr2632.test/tree/$marker",
            vaultName = marker,
            lastProjectionAtMillis = 123_456L,
            lastError = ""
        )

        try {
            store.saveSettings(testSettings)
            assertEquals(testSettings, ObsidianAndroidStateStore(context).settings())
            val rawPreferences = File(
                context.applicationInfo.dataDir,
                "shared_prefs/signalasi_obsidian_android_settings_v1.xml"
            ).takeIf(File::exists)?.readText().orEmpty()
            assertFalse(rawPreferences.contains(marker))
            assertFalse(rawPreferences.contains(testSettings.treeUri))
        } finally {
            store.saveSettings(original)
        }
    }

    @Test
    fun obsidianProjectionAllowsKnowledgeAndRedactsCredentials() {
        assertTrue(ObsidianProjectionPrivacyPolicy.safeKnowledge(
            "PR2632 keeps cognition in a resumable Android background worker."
        ))
        assertFalse(ObsidianProjectionPrivacyPolicy.safeKnowledge(
            "mqtt_password=pr2632-secret"
        ))
        assertEquals(
            "[Sensitive content omitted by SignalASI]",
            ObsidianProjectionPrivacyPolicy.transcriptText(
                "The identity_key_sha256 is pr2632-secret"
            )
        )
    }

    private companion object {
        const val SCHEDULED_WORK = "signalasi-cognition-scheduled-v1"
    }
}
