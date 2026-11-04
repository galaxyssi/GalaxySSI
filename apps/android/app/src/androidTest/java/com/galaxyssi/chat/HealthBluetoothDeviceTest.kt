package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.content.ContextWrapper
import android.view.View
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthBluetoothDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val now = Instant.parse("2026-10-04T10:01:00Z").toEpochMilli()
    private val fixture = HealthBluetoothReceipt(
        requireNotNull(HealthBloodPressurePacket.decode(byteArrayOf(0, 124, 0, 82, 0, 96, 0)))
            .copy(deviceClock = LocalDateTime.of(2026, 10, 4, 10, 0), userSlot = 2),
        "BLE fixture", "opaque-device-token", "capture-id", true, now, ZoneId.of("UTC")
    )

    private fun database(test: (HealthRecordStore) -> Unit) {
        val name = "health-ble-${UUID.randomUUID()}.db"
        try { HealthRecordStore(context, name).use(test) } finally { context.deleteDatabase(name) }
    }

    @Test fun sourceAndClockArePreservedAcrossEditAndReplayedFramesDoNotRestoreDeletion() = database { store ->
        val saved = (store.saveBluetooth(fixture, "resting") {} as HealthSaveResult.Saved).record
        assertEquals("bluetooth", saved.source)
        assertEquals("BLE fixture", saved.platformOrigin)
        assertEquals(now, saved.deviceReceivedAt)
        assertEquals(fixture.clockText, saved.deviceClock)
        assertEquals("resting", saved.draft.condition)
        assertNull(store.latestManualMeasurement(now))
        assertEquals(0L, store.confirmedImportCount())
        val edited = (store.save(saved.editable().copy(note = "checked")) as HealthSaveResult.Saved).record
        assertEquals(saved.source, edited.source)
        assertEquals(saved.deviceReceivedAt, edited.deviceReceivedAt)
        assertEquals(saved.deviceClock, edited.deviceClock)
        assertTrue(store.saveBluetooth(fixture.copy(capture = "another-link"), "unspecified") {} is HealthSaveResult.Duplicate)
        assertTrue(store.delete(saved.id, edited.revision))
        assertTrue(store.saveBluetooth(fixture, "unspecified") {} is HealthSaveResult.Duplicate)
        assertEquals(0L, store.count())
    }

    @Test fun aCancelledWriteLeavesNoMeasurementOrDeduplicationMarker() = database { store ->
        var calls = 0
        assertTrue(runCatching { store.saveBluetooth(fixture, "unspecified") {
            if (calls++ > 0) throw IllegalStateException("fixture cancellation")
        } }.isFailure)
        assertEquals(0L, store.count())
        assertTrue(store.saveBluetooth(fixture, "unspecified") {} is HealthSaveResult.Saved)
    }

    @Test fun automaticSaveTrustIsOptInAndBoundToDeviceAndUserSlot() {
        val name = "health-ble-trust-${UUID.randomUUID()}"
        val isolated = object : ContextWrapper(context) {
            override fun getSharedPreferences(ignored: String?, mode: Int) = baseContext.getSharedPreferences(name, mode)
        }
        try {
            assertFalse(HealthBluetoothTrust.enabled(isolated, fixture))
            HealthBluetoothTrust.enable(isolated, fixture)
            assertTrue(HealthBluetoothTrust.enabled(isolated, fixture))
            assertFalse(HealthBluetoothTrust.enabled(isolated, fixture.copy(bonded = false)))
            assertFalse(HealthBluetoothTrust.enabled(isolated, fixture.copy(deviceToken = "another-device")))
            assertFalse(HealthBluetoothTrust.enabled(isolated, fixture.copy(packet = fixture.packet.copy(userSlot = 4))))
            HealthBluetoothTrust.clear(isolated)
            assertFalse(HealthBluetoothTrust.enabled(isolated, fixture))
        } finally { context.deleteSharedPreferences(name) }
    }

    @Test fun openingThePageDoesNotScanOrCollectAndStoppingClearsContent() {
        assumeFalse("Bluetooth UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        ActivityScenario.launch<HealthBluetoothActivity>(Intent(context, HealthBluetoothActivity::class.java)).use { scenario ->
            scenario.onActivity {
                assertNotNull(it.window.decorView.findViewWithTag<View>("health-ble-IDLE"))
                assertNull(it.window.decorView.findViewWithTag<View>("health-ble-SCANNING"))
                assertNull(it.window.decorView.findViewWithTag<View>("health-ble-save"))
            }
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { assertNull(it.window.decorView.findViewWithTag<View>("health-ble-IDLE")) }
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.onActivity { assertNotNull(it.window.decorView.findViewWithTag<View>("health-ble-IDLE")) }
        }
    }
}
