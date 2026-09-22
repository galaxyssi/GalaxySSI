package com.galaxyssi.watch

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.nfc.NfcAdapter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.*
import com.galaxyssi.chat.NearbyContactProtocol as P
import org.json.JSONObject

class WatchNearbyActivity : Activity() {
    private val repo get() = (application as WatchApplication).repository
    private val nfc get() = intent.getBooleanExtra("nfc", false)
    private val handler = Handler(Looper.getMainLooper())
    private var ble: WatchNearbyBle? = null
    private var active = false
    private var generation = 0
    private var offer = ""
    private var remote = ""
    private var waitingId = ""
    private var busy = false
    private var status = ""
    private var initialPending = emptySet<String>()
    private val devices = linkedMapOf<String, Pair<BluetoothDevice, String>>()
    private val stop = Runnable { end(); status = getString(R.string.nearby_expired); render() }
    private val changed: () -> Unit = {
        if (active) {
            if (waitingId.isNotBlank()) {
                val state = repo.contacts.person(waitingId)?.status
                if (state == "approved") {
                    end(); startActivity(Intent(this, WatchContactsActivity::class.java).putExtra("peer", waitingId)); finish()
                } else if (state == "rejected") { status = getString(R.string.nearby_declined); render() }
            }
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); render() }
    override fun onResume() {
        super.onResume(); repo.listen(changed); repo.foreground(true)
        val permissions = if (nfc) emptyList() else listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), 81) else begin()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 81) {
            if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) begin()
            else { status = getString(R.string.nearby_permission); render() }
        }
    }
    override fun onPause() { end(); repo.unlisten(changed); repo.foreground(false); super.onPause() }
    private fun end() {
        active = false; generation++; handler.removeCallbacks(stop); ble?.close(); ble = null
        WatchNearbyOffer.close(); window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    private fun begin() {
        end(); active = true; val owner = generation; remote = ""; waitingId = ""; busy = false; devices.clear()
        initialPending = repo.contacts.people().filter { it.status == "pending" }.map { it.id }.toSet()
        status = getString(R.string.nearby_preparing); render()
        if (nfc && (NfcAdapter.getDefaultAdapter(this)?.isEnabled != true ||
                !packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION))) {
            end(); status = getString(R.string.nearby_nfc_unavailable); render(); return
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        var invitation = ""
        repo.contactAction({ invitation = createQr() }) { ok ->
            if (!active || generation != owner) return@contactAction
            if (!ok) { failure(); return@contactAction }
            offer = invitation; handler.postDelayed(stop, 120_000)
            if (nfc) {
                WatchNearbyOffer.open(offer); status = getString(R.string.nearby_nfc_help); render()
            } else {
                ble = WatchNearbyBle(this, offer, { device, name ->
                    if (!devices.containsKey(device.address) && devices.size < 20 && remote.isEmpty() && !busy) {
                        devices[device.address] = device to name.ifBlank { getString(R.string.nearby_device) + " · " + device.address.takeLast(5) }; render()
                    }
                }, { raw ->
                    val valid = repo.contacts.inspectInvitation(raw)
                    if (valid == null) failure() else { busy = false; remote = raw; status = valid.name; render() }
                }, ::failure)
                runCatching { ble?.start(); status = getString(R.string.nearby_ble_help); render() }.onFailure { failure() }
            }
        }
    }
    private fun failure() { end(); busy = false; status = getString(R.string.nearby_error); render() }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun render() {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(14), dp(20), dp(14), dp(24)); setBackgroundColor(Color.BLACK)
        }
        fun label(value: String, size: Float = 12f) { box.addView(TextView(this).apply {
            text = value; textSize = size; setTextColor(Color.WHITE); gravity = Gravity.CENTER; setPadding(0, dp(5), 0, dp(5))
        }) }
        fun button(value: String, action: () -> Unit) { box.addView(Button(this).apply {
            text = value; textSize = 12f; isAllCaps = false; setTextColor(Color.WHITE)
            background = GradientDrawable().apply { setColor(0xff19211d.toInt()); cornerRadius = dp(20).toFloat() }
            setOnClickListener { action() }; isEnabled = !busy
        }, LinearLayout.LayoutParams(-1, dp(44)).apply { topMargin = dp(5) }) }
        label(getString(if (nfc) R.string.nearby_nfc else R.string.nearby_ble), 16f)
        label(status)
        if (active && offer.isNotBlank() && waitingId.isBlank()) {
            label(getString(if (remote.isBlank()) R.string.nearby_my_code else R.string.nearby_compare))
            label(P.code(remote.ifBlank { offer }).chunked(3).joinToString(" "), 24f)
        }
        if (active && remote.isNotBlank() && waitingId.isBlank()) {
            button(getString(R.string.nearby_send_request)) {
                busy = true; render(); val raw = remote
                repo.contactAction({ requestFriend(raw) }) { ok ->
                    busy = false
                    if (!active) return@contactAction
                    if (ok) {
                        waitingId = JSONObject(raw).getString("i")
                        status = getString(R.string.nearby_wait_approval); render(); changed()
                    } else failure()
                }
            }
        } else if (active && !nfc && waitingId.isBlank()) devices.values.forEach { (device, name) ->
            button(name) { busy = true; status = getString(R.string.nearby_connecting); render(); ble?.connect(device) }
        }
        if (!active) button(getString(R.string.phone_setup_restart)) { begin() }
        button(getString(R.string.back)) { finish() }
        setContentView(ScrollView(this).apply { setBackgroundColor(Color.BLACK); addView(box) })
        window.insetsController?.hide(WindowInsets.Type.systemBars())
    }
}
