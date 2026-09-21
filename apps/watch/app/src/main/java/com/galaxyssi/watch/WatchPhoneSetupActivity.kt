package com.galaxyssi.watch

import android.app.Activity
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.*
import org.json.JSONObject
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/** No credentials or peer secrets are displayed, saved in instance state, or logged. */
class WatchPhoneSetupActivity : Activity() {
    companion object {
        const val EXTRA_CONFIGURE_MODELS = "configure_models"
    }
    private val configuringModels get() = intent.getBooleanExtra(EXTRA_CONFIGURE_MODELS, false)
    private val repo get() = (application as WatchApplication).repository
    private var server: WatchPhoneSetupServer? = null
    private var state = WatchPhoneSetupServer.State("starting")
    private var screen = "intro"
    private var generation = 0
    private var requestedDeviceName = false
    @Volatile private var resumed = false
    @Volatile private var pendingDesktop = ""
    private val desktopUpdate: () -> Unit = {}
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(false)
        requestedDeviceName = savedInstanceState?.getBoolean("requestedDeviceName") ?: false
        render()
    }
    override fun onResume() {
        super.onResume(); resumed = true; repo.listen(desktopUpdate); repo.foreground(true)
        if (!requestedDeviceName && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            requestedDeviceName = true
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 71)
            return
        }
        if (state.phase != "saved") startReceiver()
    }
    override fun onPause() {
        resumed = false; generation++; server?.close(); server = null
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        repo.unlisten(desktopUpdate); repo.foreground(false)
        super.onPause()
    }
    private fun startReceiver() {
        // Discovery is foreground-only: keep this bounded setup window visible until it ends.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        generation++; val owner = generation
        server?.close(); state = WatchPhoneSetupServer.State("starting")
        screen = "intro"; render()
        server = WatchPhoneSetupServer(this, { value ->
            if (owner == generation && resumed) {
                state = value
                if (value.phase in setOf("expired", "network_changed", "wifi_required", "error", "saved"))
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                if (value.phase == "confirm") screen = "confirm"
                else if (screen == "confirm") screen = "intro"
                if (value.phase == "saved") openHome() else render()
            }
        }, ::applyConfiguration).also { it.start() }
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("requestedDeviceName", requestedDeviceName)
        super.onSaveInstanceState(outState)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 71 && resumed && state.phase != "saved") startReceiver()
    }
    private fun applyConfiguration(payload: JSONObject): JSONObject {
        require(resumed)
        return when (payload.getString("kind")) {
            "cloud" -> {
                val profile = ApiProfile.fromJson(payload.getJSONObject("profile"))
                val previous = repo.store.apiProfile; val preferred = repo.store.apiPreferred
                try {
                    repo.store.apiProfile = profile; repo.store.apiPreferred = true
                } catch (error: Exception) {
                    repo.store.apiProfile = previous; repo.store.apiPreferred = preferred
                    throw error
                }
                JSONObject().put("status", "saved").put("kind", "cloud")
            }
            "desktop" -> {
                val qr = repo.inspectPairing(payload.getJSONObject("pairing_offer").toString())
                val completed = CompletableFuture<Boolean>()
                repo.pair(qr) { completed.complete(it) }
                require(completed.get(20, TimeUnit.SECONDS))
                pendingDesktop = qr.getString("desktop_id")
                // The existing Signal/MQTT pairing must be confirmed by the desktop before it is usable.
                JSONObject().put("status", "pairing_started").put("kind", "desktop")
            }
            "desktop_status" -> {
                require(pendingDesktop.isNotEmpty())
                val paired = repo.links().any { it.desktopId == pendingDesktop && it.paired }
                val agents = if (paired) repo.store.agents(pendingDesktop) else emptyList()
                JSONObject().put("status", if (agents.isEmpty()) "pairing_started" else "agents_ready")
                    .put("agents", org.json.JSONArray().also { list -> agents.forEach { list.put(JSONObject().put("id", it.id).put("name", it.name)) } })
            }
            "select_agent" -> {
                require(pendingDesktop.isNotEmpty() && repo.links().any { it.desktopId == pendingDesktop && it.paired })
                val selected = repo.store.agents(pendingDesktop).first { it.id == payload.getString("agent_id") }
                repo.store.selectedDesktop = pendingDesktop; repo.store.selectedAgent = selected.id
                repo.store.apiPreferred = false
                JSONObject().put("status", "saved").put("kind", "desktop").put("agent_name", selected.name)
            }
            else -> throw IllegalArgumentException("Unsupported configuration")
        }
    }
    private fun openHome() {
        server?.close()
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP))
        finish()
    }
    private fun render() {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(18), dp(8), dp(18), dp(14)); setBackgroundColor(Color.BLACK)
        }
        fun label(value: String, size: Float = 12f, color: Int = Color.WHITE, bold: Boolean = false) = TextView(this).apply {
            text = value; textSize = size; gravity = Gravity.CENTER; setTextColor(color); includeFontPadding = false
            if (bold) setTypeface(typeface, Typeface.BOLD)
            box.addView(this, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(if (configuringModels) 3 else 4) })
        }
        fun button(value: String, action: () -> Unit) {
            box.addView(Button(this).apply {
                text = value; textSize = 12f; isAllCaps = false; minHeight = dp(34); minimumHeight = dp(34)
                setPadding(dp(8), dp(2), dp(8), dp(2)); setTextColor(Color.WHITE)
                background = GradientDrawable().apply { setColor(Color.rgb(35, 42, 45)); cornerRadius = dp(24).toFloat() }
                setOnClickListener { action() }
            }, LinearLayout.LayoutParams(dp(150), -2).apply { topMargin = dp(2); bottomMargin = dp(3) })
        }
        val secondary = Color.rgb(168, 176, 184)
        if (configuringModels) {
            val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
            header.addView(TextView(this).apply {
                text = "‹"; textSize = 25f; setTextColor(Color.WHITE); gravity = Gravity.CENTER
                contentDescription = getString(R.string.back)
                setOnClickListener { finish() }
            }, LinearLayout.LayoutParams(dp(30), dp(32)))
            header.addView(TextView(this).apply {
                text = getString(R.string.configure_models); textSize = 15f; setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
            })
            box.addView(header, LinearLayout.LayoutParams(-2, dp(28)).apply { bottomMargin = dp(3) })
        }
        when (screen) {
            "agents" -> {
                label(getString(R.string.choose_agent), 17f, bold = true)
                repo.store.agents(pendingDesktop).forEach { agent ->
                    button(agent.name) {
                        repo.store.selectedDesktop = pendingDesktop; repo.store.selectedAgent = agent.id
                        repo.store.apiPreferred = false; pendingDesktop = ""; openHome()
                    }
                }
            }
            "confirm" -> {
                label(getString(R.string.phone_setup_confirm), 17f, bold = true)
                label(getString(R.string.phone_setup_compare), 12f, secondary)
                label(state.code.chunked(3).joinToString(" "), 30f, bold = true)
                label(getString(R.string.phone_setup_allow), 11f, secondary)
                button(getString(R.string.phone_setup_accept)) { server?.confirm(true); state = state.copy(phase = "receiving"); screen = "intro"; render() }
                button(getString(R.string.cancel)) { server?.confirm(false); screen = "intro"; render() }
            }
            "help" -> {
                label(getString(R.string.phone_setup_manual), 17f, bold = true)
                label(getString(R.string.phone_setup_manual_body), 12f, secondary)
                label(getString(R.string.phone_setup_address), 11f, secondary)
                label(state.host.ifBlank { "—" }, 19f)
                label(getString(R.string.phone_setup_port), 11f, secondary)
                label(if (state.port > 0) state.port.toString() else "—", 23f)
                label(getString(R.string.phone_setup_verify_after), 10f, secondary)
                button(getString(R.string.phone_setup_wifi)) { wifiSettings() }
                button(getString(R.string.back)) { screen = "intro"; render() }
            }
            else -> {
                if (configuringModels) {
                    label(getString(R.string.configure_models_title), 14f, bold = true)
                    label(getString(R.string.configure_models_wifi), 10f, secondary)
                    label(getString(R.string.configure_models_phone), 10f, secondary).apply {
                        (layoutParams as LinearLayout.LayoutParams).topMargin = dp(3)
                    }
                    label(getString(R.string.configure_models_path), 11f).apply {
                        setPadding(dp(6), dp(7), dp(6), dp(7))
                        background = GradientDrawable().apply {
                            setColor(Color.rgb(35, 38, 40)); cornerRadius = dp(18).toFloat()
                        }
                    }
                    label(getString(R.string.configure_models_description), 10f, secondary)
                } else {
                    label(java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date()), 10f, secondary)
                    val brand = LinearLayout(this).apply { gravity = Gravity.CENTER }
                    brand.addView(ImageView(this).apply { setImageResource(R.mipmap.ic_launcher) }, LinearLayout.LayoutParams(dp(28), dp(28)))
                    brand.addView(LinearLayout(this).apply {
                        orientation = LinearLayout.VERTICAL; setPadding(dp(6), 0, 0, 0)
                        addView(TextView(this@WatchPhoneSetupActivity).apply { text = getString(R.string.app_name); textSize = 14f; setTextColor(Color.WHITE); setTypeface(typeface, Typeface.BOLD) })
                        addView(TextView(this@WatchPhoneSetupActivity).apply { text = getString(R.string.agent_brand); textSize = 9f; gravity = Gravity.CENTER; setTextColor(secondary) })
                    })
                    box.addView(brand, LinearLayout.LayoutParams(-1, dp(30)))
                    label(getString(R.string.phone_setup_title), 14f, bold = true)
                    label(getString(R.string.phone_setup_step_wifi), 11f)
                    label(getString(R.string.phone_setup_step_phone), 11f)
                    label(getString(R.string.phone_setup_path), 10.5f, secondary)
                }
                val status = when (state.phase) {
                    "starting" -> R.string.phone_setup_starting
                    "wifi_required", "network_changed" -> R.string.phone_setup_need_wifi
                    "expired" -> R.string.phone_setup_expired
                    "error", "retry" -> R.string.phone_setup_retry
                    "receiving" -> R.string.phone_setup_receiving
                    "pairing_started", "agents_ready" -> R.string.phone_setup_pairing
                    else -> R.string.phone_setup_waiting
                }
                label((if (configuringModels) "●  " else "") + getString(status), 11f, Color.rgb(101, 217, 203))
                if (state.phase in setOf("error", "expired", "network_changed", "wifi_required", "retry")) {
                    button(getString(R.string.phone_setup_wifi)) { wifiSettings() }
                    button(getString(R.string.phone_setup_restart)) { startReceiver() }
                } else if (!configuringModels) button(getString(R.string.phone_setup_help)) { screen = "help"; render() }
                if (!configuringModels) button(getString(R.string.contacts)) { startActivity(Intent(this, WatchContactsActivity::class.java)) }
            }
        }
        setContentView(ScrollView(this).apply { isFillViewport = true; setBackgroundColor(Color.BLACK); addView(box) })
        window.insetsController?.hide(WindowInsets.Type.systemBars())
    }
    private fun wifiSettings() {
        val wear = Intent("com.google.android.clockwork.settings.connectivity.wifi.ADD_NETWORK_SETTINGS")
        runCatching { startActivity(wear) }.onFailure { runCatching { startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)) } }
    }
}
