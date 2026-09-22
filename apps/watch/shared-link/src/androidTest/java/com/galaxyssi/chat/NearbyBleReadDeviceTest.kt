package com.galaxyssi.chat

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.os.ParcelUuid
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Opt-in radio test: a nearby watch must display Nearby watches. Never sends a friend request. */
class NearbyBleReadDeviceTest {
    @SuppressLint("MissingPermission")
    @Test fun discoversWatchAndReadsSignedInvitation() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("nearby") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.uiAutomation.adoptShellPermissionIdentity(Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
        val context = instrumentation.context
        val adapter = context.getSystemService(BluetoothManager::class.java).adapter
        val found = CountDownLatch(1); var device: BluetoothDevice? = null
        val done = CountDownLatch(1); var invitation: String? = null
        val reader = NearbyContactProtocol.Reader()
        val scan = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) { device = result.device; found.countDown() }
        }
        var client: BluetoothGatt? = null
        try {
            adapter.bluetoothLeScanner.startScan(listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(NearbyContactProtocol.SERVICE)).build()),
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scan)
            assertTrue("Watch advertisement not found", found.await(20, TimeUnit.SECONDS))
            adapter.bluetoothLeScanner.stopScan(scan)
            client = device!!.connectGatt(context, false, object : BluetoothGattCallback() {
                fun next(gatt: BluetoothGatt) {
                    val characteristic = gatt.getService(NearbyContactProtocol.SERVICE)?.getCharacteristic(NearbyContactProtocol.INVITE)
                    if (characteristic == null) { done.countDown(); return }
                    if (gatt.writeCharacteristic(characteristic, NearbyContactProtocol.offset(reader.offset), BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) != BluetoothStatusCodes.SUCCESS) done.countDown()
                }
                override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                    if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) gatt.discoverServices()
                    else if (status != BluetoothGatt.GATT_SUCCESS) done.countDown()
                }
                override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                    if (status == BluetoothGatt.GATT_SUCCESS) next(gatt) else done.countDown()
                }
                override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
                    if (status != BluetoothGatt.GATT_SUCCESS || !gatt.readCharacteristic(characteristic)) done.countDown()
                }
                override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
                    if (status != BluetoothGatt.GATT_SUCCESS) { done.countDown(); return }
                    runCatching {
                        invitation = reader.accept(value)
                        if (invitation == null) next(gatt) else done.countDown()
                    }.onFailure { done.countDown() }
                }
            }, BluetoothDevice.TRANSPORT_LE)
            assertTrue("Invitation transfer timed out", done.await(30, TimeUnit.SECONDS))
            assertNotNull("Incomplete invitation", invitation)
            val card = PhoneContactCard.normalizeQr(JSONObject(invitation!!))
            assertNotNull("Invalid signed invitation", card)
            assertTrue(PhoneContactCard.isQrOfferValid(card!!))
        } finally {
            client?.close(); adapter.bluetoothLeScanner.stopScan(scan)
            instrumentation.uiAutomation.dropShellPermissionIdentity()
        }
    }
}
