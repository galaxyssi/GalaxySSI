package com.galaxyssi.chat

import android.content.Context
import org.jsoup.Jsoup
import java.io.File
import java.util.UUID

internal object WechatArticleExporter {
    fun export(context: Context, url: String, html: String, checkpoint: () -> Unit): WechatSavedArticle {
        checkpoint()
        val article = WechatArticleDocuments.extract(url, html.toByteArray())
        val web = AgentBoundedWebService(AgentPinnedOkHttpWebTransport(), policy = AgentWebPolicy(
            maxDownloadBytes = 8L * 1024 * 1024, maxTimeoutMillis = 20_000))
        var remaining = 48L * 1024 * 1024
        // Only image assets are downloaded here, never the browser's article document.
        val archived = AgentWebOriginalDocument.build(url, article.html.toByteArray()) { address ->
            checkpoint()
            check(remaining > 0) { "article_asset_limit" }
            val image = web.download(address, maxBytes = minOf(8L * 1024 * 1024, remaining), checkpoint = checkpoint)
            remaining -= image.body.size
            OriginalPageAsset(image.contentType.substringBefore(';').trim(), image.body)
        }
        checkpoint()
        check(archived.missing == 0) { "article_assets_incomplete" }
        val document = Jsoup.parse(archived.html)
        document.body().appendElement("p").text(context.getString(R.string.wechat_article_static))
        val id = UUID.randomUUID().toString()
        val pdf = File(context.cacheDir, "wechat-$id.pdf")
        try {
            val pages = WechatArticlePdf.render(document.outerHtml(), pdf, checkpoint)
            return WechatArticlePdf.save(context, pdf, WechatArticleDocuments.fileName(article.title, id.take(8)), pages, checkpoint)
        } finally { pdf.delete() }
    }
}
