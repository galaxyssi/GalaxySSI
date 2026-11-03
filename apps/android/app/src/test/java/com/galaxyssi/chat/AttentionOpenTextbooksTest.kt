package com.galaxyssi.chat

import java.io.File
import org.json.JSONObject
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class AttentionOpenTextbooksTest {
    private val endpoint = AttentionOpenTextbooks.endpoints.first()
    private fun page(tree: String, slug: String = "biology-2e") = Jsoup.parse("""<script>
        window.__PRELOADED_STATE__ = {"content":{"book":{"slug":"$slug","tree":$tree}}};
        </script>""")

    @Test fun structuredTocIncludesOnlyRealSectionsAndDoesNotExecuteScripts() {
        val tree = """{"contents":[{"title":"<span>4.3</span> Eukaryotic Cells","slug":"4-3-eukaryotic-cells","toc_target_type":"numbered-section"},
            {"slug":"4-review-questions","toc_target_type":"composite-page"},
            {"slug":"4-3-eukaryotic-cells","toc_target_type":"numbered-section"},
            {"slug":"../../login","toc_target_type":"numbered-section"}]}"""
        val result = AttentionOpenTextbooks.discover(page(tree), endpoint)
        assertEquals(1, result.size)
        assertEquals("4.3 Eukaryotic Cells", result.single().second)
        val script = Jsoup.parse("<script>window.__PRELOADED_STATE__ = fetch('https://evil.example');</script>")
        assertTrue(runCatching { AttentionOpenTextbooks.discover(script, endpoint) }.isFailure)
        assertTrue(runCatching { AttentionOpenTextbooks.discover(page(tree, "chemistry"), endpoint) }.isFailure)
    }

    @Test fun catalogsRejectForeignBooksQueriesAndTraversal() {
        val valid = "https://openstax.org/books/biology-2e/pages/17-1-biotechnology"
        assertTrue(AttentionOpenTextbooks.accepts(endpoint, valid))
        listOf(valid.replace("biology-2e", "chemistry"), "$valid?login=1", "$valid#section",
            valid.replace("https:", "http:"), valid.replace("openstax.org", "evil.example"),
            valid.replace("openstax.org", "user@openstax.org"), valid.replace("17-1-biotechnology", "../../login"))
            .forEach { assertFalse(it, AttentionOpenTextbooks.accepts(endpoint, it)) }
        var deep = JSONObject().put("contents", org.json.JSONArray())
        repeat(15) { deep = JSONObject().put("contents", org.json.JSONArray().put(deep)) }
        assertTrue(runCatching { AttentionOpenTextbooks.discover(page(deep.toString()), endpoint) }.isFailure)
    }

    @Test fun realTextbooksHaveBroadTocsAndCompleteScientificFigures() {
        val directory = System.getenv("GALAXYSSI_LIFE_SCIENCE_FIXTURES")?.let(::File)
        assumeTrue("Opt-in public HTTPS fixtures", directory?.isDirectory == true)
        fun html(url: String) = File(directory!!, ProactiveAttentionFeedPolicy.urlKey(url) + ".html").readText()
        var sections = 0
        AttentionOpenTextbooks.endpoints.forEach { url ->
            val found = AttentionOpenTextbooks.discover(Jsoup.parse(html(url)), url)
            assertTrue(url, found.size > 80)
            assertTrue(found.all { AttentionKnowledgeSources.accepts(url, it.first) })
            sections += found.size
            println("textbook_catalog url=$url sections=${found.size}")
        }
        assertTrue(sections > 400)
        val leaves = listOf("biology-2e/pages/4-3-eukaryotic-cells", "biology-2e/pages/17-1-biotechnology",
            "microbiology/pages/18-1-overview-of-specific-adaptive-immunity", "anatomy-and-physiology-2e/pages/3-1-the-cell-membrane")
        for (leaf in leaves) {
            val url = "https://openstax.org/books/$leaf"
            val source = AttentionArticlePolicy.extractStructured(AgentWebIntelligenceFetched(url, "text/html", html(url).toByteArray()))
            assertTrue(url, source.document.blocks.count { it.kind == "image" } >= 2)
            assertTrue(url, source.document.blocks.any { it.kind == "caption" })
            assertFalse(source.document.body.contains("Sign up"))
            val attribution = source.document.blocks.single { it.kind == "attribution" }
            assertTrue(attribution.text.contains("OpenStax"))
            assertTrue(attribution.url.startsWith("https://creativecommons.org/licenses/"))
            println("textbook_body url=$url chars=${source.article.content.length} figures=${source.document.blocks.count { it.kind == "image" }}")
        }
    }

    @Test fun sidebarClosedLayoutDoesNotEraseTheTextbookReadingPane() {
        val url = "https://openstax.org/books/biology-2e/pages/4-3-eukaryotic-cells"
        val prose = "The cell membrane separates the cytoplasm from the surrounding environment. ".repeat(8)
        val html = """<h1>Eukaryotic cells</h1><div class="content-pane-wrapper--sidebar-closed-mobile">
            <div id="main-content"><div data-type="page"><p>$prose</p><figure>
            <button class="image-button-wrapper"><img src="/cell.png" width="600" height="900" alt="Cell structure"></button>
            <figcaption>Figure 4.8. The cell.</figcaption>
            </figure></div></div><aside class="sidebar">Unrelated navigation</aside></div>"""
        val source = AttentionArticlePolicy.extractStructured(AgentWebIntelligenceFetched(url, "text/html", html.toByteArray()))
        assertTrue(source.document.body.contains("The cell membrane"))
        assertFalse(source.document.body.contains("Unrelated navigation"))
        assertEquals("https://openstax.org/cell.png", source.document.cover!!.url)
    }
}
