package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class HealthCareEvidenceDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCarePlan) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val plan = HealthCarePlanTestFixture.propose(context, names)
            HealthCareStore(context, names.care).use { test(names, it, plan) }
        } finally { listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun removePlan(names: HealthOverviewDatabases, id: String) {
        context.openOrCreateDatabase(names.care, 0, null).use { it.delete("plans", "id=?", arrayOf(id)) }
    }
    @Test fun nativeProofIsEncryptedAndSurvivesDatabaseReopen(): Unit = fixture { names, store, plan ->
        val proof = plan.sources.single().evidence!!
        assertEquals(proof, store.evidence(proof.id))
        HealthCareStore(context, names.care).use { assertEquals(proof, it.evidence(proof.id)); assertEquals(plan, it.plan(plan.id)) }
        context.openOrCreateDatabase(names.care, 0, null).use { db -> db.rawQuery("SELECT payload FROM evidence_reads", null).use {
            assertTrue(it.moveToFirst()); val encrypted = it.getBlob(0).toString(Charsets.UTF_8)
            assertFalse(encrypted.contains(proof.excerpt)); assertFalse(encrypted.contains(proof.url))
        } }
    }
    @Test fun replayDoesNotCreateDuplicatesOrAllowReceiptRewrite(): Unit = fixture { names, store, plan ->
        val proof = plan.sources.single().evidence!!
        repeat(3) { store.recordEvidence(listOf(proof)); assertEquals(plan, store.proposePlan(plan)) }
        assertTrue(runCatching { store.recordEvidence(listOf(proof.copy(excerpt = "Replaced synthetic source text"))) }.exceptionOrNull() is HealthCareConflict)
        context.openOrCreateDatabase(names.care, 0, null).use { db -> db.rawQuery("SELECT COUNT(*) FROM evidence_reads", null).use {
            it.moveToFirst(); assertEquals(1, it.getInt(0))
        } }
    }
    @Test fun inventedReceiptAndQuoteCannotBeStoredAsGroundedPlan(): Unit = fixture { names, store, plan ->
        removePlan(names, plan.id)
        val source = plan.sources.single()
        listOf(source.copy(evidenceId = UUID.randomUUID().toString(), evidence = null), source.copy(quote = "All results are normal; no follow-up is needed.", evidence = null),
            source.copy(url = "https://example.test/unread", evidence = null)).forEach {
            assertTrue(runCatching { store.proposePlan(plan.copy(sources = listOf(it))) }.exceptionOrNull() is HealthCareEvidenceMissing)
        }
        assertNull(store.plan(plan.id)); assertTrue(store.concern(plan.grant.concernId)!!.actions.isEmpty())
    }
    @Test fun samePageDifferentPassagesStayBoundToTheirOwnAction(): Unit = fixture { names, store, plan ->
        removePlan(names, plan.id)
        val first = plan.sources.single()
        val original = first.evidence!!
        val quote = "Synthetic second passage: record unresolved questions for the next clinician discussion."
        val secondRead = original.copy(id = UUID.randomUUID().toString(), invocationId = UUID.randomUUID().toString(), excerpt = quote)
        store.recordEvidence(listOf(secondRead))
        val second = first.copy(evidenceId = secondRead.id, quote = quote, evidence = null)
        val proposal = store.proposePlan(plan.copy(sources = listOf(first, second), actions = listOf(
            plan.actions.first(), plan.actions.last().copy(evidenceId = secondRead.id, supportingQuote = quote))))
        assertEquals(2, proposal.sources.size)
        assertEquals(secondRead, proposal.sources.last().evidence)
        val accepted = store.resolvePlan(proposal.id, proposal.actions.map { it.id }.toSet(), proposal.grant.revision,
            HealthPrivacyStore(context, names.privacy).use { it.policy() }, proposal.inputVersion, System.currentTimeMillis())
        assertEquals(original.id, accepted.actions.first().evidenceId)
        assertEquals(secondRead.id, accepted.actions.last().evidenceId)
        assertEquals(quote, accepted.actions.last().supportingQuote)
    }
    @Test fun anotherTurnCannotReuseAnEarlierRead(): Unit = fixture { names, store, plan ->
        val grant = plan.grant.copy(turnId = UUID.randomUUID().toString())
        store.approveDiscussion(grant)
        assertTrue(runCatching { store.proposePlan(plan.copy(grant = grant)) }.exceptionOrNull() is HealthCareEvidenceMissing)
        assertNull(store.plan(grant.turnId)); assertEquals(plan, store.plan(plan.id))
    }
    @Test fun concernChangeRejectsLateResearch(): Unit = fixture { _, store, plan ->
        store.update(plan.grant.concernId, plan.grant.revision, "fixture_change") { it.copy(stage = HealthCareStage.PAUSED) }
        assertTrue(runCatching { store.recordEvidence(listOf(plan.sources.single().evidence!!)) }.exceptionOrNull() is HealthCareConflict)
    }
    @Test fun acceptedActionKeepsItsEvidenceAndDeletingConcernRemovesIt(): Unit = fixture { names, store, plan ->
        val saved = store.resolvePlan(plan.id, setOf(plan.actions.first().id), plan.grant.revision,
            HealthPrivacyStore(context, names.privacy).use { it.policy() }, plan.inputVersion, System.currentTimeMillis())
        val action = saved.actions.single()
        assertEquals(plan.sources.single().evidenceId, action.evidenceId)
        assertEquals(plan.sources.single().quote, action.supportingQuote)
        assertNotNull(store.evidence(action.evidenceId))
        store.delete(saved.id, saved.revision)
        assertNull(store.evidence(action.evidenceId)); assertNull(store.plan(plan.id))
    }
    @Test fun indexedReceiptOwnershipCannotBeTampered(): Unit = fixture { names, store, plan ->
        val proof = plan.sources.single().evidence!!
        context.openOrCreateDatabase(names.care, 0, null).use { it.update("evidence_reads",
            ContentValues().apply { put("turn_id", UUID.randomUUID().toString()) }, "id=?", arrayOf(proof.id)) }
        assertTrue(runCatching { store.evidence(proof.id) }.isFailure)
    }
    @Test fun schemaFourUpgradeKeepsExistingConcernAndDoesNotInventReadReceipts(): Unit = fixture { names, store, plan ->
        val prior = store.concern(plan.grant.concernId)
        store.close()
        context.openOrCreateDatabase(names.care, 0, null).use {
            restoreHealthCareSchemaFive(it)
            it.execSQL("DROP TABLE evidence_reads"); it.version = 4
        }
        HealthCareStore(context, names.care).use { assertEquals(prior, it.concern(plan.grant.concernId)); assertNull(it.evidence(plan.sources.single().evidenceId)) }
    }
    @Test fun publicMedicalSourceUsesRealNativeHttpsReadAndEncryptedReceipt() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_evidence_network") == "true")
        fixture { names, store, plan ->
            val web = AgentBoundedWebService(AgentPinnedOkHttpWebTransport())
            val service = AgentWebIntelligenceService(AgentBoundedWebIntelligenceFetcher(web), AgentInMemoryWebIntelligenceStore())
            val registry = AgentNativeToolRegistry()
            HealthCareWebEvidence.wrap(AgentWebIntelligenceNativeTools.definitions(service, web.availability)) { invocation, output ->
                val proofs = HealthCareEvidencePolicy.read(output, plan.grant, invocation.invocationId, System.currentTimeMillis())
                store.recordEvidence(proofs)
                output + ("health_evidence" to proofs.map { it.output() })
            }.forEach(registry::register)
            val result = registry.invoke(AgentWebIntelligenceNativeTools.FETCH, mapOf("url" to
                "https://medlineplus.gov/lab-tests/how-to-understand-your-lab-results/", "force" to true, "length" to 8000,
                "timeout_ms" to 45000), AgentNativeToolInvocationContext(conversationId = plan.grant.conversationId, turnId = plan.grant.turnId))
            assertEquals("Native fetch failed: ${result.error?.code}", AgentNativeToolResultStatus.SUCCEEDED, result.status)
            val proofs = result.output["health_evidence"] as? List<*> ?: error("Missing native receipts")
            assertEquals(1, proofs.size)
            val id = (proofs.single() as Map<*, *>)["evidence_id"].toString()
            val proof = store.evidence(id)!!
            assertTrue(proof.url.startsWith("https://medlineplus.gov/")); assertTrue(proof.excerpt.contains("reference", ignoreCase = true))
            HealthCareStore(context, names.care).use { assertEquals(proof, it.evidence(id)) }
        }
    }
}
