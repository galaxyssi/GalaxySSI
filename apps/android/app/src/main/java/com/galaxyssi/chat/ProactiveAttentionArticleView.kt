package com.galaxyssi.chat

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.text.TextUtils
import android.text.method.LinkMovementMethod
import android.view.Gravity
import android.view.View
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONObject

internal class ProactiveAttentionArticleView(
    context: Context,
    private val toggle: (String) -> Unit,
    private val save: (String) -> Unit,
    private val ask: (GlobalProactiveInboxItem) -> Unit,
    private val sources: (GlobalProactiveInboxItem) -> Unit,
    private val evidence: (GlobalProactiveInboxItem, (JSONObject?) -> Unit) -> Unit,
    private val menu: (GlobalProactiveInboxItem) -> Unit
) : LinearLayout(context) {
    private var row: AttentionReaderRow? = null
    private var generation = 0
    private var headline: TextView? = null
    private var originalHeadline: TextView? = null
    private var displayedTranslation = ""
    private var sourceLine: TextView? = null
    private var bookmark: ImageButton? = null
    private var sourceName = ""
    private var evidenceChecked = false
    private var displayedUnread = false
    private val notices by lazy { listOf(R.string.attention_source_summary, R.string.attention_not_verified,
        R.string.attention_reviewed).flatMap(::statusTexts).toSet() }
    lateinit var readable: View
        private set
    val currentItem get() = row?.item

    init { orientation = VERTICAL }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        row?.let {
            displayedUnread = it.item.isNew
            displayedTranslation = it.item.translatedTitle
            updateHeadline(it)
            updateStatus(it)
        }
    }

    fun bind(next: AttentionReaderRow) {
        val token = ++generation
        if (!isAttachedToWindow || row?.item?.key != next.item.key) {
            displayedUnread = next.item.isNew
        }
        displayedTranslation = next.item.translatedTitle
        row = next; sourceName = ""; evidenceChecked = false
        removeAllViews()
        val item = next.item
        tag = "attention-item:${item.key}"
        val content = column().apply { setPadding(dp(18), dp(12), dp(12), dp(12)) }
        val intro = column()
        readable = intro
        val top = horizontal()
        top.addView(label(item.topic, 11f, secondary = true).apply {
            maxLines = 1; ellipsize = TextUtils.TruncateAt.END
        }, LayoutParams(0, -2, 1f))
        top.addView(label(SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(item.deliveredAtMillis)), 11f, secondary = true))
        intro.addView(top)
        val titleRow = horizontal()
        val titles = column()
        headline = label("", 19.36f).apply {
            tag = "attention-headline:${item.key}"
            setTypeface(typeface, Typeface.NORMAL)
            maxLines = if (next.expanded) Int.MAX_VALUE else 2
            minLines = if (!next.expanded && expectsTranslation(item)) 2 else 1
            ellipsize = TextUtils.TruncateAt.END
            setPadding(0, dp(6), 0, dp(5))
            if (!next.expanded && expectsTranslation(item)) reserveBilingualHeight()
        }
        titles.addView(headline)
        originalHeadline = label("", 13f, secondary = true).apply {
            tag = "attention-original-headline:${item.key}"
            maxLines = if (next.expanded) Int.MAX_VALUE else 2
            minLines = if (!next.expanded && expectsTranslation(item)) 2 else 1
            ellipsize = TextUtils.TruncateAt.END
            setPadding(0, 0, 0, dp(6))
            if (!next.expanded && expectsTranslation(item)) reserveBilingualHeight()
        }
        titles.addView(originalHeadline)
        updateHeadline(next)
        titleRow.addView(titles, LayoutParams(0, -2, 1f))
        bookmark = icon(R.drawable.ic_attention_bookmark, R.string.attention_save) { save(item.key) }
        titleRow.addView(bookmark)
        intro.addView(titleRow)
        val bodyText = articleText(item)
        val preview = plain(bodyText.split(Regex("\n\\s*\n")).firstOrNull(String::isNotBlank).orEmpty())
            .replace(Regex("\\s+"), " ")
        if (!next.expanded) intro.addView(label(preview, 13f).apply {
            maxLines = 2; ellipsize = TextUtils.TruncateAt.END; setLineSpacing(dp(2).toFloat(), 1f)
        })
        sourceLine = label("", 11f, secondary = true).apply {
            maxLines = 1; ellipsize = TextUtils.TruncateAt.END; setPadding(0, dp(7), 0, 0)
        }
        intro.addView(sourceLine)
        intro.setOnClickListener { toggle(item.key) }
        intro.setOnLongClickListener { menu(item); true }
        content.addView(intro)
        if (next.expanded) {
            content.addView(label(context.getString(R.string.attention_content_summary), 14.4f, true).apply {
                setPadding(0, dp(12), 0, dp(8))
            })
            content.addView(label("", 18f).apply {
                setLineSpacing(dp(4).toFloat(), 1f)
                text = AgentRichInlineMarkdownRenderer.render(bodyText)
                movementMethod = LinkMovementMethod.getInstance()
                setTextIsSelectable(true)
                tag = "attention-expanded:${item.key}"
            })
            val actions = horizontal()
            actions.addView(command(R.drawable.ic_conversation_external, R.string.attention_original) { sources(item) }, LayoutParams(0, dp(48), 1f))
            actions.addView(command(R.drawable.ic_tab_chat, R.string.attention_ask) { ask(item) }, LayoutParams(0, dp(48), 1f))
            content.addView(actions)
            content.addView(command(R.drawable.ic_chevron_down, R.string.attention_collapse) { toggle(item.key) }.apply {
                tag = "attention-collapse:${item.key}"
                (getChildAt(0) as ImageButton).rotation = 180f
            })
        }
        addView(content)
        addView(View(context).apply { setBackgroundColor(context.getColor(R.color.separator)) }, LayoutParams(-1, dp(1)))
        updateStatus(next)
        evidence(item) { record ->
            if (token == generation) {
                sourceName = record?.optJSONArray("sources")?.optJSONObject(0)?.optString("title").orEmpty()
                evidenceChecked = record?.optBoolean("verified", false) == true
                row?.let(::updateStatus)
            }
        }
    }

    fun updateStatus(next: AttentionReaderRow) {
        row = next
        // Freeze read color. Collapsed bilingual slots have stable heights, so translations can
        // arrive in place. Expanded text waits for the next explicit bind to avoid moving the body.
        if (!isAttachedToWindow) {
            displayedUnread = next.item.isNew
        }
        if (!isAttachedToWindow || !next.expanded) {
            displayedTranslation = next.item.translatedTitle
            updateHeadline(next)
        }
        headline?.setTextColor(context.getColor(if (displayedUnread) R.color.attention_unread_title else R.color.text_primary))
        headline?.alpha = 1f
        val status = context.getString(if (evidenceChecked) R.string.attention_reader_checked else R.string.attention_reader_unverified)
        sourceLine?.text = listOf(sourceName, status, if (displayedUnread) "" else context.getString(R.string.attention_is_read))
            .filter(String::isNotBlank).joinToString(" · ")
        bookmark?.apply {
            setImageResource(if (next.saved) R.drawable.ic_attention_bookmark_filled else R.drawable.ic_attention_bookmark)
            imageTintList = ColorStateList.valueOf(context.getColor(if (next.saved) R.color.galaxyssi_green else R.color.text_secondary))
            contentDescription = context.getString(if (next.saved) R.string.attention_unsave else R.string.attention_save)
            tooltipText = contentDescription; isSelected = next.saved
        }
    }

    private fun updateHeadline(next: AttentionReaderRow) {
        val original = next.item.title.ifBlank {
            next.item.content.lineSequence().firstOrNull().orEmpty().trim('#', '*', ' ')
        }
        headline?.text = displayedTranslation.ifBlank { original }
        originalHeadline?.apply {
            text = if (displayedTranslation.isNotBlank()) original else context.getString(R.string.attention_translation_pending)
            visibility = if (displayedTranslation.isNotBlank() || expectsTranslation(next.item)) View.VISIBLE else View.GONE
        }
    }

    private fun expectsTranslation(item: GlobalProactiveInboxItem) =
        context.resources.configuration.locales[0].language == "zh" && ProactiveAttentionTitlePolicy.needsTranslation(item.title)

    private fun TextView.reserveBilingualHeight() {
        // CJK fallback fonts can be taller than Latin fonts even with identical minLines.
        layoutParams = LayoutParams(-1,
            kotlin.math.ceil(maxOf(textSize * 1.5f, lineHeight.toFloat())).toInt() * 2 + paddingTop + paddingBottom)
    }

    private fun articleText(item: GlobalProactiveInboxItem): String {
        val lines = item.content.lines().toMutableList()
        val first = lines.indexOfFirst { it.isNotBlank() }
        if (first >= 0 && plain(lines[first]).trim('#', ' ') == item.title.trim()) lines.removeAt(first)
        return lines.filterNot { it.trim() in notices }.joinToString("\n").trim()
    }
    private fun statusTexts(id: Int) = listOf(Locale.ENGLISH, Locale.SIMPLIFIED_CHINESE).map { locale ->
        context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply { setLocale(locale) }).getString(id)
    }
    private fun plain(value: String) = value.replace(Regex("\\[([^]]+)\\]\\([^)]+\\)"), "$1").replace("**", "")
    private fun column() = LinearLayout(context).apply { orientation = VERTICAL }
    private fun horizontal() = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    private fun label(value: String, size: Float, secondary: Boolean = false) = TextView(context).apply {
        text = value; textSize = size
        setTextColor(context.getColor(if (secondary) R.color.text_secondary else R.color.text_primary))
    }
    private fun command(drawable: Int, title: Int, action: () -> Unit) = horizontal().apply {
        gravity = Gravity.CENTER; minimumHeight = dp(48)
        addView(icon(drawable, title, action))
        addView(label(context.getString(title), 13f, true))
        setOnClickListener { action() }; contentDescription = context.getString(title)
    }
    private fun icon(drawable: Int, title: Int, action: () -> Unit) = ImageButton(context).apply {
        setImageResource(drawable); contentDescription = context.getString(title); tooltipText = contentDescription
        imageTintList = ColorStateList.valueOf(context.getColor(R.color.text_secondary))
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        setPadding(dp(13), dp(13), dp(13), dp(13)); layoutParams = LayoutParams(dp(48), dp(48))
        setOnClickListener { action() }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
