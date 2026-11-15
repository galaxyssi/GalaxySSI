package com.galaxyssi.chat

import android.content.Context
import android.util.Base64
import java.time.LocalDate
import org.json.JSONObject

internal data class HealthCyclingState(
    val enabled: Boolean = false,
    val ledger: HealthCyclingLedger = HealthCyclingLedger(-1, -1),
)

internal class HealthCyclingStore(context: Context) {
    private val prefs = context.getSharedPreferences("health-cycling", Context.MODE_PRIVATE)
    private val aad = "health-cycling|auto|v1".toByteArray()
    val enabled get() = prefs.getBoolean("enabled", false)

    fun load(): HealthCyclingState {
        val encoded = prefs.getString("ledger", null) ?: return HealthCyclingState()
        val plain = AgentStorageCipher.decryptBinary(Base64.decode(encoded, Base64.NO_WRAP), aad)
        return try {
            val json = JSONObject(String(plain, Charsets.UTF_8))
            val days = json.getJSONObject("days")
            check(days.length() <= HealthCyclingLedger.DAYS)
            HealthCyclingState(enabled, HealthCyclingLedger(
                json.getInt("boot"), json.getLong("last"),
                json.optJSONObject("start")?.let { start ->
                    val elapsed = start.getLong("elapsed")
                    HealthCyclingStart(elapsed, start.getLong("wall"), start.optLong("evidence", elapsed),
                        start.readElapsed("gap"), start.readElapsed("still"),
                        start.optJSONObject("departure")?.let {
                            HealthCyclingDeparture(HealthCyclingMotion.valueOf(it.getString("motion")), it.getLong("from"), it.getLong("last"))
                        })
                },
                days.keys().asSequence().associate { key ->
                    LocalDate.parse(key) to days.getLong(key).also { check(it in 0..172_800_000) }
                },
                json.readElapsed("candidate"),
            ))
        } finally { plain.fill(0) }
    }

    fun save(state: HealthCyclingState) {
        val ledger = state.ledger
        val plain = JSONObject().put("boot", ledger.boot).put("last", ledger.lastEvent)
            .put("days", JSONObject().apply { ledger.days.forEach { (day, total) -> put(day.toString(), total) } })
            .apply {
                ledger.possibleStart?.let { put("candidate", it) }
                ledger.start?.let { start ->
                    val interval = JSONObject().put("elapsed", start.elapsed).put("wall", start.wall).put("evidence", start.evidence)
                    start.gap?.let { interval.put("gap", it) }
                    start.stillSince?.let { interval.put("still", it) }
                    start.departure?.let {
                        interval.put("departure", JSONObject().put("motion", it.motion.name).put("from", it.from).put("last", it.last))
                    }
                    put("start", interval)
                }
            }
            .toString().toByteArray(Charsets.UTF_8)
        val encrypted = try { AgentStorageCipher.encryptBinary(plain, aad) } finally { plain.fill(0) }
        check(prefs.edit().putString("ledger", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putBoolean("enabled", state.enabled).commit())
    }

    private fun JSONObject.readElapsed(key: String) = optLong(key, -1).takeIf { it >= 0 }
}
