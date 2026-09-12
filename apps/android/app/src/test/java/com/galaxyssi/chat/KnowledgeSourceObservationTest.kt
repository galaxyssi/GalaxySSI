package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class KnowledgeSourceObservationTest {
    private fun item(i: Int) = AgentKnowledgeItem(id = "id-$i", kind = AgentKnowledgeKind.DOCUMENT,
        title = "\u77e5\u8bc6 [${i + 1}/257]", content = "\u79c1\u5bc6\u6b63\u6587 $i",
        source = "content://private/\u6587\u6863", summary = if (i == 0) " " else "\u6458\u8981 $i",
        tags = listOf("tag-$i", " shared  tag ", " "), chunkIndex = i, chunkCount = 257,
        cloudAccess = AgentKnowledgeCloudAccess.entries[i % 3], agentAccess = AgentKnowledgeAgentAccess.entries[i % 3],
        allowedAgentIds = listOf("agent-$i", "shared", "https://host/$i", "C:\\Path\\$i"), updatedAtMillis = i.toLong())

    private fun folded(items: List<AgentKnowledgeItem>) = KnowledgeSourceObservation().apply {
        items.sortedWith(compareBy(AgentKnowledgeItem::chunkIndex, AgentKnowledgeItem::id)).forEach(::add)
    }.finish()
    private fun assertEquivalent(before: List<AgentKnowledgeItem>, after: List<AgentKnowledgeItem>) = assertEquals(
        GlobalPersistentContextObservationExtractor.knowledgeMutations(before, after, 1234),
        GlobalPersistentContextObservationExtractor.knowledgeSourceSnapshots(folded(before), folded(after), 1234))

    @Test fun emptySourceHasNoEvent() = assertEquivalent(emptyList(), emptyList())
    @Test fun importMatchesLegacyAcrossPagesAndMixedMetadata() = assertEquivalent(emptyList(), (256 downTo 0).map(::item))
    @Test fun replacementMatchesLegacyIncludingRetraction() = assertEquivalent((0..70).map(::item), (35..100).map { item(it).copy(content = "new $it") })
    @Test fun deletionMatchesLegacy() = assertEquivalent((0..16).map(::item), emptyList())
    @Test fun identicalSourceAndTimestampOnlyChangesAreNoOps() = assertEquivalent((0..40).map(::item), (0..40).map { item(it).copy(updatedAtMillis = 9999) })
    @Test fun policyOnlyChangeMatchesLegacy() = assertEquivalent((0..25).map(::item), (0..25).map {
        item(it).copy(cloudAccess = AgentKnowledgeCloudAccess.FULL, agentAccess = AgentKnowledgeAgentAccess.ANY_PAIRED_AGENT) })
    @Test fun summaryTagsAndLongAclNormalizationMatchLegacy() = assertEquivalent(emptyList(), (0..80).map {
        item(it).copy(summary = if (it < 5) "\n\t" else "\u4e2d\u6587 ".repeat(400),
            tags = listOf("z", "\u4e2d\u6587", "a$it", " a "), allowedAgentIds = listOf("\u03a3 Agent $it", "first|last")) })
    @Test fun internalItemAndUnicodeOrderMatchLegacy() = assertEquivalent(emptyList(), listOf(item(0).copy(source = "", id = "\ud83d\ude80")))
    @Test fun unorderedDuplicateAndCrossSourceInputAreRejected() {
        val fold = KnowledgeSourceObservation().apply { add(item(1)) }
        assertThrows(IllegalStateException::class.java) { fold.add(item(0)) }
        assertThrows(IllegalStateException::class.java) { fold.add(item(1)) }
        assertThrows(IllegalStateException::class.java) { fold.add(item(2).copy(source = "other")) }
    }
    @Test fun completedAccumulatorCannotBeReused() {
        val fold = KnowledgeSourceObservation().apply { add(item(0)); finish() }
        assertThrows(IllegalStateException::class.java) { fold.finish() }
        assertThrows(IllegalStateException::class.java) { fold.add(item(1)) }
    }
}
