package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class AgentDynamicWebArticleFetcherTest {
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
