package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.Toast
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors

internal fun Activity.healthPrivacyDatabaseName(): String {
    val name = intent.getStringExtra("health_privacy_test_db").orEmpty()
    return if (BuildConfig.DEBUG && name.matches(Regex("health-privacy-test-[0-9a-f-]{36}\\.db")) &&
        HealthProfilePolicy.uuid(name.removePrefix("health-privacy-test-").removeSuffix(".db"))) name else HealthPrivacyStore.DEFAULT_DB
}
internal fun Activity.healthPrivacyIntent() = Intent(this, HealthPrivacyActivity::class.java).putExtra("health_privacy_test_db", healthPrivacyDatabaseName())

class HealthPrivacyActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }; private val io = Executors.newSingleThreadExecutor(); private val main = Handler(Looper.getMainLooper())
    private val name by lazy { healthPrivacyDatabaseName() }
    private val store by lazy { HealthPrivacyStore(applicationContext, name) }
    private lateinit var body: LinearLayout; private var active = false; private var ticket = 0; private var saving = false
    private var history = false; private var cursor: HealthAccessCursor? = null
    private val previous = arrayListOf<HealthAccessCursor?>()
    private val observer = object : android.database.ContentObserver(main) { override fun onChange(selfChange: Boolean) { if (!saving && !history) load() } }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state); history = state?.getBoolean("history") ?: false
        fun decode(value: String?) = value?.takeIf(String::isNotEmpty)?.split('|', limit = 2)?.let { HealthAccessCursor(it[0].toLong(), it[1]) }
        cursor = decode(state?.getString("cursor")); previous.addAll(state?.getStringArrayList("previous")?.map(::decode).orEmpty())
        body = healthProfileBody(R.string.health_privacy_title) { back() }
    }
    override fun onStart() {
        super.onStart(); active = true; contentResolver.registerContentObserver(HealthPrivacyStore.changes(this, name), false, observer); load()
    }
    override fun onStop() {
        active = false; ticket++; contentResolver.unregisterContentObserver(observer); body.removeAllViews(); super.onStop()
    }
    override fun onDestroy() { io.execute { store.close() }; io.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        fun encode(c: HealthAccessCursor?) = c?.let { "${it.time}|${it.id}" }.orEmpty()
        out.putBoolean("history", history); out.putString("cursor", encode(cursor)); out.putStringArrayList("previous", ArrayList(previous.map(::encode)))
        super.onSaveInstanceState(out)
    }
    @Deprecated("Native back callback") override fun onBackPressed() = back()
    private fun back() { if (history) { history = false; cursor = null; previous.clear(); load() } else finish() }
    private fun load() {
        if (!active) return
        val current = ++ticket; val showHistory = history; val after = cursor
        io.execute {
            val result = runCatching { if (showHistory) Snapshot(page = store.page(after)) else Snapshot(policy = store.policy()) }
            main.post { if (active && current == ticket) result.fold({ if (showHistory) showHistory(requireNotNull(it.page)) else showPolicy(requireNotNull(it.policy)) }, { error() }) }
        }
    }
    private fun showPolicy(policy: HealthPrivacyPolicy) {
        val content = healthProfileContent(body)
        content.addView(ui.line().apply {
            addView(android.widget.ImageView(this@HealthPrivacyActivity).apply {
                setImageResource(R.drawable.ic_security_shield)
                imageTintList = android.content.res.ColorStateList.valueOf(0xff15975e.toInt())
            }, LinearLayout.LayoutParams(ui.dp(28), ui.dp(28)).apply { marginEnd = ui.dp(12) })
            addView(ui.text(getString(R.string.health_privacy_lead), 18f, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
        })
        ui.add(content, ui.text(getString(R.string.health_privacy_uses), 17f, bold = true), 24)
        setting(content, policy, HealthPrivacyOption.CONFIRMED_METRICS, R.string.health_privacy_metrics, R.string.health_privacy_metrics_detail)
        setting(content, policy, HealthPrivacyOption.PROFILE_CONTEXT, R.string.health_privacy_profile, R.string.health_privacy_profile_detail)
        setting(content, policy, HealthPrivacyOption.ONLINE_ANALYSIS, R.string.health_privacy_online, R.string.health_privacy_online_detail)
        setting(content, policy, HealthPrivacyOption.ORIGINAL_IMAGES, R.string.health_privacy_images, R.string.health_privacy_images_detail, policy.online)
        ui.add(content, ui.text(getString(R.string.health_privacy_storage), 17f, bold = true), 24)
        ui.add(content, ui.profileRow(getString(R.string.health_privacy_export)) { startActivity(Intent(this, HealthRecordExportActivity::class.java)) })
        ui.add(content, ui.profileRow(getString(R.string.health_original_library)) { startActivity(Intent(this, HealthOriginalLibraryActivity::class.java)) })
        ui.add(content, ui.profileRow(getString(R.string.health_privacy_history)) { history = true; load() }.apply { tag = "health-privacy-history" })
        ui.add(content, ui.profileRow(getString(R.string.health_profile_title), getString(R.string.health_privacy_manage_profile)) {
            startActivity(Intent(this, HealthProfileActivity::class.java).putExtra("health_privacy_test_db", name))
        })
    }
    private fun setting(content: LinearLayout, policy: HealthPrivacyPolicy, option: HealthPrivacyOption, title: Int, detail: Int, allowed: Boolean = true) {
        ui.add(content, ui.column().apply {
            addView(Switch(this@HealthPrivacyActivity).apply {
                text = getString(title); textSize = 16f; minHeight = ui.dp(48); isChecked = policy.enabled(option); isEnabled = allowed && !saving
                isSaveEnabled = false; tag = "health-privacy-${option.name}"
                setOnCheckedChangeListener { button, checked ->
                    if (saving) { button.setOnCheckedChangeListener(null); button.isChecked = policy.enabled(option); return@setOnCheckedChangeListener }
                    saving = true; button.isEnabled = false
                    io.execute { val result = runCatching { store.change(option, checked, policy.version) }; main.post {
                        saving = false
                        if (active) {
                            result.exceptionOrNull()?.let { Toast.makeText(this@HealthPrivacyActivity, if (it is HealthPrivacyConflict) R.string.health_privacy_conflict else R.string.health_storage_error, Toast.LENGTH_LONG).show() }
                            load()
                        }
                    } }
                }
            })
            addView(ui.text(getString(detail), 13f, muted = true))
        }, 12)
    }
    private fun showHistory(page: HealthAccessPage) {
        val content = healthProfileContent(body)
        content.addView(ui.text(getString(R.string.health_privacy_history), 19f, bold = true).apply { tag = "health-privacy-audit" })
        if (page.entries.isEmpty()) ui.add(content, ui.text(getString(R.string.health_privacy_empty), 15f, muted = true), 16)
        page.entries.forEach { event -> ui.add(content, ui.column().apply {
            addView(ui.text(getString(event.scope.purpose.title()), bold = true))
            val time = Instant.ofEpochMilli(event.time).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss"))
            ui.add(this, ui.text("$time \u00b7 ${getString(event.outcome.title())}", 13f, muted = true), 4)
            ui.add(this, ui.text(scopeText(event.scope), 14f), 4)
            addView(ui.space(8))
        }.apply { tag = "health-privacy-event" }, 14) }
        if (previous.isNotEmpty()) ui.add(content, ui.command(R.string.health_previous_page) { cursor = previous.removeAt(previous.lastIndex); load() }, 16)
        page.next?.let { next -> ui.add(content, ui.command(R.string.health_next_page) { previous += cursor; cursor = next; load() }, 16) }
    }
    private fun scopeText(scope: HealthAccessScope): String = buildList {
        if (scope.metrics.isNotEmpty()) {
            add(scope.metrics.sortedBy { it.ordinal }.joinToString(", ") { getString(it.titleResource()) })
            if (scope.from == 0L && scope.until == Long.MAX_VALUE) add(getString(R.string.health_privacy_scope_all_dates))
            else { val zone = ZoneId.of(scope.zone); add("${Instant.ofEpochMilli(scope.from).atZone(zone).toLocalDate()} \u2013 ${Instant.ofEpochMilli(scope.until - 1).atZone(zone).toLocalDate()}") }
        }
        if (scope.fields.isNotEmpty()) add(scope.fields.joinToString(", ") { getString(it.titleResource()) })
        scope.count?.let { count -> add(when (scope.purpose) {
            HealthAccessPurpose.SAVE_RECORDS -> getString(R.string.health_privacy_scope_records, count)
            HealthAccessPurpose.SAVE_ORIGINALS -> getString(R.string.health_privacy_scope_originals, count)
            HealthAccessPurpose.DELETE_PROFILE -> getString(R.string.health_privacy_scope_delete, scope.basicCount, count, scope.drafts)
            else -> getString(R.string.health_privacy_scope_entries, count)
        }) }
        if (scope.source != HealthAccessSource.ALL) add(getString(if (scope.source == HealthAccessSource.MANUAL) R.string.health_privacy_scope_manual else R.string.health_privacy_scope_original))
        scope.format?.takeUnless { it == HealthAccessFormat.ORIGINAL }?.let { add(it.name) }
        if (scope.annotations) add(getString(R.string.health_privacy_scope_notes))
        if (scope.reportRecords) add(getString(R.string.health_weekly_raw))
        scope.baselineFrom?.let { start ->
            val zone = ZoneId.of(scope.zone)
            add(getString(R.string.health_weekly_baseline_range, Instant.ofEpochMilli(start).atZone(zone).toLocalDate(),
                Instant.ofEpochMilli(scope.from - 1).atZone(zone).toLocalDate()))
        }
    }.joinToString(" \u00b7 ")
    private fun error() { val content = healthProfileContent(body); content.addView(ui.text(getString(R.string.health_storage_error))); ui.add(content, ui.command(R.string.common_retry) { load() }, 16) }
    private data class Snapshot(val policy: HealthPrivacyPolicy? = null, val page: HealthAccessPage? = null)
}
private fun HealthAccessPurpose.title() = when (this) {
    HealthAccessPurpose.TREND -> R.string.health_privacy_trend
    HealthAccessPurpose.TREND_RECORDS -> R.string.health_privacy_trend_records
    HealthAccessPurpose.TREND_SOURCES -> R.string.health_privacy_trend_sources
    HealthAccessPurpose.PROFILE_CONTEXT -> R.string.health_privacy_profile_context
    HealthAccessPurpose.WEEKLY_REPORT -> R.string.health_weekly_title
    HealthAccessPurpose.SAVE_WEEKLY_REPORT -> R.string.health_weekly_save
    HealthAccessPurpose.SAVE_RECORDS -> R.string.health_privacy_save_records
    HealthAccessPurpose.SAVE_ORIGINALS -> R.string.health_privacy_save_originals
    HealthAccessPurpose.DELETE_PROFILE -> R.string.health_privacy_delete_profile
}
private fun HealthAccessOutcome.title() = when (this) {
    HealthAccessOutcome.STARTED -> R.string.health_privacy_started
    HealthAccessOutcome.COMPLETE -> R.string.health_privacy_complete
    HealthAccessOutcome.FAILED -> R.string.health_privacy_failed
    HealthAccessOutcome.CANCELLED -> R.string.health_privacy_cancelled
    HealthAccessOutcome.BLOCKED -> R.string.health_privacy_blocked
}
