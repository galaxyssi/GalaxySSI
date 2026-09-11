package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class AgentPublicImageSearchTest {
    @Test fun automaticImageSearchDoesNotScanLearnedSourcesOrUnrelatedHealth() {
        val requestedHealth = mutableListOf<Set<String>>()
        val coordinator = AgentWebIntelligenceSearchCoordinator(
            fetcher = AgentWebIntelligenceFetcher { _, _, _, _, _ -> error("No network in selection") },
            healthProvider = { error("Full health scan") },
            learnedSourceProvider = { error("Unrelated learned sources scanned") },
            scopedHealthProvider = { ids -> requestedHealth += ids; emptyMap() })
        val selected = coordinator.selectEngines("clownfish", 3, emptyList(), setOf(AgentWebIntelligenceVertical.IMAGE))
        assertTrue(selected.isNotEmpty())
        assertTrue(requestedHealth.single().all { id ->
            AgentWebIntelligenceEngineCatalog.entries.first { it.id == id }.parser in AgentPublicImageSearchParser.directParsers
        })
    }

    private fun row(title: String = "Clownfish photo", image: String = "https://images.example/fish.jpg") = JSONObject()
        .put("title", title).put("url", "https://source.example/fish")
        .put("oriPicUrl", image).put("thumbUrl", "https://thumb.example/fish.jpg")
        .put("width", 800).put("height", 600).put("thumbWidth", 200).put("thumbHeight", 150)

    private fun html(vararg rows: JSONObject): String = "<script>window.__INITIAL_STATE__=" +
        JSONObject().put("searchList", JSONObject().put("searchList", JSONArray(rows.toList()))).toString() + ";</script>"

    @Test fun parsesStructuredPublicImagesWithoutReturningPageLinksAsImages() {
        val result = AgentPublicImageSearchParser.sogou(html(row()), 6).single()
        assertEquals("Clownfish photo", result.title)
        assertEquals("https://source.example/fish", result.url)
        assertEquals("https://images.example/fish.jpg", result.imageUrl)
        assertEquals(800, result.imageWidth)
        assertEquals(600, result.imageHeight)
        assertEquals(AgentWebIntelligenceVertical.IMAGE, result.vertical)
    }

    @Test fun decodesEscapedChineseAndDeduplicatesImages() {
        val encoded = html(row("\u82b1\u4ed9\u9c7c"), row("same photo"))
            .replace("/", "\\u002F")
            .replace("<\\u002Fscript>", "</script>")
        val result = AgentPublicImageSearchParser.sogou(encoded, 6)
        assertEquals(1, result.size)
        assertEquals("\u82b1\u4ed9\u9c7c", result.single().title)
        assertEquals("https://images.example/fish.jpg", result.single().imageUrl)
    }

    @Test fun usesSecurePreviewIfOriginalIsCleartextAndRejectsInvalidSources() {
        val unsafe = row().put("url", "javascript:alert(1)")
        val result = AgentPublicImageSearchParser.sogou(html(unsafe, row(image = "http://images.example/fish.jpg")), 6).single()
        assertEquals("https://thumb.example/fish.jpg", result.imageUrl)
        assertEquals(200, result.imageWidth)
        assertEquals(150, result.imageHeight)
    }

    @Test fun deniesChallengePagesAndDoesNotExecuteJavascript() {
        listOf("<html>Verify you are human</html>", "<script>window.__INITIAL_STATE__=fetch('https://example.com')</script>")
            .forEach { source -> assertTrue(runCatching { AgentPublicImageSearchParser.sogou(source, 6) }.isFailure) }
    }

    @Test fun imageToolUsesFastProfileWithoutFixedFiveSecondOverride() {
        val args = CloudWebGrounding.normalizeArguments("web_image_search", JSONObject().put("query", "clownfish"))
        assertEquals("fast", args["profile"])
        assertEquals(listOf("image"), args["verticals"])
        assertFalse(args.containsKey("timeout_ms"))
        assertEquals(12, args["limit"])
        assertTrue(CloudWebGrounding.currentEvidencePrompt().contains("do not append galaxyssi-rich JSON"))
        assertTrue(CloudWebGrounding.currentEvidencePrompt().contains("not recipes, comparisons"))
    }

    @Test fun imageRouteDoesNotFillSlotsWithGenericWebSearchOrSiteIndexes() {
        val coordinator = AgentWebIntelligenceSearchCoordinator(AgentWebIntelligenceFetcher { _, _, _, _, _ -> error("no network") })
        val engines = coordinator.selectEngines("clownfish", 32, emptyList(), setOf(AgentWebIntelligenceVertical.IMAGE))
        assertTrue(engines.contains("sogou_image"))
        assertTrue(engines.contains("duckduckgo_image"))
        assertFalse(engines.contains("brave_image"))
        assertTrue(engines.all { id -> AgentWebIntelligenceEngineCatalog.entries.first { it.id == id }.parser in AgentPublicImageSearchParser.directParsers })
    }

    @Test fun imageRankingPrefersSubjectTitlesOverKeywordStuffedBodiesAndDiversifiesPages() {
        fun result(rank: Int, title: String, page: String, excerpt: String = "") = AgentWebIntelligenceRawResult(
            engineId = "sogou_image", rank = rank, title = title, url = "https://source.example/$page",
            excerpt = excerpt, vertical = AgentWebIntelligenceVertical.IMAGE,
            imageUrl = "https://image.example/$rank.jpg")
        val ranked = AgentWebIntelligenceFusion().fuse("clownfish", listOf(listOf(
            result(1, "Best things to buy for your home", "unrelated", "clownfish ".repeat(40)),
            result(2, "Clownfish", "fish"),
            result(3, "Clownfish", "fish"),
            result(4, "Clownfish habitat", "habitat")
        )), 3)
        assertEquals("Clownfish", ranked.first().title)
        assertEquals(3, ranked.map { it.url }.distinct().size)
        assertEquals("Clownfish habitat", ranked[1].title)
    }

    @Test fun imageEvidenceDisplaysDiscoveredSecurePreviewWithoutWeakeningOriginalSecurity() {
        val output = AgentWebEvidencePack.attach(mapOf(
            "operation" to "search", "query" to "clownfish", "status" to "completed",
            "results" to listOf(mapOf("url" to "https://source.example/fish", "title" to "Clownfish",
                "image_url" to "https://origin.example/full.jpg", "thumbnail_url" to "https://preview.example/fish.jpg",
                "image_width" to 4000, "image_height" to 3000))
        ), 1)
        val prepared = JSONObject(CloudWebGrounding.boundedModelJson(CloudImageSearchEvidence.prepare(output)))
            .getJSONObject("evidence_pack")
        val picture = prepared.getJSONArray("items").getJSONObject(0).getJSONArray("images").getJSONObject(0)
        assertEquals("https://preview.example/fish.jpg", picture.getString("url"))
        assertEquals("https://origin.example/full.jpg", picture.getString("original_url"))
        assertEquals("search_preview", picture.getString("display_kind"))
        assertFalse(picture.has("width"))
        assertTrue(prepared.getJSONObject("synthesis_contract").has("image_response"))
        val evidence = listOf("web_image_search" to CloudWebGrounding.boundedModelJson(CloudImageSearchEvidence.prepare(output)))
        assertTrue(AgentWebEvidenceVerification.validateAnswer(
            "![Original](https://origin.example/full.jpg) [Source](https://source.example/fish)", evidence).valid)
        assertFalse(AgentWebEvidenceVerification.validateAnswer(
            "![Foreign](https://unknown.example/fish.jpg) [Source](https://source.example/fish)", evidence).valid)
        val noPreview = output.toMutableMap().apply {
            val pack = (get("evidence_pack") as Map<*, *>).entries.associate { it.key.toString() to it.value }.toMutableMap()
            val item = ((pack["items"] as List<*>).first() as Map<*, *>).entries
                .associate { it.key.toString() to it.value }.toMutableMap()
            item["images"] = listOf(mapOf("url" to "https://origin.example/full.jpg",
                "thumbnail_url" to "http://unsafe.example/fish.jpg"))
            pack["items"] = listOf(item)
            put("evidence_pack", pack)
        }
        val unchanged = JSONObject(CloudWebGrounding.boundedModelJson(CloudImageSearchEvidence.prepare(noPreview)))
            .getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0).getJSONArray("images").getJSONObject(0)
        assertEquals("https://origin.example/full.jpg", unchanged.getString("url"))
    }

    @Test fun compactImageEvidenceKeepsPerImageTitlesAndCitationIntegrity() {
        val results = (1..6).map { index -> mapOf(
            "url" to "https://source.example/page-$index", "title" to "Spacecraft $index",
            "excerpt" to "Long source description. ".repeat(90),
            "image_url" to "https://images.example/ship-$index.jpg",
            "thumbnail_url" to "https://preview.example/ship-$index.jpg") } + mapOf(
            "url" to "https://source.example/page-1", "title" to "Character portrait",
            "image_url" to "https://images.example/character.jpg")
        val output = AgentWebEvidencePack.attach(mapOf("operation" to "search", "status" to "completed",
            "query" to "spacecraft interior", "results" to results), 123)
        val before = CloudWebGrounding.boundedModelJson(output)
        val after = CloudWebGrounding.boundedModelJson(CloudImageSearchEvidence.prepare(output))
        assertTrue("Image evidence should avoid sending long article snippets", after.length < before.length * 0.8)
        val pack = JSONObject(after).getJSONObject("evidence_pack")
        assertEquals("spacecraft interior", pack.getString("query"))
        val images = pack.getJSONArray("items").getJSONObject(0).getJSONArray("images")
        assertEquals("Spacecraft 1", images.getJSONObject(0).getString("title"))
        assertEquals("Character portrait", images.getJSONObject(1).getString("title"))
        assertTrue(AgentWebEvidenceVerification.validateAnswer(
            "![Ship](https://preview.example/ship-1.jpg) [Source](https://source.example/page-1)",
            listOf("web_image_search" to after)).valid)
    }

    @Test fun enoughImagesReturnWithoutWaitingForSlowFallbackAndCancelItsTransport() {
        val waiting = CountDownLatch(1)
        val cancelled = CountDownLatch(1)
        val coordinator = AgentWebIntelligenceSearchCoordinator(AgentWebIntelligenceFetcher { url, _, _, token, _ ->
            if (url.contains("sogou.com")) {
                assertTrue(waiting.await(2, TimeUnit.SECONDS))
                AgentWebIntelligenceFetched(url, "text/html", html(row()).toByteArray())
            } else {
                val registration = token.invokeOnCancellation { cancelled.countDown() }
                try {
                    waiting.countDown()
                    cancelled.await(5, TimeUnit.SECONDS)
                    throw AgentNativeToolCancelledException()
                } finally { registration.dispose() }
            }
        })
        val start = System.nanoTime()
        val result = coordinator.search("clownfish", limit = 1, engineFanout = 3,
            verticals = setOf(AgentWebIntelligenceVertical.IMAGE), profile = "fast", timeoutMillis = 10_000)
        assertTrue((System.nanoTime() - start) / 1_000_000 < 2_000)
        assertTrue(result.earlyCompleted)
        assertEquals("sufficient_image_candidates", result.completionReason)
        assertEquals(1, result.results.size)
        assertTrue(cancelled.await(1, TimeUnit.SECONDS))
    }
}
