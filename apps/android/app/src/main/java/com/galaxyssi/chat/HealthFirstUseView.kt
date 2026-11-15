package com.galaxyssi.chat

import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout

internal class HealthFirstUseView(private val activity: HealthCenterActivity, private val externalRoutes: Boolean) {
    private val ui get() = activity.ui
    private val dark get() = activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
        Configuration.UI_MODE_NIGHT_YES
    private val divider get() = activity.getColor(R.color.separator)
    private enum class Accent(val light: Int, val ink: Int, val night: Int, val nightInk: Int) {
        GREEN(0xffe4f5ec.toInt(), 0xff147d54.toInt(), 0xff213e34.toInt(), 0xff9de8bd.toInt())
    }
    private fun label(id: Int) = activity.getString(id)
    private fun open(target: Class<*>, extras: Intent.() -> Unit = {}) {
        if (externalRoutes) activity.startActivity(Intent(activity, target).apply(extras))
    }
    private fun sources() = open(HealthSourcesActivity::class.java)

    fun showIntro(content: LinearLayout) {
        ui.add(content, ui.column().apply {
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(ui.dp(12), ui.dp(12), ui.dp(12), ui.dp(8))
            addView(glyph(R.drawable.ic_health_heart, Accent.GREEN, 18), LinearLayout.LayoutParams(ui.dp(76), ui.dp(76)))
            ui.add(this, ui.text(label(R.string.health_first_title), 23f, bold = true).apply {
                gravity = Gravity.CENTER
                tag = "health-overview-first"
            }, 16)
            ui.add(this, ui.text(label(R.string.health_first_intro), 15f, muted = true).apply { gravity = Gravity.CENTER }, 8)
        })
    }

    fun showActions(content: LinearLayout) {
        ui.add(content, panel().apply {
            addView(ui.text(label(R.string.health_first_steps), 18f, bold = true))
            addView(numbered(1, R.string.health_first_profile, R.string.health_first_profile_note) {
                open(HealthProfileActivity::class.java)
            })
            addView(rule())
            addView(numbered(2, R.string.health_first_add, R.string.health_first_add_note, ::chooseFirstRecord))
            addView(rule())
            addView(numbered(3, R.string.health_first_sources, R.string.health_first_sources_note, ::sources))
        }, 12)
        ui.add(content, ui.line().apply {
            background = ui.background(tint(Accent.GREEN), radius = 8)
            setPadding(ui.dp(10), ui.dp(8), ui.dp(10), ui.dp(8))
            addView(glyph(R.drawable.ic_info_outline, Accent.GREEN, 2), LinearLayout.LayoutParams(ui.dp(24), ui.dp(24)))
            addView(ui.text(label(R.string.health_first_no_analysis), 14f).apply {
                setPadding(ui.dp(8), 0, 0, 0)
                tag = "health-first-no-analysis"
            }, LinearLayout.LayoutParams(0, -2, 1f))
        }, 12)
        ui.add(content, ui.command(R.string.health_first_add, ::chooseFirstRecord).apply {
            tag = "health-first-add"
            background = ui.background(0xff11c36e.toInt(), radius = 8)
        }, 12)
        ui.add(content, ui.row(label(R.string.health_first_privacy)) {
            if (externalRoutes) activity.startActivity(activity.healthPrivacyIntent())
        }.apply { minimumHeight = ui.dp(48) }, 4)
        ui.add(content, ui.command(R.string.health_first_existing, activity::pickHealthFile).apply {
            tag = "health-first-existing"
            background = ui.background(stroke = divider, radius = 8)
            setTextColor(activity.getColor(R.color.text_primary))
            setPadding(ui.dp(10), ui.dp(8), ui.dp(10), ui.dp(8))
        })
    }

    private fun chooseFirstRecord() = activity.open("record_center")

    private fun panel() = ui.column().apply {
        setPadding(ui.dp(12), ui.dp(10), ui.dp(12), ui.dp(10))
        background = ui.background(stroke = divider, radius = 8)
    }

    private fun rule() = View(activity).apply {
        setBackgroundColor(divider)
        layoutParams = LinearLayout.LayoutParams(-1, ui.dp(1))
    }

    private fun numbered(number: Int, title: Int, note: Int, action: () -> Unit) = ui.line().apply {
        val badge = ui.text(number.toString(), 13f).apply {
            gravity = Gravity.CENTER
            setTextColor(ink(Accent.GREEN))
            background = ui.background(tint(Accent.GREEN), radius = 14)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        addView(badge, LinearLayout.LayoutParams(ui.dp(27), ui.dp(27)))
        addView(ui.row(label(title), label(note), action), LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = ui.dp(8) })
    }

    private fun tint(accent: Accent) = if (dark) accent.night else accent.light
    private fun ink(accent: Accent) = if (dark) accent.nightInk else accent.ink
    private fun glyph(icon: Int, accent: Accent, padding: Int = 10) = ImageView(activity).apply {
        background = ui.background(tint(accent), radius = 8)
        setImageResource(icon)
        imageTintList = ColorStateList.valueOf(ink(accent))
        setPadding(ui.dp(padding), ui.dp(padding), ui.dp(padding), ui.dp(padding))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
}
