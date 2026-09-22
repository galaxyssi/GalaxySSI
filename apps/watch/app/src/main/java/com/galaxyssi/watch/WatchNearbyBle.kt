package com.galaxyssi.watch

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import com.galaxyssi.chat.NearbyContactProtocol as P
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap

/** Foreground, bounded discovery; no pairing secrets in BLE advertisements. */
@SuppressLint("MissingPermission")
internal class WatchNearbyBle(private val context: Context, private val offer: String,
    private val found: (BluetoothDevice, String) -> Unit, private val received: (String) -> Unit,
    private val failed: () -> Unit) : AutoCloseable {
    private val main = Handler(Looper.getMainLooper())
    private val adapter = context.getSystemService(BluetoothManager::class.java).adapter
    private var server: BluetoothGattServer? = null
    private var client: BluetoothGatt? = null
    @Volatile private var closed = false
    private val positions = ConcurrentHashMap<String, Int>()
    private var reader = P.Reader()
    private val timeout = Runnable { client?.close(); client = null; if (!closed) failed() }
    private fun error() { main.post { if (!closed) failed() } }
    private val advertise = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) { error() }
    }
    private val scan = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) { error() }
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            main.post { if (!closed) found(result.device, result.scanRecord?.deviceName.orEmpty()) }
        }
    }
    private val serverEvents = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            if (closed) return
            if (status != BluetoothGatt.GATT_SUCCESS) { error(); return }
            runCatching {
                adapter.bluetoothLeAdvertiser.startAdvertising(AdvertiseSettings.Builder()
                    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setConnectable(true)
                    .setTimeout(120_000).build(),
                    AdvertiseData.Builder().addServiceUuid(ParcelUuid(P.SERVICE)).build(),
                    AdvertiseData.Builder().setIncludeDeviceName(true).build(), advertise)
            }.onFailure { error() }
        }
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_DISCONNECTED) positions.remove(device.address)
        }
        override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int,
            characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
            val valid = !closed && !preparedWrite && offset == 0 && characteristic.uuid == P.INVITE && value.size == 4 &&
                ByteBuffer.wrap(value).int in offer.toByteArray(Charsets.UTF_8).indices && (positions.size < 4 || positions.containsKey(device.address))
            if (valid) positions[device.address] = ByteBuffer.wrap(value).int
            if (responseNeeded) server?.sendResponse(device, requestId, if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE, 0, null)
        }
        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
            // Stay below MTU - 1 so Android does not issue a Read Blob continuation.
            val value = if (!closed && offset == 0 && characteristic.uuid == P.INVITE)
                positions[device.address]?.let { runCatching { P.chunk(offer.toByteArray(Charsets.UTF_8), it, 13) }.getOrNull() } else null
            server?.sendResponse(device, requestId, if (value == null) BluetoothGatt.GATT_FAILURE else BluetoothGatt.GATT_SUCCESS, 0, value)
        }
    }
    private val clientEvents = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (closed || gatt !== client) { gatt.close(); return }
            if (status != BluetoothGatt.GATT_SUCCESS) { error(); return }
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                if (!gatt.discoverServices()) error()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) error()
        }
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (!closed && gatt === client) {
                if (status != BluetoothGatt.GATT_SUCCESS) error() else next(gatt)
            }
        }
        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (closed || gatt !== client) return
            if (status != BluetoothGatt.GATT_SUCCESS || !gatt.readCharacteristic(characteristic)) error()
        }
        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            if (closed || gatt !== client) return
            if (status != BluetoothGatt.GATT_SUCCESS) { error(); return }
            runCatching {
                val complete = reader.accept(value)
                if (complete == null) next(gatt) else {
                    main.post {
                        if (!closed && client === gatt) {
                            main.removeCallbacks(timeout); client = null; gatt.close(); received(complete)
                        }
                    }
                }
            }.onFailure { error() }
        }
    }
    private fun next(gatt: BluetoothGatt) {
        val characteristic = gatt.getService(P.SERVICE)?.getCharacteristic(P.INVITE)
        if (characteristic == null || gatt.writeCharacteristic(characteristic, P.offset(reader.offset),
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) != BluetoothStatusCodes.SUCCESS) error()
    }
    fun start() {
        require(adapter?.isEnabled == true && adapter.isMultipleAdvertisementSupported)
        require(offer.toByteArray(Charsets.UTF_8).size in 1..P.MAX_BYTES)
        server = context.getSystemService(BluetoothManager::class.java).openGattServer(context, serverEvents)
        val service = BluetoothGattService(P.SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(BluetoothGattCharacteristic(P.INVITE,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_READ or BluetoothGattCharacteristic.PERMISSION_WRITE))
        check(server?.addService(service) == true)
        adapter.bluetoothLeScanner.startScan(listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(P.SERVICE)).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scan)
    }
    fun connect(device: BluetoothDevice) {
        client?.close(); reader = P.Reader()
        main.removeCallbacks(timeout); main.postDelayed(timeout, 30_000)
        client = device.connectGatt(context, false, clientEvents, BluetoothDevice.TRANSPORT_LE)
        if (client == null) error()
    }
    override fun close() {
        closed = true; main.removeCallbacks(timeout)
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scan) }
        runCatching { adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertise) }
        client?.close(); client = null; server?.close(); server = null; positions.clear()
    }
}
