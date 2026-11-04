package com.galaxyssi.chat

import android.app.AlertDialog
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Switch

internal class HealthFirstUseView(private val activity: HealthCenterActivity, private val externalRoutes: Boolean) {
    private val ui get() = activity.ui
    private val dark get() = activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
        Configuration.UI_MODE_NIGHT_YES
    private val divider get() = activity.getColor(R.color.separator)
    private enum class Accent(val light: Int, val ink: Int, val night: Int, val nightInk: Int) {
        GREEN(0xffe4f5ec.toInt(), 0xff147d54.toInt(), 0xff213e34.toInt(), 0xff9de8bd.toInt()),
        ORANGE(0xfffbede0.toInt(), 0xff985617.toInt(), 0xff483427.toInt(), 0xffffc18a.toInt()),
        BLUE(0xffeaf0ff.toInt(), 0xff4265ad.toInt(), 0xff263650.toInt(), 0xffb7cdff.toInt()),
        VIOLET(0xfff0e9fa.toInt(), 0xff76579b.toInt(), 0xff3d304c.toInt(), 0xffdac5f9.toInt())
    }
    private data class Entry(val icon: Int, val accent: Accent, val title: Int, val tag: String, val action: () -> Unit)
    private fun label(id: Int) = activity.getString(id)
    private fun open(target: Class<*>, extras: Intent.() -> Unit = {}) {
        if (externalRoutes) activity.startActivity(Intent(activity, target).apply(extras))
    }
    private fun capture(entry: HealthCaptureEntry, keepOriginal: Boolean = true) = open(HealthCaptureActivity::class.java) {
        putExtra("health_capture_entry", entry.name)
        putExtra(HEALTH_KEEP_ORIGINAL, keepOriginal)
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
        val quick = listOf(
            Entry(R.drawable.ic_agent_camera, Accent.ORANGE, R.string.health_take_photo, "health-overview-photo") { capture(HealthCaptureEntry.CAMERA) },
            Entry(R.drawable.ic_agent_new_session, Accent.GREEN, R.string.health_manual, "health-overview-manual") { activity.open("manual") },
            Entry(R.drawable.ic_settings_upload, Accent.BLUE, R.string.health_overview_import, "health-overview-import") { activity.open("import") },
            Entry(R.drawable.ic_protocol_link, Accent.VIOLET, R.string.health_sources_quick, "health-overview-sources") { sources() }
        )
        val config = activity.resources.configuration
        val columns = if (config.screenWidthDp < 350 || config.fontScale > 1.3f) 2 else 4
        ui.add(content, panel().apply {
            quick.chunked(columns).forEach { entries ->
                addView(ui.line().apply {
                    gravity = Gravity.TOP
                    entries.forEach { entry ->
                        addView(ui.column().apply {
                            tag = entry.tag
                            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                            minimumHeight = ui.dp(80)
                            setPadding(ui.dp(4), ui.dp(5), ui.dp(4), ui.dp(8))
                            isFocusable = true
                            setOnClickListener { entry.action() }
                            addView(glyph(entry.icon, entry.accent), LinearLayout.LayoutParams(ui.dp(42), ui.dp(42)))
                            ui.add(this, ui.text(label(entry.title), 13f).apply { gravity = Gravity.CENTER }, 5)
                        }, LinearLayout.LayoutParams(0, -1, 1f))
                    }
                })
            }
        }, 16)
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
        ui.add(content, ui.command(R.string.health_first_existing) { activity.open("import") }.apply {
            tag = "health-first-existing"
            background = ui.background(stroke = divider, radius = 8)
            setTextColor(activity.getColor(R.color.text_primary))
            setPadding(ui.dp(10), ui.dp(8), ui.dp(10), ui.dp(8))
        })
    }

    fun showImport(content: LinearLayout) {
        content.addView(ui.text(label(R.string.health_first_import_intro), 23f, bold = true).apply { tag = "health-import-center" })
        ui.add(content, ui.text(label(R.string.health_first_import_note), 15f, muted = true), 6)
        ui.add(content, panel().apply {
            addView(iconRow(R.drawable.ic_agent_camera, Accent.ORANGE, R.string.health_take_photo, R.string.health_first_capture_note,
                "health-import-camera") { capture(HealthCaptureEntry.CAMERA, activity.keepImportedOriginal) })
            addView(rule())
            addView(iconRow(R.drawable.ic_chat_shortcut_file, Accent.BLUE, R.string.health_first_report, R.string.health_first_report_note,
                "health-import-report") { capture(HealthCaptureEntry.REPORT, activity.keepImportedOriginal) })
            addView(rule())
            addView(iconRow(R.drawable.ic_settings_upload, Accent.GREEN, R.string.health_first_table, R.string.health_first_table_note,
                "health-import-table") { capture(HealthCaptureEntry.TABLE, activity.keepImportedOriginal) })
            addView(rule())
            addView(iconRow(R.drawable.ic_security_shield, Accent.VIOLET, R.string.health_restore_title, R.string.health_first_backup_note,
                "health-import-restore") { open(HealthRestoreActivity::class.java) })
        }, 16)
        ui.add(content, ui.text(label(R.string.health_retention_title), 18f, bold = true), 18)
        ui.add(content, panel().apply {
            addView(Switch(activity).apply {
                tag = "health-import-keep-original"
                text = label(R.string.health_retention_switch)
                setTextColor(activity.getColor(R.color.text_primary))
                minimumHeight = ui.dp(48)
                isChecked = activity.keepImportedOriginal
                setOnCheckedChangeListener { _, checked -> activity.keepImportedOriginal = checked }
            })
            ui.add(this, ui.text(label(R.string.health_retention_note), 14f, muted = true), 6)
        }, 8)
    }

    private fun chooseFirstRecord() {
        val choices = intArrayOf(R.string.health_take_photo, R.string.health_manual, R.string.health_first_existing)
        activity.showHealthDialog(AlertDialog.Builder(activity).setTitle(R.string.health_first_add)
            .setItems(choices.map(::label).toTypedArray()) { _, index ->
                when (index) {
                    0 -> capture(HealthCaptureEntry.CAMERA)
                    1 -> activity.open("manual")
                    else -> activity.open("import")
                }
            }.setNegativeButton(android.R.string.cancel, null).create())
    }

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

    private fun iconRow(icon: Int, accent: Accent, title: Int, note: Int, key: String, action: () -> Unit) = ui.line().apply {
        tag = key
        addView(glyph(icon, accent), LinearLayout.LayoutParams(ui.dp(42), ui.dp(42)))
        addView(ui.row(label(title), label(note), action).apply {
            setOnClickListener(null)
            isClickable = false
            isFocusable = false
        }, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = ui.dp(8) })
        isFocusable = true
        setOnClickListener { action() }
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
