package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AgentModelHistoryCatalogTest {
    private val scope = AgentModelLoopScope("s", "c", "t", "task", "w", "caller", "loop")
    private fun base() = AgentNativeToolRegistry().register(AgentToolDiscoveryTools.definition())

    @Test fun newRunsPersistTheirSelectionWithoutMutatingTheOriginalRegistry() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val base = base()
        val first = AgentModelHistoryCatalog.prepare(journal, scope, base)
        assertTrue(AgentModelHistoryTools.ID in first.ids())
        assertFalse(AgentModelHistoryTools.ID in base.ids())
        val restored = AgentModelHistoryCatalog.prepare(journal, scope, base())
        assertEquals(first.registeredContractCatalog().manifest, restored.registeredContractCatalog().manifest)
    }

    @Test fun allLegacyBindingKindsRetainTheirExactManifest() = runBlocking {
        for (operation in listOf("initial", AgentPlannerToolCatalogBinding.OPERATION, LocalModelLoopContinuationStore.OPERATION)) {
            val journal = InMemoryAgentModelLoopJournal()
            journal.withLease(scope) { it.write(operation, "{}") }
            val base = base()
            assertSame(base, AgentModelHistoryCatalog.prepare(journal, scope, base))
            journal.withLease(scope) { assertNull(it.read(AgentModelHistoryCatalog.OPERATION)) }
        }
    }

    @Test fun changedContractsCorruptionAndForeignMarkersNeverSilentlyResetHistory() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        AgentModelHistoryCatalog.prepare(journal, scope, base())
        val changed = base().register(AgentToolInspectionTools.definition())
        try { AgentModelHistoryCatalog.prepare(journal, scope, changed); fail("Changed catalog") }
        catch (expected: AgentModelLoopRecoveryException) { assertEquals("model_history_catalog_binding_changed", expected.message) }
        val marker = journal.withLease(scope) { it.read(AgentModelHistoryCatalog.OPERATION)!! }
        for (encoded in listOf(marker, "malformed")) {
            val other = scope.copy(turn = "foreign")
            val copy = InMemoryAgentModelLoopJournal()
            copy.withLease(other) { it.write(AgentModelHistoryCatalog.OPERATION, encoded) }
            try { AgentModelHistoryCatalog.prepare(copy, other, base()); fail("Foreign or corrupt marker") }
            catch (expected: AgentModelLoopRecoveryException) { assertEquals("model_history_catalog_binding_changed", expected.message) }
        }
    }
}
