package com.galaxyssi.chat

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.text.TextUtils
import android.text.method.LinkMovementMethod
import android.view.Gravity
import android.view.View
import android.widget.ImageButton
import android.widget.ImageView
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
    private val menu: (GlobalProactiveInboxItem) -> Unit,
    private val loadBody: (String, (String?) -> Unit) -> Unit = { _, callback -> callback(null) },
    private val loadArticle: (String, Boolean, (AttentionArticlePresentation?) -> Unit) -> Unit = { _, _, callback -> callback(null) }
) : LinearLayout(context) {
    private var row: AttentionReaderRow? = null
    private var generation = 0
    private var headline: TextView? = null
    private var displayedTranslation = ""
    private var displayedTranslationProvider = ""
    private var translationAttribution: ImageView? = null
    private var sourceLine: TextView? = null
    private var statusLine: TextView? = null
    private var bookmark: ImageButton? = null
    private var sourceName = ""
    private var evidenceChecked = false
    private var displayedUnread = false
    private var reloadPresentation: (() -> Unit)? = null
    private val notices by lazy { listOf(R.string.attention_source_summary, R.string.attention_not_verified,
        R.string.attention_reviewed).flatMap(::statusTexts).toSet() }
    lateinit var readable: View
        private set
    val currentItem get() = row?.item
    fun refreshPublicPresentation() { if (row?.expanded == false) reloadPresentation?.invoke() }

    init { orientation = VERTICAL }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        row?.let {
            displayedUnread = it.item.isNew
            displayedTranslation = it.item.translatedTitle
            displayedTranslationProvider = it.item.titleTranslationProvider
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
        displayedTranslationProvider = next.item.titleTranslationProvider
        row = next; sourceName = ""; evidenceChecked = false; reloadPresentation = null
        removeAllViews()
        val item = next.item
        val news = item.newsArticleKey.isNotBlank()
        tag = "attention-item:${item.key}"
        val content = column().apply { setPadding(dp(18), dp(16), dp(18), dp(12)) }
        val intro = column()
        readable = intro
        val top = horizontal()
        sourceLine = label(if (news) "" else item.topic, 11f, secondary = true).apply {
            maxLines = 1; ellipsize = TextUtils.TruncateAt.END
        }
        top.addView(sourceLine, LayoutParams(0, -2, 1f))
        val date = label(SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(item.deliveredAtMillis)), 11f, secondary = true)
        top.addView(date)
        intro.addView(top)
        val titleRow = horizontal()
        val titles = column()
        headline = label("", if (news) (if (next.expanded) 21f else 18f) else 19.36f).apply {
            tag = "attention-headline:${item.key}"
            setTypeface(typeface, if (news) Typeface.BOLD else Typeface.NORMAL)
            maxLines = if (next.expanded) Int.MAX_VALUE else 2
            minLines = if (!next.expanded) 2 else 1
            ellipsize = TextUtils.TruncateAt.END
            setPadding(0, dp(6), 0, dp(5))
            if (!next.expanded) reserveHeadlineHeight()
        }
        titles.addView(headline)
        translationAttribution = ImageView(context).apply {
            tag = "attention-translation-attribution:${item.key}"
            setImageResource(R.drawable.google_translate_attribution)
            contentDescription = context.getString(R.string.attention_translation_attribution)
            scaleType = ImageView.ScaleType.FIT_START
            layoutParams = LayoutParams(dp(144), dp(20))
            setPadding(0, 0, 0, dp(3))
            setOnClickListener {
                android.app.AlertDialog.Builder(context)
                    .setTitle(R.string.attention_translation_attribution)
                    .setMessage(R.string.attention_translation_disclaimer)
                    .setPositiveButton(android.R.string.ok, null).show()
            }
        }
        titles.addView(translationAttribution)
        updateHeadline(next)
        val bodyText = articleText(item)
        val preview = plain(AttentionArticleReadingPolicy.preview(AttentionArticleDocument.plain(bodyText)))
            .replace(Regex("\\s+"), " ")
        val previewView = label(preview, 13f).apply {
            maxLines = 2; minLines = 2; ellipsize = TextUtils.TruncateAt.END; setLineSpacing(dp(2).toFloat(), 1f)
            tag = "attention-preview:${item.key}"
        }
        if (!next.expanded) titles.addView(previewView)
        titleRow.addView(titles, LayoutParams(0, -2, 1f))
        val thumbnail = column().apply { visibility = View.GONE }
        if (!next.expanded) titleRow.addView(thumbnail, LayoutParams(dp(92), dp(76)).apply { leftMargin = dp(12) })
        intro.addView(titleRow)
        val status = horizontal()
        statusLine = label("", 11f, secondary = true).apply { maxLines = 1; ellipsize = TextUtils.TruncateAt.END }
        status.addView(statusLine, LayoutParams(0, -2, 1f))
        bookmark = icon(R.drawable.ic_attention_bookmark, R.string.attention_save) { save(item.key) }
        status.addView(bookmark)
        intro.addView(status)
        intro.setOnClickListener { toggle(item.key) }
        intro.setOnLongClickListener { menu(item); true }
        content.addView(intro)
        val articleBody = column()
        if (next.expanded) {
            content.addView(articleBody)
            articleBody.addView(label(context.getString(if (item.newsArticleKey.isBlank()) R.string.attention_content_summary
                else R.string.attention_article_body), 14.4f, true).apply {
                setPadding(0, dp(12), 0, dp(8))
            })
            val bodyView = label("", if (news) 16f else 18f).apply {
                setLineSpacing(dp(4).toFloat(), 1f)
                text = AgentRichInlineMarkdownRenderer.render(bodyText)
                movementMethod = LinkMovementMethod.getInstance()
                setTextIsSelectable(true)
                tag = "attention-expanded:${item.key}"
            }
            articleBody.addView(bodyView)
            if (item.newsArticleKey.isNotBlank()) loadBody(item.newsArticleKey) { full ->
                if (generation == token && row?.expanded == true && full != null)
                    bodyView.text = AgentRichInlineMarkdownRenderer.render(full)
            }
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
        var previousPresentation: AttentionArticlePresentation? = null
        var loadingPresentation = false
        if (news) reloadPresentation = request@{
          if (loadingPresentation) return@request
          loadingPresentation = true
          loadArticle(item.newsArticleKey, next.expanded) { presentation ->
            loadingPresentation = false
            if (generation == token && presentation != null && presentation != previousPresentation) {
                previousPresentation = presentation
                sourceName = presentation.publisher
                if (presentation.published > 0) date.text = SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(presentation.published))
                else date.text = context.getString(R.string.attention_news_collected,
                    SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(item.deliveredAtMillis)))
                previewView.text = presentation.preview.ifBlank { preview }
                if (!next.expanded && presentation.cover != null) {
                    thumbnail.removeAllViews()
                    thumbnail.addView(AttentionArticleImageView(context, presentation.cover, true), LayoutParams(-1, -1))
                    thumbnail.visibility = View.VISIBLE
                }
                if (next.expanded && presentation.document != null) {
                    articleBody.removeAllViews()
                    articleBody.addView(AttentionArticleBodyView(context, presentation.document).apply { tag = "attention-expanded:${item.key}" })
                }
                row?.let(::updateStatus)
            }
          }
        }
        reloadPresentation?.invoke()
        evidence(item) { record ->
            if (token == generation) {
                val source = record?.optJSONArray("sources")?.optJSONObject(0)
                sourceName = AttentionFeedCollectionPlan.publisher(source?.optString("url").orEmpty(), source?.optString("title").orEmpty())
                evidenceChecked = record?.optBoolean("verified", false) == true
                row?.let(::updateStatus)
            }
        }
    }

    fun updateStatus(next: AttentionReaderRow) {
        row = next
        // Freeze read color. Collapsed headline slots have stable heights, so translations can
        // arrive in place. Expanded text waits for the next explicit bind to avoid moving the body.
        if (!isAttachedToWindow) {
            displayedUnread = next.item.isNew
        }
        if (!isAttachedToWindow || !next.expanded) {
            displayedTranslation = next.item.translatedTitle
            displayedTranslationProvider = next.item.titleTranslationProvider
            updateHeadline(next)
        }
        headline?.setTextColor(context.getColor(if (displayedUnread && next.item.newsArticleKey.isBlank()) R.color.attention_unread_title else R.color.text_primary))
        headline?.alpha = 1f
        val status = context.getString(if (evidenceChecked) R.string.attention_reader_checked else R.string.attention_reader_unverified)
        sourceLine?.text = sourceName.ifBlank { next.item.topic }
        statusLine?.text = listOf(status, if (displayedUnread) "\u2022" else context.getString(R.string.attention_is_read))
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
        translationAttribution?.visibility = when {
            displayedTranslationProvider == AttentionMlKitTranslator.PROVIDER -> View.VISIBLE
            expectsTranslation(next.item) -> View.INVISIBLE
            else -> View.GONE
        }
    }

    private fun expectsTranslation(item: GlobalProactiveInboxItem) =
        context.resources.configuration.locales[0].language == "zh" && ProactiveAttentionTitlePolicy.needsTranslation(item.title)

    private fun TextView.reserveHeadlineHeight() {
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
        setTextColor(context.getColor(if (secondary) R.color.attention_reader_secondary else R.color.text_primary))
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
