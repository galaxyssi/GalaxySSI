package com.galaxyssi.chat

import org.commonmark.node.AbstractVisitor
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.HtmlBlock
import org.commonmark.node.HtmlInline
import org.commonmark.node.Text
import org.commonmark.parser.Parser

/** Replaceable, source-checked display only; never an accepted answer or a speech input. */
internal class CloudCitationPreview(private val evidence: List<Pair<String, String>>) {
    private val text = StringBuilder()
    private var checkedThrough = 0
    private var published = ""
    private var blocked = false

    fun append(delta: String): String? {
        if (blocked || delta.isEmpty()) return null
        text.append(delta)
        val raw = text.toString()
        if (raw.length > 200_000 || CloudWebGrounding.containsInternalToolProtocol(raw)) {
            blocked = true
            return null
        }
        val boundary = raw.lastIndexOf("\n\n").takeIf { it >= 0 }?.plus(2) ?: return null
        if (boundary <= checkedThrough) return null
        checkedThrough = boundary
        val prefix = raw.substring(0, boundary)
        var unsafe = false
        Parser.builder().build().parse(prefix).accept(object : AbstractVisitor() {
            override fun visit(node: HtmlInline) { unsafe = true }
            override fun visit(node: HtmlBlock) { unsafe = true }
            override fun visit(node: FencedCodeBlock) { unsafe = true }
            override fun visit(node: Text) {
                // An unresolved Markdown link is text in CommonMark; defer it until the final check.
                if ('[' in node.literal || ']' in node.literal) unsafe = true
            }
        })
        if (unsafe || !CloudWebGrounding.citationValidation(prefix, evidence).valid) return null
        if (prefix == published) return null
        published = prefix
        return prefix
    }
}
