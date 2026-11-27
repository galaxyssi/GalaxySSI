package com.galaxyssi.chat

import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import java.text.DateFormat
import java.util.Date

internal class HealthAnswerBasisRow(
    private val activity: MainActivity, val conversation: String, val turn: String,
    private val attached: (HealthAnswerBasisRow, Boolean) -> Unit,
    private val request: (HealthAnswerBasisRow, Boolean) -> Unit
) : LinearLayout(activity) {
    var token = 0
        private set
    private var expanded = false
    private val expiry = Runnable { hide() }

    init { orientation = VERTICAL; visibility = GONE; isSaveEnabled = false }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); attached(this, true) }
    override fun onDetachedFromWindow() { attached(this, false); hide(); super.onDetachedFromWindow() }
    fun hide() { token++; removeCallbacks(expiry); expanded = false; visibility = GONE; removeAllViews() }
    fun display(rows: List<HealthBasisSource>, until: Long, open: Boolean) {
        hide()
        val remaining = until - System.currentTimeMillis()
        if (rows.isEmpty() || remaining <= 0) return
        visibility = VISIBLE
        expanded = open
        addView(TextView(context).apply {
            tag = "health-basis:$turn"; text = context.getString(R.string.health_basis_count, rows.size)
            textSize = 13f; gravity = android.view.Gravity.CENTER_VERTICAL
            minimumHeight = activity.dp(44); setTextColor(activity.getColor(R.color.accent_green))
            setCompoundDrawablesRelativeWithIntrinsicBounds(0, 0, R.drawable.ic_chevron_down, 0)
            if (android.os.Build.VERSION.SDK_INT >= 30) stateDescription = context.getString(
                if (open) R.string.research_trace_collapse else R.string.research_trace_expand)
            setOnClickListener { if (expanded) display(rows, until, false) else request(this@HealthAnswerBasisRow, true) }
        }, LayoutParams(-2, -2))
        if (open) {
            val dates = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT)
            addView(TextView(context).apply {
                text = context.getString(R.string.health_basis_scope); textSize = 12f
                setTextColor(activity.getColor(R.color.text_secondary))
            })
            rows.forEach { row ->
                val kind = context.resources.getStringArray(R.array.health_basis_kinds)[row.kind.ordinal]
                val label = row.metric?.let { activity.getString(it.titleResource()) } ?: row.title
                addView(TextView(context).apply {
                    text = listOf(kind, label, row.at.takeIf { it > 0 }?.let { dates.format(Date(it)) }.orEmpty())
                        .filter(String::isNotBlank).joinToString(" · ")
                    textSize = 13f; setPadding(0, activity.dp(5), 0, activity.dp(5))
                    setTextColor(activity.getColor(R.color.text_primary))
                })
            }
        }
        postDelayed(expiry, remaining)
    }
}
