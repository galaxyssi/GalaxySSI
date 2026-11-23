package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import org.jsoup.Jsoup
import java.io.File
import java.util.UUID

internal object WechatArticleExporter {
    private const val IMAGE_TIMEOUT_MILLIS = 4_000L
    private const val IMAGE_BUDGET_MILLIS = 35_000L

    fun export(context: Context, url: String, html: String, checkpoint: () -> Unit): WechatSavedArticle {
        checkpoint()
        val article = WechatArticleDocuments.extract(url, html.toByteArray())
        val source = Jsoup.parse(article.html)
        source.select("script,style,link,iframe,object,embed,svg,canvas,template,noscript,input,button,select,textarea").remove()
        // The native PDF renderer uses text and inline figures, not stylesheet decorations.
        source.select("[style]").forEach { it.removeAttr("style") }
        val hasBodyText = source.selectFirst("#js_content")?.clone()?.apply {
            select("video,audio,picture source").remove()
        }?.text()?.isNotBlank() == true
        val web = AgentBoundedWebService(AgentPinnedOkHttpWebTransport(), policy = AgentWebPolicy(
            maxDownloadBytes = 8L * 1024 * 1024, maxTimeoutMillis = IMAGE_TIMEOUT_MILLIS))
        val imageDeadline = SystemClock.elapsedRealtime() + IMAGE_BUDGET_MILLIS
        var remaining = 48L * 1024 * 1024
        // Only image assets are downloaded here, never the browser's article document.
        val archived = AgentWebOriginalDocument.build(url, source.outerHtml().toByteArray(), notice = { _, _ -> "" }) { address ->
            checkpoint()
            val timeLeft = imageDeadline - SystemClock.elapsedRealtime()
            if (remaining <= 0 || timeLeft <= 0) return@build null
            val image = web.download(address, maxBytes = minOf(8L * 1024 * 1024, remaining),
                timeoutMillis = minOf(IMAGE_TIMEOUT_MILLIS, timeLeft), checkpoint = checkpoint)
            remaining -= image.body.size
            OriginalPageAsset(image.contentType.substringBefore(';').trim(), image.body)
        }
        checkpoint()
        val id = UUID.randomUUID().toString()
        val pdf = File(context.cacheDir, "wechat-$id.pdf")
        try {
            val rendered = WechatArticlePdf.renderExport(archived.html, pdf, hasBodyText,
                context.getString(R.string.wechat_article_missing_image),
                footer = { missing ->
                    context.getString(R.string.wechat_article_static) + "\n" +
                        context.getString(R.string.agent_web_original_archive_notice, missing, url)
                },
                checkpoint = checkpoint)
            return WechatArticlePdf.save(context, pdf, WechatArticleDocuments.fileName(article.title, id.take(8)),
                rendered.pages, rendered.missingImages, checkpoint)
        } finally { pdf.delete() }
    }
}
