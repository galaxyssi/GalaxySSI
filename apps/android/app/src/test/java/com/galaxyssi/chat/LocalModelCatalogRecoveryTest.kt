package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class LocalModelCatalogRecoveryTest {
    private val identity = AgentLocalDispatchIdentity(19, "local-llm", "public-conversation", "public-turn",
        "public-native-task", "public-action")
    private val stable = "a".repeat(64)
    private val before = "b".repeat(64)
    private val after = "c".repeat(64)

    @Test fun newContinuationKeepsOriginalInputAcrossAvailabilityChanges() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val store = LocalModelLoopContinuationStore(journal)
        val original = store.prepare(identity, "Preserve the public goal", "selected-profile", false, null,
            stable, "Original system", before)
        assertEquals(LocalModelLoopContinuation.REGISTERED_CONTRACTS, original.catalogBinding)
        assertEquals(original, LocalModelLoopContinuationStore(journal).restore(identity, stable, after))
        assertEquals(original, store.prepare(identity, original.prompt, original.preferredProfileId, false, null,
            stable, "Changed locale", after))
        expect("local_model_saved_catalog_changed") { store.restore(identity, "d".repeat(64), after) }
        expect("local_model_saved_request_changed") {
            store.prepare(identity, "Changed goal", original.preferredProfileId, false, null, stable, "Original system", after)
        }
        expect("local_model_saved_request_missing") { store.restore(identity.copy(actionId = "other"), stable, after) }
    }

    @Test fun legacySnapshotIsNotSilentlyPromotedToAContractBinding() = runBlocking {
        val store = LocalModelLoopContinuationStore(InMemoryAgentModelLoopJournal())
        val old = store.prepare(identity, "Original goal", "profile", false, null, before, "Original system")
        assertEquals(old, store.restore(identity, stable, before))
        assertEquals(old, store.prepare(identity, old.prompt, old.preferredProfileId, false, null,
            stable, "Other locale", before))
        assertEquals(LocalModelLoopContinuation.AVAILABLE_SNAPSHOT, old.catalogBinding)
        expect("local_model_saved_catalog_changed") { store.restore(identity, stable, after) }
        expect("local_model_saved_catalog_changed") {
            store.prepare(identity, old.prompt, old.preferredProfileId, false, null, stable, "Original system", after)
        }
    }

    @Test fun repairedDependencyCanResumeWithoutRepeatingTheCommittedInstallation() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        var ready = false
        var installs = 0
        var reads = 0
        fun descriptor(id: String) = AgentNativeToolDescriptor(id, "1.0.0", "Fixture tool", "Fixture contract",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
            AgentNativeToolRisk.LOW)
        fun registry() = AgentNativeToolRegistry().registerAll(listOf(
            AgentNativeToolDefinition(descriptor("public.pack.install"), AgentNativeToolExecutor {
                installs++; ready = true; AgentNativeToolExecutionResult.success(mapOf("installed" to true))
            }),
            AgentNativeToolDefinition(descriptor("public.browser.read").copy(
                requiredPermissions = listOf(AgentNativePermissionRequirement("public-page")),
                effect = AgentNativeToolEffect.READ_ONLY, idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
                AgentNativeToolExecutor { reads++; AgentNativeToolExecutionResult.success(mapOf("verified" to true)) },
                availabilityProvider = AgentNativeToolAvailabilityProvider { if (ready) AgentNativeToolAvailability.AVAILABLE
                    else AgentNativeToolAvailability(AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, "Fixture absent") })))
        val initialRegistry = registry()
        val contract = initialRegistry.registeredContractCatalog()
        val available = initialRegistry.availableCatalog()
        assertTrue(available.descriptors.none { it.id == "public.browser.read" })
        val saved = LocalModelLoopContinuationStore(journal).prepare(identity, "Read the public page", "fixture", false,
            null, contract.manifest.sha256, "Original system", available.manifest.sha256)
        fun request(value: LocalModelLoopContinuation, catalog: AgentNativeToolCatalogView) = value.request(
            catalog.descriptors, AgentNativeToolCancellationToken.NONE, AgentModelToolLoopEventSink.NONE)
        try {
            AgentModelToolLoop(AgentModelAdapter {
                if (it.round == 1) AgentModelResponse(toolCalls = listOf(AgentModelToolCall("install", "public.pack.install")))
                else throw CancellationException("Fixture process interrupted after dependency commit")
            }, initialRegistry, disclosedToolManifestJson = contract.manifest.json,
                disclosedToolManifestSha256 = contract.manifest.sha256, journal = journal).run(request(saved, contract))
            fail("Expected fixture interruption")
        } catch (_: CancellationException) { }
        val repairedRegistry = registry()
        val repaired = repairedRegistry.registeredContractCatalog()
        assertNotEquals(available.manifest.sha256, repairedRegistry.availableCatalog().manifest.sha256)
        assertEquals(contract.manifest, repaired.manifest)
        val restored = LocalModelLoopContinuationStore(journal).restore(identity, repaired.manifest.sha256,
            repairedRegistry.availableCatalog().manifest.sha256)
        val result = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                2 -> {
                    assertEquals(true, it.messages.last().toolResult?.output?.get("installed"))
                    AgentModelResponse(toolCalls = listOf(AgentModelToolCall("verify", "public.browser.read")))
                }
                3 -> {
                    assertEquals(true, it.messages.last().toolResult?.output?.get("verified"))
                    AgentModelResponse("Verified original public goal")
                }
                else -> error("Committed model round must be replayed, not inferred again")
            }
        }, repairedRegistry, disclosedToolManifestJson = repaired.manifest.json,
            disclosedToolManifestSha256 = repaired.manifest.sha256, journal = journal).run(request(restored, repaired))
        assertEquals(AgentModelToolLoopStatus.COMPLETED, result.status)
        assertEquals(1, installs)
        assertEquals(1, reads)
    }

    private suspend fun expect(code: String, block: suspend () -> Unit) {
        try { block(); fail("Expected $code") }
        catch (error: AgentModelLoopRecoveryException) { assertEquals(code, error.message) }
    }
}
