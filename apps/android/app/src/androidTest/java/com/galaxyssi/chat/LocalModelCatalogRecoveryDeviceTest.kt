package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real encrypted journal and local adapter, with scripted inference/dependency fixtures. */
@RunWith(AndroidJUnit4::class)
class LocalModelCatalogRecoveryDeviceTest {
    @Test fun repairedCapabilitySurvivesDatabaseReopenAndVerifiesTheOriginalChineseGoal() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val suffix = UUID.randomUUID().toString()
        val identity = AgentLocalDispatchIdentity(System.currentTimeMillis(), "local-llm", "public-conversation-$suffix",
            "public-turn-$suffix", "public-native-$suffix", "public-action-$suffix")
        val database = "public-catalog-recovery-$suffix.db"
        var store = AgentRunEventStore(context, database)
        var ready = false
        var installs = 0
        var reads = 0
        val goal = "请修好缺少的测试依赖，然后读取公开测试页并验证结果。"
        fun descriptor(id: String) = AgentNativeToolDescriptor(id, "1.0.0", "Public fixture", "Public fixture contract",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
            AgentNativeToolRisk.LOW)
        fun registry() = AgentNativeToolRegistry().registerAll(listOf(
            AgentNativeToolDefinition(descriptor("public.fixture.install"), AgentNativeToolExecutor {
                installs++; ready = true; AgentNativeToolExecutionResult.success(mapOf("public_fixture_installed" to true))
            }),
            AgentNativeToolDefinition(descriptor("public.fixture.read").copy(effect = AgentNativeToolEffect.READ_ONLY,
                idempotency = AgentNativeToolIdempotency.IDEMPOTENT), AgentNativeToolExecutor {
                reads++; AgentNativeToolExecutionResult.success(mapOf("public_fixture_verified" to true))
            }, availabilityProvider = AgentNativeToolAvailabilityProvider {
                if (ready) AgentNativeToolAvailability.AVAILABLE else AgentNativeToolAvailability(
                    AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, "Public fixture missing")
            })))
        fun request(saved: LocalModelLoopContinuation, catalog: AgentNativeToolCatalogView) = saved.request(
            catalog.descriptors, AgentNativeToolCancellationToken.NONE, AgentModelToolLoopEventSink.NONE)
        try {
            val initial = registry()
            val available = initial.availableCatalog()
            val contract = initial.registeredContractCatalog()
            val journal = EncryptedAgentModelLoopJournal(context, store)
            val saved = LocalModelLoopContinuationStore(journal).prepare(identity, goal, "public-scripted-profile",
                false, null, contract.manifest.sha256, "Public system", available.manifest.sha256)
            val interrupted = LocalModelWebToolSession(context, saved.preferredProfileId, false, inference = { _, prompt ->
                if (installs > 0) throw CancellationException("Fixture interruption after committed setup")
                assertTrue(prompt.contains(goal))
                LocalModelInferenceResult(text = """{"tool_calls":[{"id":"install","name":"public.fixture.install","arguments":{}}]}""",
                    profileId = "public-scripted-profile", backend = "fixture", smeAvailable = false, elapsedMillis = 1)
            })
            try {
                AgentModelToolLoop(interrupted.adapter(available.descriptors), initial,
                    disclosedToolManifestJson = contract.manifest.json, disclosedToolManifestSha256 = contract.manifest.sha256,
                    journal = journal).run(request(saved, contract))
                fail("Expected fixture interruption")
            } catch (_: CancellationException) { }
            assertEquals(1, installs)
            store.close()
            store = AgentRunEventStore(context, database)
            val repaired = registry()
            val currentAvailable = repaired.availableCatalog()
            val currentContract = repaired.registeredContractCatalog()
            assertNotEquals(available.manifest.sha256, currentAvailable.manifest.sha256)
            val restoredJournal = EncryptedAgentModelLoopJournal(context, store)
            val restored = LocalModelLoopContinuationStore(restoredJournal).restore(identity,
                currentContract.manifest.sha256, currentAvailable.manifest.sha256)
            assertEquals(saved, restored)
            val resumed = LocalModelWebToolSession(context, restored.preferredProfileId, false, inference = { system, prompt ->
                assertTrue(system.contains("public.fixture.read"))
                assertTrue(prompt.contains(goal))
                assertTrue(prompt.contains("public_fixture_installed"))
                val output = if (reads == 0)
                    """{"tool_calls":[{"id":"verify","name":"public.fixture.read","arguments":{}}]}"""
                else {
                    assertTrue(prompt.contains("public_fixture_verified"))
                    """{"answer":"测试依赖已恢复，已验证原始任务的公开页面结果。","tool_calls":[]}"""
                }
                LocalModelInferenceResult(text = output, profileId = "public-scripted-profile", backend = "fixture",
                    smeAvailable = false, elapsedMillis = 1)
            })
            val result = AgentModelToolLoop(resumed.adapter(currentAvailable.descriptors), repaired,
                disclosedToolManifestJson = currentContract.manifest.json,
                disclosedToolManifestSha256 = currentContract.manifest.sha256, journal = restoredJournal)
                .run(request(restored, currentContract))
            assertEquals(AgentModelToolLoopStatus.COMPLETED, result.status)
            assertTrue(result.assistantText.contains("已验证"))
            assertEquals(1, installs)
            assertEquals(1, reads)
        } finally {
            store.close()
            context.deleteDatabase(database)
            File(context.noBackupFilesDir, "model-loop-leases/${LocalModelLoopContinuation.scope(identity).digest}.lock").delete()
        }
    }
}
