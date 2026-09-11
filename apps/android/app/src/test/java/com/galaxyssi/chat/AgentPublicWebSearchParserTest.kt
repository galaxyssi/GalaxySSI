package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class AgentPublicWebSearchParserTest {
    @Test fun verificationPagesAreFailuresNotHealthyEmptySearches() {
        for (url in listOf("https://wappass.baidu.com/static/captcha/tuxing_v2.html", "https://www.baidu.com/s")) {
            try {
                AgentPublicWebSearchParser.parse("<title>\u767e\u5ea6\u5b89\u5168\u9a8c\u8bc1</title>", url, 6)
                fail("Verification must not count as an empty successful query")
            } catch (error: AgentWebMediaException) {
                assertEquals("source_verification_required", error.code)
                assertFalse(error.retryable)
            }
        }
    }

    @Test fun baiduOrdinaryCardUsesCanonicalSourceAndServerRenderedSnippet() {
        val hits = AgentPublicWebSearchParser.parse("""
            <div class=c-container mu="https://reference.org/fish">
              <h3><a href="https://www.baidu.com/link?url=opaque">Fish identity</a></h3>
              <div data-module=abstract>Taxonomy and distinguishing features from this source.</div>
            </div>
            <div class=c-container mu="https://second.org/guide">
              <h3><a href="https://www.baidu.com/link?url=opaque2">Field guide</a></h3>
              <div class=c-span-last>Classic result summary.</div>
            </div>
            <div class=c-container mu="https://nourl.ubs.baidu.com/answer">
              <div>Aggregated answer is not an ordinary source result.</div>
            </div>
        """.trimIndent(), "https://www.baidu.com/s?wd=fish", 6)
        assertEquals(listOf("https://reference.org/fish", "https://second.org/guide"), hits.map { it.url })
        assertEquals("Taxonomy and distinguishing features from this source.", hits[0].excerpt)
        assertEquals("Classic result summary.", hits[1].excerpt)
    }

    @Test fun baiduCardMetadataDoesNotPromoteUnsafeUrlsOrRewriteAnotherEngine() {
        val html = """
            <div class=c-container mu="javascript:alert(1)">
              <h3><a href="https://www.baidu.com/link?url=opaque">Unsafe</a></h3>
            </div>
            <div class=c-container mu="https://user:password@reference.org/private">
              <h3><a href="https://www.baidu.com/link?url=opaque2">Credentials</a></h3>
            </div>
        """.trimIndent()
        assertTrue(AgentPublicWebSearchParser.parse(html, "https://www.baidu.com/s", 6).isEmpty())
        val other = AgentPublicWebSearchParser.parse("""
            <div class=c-container mu="https://wrong.org/">
              <h3><a href="https://correct.org/">Ordinary source</a></h3>
            </div>
        """, "https://www.sogou.com/web", 6)
        assertEquals("https://correct.org/", other.single().url)
    }

    @Test fun bingKeepsHeadingAndSnippetInsteadOfSiteBadge() {
        val target = "https://example.org/fish"
        val redirect = "a1" + Base64.getUrlEncoder().withoutPadding().encodeToString(target.toByteArray())
        val hits = AgentPublicWebSearchParser.parse("""
            <nav><a href="https://nav.test">Navigation</a></nav>
            <li class=b_algo><a href="$target">example.org https://example.org</a>
            <h2><a href="/ck/a?u=$redirect">Fish species guide</a></h2>
            <div class=b_caption><p>Scientific name and distinguishing features of this fish.</p></div></li>
            <footer><a href="https://legal.test">Privacy</a></footer>
        """.trimIndent(), "https://www.bing.com/search?q=fish", 6)
        assertEquals(1, hits.size)
        assertEquals("Fish species guide", hits.single().title)
        assertEquals(target, hits.single().url)
        assertTrue(hits.single().excerpt.contains("Scientific name"))
    }

    @Test fun sogouMobileAndLegacyCardsKeepSourceAndSummary() {
        val hits = AgentPublicWebSearchParser.parse("""
            <div class=sa-spacing-text-heading>
              <a href="./id=abc/tc?url=https%3A%2F%2Fzhidao.baidu.com%2Fquestion%2F123"><h2>Fish identity</h2></a>
              <a href="./id=abc/tc?url=https%3A%2F%2Fzhidao.baidu.com%2Fquestion%2F123&amp;linkid=summary">
                <div class=click-sugg-content>Taxonomy and identifying features in the source answer.</div></a>
            </div>
            <div class=vrResult><h3><a href="./tc?url=https%3A%2F%2Fexample.org%2Fguide">Field guide</a></h3>
              <div class=click-sugg-content>Independent reference with additional evidence.</div></div>
        """.trimIndent(), "https://www.sogou.com/web?query=fish", 6)
        assertEquals(2, hits.size)
        assertEquals("https://zhidao.baidu.com/question/123", hits[0].url)
        assertTrue(hits[0].excerpt.contains("Taxonomy"))
        assertTrue(hits[1].excerpt.contains("Independent"))
    }

    @Test fun unsafeUrlsAdsAndNavigationDoNotBecomeResults() {
        val hits = AgentPublicWebSearchParser.parse("""
            <div class=b_ad><h2><a href="https://ad.test">Sponsored</a></h2></div>
            <h2><a href="javascript:alert(1)">Script</a></h2>
            <h2><a href="file:///private">Private file</a></h2>
            <h2><a href="https://user:password@example.test">Credentials</a></h2>
            <a href="https://navigation.test">Navigation</a>
        """.trimIndent(), "https://www.bing.com/search", 6)
        assertTrue(hits.isEmpty())
    }

    @Test fun destinationOnlyUnwrapsSearchHostRedirects() {
        val direct = "https://example.org/page?url=https%3A%2F%2Fother.org%2F"
        assertEquals(direct, AgentPublicWebSearchParser.destination(direct, "https://www.sogou.com/web"))
        assertEquals("", AgentPublicWebSearchParser.destination("/ck/a?u=a1@@@", "https://www.bing.com/search"))
    }

    @Test fun generalLookupDoesNotReadAllLearnedSourcesOrSelectSpecialistIndexes() {
        val coordinator = AgentWebIntelligenceSearchCoordinator(
            fetcher = object : AgentWebIntelligenceFetcher {
                override fun fetch(url: String, maxBytes: Long, timeoutMillis: Long,
                    cancellationToken: AgentNativeToolCancellationToken, checkpoint: () -> Unit): AgentWebIntelligenceFetched = error("Network")
            }, learnedSourceProvider = { error("Full learned-source scan on general lookup") })
        val ids = coordinator.selectEngines("\u82b1\u4ed9\u9c7c \u5b66\u540d", 6, emptyList(), emptySet())
        assertEquals(setOf("baidu", "sogou"), ids.take(2).toSet())
        assertTrue(ids.all { id -> AgentWebIntelligenceEngineCatalog.entries.single { it.id == id }.vertical in
            setOf(AgentWebIntelligenceVertical.GENERAL, AgentWebIntelligenceVertical.REGIONAL) })
    }

    @Test fun earlyCompletionRequiresRelevantSnippetsAndIndependentSitesNotEngineCount() {
        val good = (1..4).map { AgentWebIntelligenceRawResult("sogou", it, "Fish taxonomy", "https://source$it.org/fish",
            excerpt = "Fish taxonomy and scientific identification, with independent source details.") }
        fun enough(rows: List<AgentWebIntelligenceRawResult>, explicit: Boolean = false, profile: String = "fast") =
            AgentWebSearchCompletionPolicy.hasSufficientEvidence(profile, explicit, listOf(rows), 6, query = "fish taxonomy")
        assertTrue(enough(good))
        assertFalse(enough(good.map { it.copy(excerpt = "") }))
        assertFalse(enough(good.map { it.copy(title = "Flower", excerpt = "Gardening instructions and unrelated horticultural advice.") }))
        assertFalse(enough(good.map { it.copy(url = "https://single.org/${it.rank}") }))
        assertFalse(enough(good, explicit = true))
        assertFalse(enough(good, profile = "deep"))
    }

    @Test fun modelCanChooseDepthButOrdinaryWebLookupDefaultsToFast() {
        assertEquals("fast", CloudWebGrounding.normalizeArguments("web_search", JSONObject("""{"query":"test"}"""))["profile"])
        assertEquals("balanced", CloudWebGrounding.normalizeArguments("web_search", JSONObject("""{"query":"test","profile":"balanced"}"""))["profile"])
        assertEquals(3, CloudWebGrounding.normalizeArguments("web_search", JSONObject("""{"query":"test"}"""))["engine_fanout"])
        for (args in listOf("""{"profile":"balanced"}""", """{"profile":"deep"}""", """{"engines":["baidu"]}""")) {
            assertFalse(CloudWebGrounding.normalizeArguments("web_search", JSONObject(args)).containsKey("engine_fanout"))
        }
        assertEquals(8, CloudWebGrounding.normalizeArguments("web_search", JSONObject("""{"profile":"fast","engine_fanout":8}"""))["engine_fanout"])
    }
}
