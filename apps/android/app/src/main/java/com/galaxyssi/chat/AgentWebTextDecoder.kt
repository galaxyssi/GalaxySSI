package com.galaxyssi.chat

import okhttp3.MediaType.Companion.toMediaTypeOrNull
import org.jsoup.Jsoup

/** Honor transport charset, BOM and HTML meta declarations before extracting readable text. */
internal object AgentWebTextDecoder {
    fun decode(body: ByteArray, contentType: String, url: String): String {
        val declared = contentType.toMediaTypeOrNull()?.charset()
        val prefix = body.take(256).toByteArray().toString(Charsets.ISO_8859_1).trimStart()
        val html = contentType.contains("html", true) || prefix.startsWith("<!doctype html", true) ||
            prefix.startsWith("<html", true)
        if (!html) return body.toString(declared ?: Charsets.UTF_8).removePrefix("\uFEFF")
        // Jsoup's stream parser detects meta/http-equiv and BOM without guessing from decoded mojibake.
        return body.inputStream().use { Jsoup.parse(it, declared?.name(), url).outerHtml() }
    }

    fun reusable(document: AgentWebIntelligenceDocument): Boolean =
        document.metadata["text_decoder_version"] == 1 || '\uFFFD' !in document.content
}
