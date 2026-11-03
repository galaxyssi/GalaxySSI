package com.galaxyssi.chat

import java.io.File
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class AttentionKnowledgeSourcesTest {
    private val topic = AttentionLifeScienceSources.TOPIC
    private val now = 1_793_534_400_000L

    @Test fun pdbArchiveDeduplicatesImageLinksAndKeepsOlderEducationalMaterial() {
        val endpoint = AttentionKnowledgeSources.endpoints[0]
        val html = """<nav><a href="/motm/99">Navigation</a></nav><main>
            <a href="/motm/1"><img src="/one.jpg"></a><a href="/motm/1">Myoglobin</a>
            <a href="/motm/2">DNA polymerase</a><a href="/motm/motm-by-date">Archive</a>
            <a href="https://other.example/motm/3">Other</a></main>"""
        val found = AttentionKnowledgeSources.discover(html, endpoint, topic, now)
        assertEquals(listOf("https://pdb101.rcsb.org/motm/1", "https://pdb101.rcsb.org/motm/2"), found.map { it.url })
        assertTrue(found.all { it.knowledge && it.discoveryDate && it.publishedAt == 0L && it.collectedAt == now })
    }

    @Test fun relativeMedlineAndGlossaryEntriesResolveToArticlesNotSectionMenus() {
        val endpoint = "https://medlineplus.gov/genetics/understanding/howgeneswork/"
        val found = AttentionKnowledgeSources.discover("""<main><a href="protein">What are proteins?</a>
            <a href="makingprotein/">Making proteins</a><a href="../basics/">Basics</a>
            <a href="/genetics/understanding/">Contents</a></main>""", endpoint, topic, now)
        assertEquals(2, found.size)
        assertEquals("$endpoint" + "protein", found.first().url)
        assertEquals("What are proteins?", found.first().title)
        val glossary = AttentionKnowledgeSources.endpoints[1]
        val term = AttentionKnowledgeSources.discover(
            "<a href=\"/genetics-glossary/Ribonucleic-Acid-RNA\">MORE</a>", glossary, topic, now).single()
        assertEquals("Ribonucleic Acid RNA", term.title)
    }

    @Test fun beginnerGuideHasOneActualArticleAndNoUnboundedCrawl() {
        val endpoint = AttentionKnowledgeSources.endpoints[2]
        val result = AttentionKnowledgeSources.discover(
            "<h1>What is protein design?</h1><a href=\"/unrelated\">Unrelated</a>", endpoint, topic, now)
        assertEquals(1, result.size)
        assertEquals("What is protein design?", result.single().title)
        assertTrue(result.single().knowledge)
    }

    @Test fun discoveryRejectsLoginForeignHostsMalformedUrlsAndUnregisteredIndexes() {
        val endpoint = AttentionKnowledgeSources.endpoints[1]
        listOf("http://www.genome.gov/genetics-glossary/DNA", "https://evil.example/genetics-glossary/DNA",
            "https://www.genome.gov/genetics-glossary/DNA?login=1", "https://www.genome.gov/genetics-glossary/DNA#x",
            "https://user@www.genome.gov/genetics-glossary/DNA", "https://www.genome.gov:8080/genetics-glossary/DNA",
            "https://www.genome.gov/login", "https://www.genome.gov/genetics-glossary", "not a URL")
            .forEach { assertFalse(it, AttentionKnowledgeSources.accepts(endpoint, it)) }
        assertFalse(AttentionKnowledgeSources.accepts("https://www.genome.gov/", "$endpoint/DNA"))
    }

    @Test fun pdbBodyKeepsScientificDiscussionAndPicturesButNotPortalOrBibliographicLists() {
        val html = """<div data-elastic-include><h1>Protein</h1><div>Primary scientific explanation.</div>
            <img src="https://cdn.rcsb.org/picture.png"><div><h4>References</h4><ol><li>Author 1960, 185, 422-427.</li></ol></div>
            <div><h4>Topics for Further Discussion</h4><ol><li>Compare mutations.</li></ol></div>
            <div data-elastic-exclude>Related pages</div><ul class="nav-tabs"><li>JSmol</li></ul></div>
            <div id="footer_main"><p>Portal boilerplate.</p></div>"""
        val selected = AttentionEducationArticleBody.select("https://pdb101.rcsb.org/motm/1", Jsoup.parse(html))!!
        assertTrue(selected.text().contains("Primary scientific explanation"))
        assertTrue(selected.text().contains("Compare mutations"))
        assertEquals(1, selected.select("img").size)
        listOf("Author 1960", "Related pages", "JSmol", "Portal boilerplate").forEach { assertFalse(it, selected.text().contains(it)) }
        assertNull(AttentionEducationArticleBody.select("https://example.com/motm/1", Jsoup.parse(html)))
        val mixed = Jsoup.parse("<div data-elastic-include><h4>References</h4><p>Actual prose must remain.</p><ol><li>Sources</li></ol></div>")
        assertTrue(AttentionEducationArticleBody.select("https://pdb101.rcsb.org/motm/2", mixed)!!.text().contains("Actual prose"))
    }

    @Test fun cachedRealIndexesAndArticlesPassProductionParsers() {
        val directory = System.getenv("GALAXYSSI_LIFE_SCIENCE_FIXTURES")?.let(::File)
        assumeTrue("Opt-in public HTTPS fixtures", directory?.isDirectory == true)
        val unique = mutableSetOf<String>()
        for (endpoint in AttentionKnowledgeSources.endpoints) {
            val file = File(directory!!, ProactiveAttentionFeedPolicy.urlKey(endpoint) + ".html")
            assertTrue(endpoint, file.isFile)
            val records = AttentionKnowledgeSources.discover(file.readText(), endpoint, topic, now)
            assertTrue(endpoint, records.isNotEmpty())
            unique += records.map { it.key }
            println("knowledge_catalog endpoint=$endpoint discovered=${records.size}")
        }
        assertTrue("Expected a substantial educational catalog, got ${unique.size}", unique.size >= 500)
        println("knowledge_catalog unique_discoveries=${unique.size}")
        val leaves = listOf(AttentionKnowledgeSources.endpoints[2], "https://pdb101.rcsb.org/motm/1",
            "https://www.genome.gov/genetics-glossary/Ribonucleic-Acid-RNA",
            "https://medlineplus.gov/genetics/understanding/howgeneswork/protein/")
        for (url in leaves) {
            val html = File(directory!!, ProactiveAttentionFeedPolicy.urlKey(url) + ".html").readText()
            val parsed = AttentionArticlePolicy.extractStructured(AgentWebIntelligenceFetched(url, "text/html; charset=utf-8", html.toByteArray()))
            assertTrue(url, parsed.article.content.length >= 200)
            assertFalse(url, parsed.article.title.equals("MORE", true))
            if (url.contains("pdb101")) {
                assertFalse(parsed.document.body.contains("Researchers around the globe"))
                assertFalse(parsed.document.body.contains("Nature 185, 422-427"))
                assertTrue(parsed.document.body.contains("30 times"))
                assertNotNull(parsed.document.cover)
            }
            println("knowledge_body url=$url chars=${parsed.article.content.length}")
        }
        var recent = 0
        for (url in AttentionLifeScienceSources.feeds) {
            val file = File(directory!!, ProactiveAttentionFeedPolicy.urlKey(url) + ".html")
            assertTrue(url, file.isFile)
            val articles = ProactiveAttentionFeedPolicy.parse(file.readText(), topic, now, 90)
            recent += articles.size
            println("life_science_feed url=$url recent_items=${articles.size}")
        }
        println("life_science_feed recent_discoveries=$recent")
    }
}
