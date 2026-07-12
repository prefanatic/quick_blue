package com.example.quick_blue

import FlutterError
import PlatformBleInputProperty
import PlatformConnectionState
import PlatformGattStatus
import PlatformServiceDiscovered
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log

internal interface AndroidGattClient {
    val isGattClientAttached: Boolean

    fun emitConnectionState(
        deviceId: String,
        state: PlatformConnectionState,
        status: PlatformGattStatus,
    )

    fun emitServices(deviceId: String, services: List<PlatformServiceDiscovered>)
    fun emitMtuChanged(deviceId: String, mtu: Int, status: Int)
    fun emitCharacteristicValue(
        deviceId: String,
        serviceId: String,
        characteristicId: String,
        value: ByteArray,
    )

    fun closeGattStreams(deviceId: String)
}

internal data class NotificationKey(
    val deviceId: String,
    val serviceId: String,
    val characteristicId: String,
)

internal enum class GattOperationKind {
    DISCOVER_SERVICES,
    READ_CHARACTERISTIC,
    WRITE_CHARACTERISTIC,
    WRITE_DESCRIPTOR,
    REQUEST_MTU,
}

internal class GattOperation<Resource>(
    val deviceId: String,
    val kind: GattOperationKind,
    val client: AndroidGattClient? = null,
    val start: (Resource) -> Boolean,
    val onComplete: (Int, ByteArray?) -> Unit = { _, _ -> },
    val onStartFailed: () -> Unit = {},
    val onDisconnected: () -> Unit = {},
) {
    fun canDeliver(): Boolean = client?.isGattClientAttached != false
}

internal data class NotificationTransition(
    val previous: PlatformBleInputProperty?,
    val conflict: PlatformBleInputProperty?,
    val needsNativeWrite: Boolean,
)

private data class DisconnectPlan(
    val gatt: BluetoothGatt?,
    val detachOnly: Boolean,
    val unclaimedNotifications: List<NotificationKey>,
)

/** Process-wide owner of Android GATT connections shared by Flutter engines. */
@SuppressLint("MissingPermission")
internal object AndroidGattBroker {
    private val lock = Any()
    private val knownGatts = mutableMapOf<String, BluetoothGatt>()
    private val connectionStates = mutableMapOf<String, Int>()
    private val connectionClients = ConnectionClientSet<AndroidGattClient>()
    private val notificationClaims =
        NotificationClaimSet<NotificationKey, AndroidGattClient, PlatformBleInputProperty>()
    private val operationQueue = GattOperationQueue(::gatt)

    fun connectedGatts(): List<BluetoothGatt> = synchronized(lock) {
        knownGatts.values.toList()
    }

    fun attachedGatt(client: AndroidGattClient, deviceId: String): BluetoothGatt? =
        synchronized(lock) {
            if (connectionClients.contains(deviceId, client) &&
                connectionStates[deviceId] == BluetoothGatt.STATE_CONNECTED
            ) {
                knownGatts[deviceId]
            } else {
                null
            }
        }

    fun sharedGatt(deviceId: String): BluetoothGatt? = gatt(deviceId)

    fun connect(
        client: AndroidGattClient,
        context: Context,
        device: BluetoothDevice,
    ) {
        val deviceId = device.address
        synchronized(lock) {
            val existingGatt = knownGatts[deviceId]
            if (existingGatt != null) {
                when (connectionStates[deviceId]) {
                    BluetoothGatt.STATE_DISCONNECTING,
                    BluetoothGatt.STATE_DISCONNECTED -> throw FlutterError(
                        "DeviceBusy",
                        "The shared connection to $deviceId is still disconnecting",
                        null
                    )
                    BluetoothGatt.STATE_CONNECTED -> {
                        connectionClients.attach(deviceId, client)
                        client.emitConnectionState(
                            deviceId,
                            PlatformConnectionState.CONNECTED,
                            PlatformGattStatus.SUCCESS,
                        )
                    }
                    else -> connectionClients.attach(deviceId, client)
                }
                return
            }

            connectionClients.attach(deviceId, client)
            try {
                connectionStates[deviceId] = BluetoothGatt.STATE_CONNECTING
                knownGatts[deviceId] = device.connectGatt(
                    context,
                    false,
                    gattCallback,
                    BluetoothDevice.TRANSPORT_LE,
                )
            } catch (error: Throwable) {
                connectionClients.detach(deviceId, client)
                connectionStates.remove(deviceId)
                throw error
            }
        }
    }

    fun disconnect(client: AndroidGattClient, deviceId: String): List<NotificationKey> {
        val plan = synchronized(lock) {
            if (!connectionClients.contains(deviceId, client)) {
                throw FlutterError("IllegalArgument", "Unknown deviceId: $deviceId", null)
            }
            val detachOnly = connectionClients.clientCount(deviceId) > 1
            val gatt = if (detachOnly) {
                connectionClients.detach(deviceId, client)
                null
            } else {
                connectionStates[deviceId] = BluetoothGatt.STATE_DISCONNECTING
                knownGatts[deviceId]
            }
            DisconnectPlan(
                gatt = gatt,
                detachOnly = detachOnly,
                unclaimedNotifications = notificationClaims.removeClient(client) {
                    it.deviceId == deviceId
                },
            )
        }
        if (plan.detachOnly) {
            client.closeGattStreams(deviceId)
            client.emitConnectionState(
                deviceId,
                PlatformConnectionState.DISCONNECTED,
                PlatformGattStatus.SUCCESS,
            )
        } else {
            (plan.gatt
                ?: throw FlutterError("IllegalArgument", "Unknown deviceId: $deviceId", null))
                .disconnect()
        }
        return if (plan.detachOnly) plan.unclaimedNotifications else emptyList()
    }

    fun detach(client: AndroidGattClient): List<NotificationKey> {
        val gattsToClose = mutableListOf<BluetoothGatt>()
        val unclaimed = synchronized(lock) {
            connectionClients.deviceIdsFor(client).forEach { deviceId ->
                if (connectionClients.detach(deviceId, client)) {
                    operationQueue.failPending(deviceId)
                    connectionStates.remove(deviceId)
                    knownGatts.remove(deviceId)?.let(gattsToClose::add)
                }
            }
            notificationClaims.removeClient(client)
        }
        gattsToClose.forEach { gatt ->
            try {
                gatt.disconnect()
                gatt.close()
            } catch (error: Exception) {
                Log.e("AndroidGattBroker", "Failed to close ${gatt.device.address}", error)
            }
        }
        return unclaimed
    }

    fun enqueue(operation: GattOperation<BluetoothGatt>) = operationQueue.enqueue(operation)

    fun updateNotificationClaim(
        key: NotificationKey,
        client: AndroidGattClient,
        property: PlatformBleInputProperty,
        enable: Boolean,
    ): NotificationTransition = synchronized(lock) {
        if (enable) {
            val claim = notificationClaims.claim(key, client, property)
            NotificationTransition(
                previous = claim.previous,
                conflict = claim.conflict,
                needsNativeWrite = claim.conflict == null,
            )
        } else {
            val release = notificationClaims.release(key, client)
            NotificationTransition(
                previous = release.previous,
                conflict = null,
                needsNativeWrite = release.isUnclaimed,
            )
        }
    }

    fun restoreNotificationClaim(
        key: NotificationKey,
        client: AndroidGattClient,
        property: PlatformBleInputProperty?,
    ) = synchronized(lock) {
        notificationClaims.restore(key, client, property)
    }

    private fun gatt(deviceId: String): BluetoothGatt? = synchronized(lock) {
        knownGatts[deviceId]
    }

    private fun clients(deviceId: String): List<AndroidGattClient> = synchronized(lock) {
        connectionClients.clients(deviceId)
    }

    private fun isCurrentGatt(gatt: BluetoothGatt): Boolean = synchronized(lock) {
        knownGatts[gatt.device.address] === gatt
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            val gattStatus = if (status == BluetoothGatt.GATT_SUCCESS) {
                PlatformGattStatus.SUCCESS
            } else {
                PlatformGattStatus.FAILURE
            }
            val state = when (newState) {
                BluetoothGatt.STATE_CONNECTED -> PlatformConnectionState.CONNECTED
                BluetoothGatt.STATE_CONNECTING -> PlatformConnectionState.CONNECTING
                BluetoothGatt.STATE_DISCONNECTED -> PlatformConnectionState.DISCONNECTED
                BluetoothGatt.STATE_DISCONNECTING -> PlatformConnectionState.DISCONNECTING
                else -> PlatformConnectionState.UNKNOWN
            }
            val deviceId = gatt.device.address

            if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                val clients = synchronized(lock) {
                    if (knownGatts[deviceId] !== gatt) {
                        emptyList()
                    } else {
                        operationQueue.failPending(deviceId)
                        knownGatts.remove(deviceId)
                        connectionStates.remove(deviceId)
                        notificationClaims.removeMatching { it.deviceId == deviceId }
                        connectionClients.removeAll(deviceId)
                    }
                }
                clients.forEach { it.closeGattStreams(deviceId) }
                gatt.close()
                clients.forEach { it.emitConnectionState(deviceId, state, gattStatus) }
                return
            }

            val clients = synchronized(lock) {
                if (knownGatts[deviceId] === gatt) {
                    connectionStates[deviceId] = newState
                    connectionClients.clients(deviceId)
                } else {
                    emptyList()
                }
            }
            clients.forEach { it.emitConnectionState(deviceId, state, gattStatus) }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (!isCurrentGatt(gatt)) return
            // Snapshot the service tree before starting the next queued discovery. Some
            // Android stacks clear BluetoothGatt.services when discoverServices() is
            // called again.
            val services = if (status == BluetoothGatt.GATT_SUCCESS) {
                gatt.services.orEmpty().map { service ->
                    PlatformServiceDiscovered(
                        deviceId = gatt.device.address,
                        serviceUuid = service.uuid.toString(),
                        characteristics = service.characteristics.map {
                            it.toPlatformCharacteristic()
                        },
                    )
                }
            } else {
                emptyList()
            }
            operationQueue
                .complete(gatt.device.address, GattOperationKind.DISCOVER_SERVICES)
                ?.client
                ?.emitServices(gatt.device.address, services)
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (!isCurrentGatt(gatt)) return
            operationQueue
                .complete(gatt.device.address, GattOperationKind.REQUEST_MTU)
                ?.client
                ?.emitMtuChanged(gatt.device.address, mtu, status)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) = completeCharacteristicRead(gatt, characteristic.value, status)

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) = completeCharacteristicRead(gatt, value, status)

        private fun completeCharacteristicRead(gatt: BluetoothGatt, value: ByteArray?, status: Int) {
            if (!isCurrentGatt(gatt)) return
            val completedValue = if (status == BluetoothGatt.GATT_SUCCESS) {
                value?.copyOf() ?: byteArrayOf()
            } else {
                null
            }
            operationQueue.complete(
                gatt.device.address,
                GattOperationKind.READ_CHARACTERISTIC,
            )?.deliver(status, completedValue)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (!isCurrentGatt(gatt)) return
            clients(gatt.device.address).forEach { client ->
                client.emitCharacteristicValue(
                    gatt.device.address,
                    characteristic.service.uuid.toString(),
                    characteristic.uuid.toString(),
                    characteristic.value,
                )
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt?,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            val deviceId = gatt?.device?.address ?: return
            if (!isCurrentGatt(gatt)) return
            operationQueue.complete(
                deviceId,
                GattOperationKind.WRITE_CHARACTERISTIC,
            )?.deliver(status, null)
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: android.bluetooth.BluetoothGattDescriptor,
            status: Int,
        ) {
            if (!isCurrentGatt(gatt)) return
            operationQueue.complete(
                gatt.device.address,
                GattOperationKind.WRITE_DESCRIPTOR,
            )?.deliver(status, null)
        }
    }
}

internal class GattOperationQueue<Resource>(
    private val resourceProvider: (String) -> Resource?,
    private val dispatch: ((() -> Unit) -> Unit) = ::dispatchOnMain,
) {
    private val queues = mutableMapOf<String, ArrayDeque<GattOperation<Resource>>>()
    private val active = mutableMapOf<String, GattOperation<Resource>>()
    private val lock = Any()

    fun enqueue(operation: GattOperation<Resource>) {
        synchronized(lock) {
            queues.getOrPut(operation.deviceId) { ArrayDeque() }.addLast(operation)
        }
        startNext(operation.deviceId)
    }

    fun complete(deviceId: String, kind: GattOperationKind): GattOperation<Resource>? {
        val completed = synchronized(lock) {
            val operation = active[deviceId]
            if (operation?.kind != kind) return null
            active.remove(deviceId)
            operation
        }
        startNext(deviceId)
        return completed
    }

    fun failPending(deviceId: String) {
        val operations = synchronized(lock) {
            buildList {
                active.remove(deviceId)?.let(::add)
                queues.remove(deviceId)?.let(::addAll)
            }
        }
        operations.filter { it.canDeliver() }.forEach {
            dispatch(it.onDisconnected)
        }
    }

    private fun startNext(deviceId: String) {
        val operation = synchronized(lock) {
            if (active.containsKey(deviceId)) return
            val queue = queues[deviceId] ?: return
            val next = queue.removeFirstOrNull() ?: return
            if (queue.isEmpty()) queues.remove(deviceId)
            active[deviceId] = next
            next
        }
        val resource = resourceProvider(deviceId)
        if (resource == null) {
            complete(deviceId, operation.kind)
            if (operation.canDeliver()) dispatch(operation.onDisconnected)
            return
        }
        if (!operation.canDeliver()) {
            complete(deviceId, operation.kind)
            return
        }
        val started = try {
            operation.start(resource)
        } catch (error: Throwable) {
            Log.e("AndroidGattBroker", "Failed to start ${operation.kind}", error)
            false
        }
        if (!started) {
            complete(deviceId, operation.kind)
            if (operation.canDeliver()) dispatch(operation.onStartFailed)
        }
    }
}

private fun GattOperation<*>.deliver(status: Int, value: ByteArray?) {
    if (!canDeliver()) return
    dispatchOnMain { onComplete(status, value) }
}

private fun dispatchOnMain(action: () -> Unit) {
    Handler(Looper.getMainLooper()).post(action)
}
