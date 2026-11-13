package com.pocketparty.ble

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.ParcelUuid
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class PocketPartyBLE(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private val SERVICE_UUID: UUID = UUID.fromString("A7C30001-5A2B-4C9E-9D1A-8F0000000001")
        private val CHAR_UUID: UUID = UUID.fromString("A7C30002-5A2B-4C9E-9D1A-8F0000000001")
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val bluetoothManager: BluetoothManager by lazy {
        activity!!.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    }
    private val bluetoothAdapter: BluetoothAdapter? get() = bluetoothManager.adapter
    private var gattServer: BluetoothGattServer? = null
    private var localCharacteristic: BluetoothGattCharacteristic? = null
    private val subscribedCentrals = ConcurrentHashMap.newKeySet<BluetoothDevice>()
    private val remoteGatts = ConcurrentHashMap<String, BluetoothGatt>()
    private val remoteChars = ConcurrentHashMap<String, BluetoothGattCharacteristic>()
    private var isStarted = false

    override fun getPluginName(): String = "PocketPartyBLE"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("on_ble_packet", ByteArray::class.java),
        SignalInfo("on_peer_found", Int::class.javaObjectType, String::class.java, Int::class.javaObjectType)
    )

    @SuppressLint("MissingPermission")
    @UsedByGodot
    fun start_ble() {
        if (isStarted) return
        val adapter = bluetoothAdapter ?: return
        if (!adapter.isEnabled) return
        isStarted = true
        startGattServer()
        startAdvertising(adapter)
        startScanning(adapter)
    }

    @SuppressLint("MissingPermission")
    @UsedByGodot
    fun stop_ble() {
        if (!isStarted) return
        isStarted = false
        bluetoothAdapter?.bluetoothLeScanner?.stopScan(scanCallback)
        bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        remoteGatts.values.forEach { it.close() }
        remoteGatts.clear()
        remoteChars.clear()
        subscribedCentrals.clear()
        gattServer?.close()
        gattServer = null
    }

    @SuppressLint("MissingPermission")
    @UsedByGodot
    fun send_ble_packet(packet: ByteArray) {
        if (packet.isEmpty()) return
        val localChar = localCharacteristic
        val server = gattServer
        if (localChar != null && server != null) {
            localChar.value = packet
            for (device in subscribedCentrals) {
                server.notifyCharacteristicChanged(device, localChar, false)
            }
        }
        for ((addr, gatt) in remoteGatts) {
            val ch = remoteChars[addr] ?: continue
            ch.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            ch.value = packet
            gatt.writeCharacteristic(ch)
        }
    }

    @SuppressLint("MissingPermission")
    private fun startGattServer() {
        val ctx = activity ?: return
        gattServer = bluetoothManager.openGattServer(ctx, gattServerCallback)
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val ch = BluetoothGattCharacteristic(
            CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        ch.addDescriptor(BluetoothGattDescriptor(CCCD_UUID, BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ))
        localCharacteristic = ch
        service.addCharacteristic(ch)
        gattServer?.addService(service)
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertising(adapter: BluetoothAdapter) {
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTxPowerLevel(AdvertiseSettings.TX_POWER_HIGH)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        adapter.bluetoothLeAdvertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    @SuppressLint("MissingPermission")
    private fun startScanning(adapter: BluetoothAdapter) {
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        adapter.bluetoothLeScanner?.startScan(listOf(filter), settings, scanCallback)
    }

    private val advertiseCallback = object : AdvertiseCallback() {}

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device ?: return
            val addr = device.address
            if (!remoteGatts.containsKey(addr)) {
                val name = device.name ?: "PocketParty"
                emitSignal("on_peer_found", addr.hashCode() and 0x7FFFFFFF, name, result.rssi)
                val ctx = activity ?: return
                val gatt = device.connectGatt(ctx, false, gattClientCallback, BluetoothDevice.TRANSPORT_LE)
                remoteGatts[addr] = gatt
            }
        }
    }

    private val gattClientCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                val addr = gatt.device.address
                remoteChars.remove(addr)
                remoteGatts.remove(addr)?.close()
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) return
            val service = gatt.getService(SERVICE_UUID) ?: return
            val ch = service.getCharacteristic(CHAR_UUID) ?: return
            remoteChars[gatt.device.address] = ch
            gatt.setCharacteristicNotification(ch, true)
            val desc = ch.getDescriptor(CCCD_UUID)
            if (desc != null) {
                desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                gatt.writeDescriptor(desc)
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            val data = characteristic.value ?: return
            emitSignal("on_ble_packet", data)
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
        ) {
            if (value != null && value.isNotEmpty()) {
                emitSignal("on_ble_packet", value)
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
        ) {
            subscribedCentrals.add(device)
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }
    }
}
