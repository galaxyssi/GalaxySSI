package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView

class HealthDataFilesActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state); window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
            addView(ui.text(getString(R.string.health_export_data_files), 19f, bold = true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) { startActivity(Intent(this@HealthDataFilesActivity, HealthCenterActivity::class.java).putExtra("health_functions", true)) })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        root.addView(ScrollView(this).apply { addView(ui.column().apply {
            setPadding(ui.dp(16), ui.dp(16), ui.dp(16), ui.dp(24))
            addView(ui.row(getString(R.string.health_export_import_records)) { startActivity(Intent(this@HealthDataFilesActivity, HealthCaptureActivity::class.java).putExtra("health_pick_files", true)) })
            addView(ui.row(getString(R.string.health_export_import_originals)) { startActivity(Intent(this@HealthDataFilesActivity, HealthCaptureActivity::class.java).putExtra("health_pick_files", true).putExtra("health_original_only", true)) })
            addView(ui.row(getString(R.string.health_export_records)) { startActivity(Intent(this@HealthDataFilesActivity, HealthRecordExportActivity::class.java)) })
            addView(ui.row(getString(R.string.health_original_library)) { startActivity(Intent(this@HealthDataFilesActivity, HealthOriginalLibraryActivity::class.java)) })
            addView(ui.row(getString(R.string.health_export_history)) { startActivity(Intent(this@HealthDataFilesActivity, HealthRecordExportActivity::class.java).putExtra("export_history", true)) })
            addView(ui.row(getString(R.string.health_backup_create)) {
                startActivity(Intent(this@HealthDataFilesActivity, HealthBackupActivity::class.java))
            }.apply { tag = "health-backup-export-entry" })
            addView(ui.row(getString(R.string.health_backup_verify)) {
                startActivity(Intent(this@HealthDataFilesActivity, HealthBackupActivity::class.java).putExtra("verify_backup", true))
            }.apply { tag = "health-backup-verify-entry" })
            addView(ui.row(getString(R.string.health_restore_title)) {
                startActivity(Intent(this@HealthDataFilesActivity, HealthRestoreActivity::class.java))
            }.apply { tag = "health-restore-entry" })
        }) }, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
}
