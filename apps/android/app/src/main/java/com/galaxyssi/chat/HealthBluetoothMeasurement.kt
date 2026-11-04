package com.galaxyssi.chat

import java.math.BigDecimal
import java.security.MessageDigest
import java.time.LocalDateTime
import java.time.ZoneId

internal data class HealthBloodPressurePacket(
    val systolic: BigDecimal,
    val diastolic: BigDecimal,
    val unit: String,
    val pulse: BigDecimal?,
    val deviceClock: LocalDateTime?,
    val userSlot: Int?,
    val status: Int,
    val fingerprint: String,
) {
    companion object {
        fun decode(bytes: ByteArray): HealthBloodPressurePacket? {
            if (bytes.size !in 7..19) return null
            var offset = 0
            fun byte() = bytes[offset++].toInt() and 0xff
            fun word() = byte() or (byte() shl 8)
            val flags = byte()
            fun has(bit: Int) = flags and bit != 0
            if (bytes.size != 7 + (if (has(2)) 7 else 0) + (if (has(4)) 2 else 0) +
                (if (has(8)) 1 else 0) + (if (has(16)) 2 else 0)) return null
            val systolic = sfloat(word())?.takeIf { it.signum() > 0 } ?: return null
            val diastolic = sfloat(word())?.takeIf { it.signum() > 0 } ?: return null
            word() // Mean arterial pressure is not a field in this archive.
            val clock = if (has(2)) {
                val year = word()
                val month = byte()
                val day = byte()
                val hour = byte()
                val minute = byte()
                val second = byte()
                if (year in 1970..9999 && month != 0 && day != 0)
                    runCatching { LocalDateTime.of(year, month, day, hour, minute, second) }.getOrNull() else null
            } else null
            val pulse = if (has(4)) sfloat(word())?.takeIf { it.signum() > 0 } else null
            val slot = if (has(8)) byte() else null
            val status = if (has(16)) word() and 0x3f else 0
            val fingerprint = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            return HealthBloodPressurePacket(systolic, diastolic, if (has(1)) "kPa" else "mmHg", pulse, clock, slot, status, fingerprint)
        }

        private fun sfloat(raw: Int): BigDecimal? {
            if (raw in 0x07fe..0x0802) return null
            val mantissa = (raw and 0xfff).let { if (it and 0x800 != 0) it - 0x1000 else it }
            val exponent = (raw ushr 12).let { if (it and 8 != 0) it - 16 else it }
            return BigDecimal.valueOf(mantissa.toLong()).scaleByPowerOfTen(exponent)
        }
    }
}

internal data class HealthBluetoothReceipt(
    val packet: HealthBloodPressurePacket,
    val label: String,
    val deviceToken: String,
    val capture: String,
    val bonded: Boolean,
    val receivedAt: Long,
    val zone: ZoneId,
) {
    private val clockOffset = packet.deviceClock?.let { zone.rules.getValidOffsets(it).singleOrNull() }
    private val clockMillis = clockOffset?.let { packet.deviceClock!!.toInstant(it).toEpochMilli() }?.takeIf { it in 1..receivedAt }
    val clockText get() = packet.deviceClock?.toString().orEmpty()
    val measuredAt get() = clockMillis ?: receivedAt
    val usesDeviceTime get() = clockMillis != null
    val eventKey get() = if (usesDeviceTime)
        "clock:${packet.deviceClock}:${packet.userSlot ?: "single"}" else "capture:$capture:${packet.fingerprint}"
    val trustedSlot get() = packet.userSlot?.toString() ?: "single"
    val allowsAutoSave get() = bonded && clockMillis != null && receivedAt - clockMillis <= 10 * 60_000 &&
        packet.userSlot != 255 && packet.status == 0

    fun draft(condition: String) = HealthDraft(values = buildMap {
        put("systolic", packet.systolic.stripTrailingZeros().toPlainString())
        put("diastolic", packet.diastolic.stripTrailingZeros().toPlainString())
        packet.pulse?.let { put("pulse", it.stripTrailingZeros().toPlainString()) }
    }, unit = packet.unit, measuredAt = measuredAt, condition = condition)
}
