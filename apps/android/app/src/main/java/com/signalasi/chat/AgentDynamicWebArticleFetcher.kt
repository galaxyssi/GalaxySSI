package com.signalasi.chat

import android.os.Build
import java.net.URI
import java.util.Locale

/** Adds browser-compatible headers only for article hosts that reject generic HTTP clients. */
class AgentDynamicWebArticleFetcher(
    private val delegate: AgentBoundedWebIntelligenceFetcher
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
        val articleHeaders = AgentDynamicArticleRequestPolicy.headers(url)
        return delegate.fetch(
            url = url,
            maxBytes = maxBytes,
            timeoutMillis = timeoutMillis,
            headers = headers + articleHeaders,
            cancellationToken = cancellationToken,
            checkpoint = checkpoint
        )
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
