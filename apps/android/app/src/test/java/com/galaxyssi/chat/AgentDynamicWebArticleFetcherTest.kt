package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class AgentDynamicWebArticleFetcherTest {
    @Test fun rendererStartupTimeoutKeepsStaticEvidence() {
        val source = html("<p>Static evidence remains available.</p><p>Please enable JavaScript</p>")
        val fetcher = AgentDynamicWebArticleFetcher(requestFetcher { source },
            AgentDynamicWebRenderer { _, _, _, _, _ ->
                throw AgentWebRendererUnavailableException("renderer_connection_timeout")
            })
        val result = fetcher.fetch(source.url, 100_000, 5_000, AgentNativeToolCancellationToken.NONE) {}
        assertTrue(result.body.contentEquals(source.body))
        assertEquals("renderer_connection_timeout", result.dynamicFallbackError)
        assertFalse(result.fetchTier == "isolated_webview")
    }

    @Test fun unavailableRendererDoesNotRepeatAcrossDifferentPages() {
        val health = AgentWebRendererHealth()
        val attempts = AtomicInteger()
        val renderer = AgentDynamicWebRenderer { _, _, _, _, _ ->
            health.checkAvailable()
            attempts.incrementAndGet()
            health.failed()
            throw AgentWebRendererUnavailableException("renderer_initialization_failed")
        }
        val fetcher = AgentDynamicWebArticleFetcher(
            requestFetcher { html("<p>Please enable JavaScript</p>").copy(url = it) }, renderer)
        repeat(3) { index ->
            val result = fetcher.fetch("https://example.com/$index", 100_000, 5_000,
                AgentNativeToolCancellationToken.NONE) {}
            assertTrue(result.body.isNotEmpty())
            assertFalse(result.fetchTier == "isolated_webview")
        }
        assertEquals(1, attempts.get())
    }

    @Test fun cancellationAndOverallDeadlineStillPropagate() {
        for (failure in listOf(AgentNativeToolCancelledException(), AgentNativeToolTimeoutException(),
            java.util.concurrent.CancellationException())) {
            val fetcher = AgentDynamicWebArticleFetcher(
                requestFetcher { html("<p>Please enable JavaScript</p>") },
                AgentDynamicWebRenderer { _, _, _, _, _ -> throw failure })
            org.junit.Assert.assertThrows(failure.javaClass) {
                fetcher.fetch("https://example.com/", 100_000, 5_000, AgentNativeToolCancellationToken.NONE) {}
            }
        }
    }

    @Test
    fun fallbackPolicyDetectsJavascriptShellsAndChallenges() {
        assertEquals(
            "javascript_required",
            AgentDynamicWebFallbackPolicy.reason(html("<p>Please enable JavaScript to continue.</p>"))
        )
        assertEquals(
            "managed_challenge",
            AgentDynamicWebFallbackPolicy.reason(html("<script src='/cf-chl-runtime.js'></script>"))
        )
        assertEquals(
            "thin_javascript_shell",
            AgentDynamicWebFallbackPolicy.reason(
                html("<div id='root'></div><script src='/application.js'></script>")
            )
        )
    }

    @Test
    fun meaningfulServerRenderedPageDoesNotTriggerDynamicFallback() {
        val content = "A server-rendered article with useful evidence. ".repeat(30)

        assertNull(
            AgentDynamicWebFallbackPolicy.reason(
                html("<main><h1>Title</h1><p>$content</p></main><script src='/enhance.js'></script>")
            )
        )
    }

    @Test
    fun thinShellUsesRendererExactlyOnce() {
        val staticCalls = AtomicInteger()
        val renderCalls = AtomicInteger()
        val fetcher = AgentDynamicWebArticleFetcher(
            delegate = requestFetcher {
                staticCalls.incrementAndGet()
                html("<div id='app'></div><script src='/bundle.js'></script>")
            },
            renderer = AgentDynamicWebRenderer { url, _, timeout, _, checkpoint ->
                renderCalls.incrementAndGet()
                checkpoint()
                assertEquals("https://example.com/article", url)
                assertTrue(timeout in 1_000L..5_000L)
                html("<article><h1>Rendered</h1><p>Dynamic body</p></article>")
            }
        )

        val result = fetcher.fetch(
            "https://example.com/article",
            1_000_000L,
            5_000L,
            AgentNativeToolCancellationToken.NONE
        ) {}

        assertEquals(1, staticCalls.get())
        assertEquals(1, renderCalls.get())
        assertEquals("isolated_webview", result.fetchTier)
        assertEquals("thin_javascript_shell", result.dynamicFallbackReason)
        assertTrue(result.body.toString(Charsets.UTF_8).contains("Dynamic body"))
    }

    @Test
    fun rendererFailurePreservesStaticEvidenceAndDiagnostic() {
        val source = html("<div id='__next'></div><script src='/bundle.js'></script>")
        val fetcher = AgentDynamicWebArticleFetcher(
            delegate = requestFetcher { source },
            renderer = AgentDynamicWebRenderer { _, _, _, _, _ -> error("browser unavailable") }
        )

        val result = fetcher.fetch(
            "https://example.com/article",
            1_000_000L,
            5_000L,
            AgentNativeToolCancellationToken.NONE
        ) {}

        assertTrue(result.body.contentEquals(source.body))
        assertEquals("thin_javascript_shell", result.dynamicFallbackReason)
        assertEquals("browser unavailable", result.dynamicFallbackError)
    }

    @Test
    fun recoverableStaticFailureCanUpgradeToRenderer() {
        val renderCalls = AtomicInteger()
        val fetcher = AgentDynamicWebArticleFetcher(
            delegate = requestFetcher { throw IllegalStateException("static connection failed") },
            renderer = AgentDynamicWebRenderer { _, _, _, _, _ ->
                renderCalls.incrementAndGet()
                html("<article><p>Recovered dynamically</p></article>")
            }
        )

        val result = fetcher.fetch(
            "https://example.com/article",
            1_000_000L,
            5_000L,
            AgentNativeToolCancellationToken.NONE
        ) {}

        assertEquals(1, renderCalls.get())
        assertEquals("static_fetch_failed", result.dynamicFallbackReason)
        assertEquals("isolated_webview", result.fetchTier)
    }

    @Test
    fun rendererUrlPolicyRequiresPublicHttpsAndSameOriginNavigation() {
        assertTrue(AgentWebRenderUrlPolicy.allows("https://example.com/article"))
        assertFalse(AgentWebRenderUrlPolicy.allows("http://example.com/article"))
        assertFalse(AgentWebRenderUrlPolicy.allows("https://localhost/article"))
        assertFalse(AgentWebRenderUrlPolicy.allows("https://127.0.0.1/article"))
        assertFalse(AgentWebRenderUrlPolicy.allows("https://100.64.0.1/article"))
        assertFalse(AgentWebRenderUrlPolicy.allows("https://198.18.0.1/article"))
        assertFalse(AgentWebRenderUrlPolicy.allows("https://[::1]/article"))
        assertFalse(AgentWebRenderUrlPolicy.allows("https://user@example.com/article"))
        assertFalse(AgentWebRenderUrlPolicy.resolvesToPublicAddress("https://127.0.0.1/article"))
        assertTrue(AgentWebRenderUrlPolicy.allowsSubresource("data:text/plain,hello"))
        assertFalse(AgentWebRenderUrlPolicy.allowsSubresource("file:///data/local/tmp/page.html"))
        assertTrue(
            AgentWebRenderUrlPolicy.sameOrigin(
                "https://example.com/article",
                "https://example.com/other?q=1"
            )
        )
        assertFalse(
            AgentWebRenderUrlPolicy.sameOrigin(
                "https://example.com/article",
                "https://cdn.example.com/other"
            )
        )
        assertFalse(
            AgentWebRenderUrlPolicy.sameOrigin(
                "https://example.com/article",
                "https://example.com:8443/other"
            )
        )
    }

    private fun requestFetcher(
        block: (String) -> AgentWebIntelligenceFetched
    ) = AgentWebIntelligenceRequestFetcher { url, _, _, _, _, _ -> block(url) }

    private fun html(body: String) = AgentWebIntelligenceFetched(
        url = "https://example.com/article",
        contentType = "text/html; charset=utf-8",
        body = "<!doctype html><html><body>$body</body></html>".toByteArray()
    )
}
