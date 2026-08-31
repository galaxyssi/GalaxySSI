package com.signalasi.chat

import android.os.Build
import java.net.URI
import java.util.Locale
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit

fun interface AgentDynamicWebRenderer {
    fun render(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched
}

/** Adds article headers and upgrades thin JavaScript pages to the isolated renderer. */
class AgentDynamicWebArticleFetcher(
    private val delegate: AgentWebIntelligenceRequestFetcher,
    private val renderer: AgentDynamicWebRenderer? = null
) : AgentWebIntelligenceFetcher, AgentWebIntelligenceRequestFetcher {
    override fun fetch(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched = fetch(
        url,
        maxBytes,
        timeoutMillis,
        emptyMap(),
        cancellationToken,
        checkpoint
    )

    override fun fetch(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        headers: Map<String, String>,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched {
        val started = System.nanoTime()
        val deadline = started + TimeUnit.MILLISECONDS.toNanos(timeoutMillis.coerceAtLeast(1L))
        val articleHeaders = AgentDynamicArticleRequestPolicy.headers(url)
        val fetched = try {
            delegate.fetch(
                url = url,
                maxBytes = maxBytes,
                timeoutMillis = timeoutMillis,
                headers = headers + articleHeaders,
                cancellationToken = cancellationToken,
                checkpoint = checkpoint
            )
        } catch (error: AgentNativeToolCancelledException) {
            throw error
        } catch (error: AgentNativeToolTimeoutException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (staticError: Exception) {
            val activeRenderer = renderer ?: throw staticError
            val remaining = remainingMillis(deadline)
            if (remaining < MIN_RENDER_TIMEOUT_MILLIS) throw staticError
            return try {
                checkpoint()
                activeRenderer.render(
                    url = url,
                    maxBytes = maxBytes,
                    timeoutMillis = remaining,
                    cancellationToken = cancellationToken,
                    checkpoint = checkpoint
                ).copy(
                    durationMillis = elapsedMillis(started),
                    fetchTier = "isolated_webview",
                    dynamicFallbackReason = "static_fetch_failed"
                )
            } catch (error: AgentNativeToolCancelledException) {
                throw error
            } catch (error: AgentNativeToolTimeoutException) {
                throw error
            } catch (error: CancellationException) {
                throw error
            } catch (rendererError: Exception) {
                staticError.addSuppressed(rendererError)
                throw staticError
            }
        }
        val fallbackReason = AgentDynamicWebFallbackPolicy.reason(fetched) ?: return fetched
        val activeRenderer = renderer ?: return fetched.copy(
            dynamicFallbackReason = fallbackReason,
            dynamicFallbackError = "renderer_unavailable"
        )
        val remaining = remainingMillis(deadline)
        if (remaining < MIN_RENDER_TIMEOUT_MILLIS) {
            return fetched.copy(
                dynamicFallbackReason = fallbackReason,
                dynamicFallbackError = "shared_deadline_exhausted"
            )
        }
        return try {
            checkpoint()
            activeRenderer.render(
                url = fetched.url,
                maxBytes = maxBytes,
                timeoutMillis = remaining,
                cancellationToken = cancellationToken,
                checkpoint = checkpoint
            ).copy(
                durationMillis = elapsedMillis(started),
                fetchTier = "isolated_webview",
                dynamicFallbackReason = fallbackReason
            )
        } catch (error: AgentNativeToolCancelledException) {
            throw error
        } catch (error: AgentNativeToolTimeoutException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            fetched.copy(
                dynamicFallbackReason = fallbackReason,
                dynamicFallbackError = (error.message ?: error.javaClass.simpleName).take(500)
            )
        }
    }

    private fun remainingMillis(deadline: Long): Long = TimeUnit.NANOSECONDS
        .toMillis(deadline - System.nanoTime())
        .coerceAtLeast(0L)

    private fun elapsedMillis(started: Long): Long = TimeUnit.NANOSECONDS
        .toMillis(System.nanoTime() - started)

    private companion object {
        const val MIN_RENDER_TIMEOUT_MILLIS = 1_000L
    }
}

internal object AgentDynamicWebFallbackPolicy {
    private val JAVASCRIPT_REQUIRED = listOf(
        "enable javascript",
        "javascript is required",
        "please enable javascript",
        "\u8bf7\u542f\u7528javascript",
        "\u8bf7\u5f00\u542fjavascript"
    )
    private val MANAGED_CHALLENGE = listOf(
        "cf-chl-",
        "challenge-platform",
        "checking your browser"
    )
    private val APP_SHELL = Regex(
        """<(?:div|main)[^>]+id=["'](?:root|app|__next|application)["'][^>]*>\s*</(?:div|main)>""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
    )

    fun reason(fetched: AgentWebIntelligenceFetched): String? {
        val source = fetched.body.toString(Charsets.UTF_8)
        val html = fetched.contentType.contains("html", true) ||
            source.trimStart().startsWith("<!doctype html", true) ||
            source.trimStart().startsWith("<html", true)
        if (!html) return null
        val lower = source.take(300_000).lowercase(Locale.ROOT)
        if (JAVASCRIPT_REQUIRED.any(lower::contains)) return "javascript_required"
        if (MANAGED_CHALLENGE.any(lower::contains)) return "managed_challenge"
        val visible = AgentWebIntelligenceText.clean(source, 1_000)
        val hasScripts = "<script" in lower
        if (hasScripts && visible.length < 180 && APP_SHELL.containsMatchIn(source)) {
            return "thin_javascript_shell"
        }
        if (hasScripts && visible.isBlank()) return "empty_javascript_shell"
        return null
    }
}

internal object AgentDynamicArticleRequestPolicy {
    private val ARTICLE_HOSTS = setOf("mp.weixin.qq.com")

    fun headers(url: String): Map<String, String> {
        val host = runCatching { URI(url).host.orEmpty().lowercase(Locale.ROOT) }.getOrDefault("")
        if (host !in ARTICLE_HOSTS) return emptyMap()
        return linkedMapOf(
            "Accept" to "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language" to "zh-CN,zh;q=0.9,en;q=0.7",
            "Referer" to "https://mp.weixin.qq.com/",
            "User-Agent" to mobileWechatUserAgent()
        )
    }

    private fun mobileWechatUserAgent(): String {
        val release = Build.VERSION.RELEASE.orEmpty().ifBlank { "14" }
        val model = Build.MODEL.orEmpty().replace(Regex("[^A-Za-z0-9._ -]"), "").ifBlank { "Android" }
        val buildId = Build.ID.orEmpty().replace(Regex("[^A-Za-z0-9._-]"), "").ifBlank { "UP1A" }
        return "Mozilla/5.0 (Linux; Android $release; $model Build/$buildId; wv) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 " +
            "Chrome/140.0.7339.52 Mobile Safari/537.36 " +
            "MicroMessenger/8.0.60 WeChat/arm64 Weixin NetType/WIFI Language/zh_CN ABI/arm64"
    }
}
