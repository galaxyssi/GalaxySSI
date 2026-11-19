package com.galaxyssi.chat

import android.app.Activity
import android.content.res.ColorStateList
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout

/** Native labels keep all four mass transfers readable without relying on color or arrow width. */
internal class HealthAtlasRenalBalanceView(activity: Activity) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val captions = (0..3).map { index -> ui.text("", 15f, bold = true).apply {
        tag = "atlas-renal-amount-$index"
        setTextColor(activity.getColor(if (index == 1) R.color.health_atlas_blood_high else R.color.health_overview_green))
    } }
    private val arrows = (0..3).map { index -> ImageView(activity).apply {
        setImageResource(R.drawable.ic_navigation_back); rotation = if (index == 1) 0f else 180f
        imageTintList = ColorStateList.valueOf(activity.getColor(if (index == 1) R.color.health_atlas_blood_high else R.color.health_overview_green))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    } }
    var amounts = HealthAtlasRenal.amounts(100.0, 90.0, 10.0)
        set(value) {
            field = value
            val numbers = listOf(value.filtered, value.reabsorbed, value.secreted, value.excreted)
            val transfers = HealthAtlasRenalText.transfers(context, value)
            captions.forEachIndexed { index, caption -> caption.text = transfers[index] }
            arrows.forEachIndexed { index, arrow -> arrow.alpha = if (numbers[index] == 0.0) .2f else 1f }
        }
    init {
        orientation = VERTICAL; tag = "atlas-renal-balance"; isSaveEnabled = false
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_renal_balance_title), 16f, bold = true))
        for (index in 0..3) {
            val left = activity.getString(if (index == 3) R.string.health_atlas_renal_lumen else R.string.health_atlas_renal_blood)
            val right = activity.getString(if (index == 3) R.string.health_atlas_renal_urine else R.string.health_atlas_renal_lumen)
            ui.add(this, captions[index], 12)
            ui.add(this, ui.line().apply {
                gravity = Gravity.CENTER_VERTICAL
                addView(ui.text(left, 12f, muted = true).apply { gravity = Gravity.CENTER }, LayoutParams(0, -2, 1f))
                addView(arrows[index], LayoutParams(ui.dp(32), ui.dp(32)))
                addView(ui.text(right, 12f, muted = true).apply { gravity = Gravity.CENTER }, LayoutParams(0, -2, 1f))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                contentDescription = activity.getString(HealthAtlasRenalText.directions[index])
            }, 2)
        }
        amounts = amounts
    }
}

internal object HealthAtlasRenalText {
    val directions = listOf(R.string.health_atlas_renal_blood_lumen, R.string.health_atlas_renal_lumen_blood,
        R.string.health_atlas_renal_blood_lumen, R.string.health_atlas_renal_lumen_urine)
    fun transfers(context: android.content.Context, amounts: HealthAtlasRenal.Amounts): List<String> {
        val labels = listOf(R.string.health_atlas_renal_balance_filtered, R.string.health_atlas_renal_balance_reabsorbed,
            R.string.health_atlas_renal_balance_secreted, R.string.health_atlas_renal_balance_excreted)
        return listOf(amounts.filtered, amounts.reabsorbed, amounts.secreted, amounts.excreted).mapIndexed { index, value ->
            context.getString(labels[index], HealthAtlasPhysiologyText.number(value))
        }
    }
    fun context(context: android.content.Context, amounts: HealthAtlasRenal.Amounts) = buildString {
        appendLine(context.getString(R.string.health_atlas_renal_balance_scope))
        transfers(context, amounts).forEachIndexed { index, value ->
            appendLine(value + ": " + context.getString(directions[index]))
        }
    }.trim()
}
