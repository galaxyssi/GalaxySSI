package com.galaxyssi.chat

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.nfc.NfcAdapter
import android.nfc.tech.IsoDep
import android.os.Bundle
import android.view.Gravity
import android.widget.*
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** NFC carries the same signed, expiring invitation as a scanned QR code. */
class NfcWatchContactActivity : Activity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val reading = AtomicBoolean(false)
    @Volatile private var active = false
    @Volatile private var generation = 0
    @Volatile private var connection: IsoDep? = null
    private var adapter: NfcAdapter? = null
    @Volatile private var offer = ""
    private var status = ""
    private var name = ""
    override fun onCreate(state: Bundle?) {
        super.onCreate(state); adapter = NfcAdapter.getDefaultAdapter(this)
        status = getString(R.string.nearby_nfc_phone_help); render()
    }
    override fun onResume() {
        super.onResume(); active = true; generation++
        if (adapter?.isEnabled != true) { status = getString(R.string.nearby_nfc_enable); render(); return }
        adapter?.enableReaderMode(this, { tag ->
            if (!active || offer.isNotEmpty() || !reading.compareAndSet(false, true)) return@enableReaderMode
            val owner = generation
            worker.execute {
                val result = runCatching {
                    val link = IsoDep.get(tag) ?: error("Not an ISO-DEP device")
                    connection = link
                    try {
                        link.connect(); link.timeout = 3000
                        check(link.transceive(NearbyContactProtocol.SELECT).contentEquals(NearbyContactProtocol.OK))
                        val reader = NearbyContactProtocol.Reader()
                        var value: String? = null
                        val deadline = android.os.SystemClock.elapsedRealtime() + 15_000
                        while (value == null) {
                            check(active && owner == generation && android.os.SystemClock.elapsedRealtime() < deadline)
                            val reply = link.transceive(byteArrayOf(0x80.toByte(), 0x10, 0, 0, 4) + NearbyContactProtocol.offset(reader.offset))
                            check(reply.size > 2 && reply.takeLast(2).toByteArray().contentEquals(NearbyContactProtocol.OK))
                            value = reader.accept(reply.copyOfRange(0, reply.size - 2))
                        }
                        val card = PhoneContactCard.normalizeQr(JSONObject(value)) ?: error("Invalid invitation")
                        check(PhoneContactCard.isQrOfferValid(card))
                        check(card.optString("galaxyssi_id") != GalaxySSICrypto.localGalaxySSIId())
                        requireNotNull(value) to card.optString("name")
                    } finally { runCatching { link.close() }; connection = null }
                }
                runOnUiThread {
                    reading.set(false)
                    if (active && owner == generation) {
                        result.onSuccess { (raw, displayName) -> offer = raw; name = displayName; status = getString(R.string.nearby_nfc_compare) }
                            .onFailure { status = getString(R.string.nearby_nfc_failed) }
                        render()
                    }
                }
            }
        }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
    }
    override fun onPause() {
        active = false; generation++; adapter?.disableReaderMode(this)
        runCatching { connection?.close() }; super.onPause()
    }
    override fun onDestroy() { worker.shutdownNow(); super.onDestroy() }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun render() {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(32), dp(24), dp(24))
            setBackgroundColor(Color.rgb(245, 246, 247))
        }
        fun text(value: String, size: Float = 16f) { box.addView(TextView(this).apply {
            text = value; textSize = size; setTextColor(Color.rgb(30, 35, 33)); setPadding(0, dp(12), 0, dp(12))
        }) }
        text(getString(R.string.nearby_nfc_title), 23f); text(status)
        if (offer.isNotEmpty()) {
            text(name, 21f); text(NearbyContactProtocol.code(offer).chunked(3).joinToString(" "), 36f)
            box.addView(Button(this).apply {
                text = getString(R.string.nearby_nfc_send); isAllCaps = false; isEnabled = !reading.get()
                background = GradientDrawable().apply { setColor(Color.rgb(20, 198, 106)); cornerRadius = dp(20).toFloat() }
                setOnClickListener {
                    if (!reading.compareAndSet(false, true)) return@setOnClickListener
                    val raw = offer; isEnabled = false
                    worker.execute {
                        val ok = runCatching {
                            val card = PhoneContactCard.normalizeQr(JSONObject(raw)) ?: error("Invalid invitation")
                            check(AppStore.importContactQrAsRequest(this@NfcWatchContactActivity, card.toString()))
                            GalaxySSIMqttClient.publishPhoneContactRequest(card)
                        }.getOrDefault(false)
                        runOnUiThread {
                            reading.set(false); offer = ""
                            if (active) { status = getString(if (ok) R.string.nearby_nfc_sent else R.string.nearby_nfc_failed); render() }
                        }
                    }
                }
            }, LinearLayout.LayoutParams(-1, dp(52)))
        }
        box.addView(Button(this).apply { text = getString(android.R.string.cancel); setOnClickListener { finish() } })
        setContentView(ScrollView(this).apply { isFillViewport = true; addView(box) })
    }
}
