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
internal class WatchNearbyBle(private val context: Context, @Volatile private var offer: String,
    private val found: (BluetoothDevice, String, String?) -> Unit, private val received: (String) -> Unit,
    private val failed: () -> Unit) : AutoCloseable {
    private val main = Handler(Looper.getMainLooper())
    private val adapter = context.getSystemService(BluetoothManager::class.java).adapter
    private var server: BluetoothGattServer? = null
    private var client: BluetoothGatt? = null
    @Volatile private var closed = false
    private val positions = ConcurrentHashMap<String, Int>()
    private val readOffers = ConcurrentHashMap<String, ByteArray>()
    private var reader = P.Reader()
    companion object { private var lastScanStart = -10_000L }
    private var scanning = false
    private val scanStart: Runnable = Runnable {
        if (!closed) runCatching {
            lastScanStart = android.os.SystemClock.elapsedRealtime()
            adapter.bluetoothLeScanner.startScan(listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(P.SERVICE)).build()),
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scan)
            scanning = true
        }.onFailure { error() }
    }
    private val timeout = Runnable { client?.close(); client = null; if (!closed) failed() }
    private fun error() { main.post { if (!closed) failed() } }
    private val advertise = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) { error() }
    }
    private val scan: ScanCallback = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) {
            android.util.Log.w("WatchNearby", "BLE scan failed: $errorCode")
            main.post {
                if (!closed) {
                    scanning = false
                    if (errorCode == 6) { main.removeCallbacks(scanStart); main.postDelayed(scanStart, 31_000) }
                    else error()
                }
            }
        }
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val identity = WatchNearbyIdentity.decode(result.scanRecord?.getServiceData(ParcelUuid(P.SERVICE)))
            main.post { if (!closed) found(result.device, identity?.second ?: result.scanRecord?.deviceName.orEmpty(), identity?.first) }
        }
    }
    private val serverEvents = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            if (closed) return
            if (status != BluetoothGatt.GATT_SUCCESS) { error(); return }
            main.post { if (!closed) runCatching {
                adapter.bluetoothLeAdvertiser.startAdvertising(AdvertiseSettings.Builder()
                    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setConnectable(true)
                    .setTimeout(0).build(),
                    AdvertiseData.Builder().addServiceUuid(ParcelUuid(P.SERVICE)).build(),
                    AdvertiseData.Builder().addServiceData(ParcelUuid(P.SERVICE), WatchNearbyIdentity.encode(
                        org.json.JSONObject(offer).getString("i"), WatchDeviceName.current(context))).build(), advertise)
            }.onFailure { error() } }
        }
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_DISCONNECTED) { positions.remove(device.address); readOffers.remove(device.address) }
        }
        override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int,
            characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
            val position = if (value.size == 4) ByteBuffer.wrap(value).int else -1
            val snapshot = if (position == 0) offer.toByteArray(Charsets.UTF_8) else readOffers[device.address]
            val valid = !closed && !preparedWrite && offset == 0 && characteristic.uuid == P.INVITE &&
                snapshot != null && position in snapshot.indices && (positions.size < 4 || positions.containsKey(device.address))
            if (valid) { readOffers[device.address] = snapshot!!; positions[device.address] = position }
            if (responseNeeded) server?.sendResponse(device, requestId, if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE, 0, null)
        }
        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
            // Stay below MTU - 1 so Android does not issue a Read Blob continuation.
            val value = if (!closed && offset == 0 && characteristic.uuid == P.INVITE)
                positions[device.address]?.let { position -> readOffers[device.address]?.let { bytes ->
                    runCatching { P.chunk(bytes, position, 13) }.getOrNull()
                } } else null
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
        main.postDelayed(scanStart, (lastScanStart + 6_100 - android.os.SystemClock.elapsedRealtime()).coerceAtLeast(0))
    }
    fun connect(device: BluetoothDevice) {
        client?.close(); reader = P.Reader()
        main.removeCallbacks(timeout); main.postDelayed(timeout, 30_000)
        client = device.connectGatt(context, false, clientEvents, BluetoothDevice.TRANSPORT_LE)
        if (client == null) error()
    }
    fun updateOffer(value: String) {
        require(value.toByteArray(Charsets.UTF_8).size in 1..P.MAX_BYTES)
        offer = value
    }
    override fun close() {
        closed = true; main.removeCallbacks(timeout); main.removeCallbacks(scanStart)
        if (scanning) runCatching { adapter?.bluetoothLeScanner?.stopScan(scan) }
        runCatching { adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertise) }
        client?.close(); client = null; server?.close(); server = null; positions.clear(); readOffers.clear()
    }
}
