package com.galaxyssi.chat

import java.net.URI
import org.junit.Assert.*
import org.junit.Test

class AttentionFeedCollectionPlanTest {
    @Test fun discoveryRunsAlongsideSuccessfulOriginalsNotAfterTheEntireBacklog() {
        assertEquals(listOf("a", "search1", "b", "search2", "c"),
            AttentionFeedCollectionPlan.interleave(listOf("a", "b", "c"), listOf("search1", "search2")))
    }

    @Test fun batchesVisitEveryEndpointOnceWithoutDiscardingTheTail() {
        val endpoints = (1..17).map { "https://source$it.example/feed" }
        assertEquals(endpoints, (0 until endpoints.size step AttentionFeedCollectionPlan.BATCH_SIZE)
            .flatMap { AttentionFeedCollectionPlan.batch(endpoints, it) })
        assertTrue(AttentionFeedCollectionPlan.batch(endpoints, endpoints.size).isEmpty())
    }

    @Test fun explicitAndCatalogDuplicatesAreOnlyFetchedOnce() {
        assertEquals(listOf("one", "search", "two"),
            AttentionFeedCollectionPlan.interleave(listOf("one", "two", "one"), listOf("search", "two")))
    }

    @Test fun everyBuiltInTopicHasMultipleOriginalPublishersAndSearch() {
        ProactiveAttentionPolicy.categoryIds.forEach { id ->
            val topic = AttentionTopic(id, id, id)
            assertTrue(id, ProactiveAttentionFeedSources.originals(topic).map { URI(it).host }.distinct().size >= 3)
            assertTrue(id, AttentionFeedCollectionPlan.endpoints(topic).containsAll(ProactiveAttentionFeedPolicy.endpoints(topic)))
        }
    }

    @Test fun catalogCoversIndependentTechnologyFinanceAndBiologySources() {
        val urls = ProactiveAttentionPolicy.categoryIds.flatMap {
            ProactiveAttentionFeedSources.originals(AttentionTopic(it, it, it)) }.distinct()
        assertTrue(urls.map { URI(it).host }.distinct().size >= 12)
        assertTrue(urls.all { ProactiveAttentionFeedPolicy.publicUrl(it) != null })
        val biology = ProactiveAttentionFeedSources.originals(AttentionTopic("protein_life_sciences", "", ""))
        assertTrue(biology.any { it.contains("q-bio") })
        assertTrue(biology.any { it.contains("biology-and-genetics") })
    }

    @Test fun arbitraryInterestsAreNotForcedIntoTechnologyNews() {
        val topic = AttentionTopic("custom-gardening", "Gardening", "Gardening https://example.org/news")
        assertTrue(ProactiveAttentionFeedSources.originals(topic).isEmpty())
        assertTrue(AttentionFeedCollectionPlan.endpoints(topic).contains("https://example.org/news"))
        assertEquals(3, AttentionFeedCollectionPlan.endpoints(topic).size)
    }

    @Test fun discoveryChannelDoesNotMasqueradeAsOriginalPublisher() {
        assertEquals("example.org", AttentionFeedCollectionPlan.publisher("https://www.example.org/article", "Hacker News"))
        assertEquals("Named publisher", AttentionFeedCollectionPlan.publisher("https://example.org/article", "Named publisher"))
        assertEquals("", AttentionFeedCollectionPlan.publisher("", ""))
    }

    @Test fun arxivNamespacedDatesAreNotSilentlyDropped() {
        val now = java.time.Instant.parse("2026-10-23T12:00:00Z").toEpochMilli()
        val xml = """<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <item><title>Protein research</title><link>https://arxiv.org/abs/1234.5678</link>
            <dc:date>2026-10-23T00:00:00Z</dc:date></item></rdf:RDF>"""
        val article = ProactiveAttentionFeedPolicy.parse(xml, "protein_life_sciences", now).single()
        assertFalse(article.discoveryDate)
    }
}
