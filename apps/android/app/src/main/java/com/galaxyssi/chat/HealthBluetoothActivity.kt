package com.galaxyssi.chat

import android.bluetooth.BluetoothDevice
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal object HealthBluetoothTrust {
    private fun prefs(context: Context) = context.getSharedPreferences("health-bluetooth-trust", Context.MODE_PRIVATE)
    private fun slot(receipt: HealthBluetoothReceipt) = AgentMemoryIndexKey.token("health-bluetooth-owner-v1|${receipt.deviceToken}|${receipt.trustedSlot}")

    fun enabled(context: Context, receipt: HealthBluetoothReceipt): Boolean = receipt.allowsAutoSave &&
        prefs(context).getStringSet(receipt.deviceToken, emptySet()).orEmpty().contains(slot(receipt))

    @Synchronized fun enable(context: Context, receipt: HealthBluetoothReceipt) {
        require(receipt.allowsAutoSave)
        val prefs = prefs(context)
        val slots = prefs.getStringSet(receipt.deviceToken, emptySet()).orEmpty() + slot(receipt)
        prefs.edit().putStringSet(receipt.deviceToken, slots).apply()
    }

    @Synchronized fun clear(context: Context) { prefs(context).edit().clear().apply() }
}

class HealthBluetoothActivity : ComponentActivity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val tasks = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private var started = false
    private var generation = 0
    private var processing = false
    private var pending: HealthBluetoothReceipt? = null
    private var condition = "unspecified"
    private var self = false
    private var remember = false
    private var notice = ""
    private var savedId: String? = null
    private lateinit var content: LinearLayout
    private var state = HealthBleState.IDLE
    private var candidates = emptyList<HealthBleCandidate>()
    private var chosen: HealthBleCandidate? = null
    private val link by lazy {
        HealthBluetoothLink(this, { state, list, chosen ->
            this.state = state
            candidates = list
            this.chosen = chosen
            if (started) show()
        }, ::received)
    }
    private val permission = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        if (started) link.scan()
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.statusBarColor = getColor(R.color.page_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        content = ui.column().apply { setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(24)) }
        setContentView(ui.column().apply {
            setBackgroundColor(getColor(R.color.page_bg))
            addView(ui.line().apply {
                addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { finish() })
                addView(ui.text(getString(R.string.health_ble_title), 19f, bold = true).apply { gravity = Gravity.CENTER },
                    LinearLayout.LayoutParams(0, -2, 1f))
                addView(View(this@HealthBluetoothActivity), LinearLayout.LayoutParams(ui.dp(48), 1))
            }, LinearLayout.LayoutParams(-1, ui.dp(56)))
            addView(ScrollView(this@HealthBluetoothActivity).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        })
    }

    override fun onStart() { started = true; super.onStart(); show() }
    override fun onStop() {
        started = false
        generation++
        job?.cancel(); job = null
        link.stop()
        state = HealthBleState.IDLE; candidates = emptyList(); chosen = null
        pending = null; savedId = null; processing = false
        notice = ""; self = false; remember = false; condition = "unspecified"
        content.removeAllViews()
        super.onStop()
    }
    override fun onDestroy() { tasks.cancel(); super.onDestroy() }

    private fun search() {
        notice = ""; savedId = null
        if (link.permitted()) link.scan() else permission.launch(link.permissions())
    }

    private fun show() {
        content.removeAllViews()
        ui.add(content, ui.text(getString(R.string.health_ble_compatibility), 15f, bold = true), 4)
        ui.add(content, ui.text(getString(R.string.health_ble_supported_profile), 14f, muted = true), 6)
        ui.add(content, ui.card().apply {
            addView(ui.text(getString(state.resource()), 16f, bold = true).apply { tag = "health-ble-${state.name}" })
            chosen?.let { ui.add(this, ui.text(deviceName(it), 14f, muted = true), 4) }
            if (notice.isNotBlank()) ui.add(this, ui.text(notice, 14f).apply { tag = "health-ble-notice" }, 8)
        }, 14)
        if (processing) {
            ui.add(content, ui.text(getString(R.string.health_ble_processing), 14f, muted = true), 12)
            return
        }
        pending?.let { stage(it); return }
        if (state == HealthBleState.SCANNING || state == HealthBleState.CHOOSE) {
            if (candidates.isEmpty() && state == HealthBleState.CHOOSE)
                ui.add(content, ui.text(getString(R.string.health_ble_no_devices), 14f, muted = true), 12)
            candidates.forEach { candidate ->
                ui.add(content, ui.row(deviceName(candidate)) { choose(candidate) }.apply { tag = "health-ble-device" }, 2)
            }
        }
        if (state in setOf(HealthBleState.PAIR_REQUIRED, HealthBleState.PAIR_FAILED, HealthBleState.DISCONNECTED)) {
            chosen?.let { candidate ->
                ui.add(content, ui.row(getString(R.string.health_ble_pair_connect)) { link.connect(candidate, pair = true) })
                ui.add(content, ui.row(getString(R.string.health_ble_connect)) { link.connect(candidate) })
            }
        }
        if (link.linked() && state != HealthBleState.WAITING && state != HealthBleState.INVALID_PACKET)
            ui.add(content, ui.command(R.string.health_ble_next) { notice = ""; savedId = null; link.next() }, 12)
        if (state == HealthBleState.WAITING || state == HealthBleState.INVALID_PACKET)
            ui.add(content, ui.row(getString(R.string.health_ble_pause)) { link.pause() }, 10)
        savedId?.let { id ->
            ui.add(content, ui.row(getString(R.string.health_ble_view_record)) {
                startActivity(Intent(this, HealthCenterActivity::class.java).putExtra("health_record", id))
            }, 6)
        }
        if (state in ACTIVE_STATES) {
            ui.add(content, ui.row(getString(if (state == HealthBleState.SCANNING) R.string.health_ble_stop_scan else R.string.health_ble_disconnect)) {
                if (state == HealthBleState.SCANNING) link.stopScan() else link.disconnect()
            }, 10)
        } else if (state != HealthBleState.UNSUPPORTED) {
            ui.add(content, ui.command(R.string.health_ble_scan, ::search).apply { tag = "health-ble-scan" }, 12)
        }
        if (state == HealthBleState.BLUETOOTH_OFF) ui.add(content, ui.row(getString(R.string.health_ble_bluetooth_settings)) {
            val settings = Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
            if (settings.resolveActivity(packageManager) != null) startActivity(settings)
        })
        ui.add(content, ui.row(getString(R.string.health_ble_clear_auto)) {
            android.app.AlertDialog.Builder(this).setTitle(R.string.health_ble_clear_auto).setMessage(R.string.health_ble_clear_auto_detail)
                .setNegativeButton(android.R.string.cancel, null).setPositiveButton(android.R.string.ok) { _, _ ->
                    HealthBluetoothTrust.clear(this)
                    notice = getString(R.string.health_ble_auto_cleared); show()
                }.show()
        }, 8)
    }

    private fun choose(candidate: HealthBleCandidate) {
        android.app.AlertDialog.Builder(this).setTitle(deviceName(candidate))
            .setItems(arrayOf(getString(R.string.health_ble_connect), getString(R.string.health_ble_pair_connect))) { _, option ->
                notice = ""; link.connect(candidate, pair = option == 1)
            }.setNegativeButton(android.R.string.cancel, null).show()
    }

    @android.annotation.SuppressLint("MissingPermission")
    private fun deviceName(candidate: HealthBleCandidate): String =
        candidate.label.ifBlank { getString(R.string.health_ble_unnamed, candidate.device.address.takeLast(5)) }

    @android.annotation.SuppressLint("MissingPermission")
    private fun received(value: HealthBleReading) {
        if (!started || processing || pending != null) return
        processing = true; notice = ""; savedId = null; show()
        val token = ++generation
        job = tasks.launch {
            try {
                val (receipt, auto) = withContext(Dispatchers.IO) {
                    val deviceToken = AgentMemoryIndexKey.token("health-bluetooth-device-v1|${value.device.device.address}")
                    val receipt = HealthBluetoothReceipt(value.packet, deviceName(value.device), deviceToken,
                        value.capture, value.bonded, value.receivedAt, ZoneId.systemDefault())
                    receipt to HealthBluetoothTrust.enabled(this@HealthBluetoothActivity, receipt)
                }
                if (token != generation) return@launch
                pending = receipt; self = false; remember = false; condition = "unspecified"
                processing = false
                if (auto && link.permitted()) persist(receipt, "unspecified", auto = true, trust = false) else show()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) {
                if (token == generation) {
                    processing = false; notice = getString(R.string.health_ble_save_failed); show()
                }
            }
        }
    }

    private fun stage(receipt: HealthBluetoothReceipt) {
        ui.add(content, ui.card().apply {
            addView(ui.text(getString(R.string.health_ble_pending), 16f, bold = true))
            ui.add(this, ui.text(healthDisplayValue(receipt.draft(condition)), 24f, bold = true), 8)
            receipt.packet.pulse?.let { pulse ->
                ui.add(this, ui.text("${getString(R.string.health_pulse)}: ${pulse.stripTrailingZeros().toPlainString()} bpm", 14f), 4)
            }
            val formatter = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
            ui.add(this, ui.text(getString(R.string.health_ble_received_time, formatter.format(Date(receipt.receivedAt))), 13f, muted = true), 8)
            ui.add(this, ui.text(if (receipt.usesDeviceTime) getString(R.string.health_ble_clock, receipt.clockText.replace('T', ' '))
                else getString(R.string.health_ble_no_clock), 13f, muted = true), 4)
            receipt.packet.userSlot?.let { slot ->
                ui.add(this, ui.text(if (slot == 255) getString(R.string.health_ble_unknown_slot) else getString(R.string.health_ble_slot, slot), 13f), 4)
            }
            if (receipt.packet.status != 0) ui.add(this, ui.text(getString(R.string.health_ble_quality), 13f), 8)
        }, 12)
        ui.add(content, ui.text(getString(R.string.health_ble_condition), 16f, bold = true), 12)
        ui.add(content, RadioGroup(this).apply {
            listOf("unspecified", "resting", "after_exercise").forEach { value ->
                addView(RadioButton(this@HealthBluetoothActivity).apply {
                    id = View.generateViewId(); minimumHeight = ui.dp(48)
                    text = getString(healthContextResource(value))
                    tag = value; isChecked = condition == value
                })
            }
            setOnCheckedChangeListener { group, id -> condition = group.findViewById<View>(id)?.tag as? String ?: "unspecified" }
        })
        val save = ui.command(R.string.health_ble_save) {
            if (self) persist(receipt, condition, auto = false, trust = remember)
        }.apply { isEnabled = self; alpha = if (self) 1f else .48f; tag = "health-ble-save" }
        ui.add(content, CheckBox(this).apply {
            text = getString(R.string.health_ble_self); minimumHeight = ui.dp(48); isChecked = self
            setOnCheckedChangeListener { _, checked -> self = checked; save.isEnabled = checked; save.alpha = if (checked) 1f else .48f }
        })
        if (receipt.allowsAutoSave) ui.add(content, CheckBox(this).apply {
            text = getString(R.string.health_ble_trust); minimumHeight = ui.dp(48); isChecked = remember
            setOnCheckedChangeListener { _, checked -> remember = checked }
        })
        ui.add(content, save, 12)
        ui.add(content, ui.row(getString(R.string.health_ble_discard)) {
            pending = null; notice = ""; self = false; remember = false; show()
        })
        if (link.linked()) ui.add(content, ui.row(getString(R.string.health_ble_disconnect)) { link.disconnect() })
    }

    private fun persist(receipt: HealthBluetoothReceipt, condition: String, auto: Boolean, trust: Boolean) {
        if (processing) return
        processing = true; show()
        val token = ++generation
        job = tasks.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    val context = currentCoroutineContext()
                    val saved = HealthRecordStore(this@HealthBluetoothActivity).use { it.saveBluetooth(receipt, condition) { context.ensureActive() } }
                    if (trust && saved is HealthSaveResult.Saved) HealthBluetoothTrust.enable(this@HealthBluetoothActivity, receipt)
                    saved
                }
                if (token != generation) return@launch
                when (result) {
                    is HealthSaveResult.Saved -> {
                        savedId = result.record.id; pending = null
                        notice = getString(if (auto) R.string.health_ble_auto_saved else R.string.health_ble_saved)
                    }
                    is HealthSaveResult.Duplicate -> { pending = null; notice = getString(R.string.health_ble_duplicate) }
                    HealthSaveResult.Conflict -> notice = getString(R.string.health_ble_save_failed)
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { if (token == generation) notice = getString(R.string.health_ble_save_failed) }
            finally { if (token == generation) { processing = false; if (started) show() } }
        }
    }

    private fun HealthBleState.resource() = when (this) {
        HealthBleState.IDLE -> R.string.health_ble_idle
        HealthBleState.SCANNING -> R.string.health_ble_scanning
        HealthBleState.CHOOSE -> R.string.health_ble_choose
        HealthBleState.PAIRING -> R.string.health_ble_pairing
        HealthBleState.CONNECTING -> R.string.health_ble_connecting
        HealthBleState.DISCOVERING, HealthBleState.SUBSCRIBING -> R.string.health_ble_discovering
        HealthBleState.WAITING -> R.string.health_ble_waiting
        HealthBleState.RECEIVED -> R.string.health_ble_received
        HealthBleState.PAUSED -> R.string.health_ble_paused
        HealthBleState.DISCONNECTED -> R.string.health_ble_disconnected
        HealthBleState.PERMISSION -> if (Build.VERSION.SDK_INT >= 31) R.string.health_ble_permission else R.string.health_ble_legacy_permission
        HealthBleState.UNSUPPORTED -> R.string.health_ble_unsupported
        HealthBleState.BLUETOOTH_OFF -> R.string.health_ble_off
        HealthBleState.SCAN_FAILED -> R.string.health_ble_scan_failed
        HealthBleState.PAIR_FAILED -> R.string.health_ble_pair_failed
        HealthBleState.LINK_FAILED -> R.string.health_ble_link_failed
        HealthBleState.PROFILE_UNSUPPORTED -> R.string.health_ble_profile_unsupported
        HealthBleState.PAIR_REQUIRED -> R.string.health_ble_pair_required
        HealthBleState.TIMEOUT -> R.string.health_ble_timeout
        HealthBleState.INVALID_PACKET -> R.string.health_ble_invalid_packet
    }

    companion object {
        private val ACTIVE_STATES = setOf(HealthBleState.SCANNING, HealthBleState.PAIRING, HealthBleState.CONNECTING,
            HealthBleState.DISCOVERING, HealthBleState.SUBSCRIBING, HealthBleState.WAITING, HealthBleState.RECEIVED, HealthBleState.INVALID_PACKET, HealthBleState.PAUSED)
    }
}
