package com.galaxyssi.chat

import android.app.Dialog
import android.graphics.Typeface
import android.text.SpannableString
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.*

internal fun MainActivity.messageHistoryReader(hit: LocalMessageHit, query: String, closed: () -> Unit): Dialog {
    val d = Dialog(this)
    val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(getColor(R.color.page_bg)) }
    val lines = mutableListOf<LocalHistoryLine>()
    val list = ListView(this).apply { divider = null; isSaveEnabled = false; setPadding(dp(12), 0, dp(12), 0) }
    var before: Long? = null
    var after: Long? = null
    var busy = false
    fun button(label: Int, action: () -> Unit) = TextView(this).apply {
        setText(label); gravity = Gravity.CENTER; minHeight = dp(48); isFocusable = true; setTextColor(getColor(R.color.composer_send_icon))
        setOnClickListener { action() }
    }
    val head = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
    head.addView(ImageButton(this).apply {
        setImageResource(R.drawable.ic_chevron_down); rotation = 90f
        setColorFilter(getColor(R.color.text_primary)); setBackgroundColor(0)
        contentDescription = getString(R.string.chat_search_back); setOnClickListener { d.dismiss() }
    }, dp(48), dp(48))
    head.addView(TextView(this).apply { text = hit.ownerTitle; textSize = 17f; setSingleLine(); ellipsize = android.text.TextUtils.TruncateAt.END
        setTextColor(getColor(R.color.text_primary)); setTypeface(typeface, Typeface.BOLD) }, LinearLayout.LayoutParams(0, -2, 1f))
    root.addView(head); root.addView(list, LinearLayout.LayoutParams(-1, 0, 1f))
    val adapter = object : BaseAdapter() {
        override fun getCount() = lines.size
        override fun getItem(position: Int) = lines[position]
        override fun getItemId(position: Int) = position.toLong()
        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val item = getItem(position)
            val block = LinearLayout(this@messageHistoryReader).apply { orientation = LinearLayout.VERTICAL; setPadding(0, dp(6), 0, dp(6)) }
            val time = android.text.format.DateUtils.formatDateTime(this@messageHistoryReader, item.time,
                android.text.format.DateUtils.FORMAT_SHOW_DATE or android.text.format.DateUtils.FORMAT_SHOW_TIME)
            block.addView(TextView(this@messageHistoryReader).apply { text = time; textSize = 12f
                gravity = if (item.mine) Gravity.END else Gravity.START; setTextColor(getColor(R.color.text_secondary)) })
            val content = (listOf(item.text) + item.files.map { getString(R.string.chat_search_attachment, it) }).filter(String::isNotBlank).joinToString("\n")
            val span = SpannableString(content)
            val match = if (item.id == hit.message) content.indexOf(query, ignoreCase = true) else -1
            if (match >= 0) span.setSpan(StyleSpan(Typeface.BOLD), match, match + query.length, 0)
            block.addView(TextView(this@messageHistoryReader).apply {
                tag = item.id; text = span; setTextIsSelectable(true); textSize = 15f; setTextColor(getColor(R.color.text_primary))
                setPadding(dp(12), dp(8), dp(12), dp(8)); setBackgroundResource(if (item.mine) R.drawable.bubble_self_background else R.drawable.bubble_other_background)
            }, LinearLayout.LayoutParams(-2, -2).apply { gravity = if (item.mine) Gravity.END else Gravity.START })
            return block
        }
    }
    list.adapter = adapter
    lateinit var load: (Int) -> Unit
    val previous = button(R.string.chat_search_earlier) { load(-1) }
    val next = button(R.string.chat_search_later) { load(1) }
    root.addView(LinearLayout(this).apply { addView(previous, LinearLayout.LayoutParams(0, -2, 1f)); addView(next, LinearLayout.LayoutParams(0, -2, 1f)) })
    fun controls() {
        previous.visibility = if (before == null) View.GONE else View.VISIBLE; next.visibility = if (after == null) View.GONE else View.VISIBLE
        previous.isEnabled = !busy; next.isEnabled = !busy
    }
    controls()
    load = read@{ direction ->
        if (busy || !d.isShowing) return@read
        busy = true; controls()
        val b = before.takeIf { direction < 0 }; val n = after.takeIf { direction > 0 }
        agentTranscriptContentExecutor.execute {
            val page = runCatching { hit.contextPage(this, b, n) }.getOrNull()
            handler.post apply@{
                if (!d.isShowing || isDestroyed || runtimePlaintextCleared) return@apply
                busy = false
                if (page == null) { d.dismiss(); Toast.makeText(this, R.string.chat_search_gone, Toast.LENGTH_SHORT).show(); return@apply }
                val pos = list.firstVisiblePosition; val top = list.getChildAt(0)?.top ?: 0
                if (direction <= 0) before = page.older
                if (direction >= 0) after = page.newer
                if (direction < 0) lines.addAll(0, page.lines) else lines.addAll(page.lines)
                adapter.notifyDataSetChanged(); controls()
                if (direction != 0) list.setSelectionFromTop(pos + if (direction < 0) page.lines.size else 0, top)
                else {
                    val target = lines.indexOfFirst { it.id == hit.message }
                    list.setSelectionFromTop(target, dp(8))
                    list.post {
                        val tv = list.findViewWithTag<TextView>(hit.message) ?: return@post
                        val i = tv.text.toString().indexOf(query, ignoreCase = true)
                        val layout = tv.layout
                        if (i >= 0 && layout != null) {
                            val line = layout.getLineTop(layout.getLineForOffset(i))
                            if (line > list.height / 2) list.setSelectionFromTop(target, list.height / 3 - line)
                        }
                    }
                }
            }
        }
    }
    d.setContentView(root)
    d.setOnDismissListener { list.adapter = null; lines.clear(); closed() }
    d.show(); d.window?.setLayout(-1, -1); d.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    load(0); return d
}
