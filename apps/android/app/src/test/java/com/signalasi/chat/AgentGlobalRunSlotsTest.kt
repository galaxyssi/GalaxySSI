package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentGlobalRunSlotsTest {
    @Test
    fun `ten conversations share one runtime capacity`() {
        val ledger = AgentGlobalRunSlotLedger()

        repeat(10) { index ->
            assertTrue(ledger.acquire("conversation-$index", "desktop-a:codex", 10, index.toLong()))
        }

        assertEquals(10, ledger.activeCount("desktop-a:codex"))
        assertFalse(ledger.acquire("conversation-11", "desktop-a:codex", 10, 11L))
        assertTrue(ledger.acquire("deepseek-1", "cloud-model:deepseek", 10, 11L))
    }

    @Test
    fun `terminal source releases a global slot`() {
        val ledger = AgentGlobalRunSlotLedger()
        assertTrue(ledger.acquire("run-1", "desktop-a:codex", 10, 1L))
        assertTrue(ledger.bindSourceMessage("run-1", 42L))

        assertTrue(ledger.releaseBySourceMessageId(42L))

        assertEquals(0, ledger.activeCount("desktop-a:codex"))
    }

    @Test
    fun `stream activity renews slot before inactivity pruning`() {
        val ledger = AgentGlobalRunSlotLedger()
        assertTrue(ledger.acquire("run-1", "desktop-a:codex", 10, 1_000L))
        assertTrue(ledger.bindSourceMessage("run-1", 42L))

        assertTrue(ledger.touchBySourceMessageId(42L, 5_000L))
        assertFalse(ledger.pruneBefore(4_000L))
        assertEquals(1, ledger.activeCount("desktop-a:codex"))

        assertTrue(ledger.pruneBefore(6_000L))
        assertEquals(0, ledger.activeCount("desktop-a:codex"))
    }

    @Test
    fun `mention picker hides generic alias when concrete runtime is available`() {
        val generic = registration("codex", "Codex", "desktop-a:codex")
        val concrete = registration(
            "desktop-a:codex",
            "Codex Agent · DESKTOP-T14",
            "desktop-a:codex",
            activeRuns = 4
        )
        val targets = listOf(generic, concrete).map { registration ->
            AgentCallableTarget(
                id = registration.agentId,
                title = registration.displayName,
                kind = AgentConnectorKind.AGENT,
                status = AgentConnectorStatus.AVAILABLE,
                capabilities = registration.capabilities.toList(),
                runtimeFailureDomain = registration.runtimeFailureDomain
            )
        }

        val selected = AgentMentionCandidatePolicy.select(
            targets = targets,
            registrations = listOf(generic, concrete),
            reservedByAgentId = emptyMap(),
            limit = 12
        )

        assertEquals(listOf("desktop-a:codex"), selected.map(AgentRegistration::agentId))
        assertEquals(4, selected.single().activeRuns)
        assertEquals(10, selected.single().maxParallelRuns)
    }

    @Test
    fun `mention picker keeps generic alias without concrete endpoint`() {
        val generic = registration("codex", "Codex", "desktop-a:codex")
        val target = AgentCallableTarget(
            id = generic.agentId,
            title = generic.displayName,
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = generic.capabilities.toList(),
            runtimeFailureDomain = generic.runtimeFailureDomain
        )

        val selected = AgentMentionCandidatePolicy.select(
            targets = listOf(target),
            registrations = listOf(generic),
            reservedByAgentId = emptyMap(),
            limit = 12
        )

        assertEquals(listOf("codex"), selected.map(AgentRegistration::agentId))
    }

    @Test
    fun `generic alias is hidden by concrete product even when runtime domains differ`() {
        val generic = registration("codex", "Codex", "builtin:codex")
        val concrete = registration(
            "desktop-a:codex",
            "Codex Agent · DESKTOP-T14",
            "desktop-a:codex"
        )
        val targets = listOf(generic, concrete).map { registration ->
            AgentCallableTarget(
                id = registration.agentId,
                title = registration.displayName,
                kind = AgentConnectorKind.AGENT,
                status = AgentConnectorStatus.AVAILABLE,
                capabilities = registration.capabilities.toList(),
                runtimeFailureDomain = registration.runtimeFailureDomain
            )
        }

        val selected = AgentMentionCandidatePolicy.select(
            targets = targets,
            registrations = listOf(generic, concrete),
            reservedByAgentId = emptyMap(),
            limit = 12
        )

        assertEquals(listOf("desktop-a:codex"), selected.map(AgentRegistration::agentId))
    }

    @Test
    fun `generic alias stays hidden when concrete runtime is reserved to capacity`() {
        val generic = registration("codex", "Codex", "desktop-a:codex")
        val concrete = registration("desktop-a:codex", "Codex Agent", "desktop-a:codex")
        val targets = listOf(generic, concrete).map { registration ->
            AgentCallableTarget(
                id = registration.agentId,
                title = registration.displayName,
                kind = AgentConnectorKind.AGENT,
                status = AgentConnectorStatus.AVAILABLE,
                capabilities = registration.capabilities.toList(),
                runtimeFailureDomain = registration.runtimeFailureDomain
            )
        }

        val selected = AgentMentionCandidatePolicy.select(
            targets = targets,
            registrations = listOf(generic, concrete),
            reservedByAgentId = mapOf(concrete.agentId to 10),
            limit = 12
        )

        assertTrue(selected.isEmpty())
    }

    private fun registration(
        agentId: String,
        displayName: String,
        runtimeKey: String,
        activeRuns: Int = 0
    ) = AgentRegistration(
        agentId = agentId,
        installationId = "desktop-a",
        deviceId = "desktop-a",
        providerId = "desktop-a",
        displayName = displayName,
        kind = AgentConnectorKind.AGENT,
        location = AgentResourceLocation.TRUSTED_DESKTOP,
        status = AgentEndpointStatus.ONLINE,
        capabilities = setOf(AgentCapability.CHAT, AgentCapability.TASK_EXECUTION),
        protocol = AgentProtocolRange("1.0", "1.0", "1.0"),
        connectionKind = AgentConnectionKind.SIGNALASI_LINK,
        activeRuns = activeRuns,
        maxParallelRuns = 10,
        failureDomain = "desktop-a",
        runtimeFailureDomain = runtimeKey,
        adapterType = "codex-app-server-or-cli"
    )
}
