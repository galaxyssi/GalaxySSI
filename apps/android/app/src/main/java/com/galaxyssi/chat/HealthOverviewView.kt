package com.galaxyssi.chat

import android.content.Intent
import android.content.res.ColorStateList
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout

internal class HealthOverviewView(private val activity: HealthCenterActivity, private val names: HealthOverviewDatabases) {
    private val ui get() = activity.ui
    private val metricView = HealthOverviewMetricView(activity)
    private fun label(id: Int, vararg args: Any) = activity.getString(id, *args)
    private fun color(id: Int) = activity.getColor(id)
    private fun start(type: Class<*>, extras: Intent.() -> Unit = {}) {
        if (names.fixture == null) activity.startActivity(Intent(activity, type).apply(extras))
    }
    private fun openCare(type: Class<*>, concern: String? = null, visit: String? = null) {
        activity.startActivity(Intent(activity, type).putHealthNavigationFixture(names).apply {
            concern?.let { putExtra("health_care_id", it) }
            visit?.let { putExtra("health_encounter_id", it) }
        })
    }

    fun show(content: LinearLayout, snapshot: HealthOverviewSnapshot, firstUse: HealthFirstUseView) {
        content.removeAllViews()
        if (!snapshot.hasRecords) firstUse.showIntro(content)
        if (!snapshot.hasRecords) {
            firstUse.showActions(content)
            showCare(content, snapshot.care)
            return
        }
        content.addView(ui.line().apply {
            addView(ui.text(label(R.string.health_overview_metrics_heading), 20f, bold = true),
                LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.text(label(R.string.health_overview_view_all), 14f, bold = true).apply {
                setTextColor(color(R.color.health_overview_green))
                gravity = Gravity.CENTER_VERTICAL or Gravity.END
                minimumHeight = ui.dp(48)
                setPadding(ui.dp(10), 0, 0, 0)
                isFocusable = true
                setOnClickListener { start(HealthCatalogActivity::class.java) }
            })
        })
        content.addView(ui.column().apply {
            tag = "health-overview-metrics"
            snapshot.metrics.forEach { addView(metricView.row(it, ::openRecord)) }
        })
        showCare(content, snapshot.care)
    }

    private fun showCare(content: LinearLayout, care: HealthOverviewCare) {
        if (care.enabled && care.permitted && !care.unavailable) {
            ui.add(content, ui.text(label(R.string.health_overview_today_actions), 18f, bold = true), 16)
            if (!care.actionsReady) {
                ui.add(content, ui.text(label(R.string.health_overview_care_pending), 14f, muted = true), 6)
            } else if (care.actions.isEmpty()) {
                ui.add(content, ui.text(label(R.string.health_overview_no_due_actions), 14f, muted = true), 6)
            }
            (care.actions + listOfNotNull(care.upcoming)).forEach { action ->
                val timing = when {
                    action == care.upcoming -> R.string.health_overview_next_action
                    action.overdue -> R.string.health_overview_overdue_action
                    else -> R.string.health_overview_due_action
                }
                ui.add(content, ui.profileRow(action.title, label(timing, activity.date(action.dueAt))) {
                    activity.openOverviewAction(action.concernId, action.id)
                }.apply { tag = "health-overview-action-${action.id}" }, 4)
            }
        }
        if (care.enabled) ui.add(content, ui.profileRow(label(R.string.health_agenda_title), label(R.string.health_agenda_summary)) {
            openCare(HealthCareActionsActivity::class.java)
        }.apply { tag = "health-overview-action-agenda" }, 8)
        if (care.unavailable || !care.permitted || care.concerns.isNotEmpty()) {
            ui.add(content, ui.text(label(R.string.health_overview_ongoing_care), 18f, bold = true), 16)
            val status = when {
                care.unavailable -> R.string.health_overview_care_unavailable
                !care.permitted -> R.string.health_overview_care_permission
                !care.enabled -> R.string.health_care_disabled
                else -> null
            }
            status?.let { ui.add(content, ui.text(label(it), 14f, muted = true)
                .apply { tag = "health-overview-care-status" }, 6) }
            care.concerns.forEach { concern ->
                val statusText = if (concern.sourceChanged && concern.stage != HealthCareStage.PAUSED)
                    R.string.health_overview_care_changed else concern.stage.titleResource()
                ui.add(content, ui.profileRow(label(concern.metric.titleResource()), label(statusText)) {
                    openCare(HealthCareActivity::class.java, concern.id)
                }.apply { tag = "health-overview-concern-${concern.id}" }, 4)
            }
        }
        if (care.visits.isNotEmpty()) {
            ui.add(content, ui.text(label(R.string.health_overview_visits), 18f, bold = true), 16)
            care.visits.forEach { visit ->
                val detail = listOfNotNull(label(visit.state.label()),
                    visit.at?.let { encounterTime(activity, it, visit.zone) },
                    visit.journal?.let { label(it.label()) }).joinToString(" \u00b7 ")
                ui.add(content, ui.profileRow(visit.purpose, detail) {
                    openCare(if (visit.journal != null) HealthCareVisitFollowUpActivity::class.java
                        else HealthCareEncountersActivity::class.java, visit.concernId, visit.id)
                }.apply { tag = "health-overview-visit-${visit.id}" }, 4)
            }
        }
    }

    private data class Shortcut(val icon: Int, val title: Int, val tag: String, val action: () -> Unit)

    fun quicks() = ui.column().apply {
        tag = "health-overview-bottom-actions"
        setBackgroundColor(color(R.color.surface_bg))
        addView(View(activity).apply { setBackgroundColor(color(R.color.separator)) }, LinearLayout.LayoutParams(-1, ui.dp(1)))
        val entries = listOf(
            Shortcut(R.drawable.ic_agent_camera, R.string.health_overview_photo, "health-overview-photo") {
                if (names.fixture == null) activity.startActivity(healthCaptureIntent(activity, names, HealthCaptureEntry.CAMERA))
            },
            Shortcut(R.drawable.ic_hub_compose, R.string.health_manual, "health-overview-manual") { activity.open("manual") },
            Shortcut(R.drawable.ic_settings_upload, R.string.health_overview_import, "health-overview-import", activity::pickHealthFile),
            Shortcut(R.drawable.ic_settings_devices, R.string.health_sources_quick, "health-overview-sources") { start(HealthSourcesActivity::class.java) },
        )
        val configuration = activity.resources.configuration
        val columns = if (configuration.fontScale >= 1.5f || configuration.screenWidthDp < 310) 2 else 4
        entries.chunked(columns).forEach { row ->
            addView(ui.line().apply {
                row.forEach { entry ->
                    addView(ui.column().apply {
                        tag = entry.tag
                        gravity = Gravity.CENTER
                        minimumHeight = ui.dp(54)
                        isFocusable = true
                        setPadding(ui.dp(2), ui.dp(6), ui.dp(2), ui.dp(6))
                        setOnClickListener { entry.action() }
                        addView(ImageView(activity).apply {
                            setImageResource(entry.icon)
                            imageTintList = ColorStateList.valueOf(color(R.color.health_overview_green))
                            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                        }, LinearLayout.LayoutParams(ui.dp(18), ui.dp(18)))
                        ui.add(this, ui.text(label(entry.title), 12f, bold = true).apply { gravity = Gravity.CENTER }, 4)
                    }, LinearLayout.LayoutParams(0, -1, 1f))
                }
            })
        }
    }
    private fun openRecord(record: HealthObservation) = start(HealthRecordRevisionActivity::class.java) {
        putExtra("health_record", record.id); putExtra("health_revision", record.revision)
    }
}
