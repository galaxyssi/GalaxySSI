package com.galaxyssi.chat

import android.app.AlertDialog
import android.graphics.Typeface
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.DateFormat
import java.text.NumberFormat
import java.util.Date

internal fun MainActivity.showTurnReceipt(anchor: View, entry: AgentTranscriptEntry, completedAt: Long?) {
    AgentTurnReceipt.read(this, entry.conversationId, entry.turnId) { r ->
        if (isFinishing || isDestroyed || !anchor.isAttachedToWindow) return@read
        val missing = getString(R.string.turn_receipt_missing)
        val time = DateFormat.getTimeInstance(DateFormat.MEDIUM)
        fun clock(ms: Long) = if (ms > 0) time.format(Date(ms)) else missing
        fun info(vararg keys: String) = keys.map { r.optString(it) }.filter(String::isNotBlank)
            .joinToString(" · ").ifBlank { missing }
        val rows = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), 0, dp(24), dp(8)) }
        fun heading(label: Int) = rows.addView(TextView(this).apply {
            setText(label); setTypeface(typeface, Typeface.BOLD); textSize = 15f
            setPadding(0, dp(16), 0, dp(4)); setTextColor(getColorCompat(R.color.text_primary))
            androidx.core.view.ViewCompat.setAccessibilityHeading(this, true)
        })
        fun line(label: Int, value: String) = rows.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(5), 0, dp(3))
            addView(TextView(this@showTurnReceipt).apply {
                setText(label); textSize = 13f; setTextColor(getColorCompat(R.color.text_secondary))
            })
            addView(TextView(this@showTurnReceipt).apply {
                text = value; textSize = 16f; setTextColor(getColorCompat(R.color.text_primary))
            })
        })
        heading(R.string.turn_receipt_timing)
        line(R.string.turn_receipt_sent, clock(r.optLong("sent")))
        line(R.string.turn_receipt_desktop, clock(r.optLong("desktop_received")))
        val body = clock(r.optLong("body"))
        val seconds = NumberFormat.getNumberInstance().apply { maximumFractionDigits = 2 }
        line(R.string.turn_receipt_body, if (r.has("body_ms")) getString(R.string.turn_receipt_since, body,
            seconds.format(r.optLong("body_ms") / 1000.0)) else body)
        if (r.has("result")) line(R.string.turn_receipt_result, clock(r.optLong("result")))
        line(R.string.turn_receipt_done, clock(completedAt ?: 0))
        heading(R.string.turn_receipt_route)
        val choice = when (r.optString("mode")) {
            "AUTO" -> getString(R.string.turn_receipt_auto)
            "MANUAL" -> getString(R.string.turn_receipt_manual)
            else -> ""
        }
        line(R.string.turn_receipt_choice, listOf(choice, r.optString("request"), r.optString("effort"))
            .filter(String::isNotBlank).joinToString(" · ").ifBlank { missing })
        if (r.has("wire")) line(R.string.turn_receipt_wire, info("wire", "wire_effort"))
        val desktop = r.has("wire") || r.has("desktop_received") || r.has("provider")
        if (desktop) {
            line(R.string.turn_receipt_submitted, info("provider", "submitted", "submitted_effort"))
            line(R.string.turn_receipt_desktop_actual, missing)
        }
        if (r.has("cloud_request") || (!desktop && !r.has("local_profile"))) {
            line(R.string.turn_receipt_cloud, info("cloud_request"))
            line(R.string.turn_receipt_actual, info("cloud_actual"))
            line(R.string.turn_receipt_actual_effort, info("cloud_effort"))
        }
        if (r.has("local_profile")) line(R.string.turn_receipt_local, info("local_profile"))
        val devices = buildList {
            if (r.optBoolean("phone_executed")) add(getString(R.string.turn_receipt_phone))
            if (r.optBoolean("desktop_executed")) add("Desktop")
        }
        line(R.string.turn_receipt_device, devices.joinToString(" · ").ifBlank { missing })
        AlertDialog.Builder(this).setTitle(R.string.turn_receipt_title)
            .setView(ScrollView(this).apply { addView(rows) })
            .setPositiveButton(android.R.string.ok, null).show()
    }
}
