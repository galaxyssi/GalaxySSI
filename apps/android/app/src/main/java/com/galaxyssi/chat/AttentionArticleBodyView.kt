package com.galaxyssi.chat

import android.content.Context
import android.graphics.Typeface
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StyleSpan
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

internal class AttentionArticleBodyView(context: Context, document: AttentionArticleDocument,
    private val articleId: String = "") : LinearLayout(context) {
    private val spokenBlocks = mutableListOf<Pair<TextView, Int>>()
    private val playbackListener: (VoiceNewsPlaybackState) -> Unit = { updateSpokenParagraph(it) }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (articleId.isNotBlank()) VoiceNewsPlaybackBus.add(playbackListener)
    }
    override fun onDetachedFromWindow() {
        VoiceNewsPlaybackBus.remove(playbackListener)
        updateSpokenParagraph(VoiceNewsPlaybackState())
        super.onDetachedFromWindow()
    }
    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        updateSpokenParagraph(if (visibility == View.VISIBLE) VoiceNewsPlaybackBus.current else VoiceNewsPlaybackState())
    }
    private fun updateSpokenParagraph(state: VoiceNewsPlaybackState) {
        val spoken = state.paragraph.takeIf { state.articleId == articleId && state.state == "playing" && windowVisibility == View.VISIBLE }.orEmpty()
        spokenBlocks.forEach { (view, color) ->
            val selected = VoiceNewsHighlightPolicy.matches(view.text.toString(), spoken)
            if (view.isSelected != selected) {
                view.isSelected = selected
                view.setBackgroundColor(if (selected) context.getColor(R.color.agent_user_bubble_bg) else color)
            }
        }
    }
    private val blocks = document.blocks.flatMap { block ->
        if (block.kind == "image") listOf(block) else AttentionArticlePolicy.parts(block.text, 1600).map { block.copy(text = it) }
    }
    private var offset = 0
    private var more: View? = null

    init {
        orientation = VERTICAL
        val excerpts = AttentionArticleReadingPolicy.excerpts(document)
        if (excerpts.isNotEmpty()) {
            addView(text(context.getString(R.string.attention_news_excerpts), 12f, true).apply {
                setTextColor(context.getColor(R.color.attention_reader_accent)); setPadding(0, dp(12), 0, dp(6))
            })
            excerpts.take(2).forEach { excerpt -> addView(text("• $excerpt", 15f).apply {
                maxLines = 3; ellipsize = android.text.TextUtils.TruncateAt.END
                tag = "attention-body-excerpt"
                setPadding(dp(10), dp(5), dp(10), dp(5))
                setBackgroundColor(context.getColor(R.color.attention_reader_excerpt_bg))
            }) }
        }
        addView(text(context.getString(R.string.attention_article_body), 12f, true).apply {
            setTextColor(context.getColor(R.color.text_secondary)); setPadding(0, dp(20), 0, dp(8))
        })
        appendPage()
    }

    private fun appendPage() {
        more?.let(::removeView)
        val end = minOf(offset + 30, blocks.size)
        for (index in offset until end) {
            val block = blocks[index]
            if (block.kind == "image") {
                addView(AttentionArticleImageView(context, block), LayoutParams(-1, -2).apply { topMargin = dp(10); bottomMargin = dp(10) })
                continue
            }
            val heading = block.kind == "heading"
            val caption = block.kind == "caption"
            val label = text((if (block.kind == "list") "• " else "") + block.text,
                if (heading) 19f else if (caption) 12f else 16f, heading)
            label.setPadding(if (block.kind == "quote") dp(12) else 0, dp(if (heading) 16 else 5), 0, dp(8))
            if (caption) label.setTextColor(context.getColor(R.color.text_secondary))
            if (block.kind in setOf("code", "table")) label.typeface = Typeface.MONOSPACE
            if (block.kind == "quote") label.setBackgroundColor(context.getColor(R.color.attention_reader_excerpt_bg))
            spokenBlocks.add(label to if (block.kind == "quote") context.getColor(R.color.attention_reader_excerpt_bg) else android.graphics.Color.TRANSPARENT)
            if (!heading) {
                val styled = SpannableString(label.text)
                for (term in block.emphasis) {
                    val start = styled.toString().indexOf(term)
                    if (start >= 0 && term.length <= 120) styled.setSpan(StyleSpan(Typeface.BOLD), start, start + term.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                label.text = styled
            }
            addView(label)
        }
        offset = end
        more = if (offset < blocks.size) text(context.getString(R.string.attention_news_read_more), 14f, true).apply {
            gravity = android.view.Gravity.CENTER; minimumHeight = dp(48)
            setTextColor(context.getColor(R.color.attention_reader_accent))
            setTextIsSelectable(false)
            setOnClickListener { appendPage() }
            tag = "attention-body-more"
            this@AttentionArticleBodyView.addView(this)
        } else null
        updateSpokenParagraph(VoiceNewsPlaybackBus.current)
    }

    private fun text(value: String, size: Float, bold: Boolean = false) = TextView(context).apply {
        text = value; textSize = size
        setTextColor(context.getColor(R.color.text_primary))
        setLineSpacing(dp(5).toFloat(), 1.05f)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setTextIsSelectable(true)
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
