package com.galaxyssi.chat

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Requires an explicitly identified external fixture advertising the standard pressure service. */
class HealthBluetoothRadioDeviceTest {
    @SuppressLint("MissingPermission")
    @Test fun standardIndicationCrossesThePhysicalRadioWithoutPersistingAnything() {
        val address = InstrumentationRegistry.getArguments().getString("bleFixtureAddress").orEmpty()
        val name = InstrumentationRegistry.getArguments().getString("bleFixtureName").orEmpty()
        assumeTrue("Requires a specified lab peripheral", Build.VERSION.SDK_INT >= 31 && address.isNotBlank())
        val test = InstrumentationRegistry.getInstrumentation()
        val context = test.targetContext
        val result = AtomicReference<HealthBleReading?>()
        val state = AtomicReference(HealthBleState.IDLE)
        val matched = CountDownLatch(1)
        val done = CountDownLatch(1)
        var attempted = false
        lateinit var link: HealthBluetoothLink
        test.uiAutomation.adoptShellPermissionIdentity(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        try {
            ActivityScenario.launch<HealthBluetoothActivity>(Intent(context, HealthBluetoothActivity::class.java)).use { scenario ->
                scenario.onActivity { activity ->
                    link = HealthBluetoothLink(activity, { next, candidates, _ ->
                        state.set(next)
                        if (!attempted && next in listOf(HealthBleState.SCANNING, HealthBleState.CHOOSE)) {
                            val fixture = candidates.firstOrNull {
                                it.device.address.equals(address, ignoreCase = true) ||
                                    (name.isNotBlank() && it.label.equals(name, ignoreCase = true))
                            }
                            if (fixture != null) {
                                attempted = true
                                matched.countDown()
                                link.connect(fixture)
                            }
                        }
                        if (next in listOf(HealthBleState.PERMISSION, HealthBleState.SCAN_FAILED, HealthBleState.LINK_FAILED,
                                HealthBleState.PROFILE_UNSUPPORTED, HealthBleState.TIMEOUT)) done.countDown()
                    }, { value -> result.set(value); done.countDown() })
                    assertTrue("Instrumentation did not receive temporary scan/connect permissions", link.permitted())
                    link.scan()
                }
                try {
                    assertTrue("No matching BLE fixture; final scan state: ${state.get()}", matched.await(19, TimeUnit.SECONDS))
                    assertTrue("No measurement; final link state: ${state.get()}", done.await(35, TimeUnit.SECONDS))
                    val reading = requireNotNull(result.get()) { "No accepted measurement; final link state: ${state.get()}" }
                    assertEquals("124", reading.packet.systolic.toPlainString())
                    assertEquals("82", reading.packet.diastolic.toPlainString())
                    assertEquals("68", reading.packet.pulse?.toPlainString())
                    assertEquals(2, reading.packet.userSlot)
                    assertTrue(reading.receivedAt > 0)
                    scenario.onActivity { link.pause(); assertEquals(HealthBleState.PAUSED, state.get()) }
                } finally { scenario.onActivity { link.stop() } }
            }
        } finally { test.uiAutomation.dropShellPermissionIdentity() }
    }
}
