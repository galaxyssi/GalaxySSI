package com.galaxyssi.chat

import org.jsoup.Jsoup
import org.jsoup.nodes.DataNode
import org.jsoup.nodes.Element
import java.net.URI
import java.util.Base64

internal data class OriginalPageAsset(val type: String, val bytes: ByteArray)
internal data class OriginalPageDocument(val html: String, val embedded: Int, val missing: Int)

/** Preserves DOM order rather than rebuilding an article from separate text/image lists. */
internal object AgentWebOriginalDocument {
    private val imageTypes = setOf("image/jpeg", "image/png", "image/gif", "image/webp", "image/avif")
    private val cssUrl = Regex("url\\(\\s*(['\"]?)(.*?)\\1\\s*\\)", RegexOption.IGNORE_CASE)

    fun build(url: String, source: ByteArray, load: (String) -> OriginalPageAsset?): OriginalPageDocument {
        val document = source.inputStream().use { Jsoup.parse(it, null, url) }
        document.outputSettings().prettyPrint(false).charset(Charsets.UTF_8)
        var embedded = 0
        val missing = mutableSetOf<String>()
        var missingImages = 0
        var decorationRequests = 0
        val assets = mutableMapOf<String, OriginalPageAsset?>()
        fun absolute(value: String, base: String): String? = runCatching {
            val uri = URI(base).resolve(value.trim())
            uri.toString().takeIf { uri.scheme.equals("https", true) && !uri.host.isNullOrBlank() && uri.userInfo == null }
        }.getOrNull()
        fun asset(value: String, base: String): OriginalPageAsset? {
            val address = absolute(value, base) ?: return null
            if (address !in assets && assets.size < 128) assets[address] = runCatching { load(address) }.getOrNull()
            return assets[address]
        }
        fun image(value: String, base: String): String? {
            if (value.startsWith("data:image/", true)) {
                val type = value.substringAfter("data:").substringBefore(';').lowercase()
                return value.takeIf { type in imageTypes && value.length < 12 * 1024 * 1024 }
            }
            val item = asset(value, base)?.takeIf { it.type.lowercase() in imageTypes } ?: return null
            embedded++
            return "data:${item.type};base64,${Base64.getEncoder().encodeToString(item.bytes)}"
        }
        fun css(text: String, base: String): String = cssUrl.replace(text) { match ->
            val value = match.groupValues[2]
            if (value.isBlank() || value.startsWith('#')) match.value else {
                val address = absolute(value, base)
                val local = if (value.startsWith("data:image/", true) || address in assets || decorationRequests++ < 8)
                    image(value, base) else null
                if (local == null) missing += address ?: value
                "url(\"${local.orEmpty()}\")"
            }
        }.replace(Regex("@import\\s+[^;]+;?", RegexOption.IGNORE_CASE), "").replace("</", "<\\/")

        document.select("script,iframe,object,embed,svg,canvas,template,noscript,input,button,select,textarea,base,meta[http-equiv]").remove()
        document.select("form").forEach { it.unwrap() }
        // Article figures take precedence over optional sprites referenced by large site stylesheets.
        document.select("img").forEach { img ->
            val original = listOf("data-src", "data-original", "data-lazy-src", "src")
                .map(img::attr).firstOrNull(String::isNotBlank).orEmpty()
            val local = image(original, url)
            img.removeAttr("srcset").removeAttr("sizes").removeAttr("loading")
            listOf("data-src", "data-original", "data-lazy-src").forEach(img::removeAttr)
            if (local != null) img.attr("src", local)
            else {
                missing += absolute(original, url) ?: original
                missingImages++
                img.removeAttr("src")
                img.attr("alt", img.attr("alt").ifBlank { "[Image not saved offline]" })
            }
        }
        document.select("link").toList().forEach { link ->
            if (link.attr("rel").equals("stylesheet", true)) {
                val address = absolute(link.attr("href"), url)
                val style = address?.let { asset(it, url) }?.takeIf { it.type.startsWith("text/css") }
                if (style != null) {
                    link.replaceWith(Element("style").appendChild(DataNode(css(style.bytes.toString(Charsets.UTF_8), address!!))))
                } else { missing += address ?: link.attr("href"); link.remove() }
            } else link.remove()
        }
        document.select("style").forEach { style ->
            // External styles were already rewritten; data URLs are retained without downloading again.
            val text = css(style.data(), url)
            style.empty().appendChild(DataNode(text))
        }
        document.getAllElements().forEach { element ->
            element.attributes().asList().filter {
                it.key.startsWith("on", true) || it.key in setOf("srcdoc", "nonce", "integrity", "autofocus")
            }.forEach { element.removeAttr(it.key) }
            if (element.hasAttr("style")) element.attr("style", css(element.attr("style"), url))
        }
        document.select("picture source,video,audio").forEach { element ->
            missing += "media:${element.tagName()}:${element.attr("src")}"
            element.replaceWith(Element("span").text("[Dynamic media not saved offline]"))
        }
        document.select("a[href]").forEach { link ->
            val href = link.attr("href")
            val address = absolute(href, url)
            if (!href.startsWith('#') && address == null) link.removeAttr("href")
            else if (address != null) link.attr("href", address).attr("rel", "noopener noreferrer")
        }
        document.select("#js_content,.rich_media_content").forEach {
            it.attr("style", it.attr("style") + ";visibility:visible!important;opacity:1!important;")
        }
        document.head().select("meta[charset]").remove()
        document.head().prependElement("meta").attr("charset", "utf-8")
        document.head().prependElement("meta").attr("http-equiv", "Content-Security-Policy")
            .attr("content", "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'")
        document.head().appendElement("meta").attr("name", "referrer").attr("content", "no-referrer")
        document.head().appendElement("meta").attr("name", "galaxyssi-archive-missing-assets").attr("content", missing.size.toString())
        document.body().appendElement("p").attr("style", "font:12px sans-serif;color:#666;white-space:normal")
            .text("GalaxySSI 网页静态备份 · 保留抓取时图文顺序；脚本及交互不运行，未加载内容不保证完整。未保存图片：$missingImages；部分字体和装饰可能缺失。来源：$url")
        return OriginalPageDocument(document.outerHtml(), embedded, missing.size)
    }
}
