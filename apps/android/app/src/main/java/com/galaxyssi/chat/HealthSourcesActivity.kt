package com.galaxyssi.chat

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ImageView
import android.widget.ScrollView
import android.widget.Toast
import androidx.health.connect.client.HealthConnectClient
import java.text.DateFormat
import java.util.Date
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.Future

class HealthSourcesActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var body: LinearLayout
    private lateinit var scroll: ScrollView
    private lateinit var names: HealthOverviewDatabases
    private var work: Future<*>? = null
    private var generation = 0
    private var scrollY = 0

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.statusBarColor = getColor(R.color.page_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        val fixture = if (BuildConfig.DEBUG) intent.getStringExtra("health_sources_test_id")
            ?.takeIf { runCatching { UUID.fromString(it).toString() == it }.getOrDefault(false) } else null
        names = HealthOverviewDatabases(fixture)
        scrollY = state?.getInt("scroll") ?: 0
        body = ui.column().apply { setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(24)) }
        scroll = ScrollView(this).apply { addView(body) }
        setContentView(ui.column().apply {
            setBackgroundColor(getColor(R.color.page_bg))
            addView(ui.line().apply {
                addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
                addView(ui.text(getString(R.string.health_sources_title), 19f, bold = true).apply { gravity = Gravity.CENTER },
                    LinearLayout.LayoutParams(0, -2, 1f))
                addView(ui.icon(R.drawable.ic_health_grid, R.string.health_functions) {
                    if (names.fixture == null) {
                        startActivity(Intent(this@HealthSourcesActivity, HealthCenterActivity::class.java).putExtra("health_functions", true))
                        finish()
                    }
                })
            }, LinearLayout.LayoutParams(-1, ui.dp(56)))
            addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        })
    }

    override fun onResume() {
        super.onResume()
        val request = ++generation
        body.addView(ui.text(getString(R.string.health_sources_checking), 14f, muted = true))
        work = worker.submit {
            val result = HealthSourcesRepository.load(this, names, System.currentTimeMillis())
            runOnUiThread {
                if (request == generation && !isFinishing && !isDestroyed) {
                    show(result)
                    scroll.post { if (request == generation) scroll.scrollTo(0, scrollY) }
                }
            }
        }
    }

    override fun onPause() {
        if (body.findViewWithTag<View>("health-sources-ready") != null) scrollY = scroll.scrollY
        generation++
        work?.cancel(true); work = null
        body.removeAllViews()
        super.onPause()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("scroll", if (body.childCount > 1) scroll.scrollY else scrollY)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    private fun show(snapshot: HealthSourcesSnapshot) {
        body.removeAllViews()
        body.addView(ui.card().apply {
            tag = "health-sources-ready"
            background = ui.background(color = getColor(R.color.page_bg), stroke = getColor(R.color.separator), radius = 8)
            val summary = when {
                snapshot.platformScopes != null && snapshot.platformScopes > 0 -> getString(R.string.health_connect_scope_count, snapshot.platformScopes)
                snapshot.platform == HealthPlatformAvailability.AVAILABLE && snapshot.platformScopes == null ->
                    getString(R.string.health_connect_grant_status_unavailable)
                else -> getString(R.string.health_sources_summary_detail)
            }
            addView(sourceRow(R.drawable.ic_protocol_link, getString(R.string.health_sources_summary), summary))
        })
        ui.add(body, ui.text(getString(R.string.health_sources_platforms), 18f, bold = true), 20)
        val status = when (snapshot.platform) {
            HealthPlatformAvailability.AVAILABLE -> R.string.health_sources_platform_available
            HealthPlatformAvailability.INSTALL_OR_UPDATE -> R.string.health_sources_platform_install
            HealthPlatformAvailability.UNSUPPORTED -> R.string.health_sources_platform_unsupported
            HealthPlatformAvailability.CHECK_FAILED -> R.string.health_sources_platform_error
        }
        ui.add(body, ui.card().apply {
            addView(sourceRow(R.drawable.ic_health_heart, getString(R.string.health_sources_platform_name), getString(status))
                .apply { tag = "health-platform-${snapshot.platform.name}" })
            val last = snapshot.lastConfirmedImport.takeIf { it > 0 }?.let {
                getString(R.string.health_connect_last_import, DateFormat.getDateTimeInstance().format(Date(it)))
            } ?: getString(R.string.health_connect_no_import)
            ui.add(this, ui.text(last, 13f, muted = true), 6)
            addView(ui.profileRow(getString(R.string.health_connect_authorize)) {
                openLocal(Intent(this@HealthSourcesActivity, HealthConnectActivity::class.java))
            }.apply { tag = "health-connect-entry" })
            when (snapshot.platform) {
                HealthPlatformAvailability.AVAILABLE -> addView(ui.profileRow(getString(R.string.health_sources_system_settings)) {
                    openExternal(Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS))
                })
                HealthPlatformAvailability.INSTALL_OR_UPDATE -> addView(ui.profileRow(getString(R.string.health_sources_open_store)) {
                    val provider = HealthSourcesRepository.PROVIDER_PACKAGE
                    openExternal(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$provider")),
                        Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$provider")))
                })
                else -> Unit
            }
        }, 8)
        ui.add(body, ui.text(getString(R.string.health_sources_devices), 18f, bold = true), 20)
        ui.add(body, ui.card().apply {
            addView(sourceRow(R.drawable.ic_settings_devices, getString(R.string.health_sources_bluetooth),
                getString(if (snapshot.bluetoothLe) R.string.health_sources_ble_supported else R.string.health_sources_ble_unavailable)))
        }, 8)
        ui.add(body, ui.text(getString(R.string.health_sources_local), 18f, bold = true), 20)
        val local = snapshot.local
        ui.add(body, ui.card().apply {
            val files = local?.let { getString(R.string.health_sources_file_counts, it.originals, it.confirmedImports) }
                ?: getString(R.string.health_sources_local_error)
            val manual = when {
                local == null -> getString(R.string.health_sources_local_error)
                local.manualMeasuredAt == null -> getString(R.string.health_sources_manual_empty)
                else -> getString(R.string.health_sources_manual_latest, DateFormat.getDateTimeInstance().format(Date(local.manualMeasuredAt)))
            }
            addView(sourceRow(R.drawable.ic_chat_shortcut_file, getString(R.string.health_sources_files), files) {
                openLocal(Intent(this@HealthSourcesActivity, HealthDataFilesActivity::class.java))
            }
                .apply { tag = "health-sources-files" })
            addView(View(this@HealthSourcesActivity).apply { setBackgroundColor(getColor(R.color.separator)) },
                LinearLayout.LayoutParams(-1, ui.dp(1)).apply { topMargin = ui.dp(8); bottomMargin = ui.dp(8) })
            addView(sourceRow(R.drawable.ic_health_heart, getString(R.string.health_manual), manual) {
                openLocal(Intent(this@HealthSourcesActivity, HealthCenterActivity::class.java).putExtra("health_manual", true))
            }.apply { tag = "health-sources-manual" })
        }, 8)
    }

    private fun sourceRow(icon: Int, title: String, subtitle: String, action: (() -> Unit)? = null) = ui.line().apply {
        minimumHeight = ui.dp(50)
        addView(ImageView(this@HealthSourcesActivity).apply {
            setImageResource(icon)
            imageTintList = ColorStateList.valueOf(getColor(R.color.text_primary))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            background = ui.background(color = getColor(R.color.page_bg), radius = 8)
            setPadding(ui.dp(9), ui.dp(9), ui.dp(9), ui.dp(9))
        }, LinearLayout.LayoutParams(ui.dp(38), ui.dp(38)).apply { marginEnd = ui.dp(12) })
        addView(ui.column().apply {
            addView(ui.text(title, bold = true))
            addView(ui.text(subtitle, 13f, muted = true).apply { tag = "health-source-caption" })
        }, LinearLayout.LayoutParams(0, -2, 1f))
        action?.let {
            addView(ui.text("\u203a", 22f, muted = true).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO })
            isFocusable = true
            setOnClickListener { action() }
        }
    }

    private fun openLocal(intent: Intent) {
        if (names.fixture == null) startActivity(intent)
    }

    private fun openExternal(primary: Intent, fallback: Intent? = null) {
        if (names.fixture != null) return
        if (launch(primary) || (fallback != null && launch(fallback))) return
        Toast.makeText(this, R.string.health_sources_external_unavailable, Toast.LENGTH_SHORT).show()
    }

    private fun launch(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }
}
