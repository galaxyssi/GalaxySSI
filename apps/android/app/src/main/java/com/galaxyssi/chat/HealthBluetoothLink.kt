package com.galaxyssi.chat

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.util.UUID

internal enum class HealthBleState {
    IDLE, SCANNING, CHOOSE, PAIRING, CONNECTING, DISCOVERING, SUBSCRIBING, WAITING,
    RECEIVED, PAUSED, DISCONNECTED, PERMISSION, UNSUPPORTED, BLUETOOTH_OFF, SCAN_FAILED,
    PAIR_FAILED, LINK_FAILED, PROFILE_UNSUPPORTED, PAIR_REQUIRED, TIMEOUT, INVALID_PACKET
}

internal data class HealthBleCandidate(val device: BluetoothDevice, val label: String)
internal data class HealthBleReading(val device: HealthBleCandidate, val packet: HealthBloodPressurePacket,
    val capture: String, val receivedAt: Long, val bonded: Boolean)

@SuppressLint("MissingPermission")
internal class HealthBluetoothLink(
    private val context: Context,
    private val changed: (HealthBleState, List<HealthBleCandidate>, HealthBleCandidate?) -> Unit,
    private val reading: (HealthBleReading) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val adapter get() = context.getSystemService(BluetoothManager::class.java)?.adapter
    private var scanner: BluetoothLeScanner? = null
    private var scan: ScanCallback? = null
    private val found = linkedMapOf<String, HealthBleCandidate>()
    private var gatt: BluetoothGatt? = null
    private var selected: HealthBleCandidate? = null
    private var bondReceiver: BroadcastReceiver? = null
    private var timer: Runnable? = null
    private var early: Pair<HealthBloodPressurePacket, Long>? = null
    private var capture = ""
    private var state = HealthBleState.IDLE

    fun permissions(): Array<String> = if (Build.VERSION.SDK_INT >= 31)
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

    fun permitted() = permissions().all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    fun linked() = gatt != null && state in setOf(HealthBleState.WAITING, HealthBleState.RECEIVED, HealthBleState.INVALID_PACKET, HealthBleState.PAUSED)

    fun scan() {
        release(); selected = null; found.clear()
        if (!permitted()) return show(HealthBleState.PERMISSION)
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) return show(HealthBleState.UNSUPPORTED)
        guarded(HealthBleState.SCAN_FAILED) {
            val radio = adapter
            if (radio?.isEnabled != true) return@guarded show(HealthBleState.BLUETOOTH_OFF)
            val serviceScanner = radio.bluetoothLeScanner ?: return@guarded show(HealthBleState.SCAN_FAILED)
            val callback = object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) {
                    handler.post {
                        if (scan !== this) return@post
                        guarded(HealthBleState.SCAN_FAILED) {
                            if (result.isConnectable && found.size < 40 && !found.containsKey(result.device.address)) {
                                val name = safeLabel(result.scanRecord?.deviceName ?: result.device.name.orEmpty())
                                found[result.device.address] = HealthBleCandidate(result.device, name)
                                show(HealthBleState.SCANNING)
                            }
                        }
                    }
                }
                override fun onScanFailed(errorCode: Int) {
                    handler.post { if (scan === this) fail(HealthBleState.SCAN_FAILED) }
                }
            }
            scanner = serviceScanner; scan = callback
            serviceScanner.startScan(listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()),
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
            show(HealthBleState.SCANNING)
            timeout(15_000) { endScan(); show(HealthBleState.CHOOSE) }
        }
    }

    fun connect(candidate: HealthBleCandidate, pair: Boolean = false) {
        release(); selected = candidate
        if (!permitted()) return show(HealthBleState.PERMISSION)
        guarded(HealthBleState.LINK_FAILED) {
            if (adapter?.isEnabled != true) return@guarded show(HealthBleState.BLUETOOTH_OFF)
            if (pair && candidate.device.bondState != BluetoothDevice.BOND_BONDED) startBond(candidate)
            else openGatt(candidate)
        }
    }

    private fun startBond(candidate: HealthBleCandidate) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED || bondReceiver !== this) return
                @Suppress("DEPRECATION")
                val device = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    else intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                if (device != candidate.device) return
                guarded(HealthBleState.PAIR_FAILED) {
                    when (candidate.device.bondState) {
                        BluetoothDevice.BOND_BONDED -> { endBond(); openGatt(candidate) }
                        BluetoothDevice.BOND_NONE -> fail(HealthBleState.PAIR_FAILED)
                    }
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED), Context.RECEIVER_EXPORTED)
        else context.registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED))
        bondReceiver = receiver
        if (candidate.device.bondState != BluetoothDevice.BOND_BONDING && !candidate.device.createBond()) return fail(HealthBleState.PAIR_FAILED)
        show(HealthBleState.PAIRING)
        timeout(45_000) { fail(HealthBleState.PAIR_FAILED) }
    }

    private fun openGatt(candidate: HealthBleCandidate) {
        show(HealthBleState.CONNECTING)
        gatt = candidate.device.connectGatt(context, false, callbacks, BluetoothDevice.TRANSPORT_LE)
        if (gatt == null) return fail(HealthBleState.LINK_FAILED)
        timeout(25_000) { fail(HealthBleState.TIMEOUT) }
    }

    private val callbacks = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(link: BluetoothGatt, status: Int, newState: Int) = dispatch(link) {
            if (status != BluetoothGatt.GATT_SUCCESS) return@dispatch fail(HealthBleState.LINK_FAILED)
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    show(HealthBleState.DISCOVERING)
                    if (!link.discoverServices()) fail(HealthBleState.LINK_FAILED)
                }
                BluetoothProfile.STATE_DISCONNECTED -> fail(HealthBleState.DISCONNECTED)
            }
        }

        override fun onServicesDiscovered(link: BluetoothGatt, status: Int) = dispatch(link) {
            if (state != HealthBleState.DISCOVERING) return@dispatch
            if (status != BluetoothGatt.GATT_SUCCESS) return@dispatch fail(HealthBleState.LINK_FAILED)
            val measure = link.getService(SERVICE)?.getCharacteristic(MEASUREMENT)
                ?: return@dispatch fail(HealthBleState.PROFILE_UNSUPPORTED)
            val ccc = measure.getDescriptor(CCC) ?: return@dispatch fail(HealthBleState.PROFILE_UNSUPPORTED)
            if (measure.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE == 0)
                return@dispatch fail(HealthBleState.PROFILE_UNSUPPORTED)
            if (!link.setCharacteristicNotification(measure, true)) return@dispatch fail(HealthBleState.LINK_FAILED)
            capture = UUID.randomUUID().toString()
            show(HealthBleState.SUBSCRIBING)
            if (!enableIndications(link, ccc)) fail(HealthBleState.LINK_FAILED)
        }

        override fun onDescriptorWrite(link: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) = dispatch(link) {
            if (descriptor.uuid != CCC || descriptor.characteristic.uuid != MEASUREMENT || state != HealthBleState.SUBSCRIBING) return@dispatch
            when (status) {
                BluetoothGatt.GATT_SUCCESS -> {
                    show(HealthBleState.WAITING)
                    timeout(120_000) { fail(HealthBleState.TIMEOUT) }
                    early?.let { (packet, time) -> accept(packet, time) }
                    early = null
                }
                BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION, BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION ->
                    fail(HealthBleState.PAIR_REQUIRED)
                else -> fail(HealthBleState.LINK_FAILED)
            }
        }

        override fun onCharacteristicChanged(link: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            if (characteristic.uuid == MEASUREMENT && characteristic.service?.uuid == SERVICE) received(link, value)
        }

        @Deprecated("Pre-Android 13 indication callback")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(link: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33 && characteristic.uuid == MEASUREMENT && characteristic.service?.uuid == SERVICE)
                characteristic.value?.let { received(link, it) }
        }
    }

    private fun received(link: BluetoothGatt, value: ByteArray) {
        val time = System.currentTimeMillis()
        val copied = if (value.size in 7..19) value.copyOf() else ByteArray(0)
        handler.post {
            try {
                if (gatt !== link || state !in RECEIVE_STATES) return@post
                guarded(HealthBleState.LINK_FAILED) {
                    val packet = HealthBloodPressurePacket.decode(copied)
                    if (state == HealthBleState.SUBSCRIBING) {
                        if (early == null && packet != null) early = packet to time
                    } else if (packet == null) show(HealthBleState.INVALID_PACKET)
                    else accept(packet, time)
                }
            } finally {
                copied.fill(0)
            }
        }
    }

    private fun accept(packet: HealthBloodPressurePacket, time: Long) {
        val device = selected ?: return
        val bonded = device.device.bondState == BluetoothDevice.BOND_BONDED
        cancelTimer()
        show(HealthBleState.RECEIVED)
        reading(HealthBleReading(device, packet, capture, time, bonded))
    }

    fun next() {
        if (!linked()) return
        capture = UUID.randomUUID().toString()
        show(HealthBleState.WAITING)
        timeout(120_000) { fail(HealthBleState.TIMEOUT) }
    }

    fun disconnect() { release(); show(HealthBleState.DISCONNECTED) }
    fun pause() { if (linked()) { cancelTimer(); show(HealthBleState.PAUSED) } }
    fun stopScan() { cancelTimer(); endScan(); show(HealthBleState.CHOOSE) }
    fun stop() { release(); selected = null; found.clear(); state = HealthBleState.IDLE }

    @Suppress("DEPRECATION")
    private fun enableIndications(link: BluetoothGatt, descriptor: BluetoothGattDescriptor): Boolean {
        val value = BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
        return if (Build.VERSION.SDK_INT >= 33) link.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS
        else { descriptor.value = value; link.writeDescriptor(descriptor) }
    }

    private fun dispatch(link: BluetoothGatt, work: () -> Unit) {
        handler.post { if (gatt === link) guarded(HealthBleState.LINK_FAILED, work) }
    }

    private fun guarded(failure: HealthBleState, work: () -> Unit) {
        try { work() } catch (_: SecurityException) { fail(HealthBleState.PERMISSION) }
        catch (_: IllegalStateException) { fail(failure) }
    }

    private fun fail(state: HealthBleState) { release(); show(state) }
    private fun show(next: HealthBleState) { state = next; changed(next, found.values.toList(), selected) }
    private fun timeout(delay: Long, fire: () -> Unit) { cancelTimer(); timer = Runnable(fire).also { handler.postDelayed(it, delay) } }
    private fun cancelTimer() { timer?.let(handler::removeCallbacks); timer = null }
    private fun endScan() {
        val callback = scan; val previous = scanner
        scan = null; scanner = null
        if (callback != null) runCatching { previous?.stopScan(callback) }
    }
    private fun endBond() { bondReceiver?.let { runCatching { context.unregisterReceiver(it) } }; bondReceiver = null }
    private fun release() {
        cancelTimer(); endScan(); endBond(); early = null
        val previous = gatt; gatt = null
        if (previous != null) {
            runCatching { previous.disconnect() }
            runCatching { previous.close() }
        }
    }

    companion object {
        private val SERVICE = UUID.fromString("00001810-0000-1000-8000-00805f9b34fb")
        private val MEASUREMENT = UUID.fromString("00002a35-0000-1000-8000-00805f9b34fb")
        private val CCC = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private val RECEIVE_STATES = setOf(HealthBleState.SUBSCRIBING, HealthBleState.WAITING, HealthBleState.INVALID_PACKET)
        private fun safeLabel(raw: String) = raw.filterNot { it.isISOControl() || Character.getType(it) == Character.FORMAT.toInt() }.trim().take(80)
    }
}
