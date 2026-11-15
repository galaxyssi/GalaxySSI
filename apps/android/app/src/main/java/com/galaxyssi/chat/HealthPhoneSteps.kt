package com.galaxyssi.chat

import android.content.Context
import android.util.Base64
import java.nio.ByteBuffer
import java.time.LocalDate
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class HealthPhoneStepLedger(val day: LocalDate, val total: Long = 0, val counter: Long? = null, val boot: Int = -1) {
    fun today(date: LocalDate) = if (day == date) this else copy(day = date, total = 0)

    fun observe(raw: Long, bootCount: Int, date: LocalDate, eventDate: LocalDate): HealthPhoneStepLedger {
        require(raw >= 0)
        val current = today(date)
        val delta = if (bootCount == boot && counter != null && raw >= counter && eventDate == date) raw - counter else 0
        return current.copy(total = (current.total + delta).coerceAtMost(Int.MAX_VALUE.toLong()), counter = raw, boot = bootCount)
    }
}

internal data class HealthPhoneStepReading(val ledger: HealthPhoneStepLedger?, val active: Boolean = false, val failed: Boolean = false)

internal object HealthPhoneStepUpdates {
    private val state = MutableStateFlow<HealthPhoneStepReading?>(null)
    val readings = state.asStateFlow()
    fun publish(value: HealthPhoneStepReading) { state.value = value }
}

internal class HealthPhoneStepStore(context: Context) {
    private val prefs = context.getSharedPreferences("health-phone-step-counter", Context.MODE_PRIVATE)
    private val aad = "health-phone-step-counter|v1".toByteArray()
    val enabled get() = prefs.getBoolean("enabled", false)

    fun load(): HealthPhoneStepLedger? {
        val encoded = prefs.getString("checkpoint", null) ?: return null
        val plain = AgentStorageCipher.decryptBinary(Base64.decode(encoded, Base64.NO_WRAP), aad)
        return try {
            check(plain.size == 28)
            val input = ByteBuffer.wrap(plain)
            val day = LocalDate.ofEpochDay(input.long)
            val total = input.long.also { check(it in 0..Int.MAX_VALUE.toLong()) }
            val counter = input.long.also { check(it in -1..Int.MAX_VALUE.toLong()) }.takeIf { it >= 0 }
            HealthPhoneStepLedger(day, total, counter, input.int)
        } finally { plain.fill(0) }
    }

    fun save(value: HealthPhoneStepLedger, enabled: Boolean) {
        val plain = ByteBuffer.allocate(28).putLong(value.day.toEpochDay()).putLong(value.total)
            .putLong(value.counter ?: -1).putInt(value.boot).array()
        val encrypted = try { AgentStorageCipher.encryptBinary(plain, aad) } finally { plain.fill(0) }
        prefs.edit().putString("checkpoint", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putBoolean("enabled", enabled).apply()
    }
}
