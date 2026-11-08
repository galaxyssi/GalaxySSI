package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.database.ContentObserver
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.Toast
import java.util.concurrent.Executors

class HealthCareVisitActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val names by lazy { intent.healthNavigationDatabases() }
    private val repository by lazy { HealthCareVisitRepository(applicationContext, names) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var body: LinearLayout
    private var concernId = ""
    private var active = false
    private var generation = 0
    private var busy = false
    private var document: HealthCareVisitSummary? = null
    private var dialog: AlertDialog? = null
    private val sections = HealthCareVisitSection.entries.filter { it != HealthCareVisitSection.PROFILE }.toMutableSet()
    private val selected = linkedSetOf<String>()
    private val expiry = Runnable { if (active) invalidate() }
    private val observer = object : ContentObserver(main) { override fun onChange(selfChange: Boolean) { if (active) invalidate() } }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        concernId = intent.getStringExtra("health_care_id").orEmpty()
        if (!HealthProfilePolicy.uuid(concernId)) { finish(); return }
        body = healthProfileBody(R.string.health_visit_title) { finish() }
    }
    override fun onStart() {
        super.onStart(); if (!::body.isInitialized) return
        active = true
        listOf(HealthCareStore.changes(this, names.care), HealthRecordStore.changes(this, names.records),
            HealthPrivacyStore.changes(this, names.privacy), HealthProfileStore.changes(this, names.profile))
            .forEach { contentResolver.registerContentObserver(it, false, observer) }
        scope()
    }
    override fun onStop() {
        if (::body.isInitialized) {
            active = false; clear(); contentResolver.unregisterContentObserver(observer)
        }
        super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (::body.isInitialized && level >= TRIM_MEMORY_RUNNING_LOW) {
            clear(); if (active) scope(R.string.health_visit_changed)
        }
    }
    private fun clear() {
        generation++; document = null; selected.clear(); dialog?.dismiss(); dialog = null
        main.removeCallbacks(expiry); body.removeAllViews()
    }
    private fun invalidate() { clear(); scope(R.string.health_visit_changed) }
    private fun scope(notice: Int? = null) {
        val content = healthProfileContent(body)
        notice?.let { ui.add(content, ui.text(getString(it), 14f, muted = true), 8) }
        content.addView(ui.text(getString(R.string.health_visit_scope), 18f, bold = true))
        ui.add(content, ui.text(getString(R.string.health_visit_scope_notice), 14f, muted = true), 8)
        HealthCareVisitSection.entries.forEach { section -> ui.add(content, CheckBox(this).apply {
            text = getString(section.titleResource()); textSize = 16f; minHeight = ui.dp(48)
            tag = "health-visit-scope-${section.name}"; isSaveEnabled = false; isChecked = section in sections
            setOnCheckedChangeListener { _, checked -> if (checked) sections += section else sections -= section }
        }, 8) }
        ui.add(content, ui.command(R.string.health_visit_preview) {
            if (sections.isEmpty()) Toast.makeText(this, R.string.health_visit_choose, Toast.LENGTH_SHORT).show()
            else load()
        }.apply { tag = "health-visit-preview" }, 16)
    }
    private fun load() {
        if (busy) return
        clear(); val chosen = sections.toSet()
        healthProfileContent(body).addView(ui.text(getString(R.string.health_loading)))
        work({ repository.load(concernId, chosen) }) { value ->
            document = value; selected.addAll(value.items.map { it.key }); render(value)
            main.postDelayed(expiry, (HealthCareVisitSummary.MAX_AGE - (System.currentTimeMillis() - value.createdAt)).coerceAtLeast(1))
        }
    }
    private fun render(value: HealthCareVisitSummary) {
        val content = healthProfileContent(body).apply { tag = "health-visit-document" }
        content.addView(ui.text(value.introduction, 15f))
        HealthCareVisitSection.entries.filter { it in value.sections }.forEach { section ->
            ui.add(content, ui.text(getString(section.titleResource()), 18f, bold = true), 20)
            val items = value.items.filter { it.section == section }
            if (items.isEmpty()) ui.add(content, ui.text(getString(R.string.health_visit_empty), 14f, muted = true), 8)
            items.forEach { item ->
                ui.add(content, CheckBox(this).apply {
                    text = item.title; textSize = 16f; minHeight = ui.dp(48); isSaveEnabled = false
                    isChecked = item.key in selected; tag = "health-visit-item-${item.key}"
                    setOnCheckedChangeListener { _, checked -> if (checked) selected += item.key else selected -= item.key }
                }, 12)
                ui.add(content, ui.text(item.text, 14f), 4)
                item.record?.let { record -> ui.add(content, ui.profileRow(getString(R.string.health_visit_original)) {
                    work({ repository.validate(value) }) {
                        startActivity(Intent(this, HealthRecordRevisionActivity::class.java).putHealthNavigationFixture(names)
                            .putExtra("health_record", record.id).putExtra("health_revision", record.revision))
                    }
                }.apply { tag = "health-visit-original-${record.id}" }, 4) }
            }
        }
        ui.add(content, ui.text(value.limitations, 14f, muted = true), 20)
        ui.add(content, ui.command(R.string.health_visit_share_review) { confirmShare(value) }
            .apply { tag = "health-visit-share" }, 16)
        ui.add(content, ui.profileRow(getString(R.string.health_visit_change_scope)) { clear(); scope() }, 8)
    }
    private fun confirmShare(value: HealthCareVisitSummary) {
        val keys = selected.toSet()
        if (keys.isEmpty()) { Toast.makeText(this, R.string.health_visit_choose, Toast.LENGTH_SHORT).show(); return }
        if (runCatching { value.selectedText(keys) }.isFailure) {
            Toast.makeText(this, R.string.health_visit_too_large, Toast.LENGTH_LONG).show(); return
        }
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_visit_share_review)
            .setMessage(getString(R.string.health_visit_share_warning, keys.size))
            .setNegativeButton(R.string.common_cancel, null).setPositiveButton(R.string.health_export_share) { _, _ ->
                work({ repository.validate(value); value.selectedText(keys) }) { text ->
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_SUBJECT, value.title).putExtra(Intent.EXTRA_TEXT, text)
                    runCatching { startActivity(Intent.createChooser(send, null)) }.onFailure {
                        Toast.makeText(this, R.string.health_export_share_unavailable, Toast.LENGTH_LONG).show()
                    }
                }
            }.show()
    }
    private fun <T> work(action: () -> T, done: (T) -> Unit) {
        if (busy) return
        busy = true; val token = generation
        worker.execute {
            val result = runCatching(action)
            main.post {
                busy = false
                if (active && token == generation && !isFinishing && !isDestroyed) result.fold(done, {
                    clear(); scope(R.string.health_visit_changed)
                })
            }
        }
    }
}
