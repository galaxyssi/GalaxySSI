package com.galaxyssi.chat

import java.net.URI
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

/** Publisher-specific reading regions exclude portal navigation while preserving scientific figures. */
internal object AttentionEducationArticleBody {
    fun select(url: String, document: Document): Element? {
        val uri = runCatching { URI(url) }.getOrNull() ?: return null
        if (AttentionOpenTextbooks.isArticle(url)) return document.selectFirst("#main-content [data-type=page]")?.apply {
            // Image zoom controls wrap the actual figure; discard the control, not its image.
            select("button.image-button-wrapper").filter { it.select("img").isNotEmpty() }
                .forEach(Element::unwrap)
        }
        if (uri.host != "pdb101.rcsb.org" || !uri.path.matches(Regex("/motm/[0-9]+/?"))) return null
        val body = document.select("[data-elastic-include]").singleOrNull() ?: return null
        body.select("[data-elastic-exclude],.nav-tabs,iframe").remove()
        // Bibliographic author/page-number lists remain accessible through the original-source link.
        // Do not mistake their proper names for untranslated article prose or delete discussion sections.
        body.select("h4").filter { it.text().trim().equals("References", true) }.forEach { heading ->
            val section = heading.parent() ?: return@forEach
            if (section != body && section.children().size == 2 && section.child(0) == heading &&
                section.child(1).normalName() in setOf("ol", "ul")) section.remove()
        }
        return body
    }
}
