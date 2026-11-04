package com.galaxyssi.chat

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthBluetoothPacketTest {
    private fun packet(vararg values: Int) = HealthBloodPressurePacket.decode(ByteArray(values.size) { values[it].toByte() })
    private val now = Instant.parse("2026-11-04T12:05:00Z").toEpochMilli()
    private val zone = ZoneId.of("UTC")
    private fun receipt(packet: HealthBloodPressurePacket, capture: String = "attempt-1", bonded: Boolean = true) =
        HealthBluetoothReceipt(packet, "fixture", "device-token", capture, bonded, now, zone)

    @Test fun optionalFieldsDecodeInProtocolOrder() {
        val p = packet(0x1e, 124, 0, 82, 0, 96, 0, 0xea, 0x07, 11, 4, 12, 4, 10, 68, 0, 3, 1, 0)!!
        assertEquals("124", p.systolic.toPlainString())
        assertEquals("82", p.diastolic.toPlainString())
        assertEquals("68", p.pulse?.toPlainString())
        assertEquals("mmHg", p.unit)
        assertEquals(LocalDateTime.of(2026, 11, 4, 12, 4, 10), p.deviceClock)
        assertEquals(3, p.userSlot)
        assertEquals(1, p.status)
        assertFalse(receipt(p).allowsAutoSave)
    }

    @Test fun decimalKilopascalsAndOptionalUnavailablePulseStayDistinct() {
        val p = packet(0x05, 0xa5, 0xf0, 0x70, 0xf0, 0x86, 0xf0, 0xff, 0x07)!!
        assertEquals("16.5", p.systolic.toPlainString())
        assertEquals("11.2", p.diastolic.toPlainString())
        assertEquals("kPa", p.unit)
        assertNull(p.pulse)
        assertNull(p.deviceClock)
    }

    @Test fun truncatedTrailingAndNonFiniteMeasurementsAreRejected() {
        assertNull(packet(2, 120, 0, 80, 0, 90, 0))
        assertNull(packet(0, 120, 0, 80, 0, 90, 0, 7))
        assertNull(packet(0, 0xff, 0x07, 80, 0, 90, 0))
        assertNull(packet(0, 0xff, 0x0f, 80, 0, 90, 0))
        assertNotNull(packet(0x80, 120, 0, 80, 0, 90, 0))
    }

    @Test fun trustedSavingRequiresRecentClockKnownSlotAndBond() {
        val p = packet(0x0a, 120, 0, 80, 0, 90, 0, 0xea, 0x07, 11, 4, 12, 4, 0, 3)!!
        assertTrue(receipt(p).allowsAutoSave)
        assertFalse(receipt(p, bonded = false).allowsAutoSave)
        assertFalse(receipt(p.copy(userSlot = 255)).allowsAutoSave)
        assertFalse(receipt(p.copy(deviceClock = p.deviceClock!!.minusHours(1))).allowsAutoSave)
        assertFalse(receipt(p.copy(deviceClock = p.deviceClock!!.plusHours(1))).allowsAutoSave)
        assertEquals(receipt(p).eventKey, receipt(p, capture = "after-reconnect").eventKey)
        assertNotEquals(receipt(p).eventKey, receipt(p.copy(userSlot = 4)).eventKey)
    }

    @Test fun untimedPacketsUseReceiptTimeAndOnlyDeduplicateWithinExplicitCapture() {
        val p = packet(0, 120, 0, 80, 0, 90, 0)!!
        assertEquals(now, receipt(p).measuredAt)
        assertFalse(receipt(p).usesDeviceTime)
        assertFalse(receipt(p).allowsAutoSave)
        assertEquals(receipt(p).eventKey, receipt(p).eventKey)
        assertNotEquals(receipt(p).eventKey, receipt(p, capture = "new-capture").eventKey)
    }
}
