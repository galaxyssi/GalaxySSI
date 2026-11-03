package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AgentPlannerToolCatalogBindingTest {
    private val request = AgentModelToolLoopRequest("session", "conversation", "turn", "task", "workspace",
        messages = listOf(AgentModelMessage.user("Preserve the original public goal")),
        loopId = "planner-public", recoveryInputIdentity = "public-original-input")
    private fun descriptor(id: String) = AgentNativeToolDescriptor(id, "1.0.0", "Public tool", "Public contract",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW)

    private class Readiness { var ready = false; var probes = 0; var installs = 0; var reads = 0 }
    private fun registry(state: Readiness, read: AgentNativeToolDescriptor = descriptor("public.browser.read")) =
        AgentNativeToolRegistry(clock = AgentNativeClock { 10L }, descriptorCacheTtlMillis = 60_000).registerAll(listOf(
            AgentToolInspectionTools.definition(),
            AgentNativeToolDefinition(descriptor("public.pack.install"), AgentNativeToolExecutor {
                state.installs++; state.ready = true; AgentNativeToolExecutionResult.success(mapOf("installed" to true))
            }),
            AgentNativeToolDefinition(read.copy(effect = AgentNativeToolEffect.READ_ONLY), AgentNativeToolExecutor {
                state.reads++; AgentNativeToolExecutionResult.success(mapOf("verified" to true))
            }, availabilityProvider = AgentNativeToolAvailabilityProvider {
                state.probes++
                if (state.ready) AgentNativeToolAvailability.AVAILABLE else AgentNativeToolAvailability(
                    AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, "Public dependency missing")
            })))

    private fun model(session: AgentPlannerToolCatalogSession, tool: String? = null, call: String = "observation") =
        AgentModelRequest(request.sessionId, request.conversationId, request.turnId, request.taskId, request.workspaceId,
            1, request.messages + if (tool == null) emptyList() else listOf(AgentModelMessage(AgentModelMessageRole.TOOL,
                toolResult = AgentModelToolResultContent(call, tool, "succeeded", invocationId = call))),
            session.binding.manifest.json, session.binding.manifest.sha256, 10, 10_000, 30_000, 4,
            AgentNativeToolCancellationToken.NONE)

    private suspend fun expect(code: String, body: suspend () -> Unit) {
        try { body(); fail("Expected $code") }
        catch (error: AgentModelLoopRecoveryException) { assertEquals(code, error.message) }
    }

    @Test fun preparedButNotInferredRequestPinsContractsBeforeAnyDependencyChanges() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val state = Readiness()
        val first = AgentPlannerToolCatalogBinding.prepare(journal, request, registry(state))
        assertFalse(journal.hasRecords(AgentModelLoopScope.from(request)))
        assertTrue(first.initialAvailable.descriptors.none { it.id == "public.browser.read" })
        state.ready = true
        val reopened = AgentPlannerToolCatalogBinding.prepare(journal, request, registry(state))
        assertEquals(first.binding.manifest, reopened.binding.manifest)
        assertTrue(reopened.initialAvailable.descriptors.any { it.id == "public.browser.read" })
    }

    @Test fun genuineContractChangesCannotBeMisclassifiedAsReadinessChanges() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val state = Readiness()
        AgentPlannerToolCatalogBinding.prepare(journal, request, registry(state))
        val original = descriptor("public.browser.read")
        val changed = listOf(original.copy(version = "2.0.0"),
            original.copy(inputSchema = AgentNativeJsonSchema.objectSchema(mapOf("page" to AgentNativeJsonSchema.string()))),
            original.copy(requiredPermissions = listOf(AgentNativePermissionRequirement("changed-access"))),
            original.copy(description = "Changed contract"), original.copy(risk = AgentNativeToolRisk.HIGH))
        for (contract in changed) expect("planner_tool_contracts_changed") {
            AgentPlannerToolCatalogBinding.prepare(journal, request, registry(state, contract))
        }
    }

    @Test fun removedOrAddedUnavailableToolsChangeTheRegisteredView() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val state = Readiness()
        val original = registry(state)
        AgentPlannerToolCatalogBinding.prepare(journal, request, original)
        expect("planner_tool_contracts_changed") {
            AgentPlannerToolCatalogBinding.prepare(journal, request, original.subset { it.id != "public.browser.read" })
        }
        original.register(AgentNativeToolDefinition(descriptor("public.extra"), AgentNativeToolExecutor { error("Not executed") },
            availabilityProvider = AgentNativeToolAvailabilityProvider {
                AgentNativeToolAvailability(AgentNativeToolAvailabilityStatus.UNAVAILABLE, "Public unavailable") }))
        expect("planner_tool_contracts_changed") { AgentPlannerToolCatalogBinding.prepare(journal, request, original) }
    }

    @Test fun liveProviderCannotAcquireARegisteredCapabilityOutsideItsPinnedView() = runBlocking {
        val state = Readiness()
        val registry = registry(state)
        val session = AgentPlannerToolCatalogBinding.prepare(InMemoryAgentModelLoopJournal(), request, registry)
        registry.register(AgentNativeToolDefinition(descriptor("public.new-tool"), AgentNativeToolExecutor { error("Not executed") }))
        expect("planner_tool_contracts_changed") { session.providerCatalog(model(session)) }
    }

    @Test fun providerCatalogCannotBeUsedForAnotherConversationTurnOrManifest() = runBlocking {
        val session = AgentPlannerToolCatalogBinding.prepare(InMemoryAgentModelLoopJournal(), request, registry(Readiness()))
        val own = model(session)
        for (foreign in listOf(own.copy(conversationId = "foreign"), own.copy(turnId = "later"),
            own.copy(taskId = "other"), own.copy(sessionId = "different"), own.copy(workspaceId = "elsewhere"),
            own.copy(toolManifestSha256 = "a".repeat(64)))) expect("planner_provider_catalog_owner_changed") {
            session.providerCatalog(foreign)
        }
    }

    @Test fun mutationAndExplicitInspectionRefreshReadinessWithoutWaitingForCacheExpiry() = runBlocking {
        val state = Readiness()
        val session = AgentPlannerToolCatalogBinding.prepare(InMemoryAgentModelLoopJournal(), request, registry(state))
        val before = session.providerCatalog(model(session))
        state.ready = true
        val repaired = session.providerCatalog(model(session, "public.pack.install"))
        assertTrue(repaired.descriptors.any { it.id == "public.browser.read" })
        assertNotEquals(before.manifest.sha256, repaired.manifest.sha256)
        state.ready = false
        val unavailable = session.providerCatalog(model(session, AgentToolInspectionTools.DESCRIBE, "inspect"))
        assertTrue(unavailable.descriptors.none { it.id == "public.browser.read" })
        assertEquals(before.manifest.sha256, unavailable.manifest.sha256)
    }

    @Test fun readOnlyResultsAndRepeatedModelRoundsDoNotForceAvailabilityRescans() = runBlocking {
        val state = Readiness().also { it.ready = true }
        val session = AgentPlannerToolCatalogBinding.prepare(InMemoryAgentModelLoopJournal(), request, registry(state))
        val probes = state.probes
        repeat(3) { session.providerCatalog(model(session, "public.browser.read", "read-$it")) }
        assertEquals(probes, state.probes)
        val mutation = model(session, "public.pack.install", "install")
        session.providerCatalog(mutation)
        val refreshed = state.probes
        repeat(3) { session.providerCatalog(mutation) }
        assertEquals(probes + 1, refreshed)
        assertEquals(refreshed, state.probes)
    }

    @Test fun encodedProviderCatalogUsesTheActualReadinessSnapshotNotTheDurableBindingHash() = runBlocking {
        val state = Readiness()
        val session = AgentPlannerToolCatalogBinding.prepare(InMemoryAgentModelLoopJournal(), request, registry(state))
        val before = session.providerCatalog(model(session))
        state.ready = true
        val after = session.providerCatalog(model(session, "public.pack.install"))
        for (provider in AgentModelToolProvider.entries) {
            val protocol = AgentModelToolProtocolAdapters.forProvider(provider)
            val old = AgentModelToolCatalogSnapshot(protocol, before.descriptors, before.manifest.sha256).encoded
            val current = AgentModelToolCatalogSnapshot(protocol, after.descriptors, after.manifest.sha256).encoded
            assertFalse(old.toString().contains("public.browser.read"))
            assertTrue(current.toString().contains("public.browser.read"))
            assertNotSame(old, current)
        }
    }

    @Test fun legacyParallelReadMetadataDoesNotBecomeAMutationForCacheRefresh() = runBlocking {
        var probes = 0
        val descriptor = descriptor("public.legacy.read").copy(idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY)
        val tools = AgentNativeToolRegistry(clock = AgentNativeClock { 10L }).register(AgentNativeToolDefinition(descriptor,
            AgentNativeToolExecutor { error("Metadata only") }, availabilityProvider = AgentNativeToolAvailabilityProvider {
                probes++; AgentNativeToolAvailability.AVAILABLE
            }))
        val session = AgentPlannerToolCatalogBinding.prepare(InMemoryAgentModelLoopJournal(), request, tools)
        val initialProbes = probes
        repeat(3) { session.providerCatalog(model(session, descriptor.id, "read-$it")) }
        assertEquals(initialProbes, probes)
    }

    @Test fun aLaterReadOnlyResultCannotHideAnEarlierMutationInTheSameToolBatch() = runBlocking {
        val state = Readiness()
        val tools = registry(state).register(AgentNativeToolDefinition(descriptor("public.metadata.observe")
            .copy(effect = AgentNativeToolEffect.READ_ONLY), AgentNativeToolExecutor { error("Metadata only") }))
        val session = AgentPlannerToolCatalogBinding.prepare(InMemoryAgentModelLoopJournal(), request, tools)
        state.ready = true
        val requestWithBatch = model(session).copy(messages = request.messages +
            model(session, "public.pack.install", "install").messages.last() +
            model(session, "public.metadata.observe", "observe").messages.last())
        assertTrue(session.providerCatalog(requestWithBatch).descriptors.any { it.id == "public.browser.read" })
        val probes = state.probes
        session.providerCatalog(requestWithBatch)
        assertEquals(probes, state.probes)
    }

    @Test fun legacyAvailableOnlyCheckpointsKeepTheirExactCatalogAndAreNotPromoted() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val state = Readiness()
        val original = registry(state).availableCatalog()
        journal.withLease(AgentModelLoopScope.from(request)) { AgentModelLoopCheckpoint(it).initial(request, original.manifest.sha256) }
        val legacy = AgentPlannerToolCatalogBinding.prepare(journal, request, registry(state))
        assertEquals(original.manifest, legacy.binding.manifest)
        state.ready = true
        assertEquals(original.manifest, legacy.providerCatalog(model(legacy, "public.pack.install")).manifest)
        expect("planner_legacy_catalog_changed") {
            AgentPlannerToolCatalogBinding.prepare(journal, request, registry(state))
        }
        journal.withLease(AgentModelLoopScope.from(request)) { assertNull(it.read(AgentPlannerToolCatalogBinding.OPERATION)) }
    }

    @Test fun corruptOrForeignMarkersCannotFallBackToANewCatalog() = runBlocking {
        for (encoded in listOf("not-json", """{"version":1,"kind":"registered_contracts_v1","scope":{},"manifest":"${"a".repeat(64)}"}""")) {
            val journal = InMemoryAgentModelLoopJournal()
            journal.withLease(AgentModelLoopScope.from(request)) { it.write(AgentPlannerToolCatalogBinding.OPERATION, encoded) }
            expect("planner_tool_catalog_binding_invalid") { AgentPlannerToolCatalogBinding.prepare(journal, request, registry(Readiness())) }
        }
    }

    @Test fun repairRecoveryKeepsOriginalMessagesAndDoesNotRepeatCommittedInstallation() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val state = Readiness()
        val firstRegistry = registry(state)
        val first = AgentPlannerToolCatalogBinding.prepare(journal, request, firstRegistry)
        try {
            AgentModelToolLoop(AgentModelAdapter { incoming ->
                first.providerCatalog(incoming)
                if (incoming.round == 1) AgentModelResponse(toolCalls = listOf(AgentModelToolCall("install", "public.pack.install")))
                else throw CancellationException("Public interruption after setup")
            }, firstRegistry, disclosedToolManifestJson = first.binding.manifest.json,
                disclosedToolManifestSha256 = first.binding.manifest.sha256, journal = journal).run(request)
            fail("Expected interruption")
        } catch (_: CancellationException) { }
        val restoredRegistry = registry(state)
        val resumed = AgentPlannerToolCatalogBinding.prepare(journal, request, restoredRegistry)
        val result = AgentModelToolLoop(AgentModelAdapter { incoming ->
            assertTrue(resumed.providerCatalog(incoming).descriptors.any { it.id == "public.browser.read" })
            assertTrue(incoming.messages.any { it.text.contains("Preserve the original public goal") })
            when (incoming.round) {
                2 -> AgentModelResponse(toolCalls = listOf(AgentModelToolCall("read", "public.browser.read")))
                3 -> AgentModelResponse("Verified original goal")
                else -> error("Committed inference must not repeat")
            }
        }, restoredRegistry, disclosedToolManifestJson = resumed.binding.manifest.json,
            disclosedToolManifestSha256 = resumed.binding.manifest.sha256, journal = journal)
            .run(request.copy(messages = listOf(AgentModelMessage.user("Fresh volatile context"))))
        assertEquals(AgentModelToolLoopStatus.COMPLETED, result.status)
        assertEquals(1, state.installs)
        assertEquals(1, state.reads)
    }
}
