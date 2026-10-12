package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class LocalModelLoopContinuationTest {
    private val identity = AgentLocalDispatchIdentity(71, "local-llm", "conversation", "ui-turn", "transport-session", "action")
    private val manifest = "a".repeat(64)
    private suspend fun prepare(store: LocalModelLoopContinuationStore, id: AgentLocalDispatchIdentity = identity,
        prompt: String = "Original goal", profile: String = "selected-profile", attachments: Boolean = false,
        source: Long? = null, catalog: String = manifest, system: String = "Original system") =
        store.prepare(id, prompt, profile, attachments, source, catalog, system)

    @Test fun restoresOriginalSelectionAndInputFromANewStoreInstance() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val saved = prepare(LocalModelLoopContinuationStore(journal))
        val restored = LocalModelLoopContinuationStore(journal).restore(identity, manifest)
        assertEquals(saved, restored)
        assertEquals("selected-profile", restored.preferredProfileId)
        assertEquals("Original goal", restored.prompt)
        assertEquals(identity.taskId, restored.scope.task)
        assertEquals(identity.turnId, restored.scope.turn)
        assertNotEquals(restored.scope.task, restored.scope.turn)
    }

    @Test fun localeChangeRetainsOriginalSystemPromptAndCheckpointInput() = runBlocking {
        val store = LocalModelLoopContinuationStore(InMemoryAgentModelLoopJournal())
        val original = prepare(store)
        val restored = prepare(store, system = "Different locale system")
        assertEquals(original, restored)
        assertEquals(original.request(emptyList(), AgentNativeToolCancellationToken.NONE, AgentModelToolLoopEventSink.NONE)
            .recoveryInputIdentity, restored.request(emptyList(), AgentNativeToolCancellationToken.NONE,
                AgentModelToolLoopEventSink.NONE).recoveryInputIdentity)
    }

    @Test fun changedInputCannotStartAFreshLoopUnderTheSameDispatch() = runBlocking {
        val store = LocalModelLoopContinuationStore(InMemoryAgentModelLoopJournal())
        val original = prepare(store)
        for (change in listOf<suspend () -> Unit>(
            { prepare(store, prompt = "Different goal") }, { prepare(store, profile = "other-model") },
            { prepare(store, attachments = true) }, { prepare(store, source = 13) },
            { prepare(store, catalog = "b".repeat(64)) })) {
            expect("local_model_saved_request_changed", change)
            assertEquals(original, store.restore(identity, manifest))
        }
    }

    @Test fun allDispatchIdentityFieldsFenceRestoration() = runBlocking {
        val store = LocalModelLoopContinuationStore(InMemoryAgentModelLoopJournal())
        prepare(store)
        val others = listOf(identity.copy(sourceMessageId = 72), identity.copy(contactId = "other-contact"),
            identity.copy(conversationId = "other-conversation"), identity.copy(turnId = "other-turn"),
            identity.copy(taskId = "other-transport"), identity.copy(actionId = "other-action"))
        for (other in others) {
            assertNotEquals(LocalModelLoopContinuation.scope(identity), LocalModelLoopContinuation.scope(other))
            expect("local_model_saved_request_missing") { store.restore(other, manifest) }
        }
    }

    @Test fun identicalPromptsInTwoTurnsRemainIndependent() = runBlocking {
        val store = LocalModelLoopContinuationStore(InMemoryAgentModelLoopJournal())
        val first = prepare(store)
        val secondId = identity.copy(sourceMessageId = 99, turnId = "second-turn")
        val second = prepare(store, id = secondId)
        assertNotEquals(first.scope, second.scope)
        assertEquals(first, store.restore(identity, manifest))
        assertEquals(second, store.restore(secondId, manifest))
    }

    @Test fun catalogChangeIsNotSilentlyAcceptedOnRestore() = runBlocking {
        val store = LocalModelLoopContinuationStore(InMemoryAgentModelLoopJournal())
        prepare(store)
        expect("local_model_saved_catalog_changed") { store.restore(identity, "b".repeat(64)) }
    }

    @Test fun automaticCooperationPreferenceIsPreservedRatherThanForcedToOneModel() = runBlocking {
        val store = LocalModelLoopContinuationStore(InMemoryAgentModelLoopJournal())
        val saved = prepare(store, profile = "", attachments = true, source = 83)
        assertEquals("", store.restore(identity, manifest).preferredProfileId)
        assertEquals(83L, saved.collaborationSourceMessageId)
        val request = saved.request(emptyList(), AgentNativeToolCancellationToken.NONE, AgentModelToolLoopEventSink.NONE)
        assertEquals(saved.scope, AgentModelLoopScope.from(request))
        assertFalse(request.budget.enforceCountLimits)
        assertEquals(60L * 60_000, request.budget.maxDurationMillis)
    }

    @Test fun legacyCheckpointRequiresReconciliationInsteadOfReexecuting() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val scope = LocalModelLoopContinuation.scope(identity).copy(loop =
            LocalModelLoopContinuation.legacyLoopId("Original goal", "selected-profile", false, null))
        journal.withLease(scope) { it.write("initial", "{}") }
        expect("local_model_legacy_checkpoint_requires_reconciliation") {
            prepare(LocalModelLoopContinuationStore(journal))
        }
    }

    @Test fun failedRequestCommitLeavesNoUsableContinuationAndCanBeRetried() = runBlocking {
        val backing = InMemoryAgentModelLoopJournal()
        var failWrite = true
        val journal = object : AgentModelLoopJournal {
            override fun hasRecords(scope: AgentModelLoopScope) = backing.hasRecords(scope)
            override suspend fun <T> withLease(scope: AgentModelLoopScope, block: suspend (AgentModelLoopRecords) -> T): T =
                backing.withLease(scope) { records -> block(object : AgentModelLoopRecords by records {
                    override fun write(operation: String, json: String) {
                        if (failWrite) throw AgentModelLoopRecoveryException("public_commit_failed")
                        records.write(operation, json)
                    }
                }) }
        }
        val store = LocalModelLoopContinuationStore(journal)
        expect("public_commit_failed") { prepare(store) }
        expect("local_model_saved_request_missing") { store.restore(identity, manifest) }
        failWrite = false
        assertEquals(prepare(store), store.restore(identity, manifest))
    }

    @Test fun malformedOrForeignRecordNeverFallsBackToAFreshRequest() = runBlocking {
        for (encoded in listOf("{", "{\"version\":2}",
            "{\"version\":1,\"scope\":{\"session\":\"foreign\"}}")) {
            val journal = object : AgentModelLoopJournal {
                override fun hasRecords(scope: AgentModelLoopScope) = false
                override suspend fun <T> withLease(scope: AgentModelLoopScope, block: suspend (AgentModelLoopRecords) -> T): T =
                    block(object : AgentModelLoopRecords {
                        override fun read(operation: String) = encoded
                        override fun write(operation: String, json: String) = error("Must not overwrite an invalid record")
                    })
            }
            expect("local_model_saved_request_invalid") { prepare(LocalModelLoopContinuationStore(journal)) }
        }
    }

    private suspend fun expect(code: String, block: suspend () -> Unit) {
        try { block(); fail("Expected $code") }
        catch (error: AgentModelLoopRecoveryException) { assertEquals(code, error.message) }
    }
}
