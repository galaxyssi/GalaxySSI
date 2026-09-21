package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentStableAutoRoutePolicyTest {
    private val codex = target("desktop:t14:codex", AgentConnectorKind.AGENT)
    private val cloud = target("cloud:deepseek", AgentConnectorKind.MODEL)

    @Test fun newConversationUsesSameCodexDefaultAsHeader() {
        assertEquals(codex, AgentStableAutoRoutePolicy.displayedTarget(listOf(cloud, codex), ""))
    }

    @Test fun rememberedCloudIsNotReplacedByCodexDefault() {
        assertEquals(cloud, AgentStableAutoRoutePolicy.displayedTarget(listOf(codex, cloud), cloud.id))
    }

    @Test fun rememberedIdentityNeverMatchesAnotherDesktopBySuffix() {
        val other = codex.copy(id = "desktop:other:codex")
        assertEquals(codex, AgentStableAutoRoutePolicy.displayedTarget(listOf(other, codex), codex.id))
    }

    @Test fun transientHeartbeatDoesNotSilentlyChangeDisplayedIdentity() {
        val disconnected = codex.copy(status = AgentConnectorStatus.DISCONNECTED)
        assertEquals(disconnected, AgentStableAutoRoutePolicy.displayedTarget(listOf(cloud, disconnected), codex.id))
    }

    @Test fun removedPrimaryGetsConfiguredReplacement() {
        assertEquals(cloud, AgentStableAutoRoutePolicy.displayedTarget(listOf(cloud), codex.id))
    }

    @Test fun healthyPrimaryKeepsItsIdentityRegardlessOfSoftScore() {
        val preferred = candidate(codex, 12)
        assertEquals(preferred, AgentStableAutoRoutePolicy.usablePrimary(preferred))
        val selection = AgentStableAutoRoutePolicy.select(listOf(cloud, codex), decision(preferred))
        assertEquals(codex, selection?.target)
        assertTrue(selection?.decision?.fallbacks?.isEmpty() == true)
    }

    @Test fun hardRejectionsCannotBeRevivedByDefaultCodexPreference() {
        for (score in listOf(-10_000, -9_500, -9_100, -9_000, -8_600, -8_500, -8_200, -8_000, -7_000)) {
            assertNull(AgentStableAutoRoutePolicy.usablePrimary(candidate(codex, score)))
        }
        assertEquals(cloud, AgentStableAutoRoutePolicy.select(listOf(codex, cloud), decision(candidate(cloud, 600)))?.target)
    }

    @Test fun noEligibleCandidatesDoesNotBypassSafetyViaCatalog() {
        assertNull(AgentStableAutoRoutePolicy.select(listOf(codex, cloud), decision(null)))
    }

    @Test fun latestFailureScoresChooseAlternative() {
        val ranked = decision(candidate(cloud, 900)).copy(fallbacks = listOf(candidate(codex, 200)))
        assertEquals(cloud, AgentStableAutoRoutePolicy.select(listOf(codex, cloud), ranked)?.target)
    }

    @Test fun oldTurnCannotOverwriteNewerDispatch() {
        assertFalse(AgentStableAutoRoutePolicy.acceptsUpdate("new-turn", "old-turn"))
        assertTrue(AgentStableAutoRoutePolicy.acceptsUpdate("new-turn", "new-turn"))
        assertFalse(AgentStableAutoRoutePolicy.acceptsUpdate("new-turn", ""))
        assertTrue(AgentStableAutoRoutePolicy.acceptsUpdate("", "recovered-turn"))
    }

    private fun target(id: String, kind: AgentConnectorKind) = AgentCallableTarget(
        id, id, kind, AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT, AgentCapability.REASONING)
    )

    private fun candidate(target: AgentCallableTarget, score: Int) = AgentResourceCandidate(
        resource(target), score, emptyList()
    )

    private fun resource(target: AgentCallableTarget) = AgentResourceDescriptor(
        id = "target:${target.id}", title = target.title, targetId = target.id,
        type = if (target == codex) AgentResourceType.REMOTE_AGENT else AgentResourceType.CLOUD_MODEL,
        location = if (target == codex) AgentResourceLocation.TRUSTED_DESKTOP else AgentResourceLocation.CLOUD,
        status = target.status, capabilities = target.capabilities.toSet(), cost = AgentResourceCost.FREE,
        latency = AgentResourceLatency.NORMAL, quality = AgentResourceQuality.STRONG, supportsTools = true
    )

    private fun decision(primary: AgentResourceCandidate?) = AgentRoutingDecision(
        requirements = AgentTaskRequirements(setOf(AgentCapability.CHAT), AgentRoutingMode.BALANCED,
            false, false, false, 100),
        primary = primary, fallbacks = emptyList(), catalog = listOf(resource(codex), resource(cloud))
    )
}
