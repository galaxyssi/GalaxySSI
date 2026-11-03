package com.galaxyssi.chat

import java.net.URI
import java.net.URLDecoder
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class AttentionLifeScienceSourcesTest {
    private val topic = AttentionTopic(AttentionLifeScienceSources.TOPIC, "Life sciences", "Protein design")

    @Test fun variedResearchAndChineseEducationAreMatchedWithoutPhoneFalsePositives() {
        val positive = listOf("Proteins made from scratch", "Antibodies against disease", "Enzymes with new functions",
            "Cell biology of organelles", "Stem cells and tissue repair", "New RNA mechanisms", "mRNA delivery",
            "DNA repair", "Genomics and CRISPR", "Drug discovery through molecular docking", "RFdiffusion methods",
            "ProteinMPNN tutorial", "Proteomics with cryo-EM", "Synthetic biology and metabolic engineering",
            "线粒体如何供能", "细胞的结构", "核酸与遗传", "药物设计基础", "蛋白质科普", "基因编辑与转录",
            "Immunology and vaccines", "Microbiome diversity", "Gene therapy", "Organoids model development",
            "Cell signaling and metabolism", "Pharmacogenomics and targeted therapy", "Cancer biology",
            "Neuroscience and synapses", "靶向治疗基础", "菌群与免疫", "再生医学和药理")
        positive.forEach { title -> assertTrue(title, matches(title)) }
        listOf("New cell phone launched", "Satellite cellular coverage", "折叠手机发布", "Journalism award",
            "General market news", "Internal software design").forEach { title -> assertFalse(title, matches(title)) }
    }

    @Test fun searchesUseIndependentFacetsAndBothDiscoveryProviders() {
        val queries = ProactiveAttentionSourceCatalog.searchQueries(topic)
        assertEquals(16, queries.size)
        assertTrue(queries.all { it.contains(" OR ") })
        val endpoints = ProactiveAttentionFeedPolicy.endpoints(topic)
        assertEquals(32, endpoints.distinct().size)
        queries.forEach { query -> assertEquals(2, endpoints.count { URLDecoder.decode(it, "UTF-8").contains(query) }) }
        assertTrue(endpoints.filter { it.contains("google.com") }.all { it.contains("when%3A90d") })
    }

    @Test fun curatedPublishersAndKnowledgeIndexesSurviveBoundedBatchRotation() {
        val feeds = ProactiveAttentionFeedSources.originals(topic)
        assertEquals(15, feeds.distinct().size)
        assertTrue(feeds.all { URI(it).scheme == "https" && ProactiveAttentionSourceCatalog.dedicated(it, topic.id) })
        val endpoints = AttentionFeedCollectionPlan.endpoints(topic)
        assertEquals(67, endpoints.size)
        assertEquals(feeds.first(), endpoints[0])
        assertEquals(AttentionKnowledgeSources.endpoints.first(), endpoints[1])
        val batches = (endpoints.indices step AttentionFeedCollectionPlan.BATCH_SIZE)
            .map { AttentionFeedCollectionPlan.batch(endpoints, it) }
        assertTrue(batches.all { it.size <= 4 })
        assertEquals(endpoints, batches.flatten())
        assertTrue(endpoints.containsAll(AttentionKnowledgeSources.endpoints))
    }

    @Test fun researchWindowDoesNotPretendOldNewsWasPublishedToday() {
        val now = Instant.parse("2026-11-01T12:00:00Z").toEpochMilli()
        fun feed(days: Int) = "<rss><channel><item><title>Protein design</title><link>https://example.org/article</link>" +
            "<pubDate>${Instant.ofEpochMilli(now - days * 86_400_000L)}</pubDate></item></channel></rss>"
        val age = ProactiveAttentionSourceCatalog.maxAgeDays(topic.id)
        val article = ProactiveAttentionFeedPolicy.parse(feed(60), topic.id, now, age).single()
        assertEquals(now - 60 * 86_400_000L, article.publishedAt)
        assertFalse(article.discoveryDate)
        assertFalse(article.knowledge)
        assertTrue(ProactiveAttentionFeedPolicy.parse(feed(91), topic.id, now, age).isEmpty())
        assertEquals(30, ProactiveAttentionSourceCatalog.maxAgeDays("research_papers"))
        assertEquals(7, ProactiveAttentionSourceCatalog.maxAgeDays("ai_models"))
        assertTrue(AttentionKnowledgeSources.endpoints("ai_models").isEmpty())
    }

    private fun matches(title: String) = ProactiveAttentionFeedSources.matches(
        AttentionFeedArticle("a", topic.id, title, "", "https://example.org/a", "Example", 1, 1), topic)
}
