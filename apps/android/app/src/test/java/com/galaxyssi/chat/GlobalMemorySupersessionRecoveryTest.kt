package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class GlobalMemorySupersessionRecoveryTest {
    private fun item(id: String, time: Long = 1L) = GlobalWorldItem(
        id = id, stableKey = "shared", kind = GlobalWorldItemKind.FACT, layer = GlobalWorldLayer.TOPIC,
        topic = "Runtime", value = "Runtime ready", confidence = 0.9,
        evidenceCount = 1, conversationIds = setOf("chat"), evidenceEventIds = listOf("event-$id"),
        firstSeenAtMillis = time, lastSeenAtMillis = time)

    @Test fun auditRetainsAllInverseLinksBeyondTwelveDuplicates() {
        val world = PersonalWorldModel(items = (1..40).map { item("item-$it", it.toLong()) })
        val (audited, _) = GlobalMemoryCritic.audit(world, GlobalMemoryInbox(), 100L)
        GlobalMemorySupersessionPolicy.inspect(audited).requireSafe()
        assertEquals(39, audited.items.single { it.status == GlobalWorldItemStatus.ACTIVE }.supersedesItemIds.size)
        assertEquals(40, audited.items.size)
    }

    private fun legacy(): PersonalWorldModel {
        val previous = (1..14).map { item("old-$it").copy(status = GlobalWorldItemStatus.SUPERSEDED,
            temporalState = GlobalMemoryTemporalState.DEPRECATED, supersededByItemId = "new") }
        return PersonalWorldModel(items = previous + item("new", 20L).copy(
            supersedesItemIds = previous.takeLast(12).map { it.id }))
    }

    @Test fun legacyTruncationRestoresOnlyMissingLinksWithoutChangingEvidence() {
        val world = legacy()
        assertEquals(2, GlobalMemorySupersessionPolicy.inspect(world).violations.size)
        val repaired = GlobalMemorySupersessionPolicy.restoreTruncatedForwardLinks(world)
        GlobalMemorySupersessionPolicy.inspect(repaired).requireSafe()
        assertEquals(14, repaired.items.last().supersedesItemIds.size)
        assertEquals(world.items.dropLast(1), repaired.items.dropLast(1))
        assertEquals(world.items.last(), repaired.items.last().copy(supersedesItemIds = world.items.last().supersedesItemIds))
        assertEquals(repaired, GlobalMemorySupersessionPolicy.restoreTruncatedForwardLinks(repaired))
    }

    @Test fun ambiguousOrCrossNamespaceOrMissingTargetsRemainBlocked() {
        val world = legacy()
        val broken = listOf(
            world.copy(items = world.items.dropLast(1)),
            world.copy(items = world.items.map { if (it.id == "old-1") it.copy(namespaceId = "other") else it }),
            world.copy(items = world.items.map { if (it.id == "old-1") it.copy(status = GlobalWorldItemStatus.ACTIVE) else it }),
            world.copy(items = world.items + world.items.first())
        )
        broken.forEach { assertEquals(it, GlobalMemorySupersessionPolicy.restoreTruncatedForwardLinks(it)) }
    }

    @Test fun cyclesAreNeverRepairedIntoAcceptedMemory() {
        val a = item("a").copy(status = GlobalWorldItemStatus.SUPERSEDED, supersededByItemId = "b")
        val b = item("b").copy(status = GlobalWorldItemStatus.SUPERSEDED, supersededByItemId = "a")
        val world = PersonalWorldModel(items = listOf(a, b))
        assertEquals(world, GlobalMemorySupersessionPolicy.restoreTruncatedForwardLinks(world))
        assertTrue(GlobalMemorySupersessionPolicy.inspect(world).violations.contains("cycle"))
    }

    @Test fun candidateCodecPreservesMoreThanTwelveHistoricalLinks() {
        val memory = item("replacement").copy(supersedesItemIds = (1..40).map { "old-$it" })
        val candidate = GlobalMemoryCandidate("candidate", "event", "chat", GlobalMemoryCandidateKind.PROJECT_STATE,
            GlobalMemoryTemporalState.CURRENT, GlobalMemoryCandidateRisk.LOW, GlobalMemoryCandidateStatus.APPROVED,
            item = memory, reason = "fixture")
        val inbox = GlobalMemoryInbox(listOf(candidate))
        assertEquals(memory.supersedesItemIds, GlobalMemoryEvolutionCodec.decodeInbox(
            GlobalMemoryEvolutionCodec.encodeInbox(inbox).toString()).candidates.single().item.supersedesItemIds)
    }
}
