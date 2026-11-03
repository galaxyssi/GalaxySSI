package com.galaxyssi.chat

import android.content.Context
import android.graphics.Typeface
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView

internal class AttentionKnowledgeReaderView(context: Context, private val document: AttentionArticleDocument,
    private val articleId: String) : LinearLayout(context) {
    private val figures = AttentionKnowledgeFigures.extract(document)
    private val content = LinearLayout(context).apply { orientation = VERTICAL }
    private val tabs = mutableListOf<TextView>()
    private var selected = -1

    init {
        orientation = VERTICAL
        if (figures != null) {
            val bar = LinearLayout(context).apply { orientation = HORIZONTAL }
            listOf(R.string.attention_knowledge_figures, R.string.attention_knowledge_full_text).forEachIndexed { index, title ->
                val tab = TextView(context).apply {
                    setText(title); textSize = 14f; gravity = Gravity.CENTER
                    setTypeface(typeface, Typeface.BOLD)
                    contentDescription = text; isFocusable = true
                    tag = "attention-knowledge-tab:$index"
                    setOnClickListener { select(index) }
                }
                tabs += tab
                bar.addView(tab, LayoutParams(0, dp(48), 1f))
            }
            addView(bar)
        }
        addView(content)
        select(if (figures == null) 1 else 0)
    }

    private fun select(index: Int) {
        if (selected == index) return
        selected = index
        tabs.forEachIndexed { position, tab ->
            tab.isSelected = position == index
            tab.setTextColor(context.getColor(if (tab.isSelected) R.color.attention_reader_accent else R.color.text_secondary))
            tab.background = if (tab.isSelected) android.graphics.drawable.GradientDrawable().apply {
                setColor(context.getColor(R.color.attention_reader_excerpt_bg)); cornerRadius = dp(4).toFloat()
            } else null
        }
        content.removeAllViews()
        content.addView(AttentionArticleBodyView(context, if (index == 0) figures!! else document, articleId,
            figureMode = index == 0))
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
