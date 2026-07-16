package com.example.quick_blue

import FlutterError
import BluetoothStateStreamHandler
import BondStateChangesStreamHandler
import L2CapSocketEventsStreamHandler
import MtuChangedStreamHandler
import PigeonEventSink
import PlatformBleInputProperty
import PlatformBleCompanionFilter
import PlatformBleOutputProperty
import PlatformAndroidScanCallbackType
import PlatformAndroidScanMatchMode
import PlatformAndroidScanMode
import PlatformAndroidScanNumOfMatches
import PlatformAndroidScanOptions
import PlatformAndroidScanPhy
import PlatformBondState
import PlatformBondStateChange
import PlatformBluetoothState
import PlatformCharacteristic
import PlatformCharacteristicValueChanged
import PlatformCompanionAssociation
import PlatformCompanionAssociationRequest
import PlatformConnectionState
import PlatformConnectionStateChange
import PlatformGattStatus
import PlatformL2CapSocketEvent
import PlatformMtuChange
import PlatformScanResult
import PlatformServiceDiscovered
import QuickBlueApi
import QuickBlueFlutterApi
import ScanResultsStreamHandler
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.companion.AssociationInfo
import android.companion.AssociationRequest
import android.companion.BluetoothLeDeviceFilter
import android.companion.CompanionDeviceManager
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentSender
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.ActivityCompat.startIntentSenderForResult
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.newSingleThreadContext
import kotlinx.coroutines.withContext
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.Executor
import java.util.regex.Pattern

private const val SELECT_DEVICE_REQUEST_CODE = 10011

private fun gattError(message: String, status: Int): FlutterError {
    return FlutterError(
        "GattError",
        "$message with GATT status $status",
        status
    )
}

/** QuickBluePlugin */
@SuppressLint("MissingPermission")
class QuickBluePlugin : FlutterPlugin, PluginRegistry.ActivityResultListener,
    ActivityAware, QuickBlueApi, AndroidGattClient {

    private val scanResultListener = ScanResultListener()
    private val mtuChangedListener = MtuChangedListener()
    private val l2CapSocketEventsListener = L2CapSocketEventsListener()
    private val bondStateChangesListener = BondStateChangesListener()
    private val bondStateReceiver = BondStateReceiver()
    private lateinit var bluetoothStateListener: BluetoothStateListener

    private fun setUp(messenger: BinaryMessenger, context: Context) {
        QuickBlueApi.setUp(messenger, this)
        bluetoothStateListener = BluetoothStateListener(context, bluetoothManager)
        BluetoothStateStreamHandler.register(messenger, bluetoothStateListener)
        BondStateChangesStreamHandler.register(messenger, bondStateChangesListener)
        ScanResultsStreamHandler.register(messenger, scanResultListener)
        MtuChangedStreamHandler.register(messenger, mtuChangedListener)
        L2CapSocketEventsStreamHandler.register(messenger, l2CapSocketEventsListener)

        quickBlueFlutterApi = QuickBlueFlutterApi(messenger)
        this.context = context
        ContextCompat.registerReceiver(
            context,
            bondStateReceiver,
            IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        isAttachedToEngine = true
        mainThreadHandler = Handler(Looper.getMainLooper())
        bluetoothManager =
            binding.applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        companionDeviceManager =
            binding.applicationContext.getSystemService(Context.COMPANION_DEVICE_SERVICE) as CompanionDeviceManager

        setUp(binding.binaryMessenger, binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("QuickBluePlugin", "onDetachedFromEngine")
        bluetoothManager.adapter.bluetoothLeScanner?.stopScan(scanCallback)
        isAttachedToEngine = false

        val unclaimedNotifications = AndroidGattBroker.detach(this)
        disableUnclaimedNotifications(unclaimedNotifications)

        executor.execute {
            streamDelegates.values.forEach(L2CapStreamDelegate::close)
            streamDelegates.clear()
        }

        QuickBlueApi.setUp(binding.binaryMessenger, null)
        quickBlueFlutterApi = null
        try {
            context.unregisterReceiver(bondStateReceiver)
        } catch (_: IllegalArgumentException) {
        }
        if (::bluetoothStateListener.isInitialized) {
            bluetoothStateListener.onEventsDone()
        }
        scanResultListener.onEventsDone()
        bondStateChangesListener.onEventsDone()
        mtuChangedListener.onEventsDone()
        l2CapSocketEventsListener.onEventsDone()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            SELECT_DEVICE_REQUEST_CODE -> when (resultCode) {
                Activity.RESULT_OK -> {
                    // TODO(cg): unlikely we need to do anything here; handling the association is
                    //           managed within onAssociationCreated.
                    return true
                }
            }
        }
        return false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private lateinit var context: Context
    private lateinit var mainThreadHandler: Handler
    private lateinit var bluetoothManager: BluetoothManager
    private lateinit var companionDeviceManager: CompanionDeviceManager
    private var quickBlueFlutterApi: QuickBlueFlutterApi? = null
    @Volatile
    private var isAttachedToEngine = false
    override val isGattClientAttached: Boolean
        get() = isAttachedToEngine
    private var activeScanRssi: Long? = null

    private var activity: Activity? = null

    private val executor: Executor = Executor { it.run() }
    private val streamDelegates = mutableMapOf<String, L2CapStreamDelegate>()
    private val bondLock = Any()
    private val pendingPairCallbacks =
        mutableMapOf<String, MutableList<(Result<Unit>) -> Unit>>()

    private inner class BondStateReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) {
                return
            }
            val device = intent.bluetoothDeviceExtra ?: return
            val state = intent.getIntExtra(
                BluetoothDevice.EXTRA_BOND_STATE,
                BluetoothDevice.ERROR
            )
            val previousState = intent.getIntExtra(
                BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE,
                BluetoothDevice.ERROR
            )
            bondStateChangesListener.onBondStateChanged(
                PlatformBondStateChange(
                    deviceId = device.address,
                    state = state.toPlatformBondState(),
                    previousState = previousState.toPlatformBondState(),
                )
            )
            when (state) {
                BluetoothDevice.BOND_BONDED -> completePendingPair(
                    device.address,
                    Result.success(Unit)
                )
                BluetoothDevice.BOND_NONE -> completePendingPair(
                    device.address,
                    Result.failure(
                        FlutterError(
                            "BondFailed",
                            "Pairing failed for ${device.address}",
                            null
                        )
                    )
                )
            }
        }
    }

    private fun completePendingPair(deviceId: String, result: Result<Unit>) {
        val callbacks = synchronized(bondLock) {
            pendingPairCallbacks.remove(deviceId)?.toList() ?: emptyList()
        }
        callbacks.forEach { it(result) }
    }

    override fun emitConnectionState(
        deviceId: String,
        state: PlatformConnectionState,
        status: PlatformGattStatus,
        nativeStatus: Int,
    ) {
        if (!isAttachedToEngine) return
        mainThreadHandler.post {
            if (!isAttachedToEngine) return@post
            quickBlueFlutterApi?.onConnectionStateChange(
                PlatformConnectionStateChange(
                    deviceId = deviceId,
                    state = state,
                    gattStatus = status,
                    nativeStatus = nativeStatus.toLong(),
                )
            ) {}
        }
    }

    override fun emitServices(
        deviceId: String,
        services: List<PlatformServiceDiscovered>,
    ) {
        if (!isAttachedToEngine) return
        mainThreadHandler.post {
            if (!isAttachedToEngine) return@post
            if (services.isEmpty()) {
                quickBlueFlutterApi?.onServiceDiscoveryComplete(deviceId) {}
                return@post
            }

            var pendingServiceCallbacks = services.size
            services.forEach { service ->
                quickBlueFlutterApi?.onServiceDiscovered(
                    service
                ) {
                    pendingServiceCallbacks -= 1
                    if (pendingServiceCallbacks == 0) {
                        quickBlueFlutterApi?.onServiceDiscoveryComplete(deviceId) {}
                    }
                }
            }
        }
    }

    override fun emitMtuChanged(deviceId: String, mtu: Int, status: Int) {
        if (!isAttachedToEngine) return
        mainThreadHandler.post {
            if (!isAttachedToEngine) return@post
            if (status == BluetoothGatt.GATT_SUCCESS) {
                mtuChangedListener.onScanResult(
                    PlatformMtuChange(deviceId = deviceId, mtu = mtu.toLong())
                )
            } else {
                mtuChangedListener.onScanError(status)
            }
        }
    }

    override fun emitCharacteristicValue(
        deviceId: String,
        serviceId: String,
        characteristicId: String,
        value: ByteArray,
    ) {
        if (!isAttachedToEngine) return
        mainThreadHandler.post {
            if (!isAttachedToEngine) return@post
            quickBlueFlutterApi?.onCharacteristicValueChanged(
                PlatformCharacteristicValueChanged(
                    deviceId = deviceId,
                    serviceUuid = serviceId,
                    characteristicId = characteristicId,
                    value = value,
                )
            ) {}
        }
    }

    override fun closeGattStreams(deviceId: String) {
        streamDelegates.remove(deviceId)?.close()
    }

    private fun disableUnclaimedNotifications(keys: List<NotificationKey>) {
        keys.forEach { key ->
            val gatt = AndroidGattBroker.sharedGatt(key.deviceId) ?: return@forEach
            val characteristic = try {
                gatt.getKnownCharacteristic(key.serviceId, key.characteristicId)
            } catch (_: FlutterError) {
                return@forEach
            }
            val descriptor = characteristic.getDescriptor(DESC__CLIENT_CHAR_CONFIGURATION)
                ?: return@forEach
            AndroidGattBroker.enqueue(
                GattOperation(
                    deviceId = key.deviceId,
                    kind = GattOperationKind.WRITE_DESCRIPTOR,
                    start = {
                        descriptor.value = BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                        it.setCharacteristicNotification(characteristic, false) &&
                            it.writeDescriptor(descriptor)
                    },
                    onComplete = { status, _ ->
                        if (status != BluetoothGatt.GATT_SUCCESS) {
                            Log.w(
                                "QuickBluePlugin",
                                "Failed to disable ${key.characteristicId} after engine detach: $status"
                            )
                        }
                    },
                )
            )
        }
    }

    private fun attachedGatt(deviceId: String): BluetoothGatt? =
        AndroidGattBroker.attachedGatt(this, deviceId)

    private val scanCallback = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) {
            scanResultListener.onScanError(errorCode)
        }

        override fun onScanResult(callbackType: Int, result: ScanResult) {
            activeScanRssi?.let {
                if (result.rssi < it) {
                    return
                }
            }
            scanResultListener.onScanResult(
                PlatformScanResult(
                    name = result.scanRecord?.deviceName ?: "",
                    deviceId = result.device.address,
                    manufacturerDataHead = result.manufacturerDataHead ?: byteArrayOf(),
                    manufacturerData = result.manufacturerData ?: byteArrayOf(),
                    rssi = result.rssi.toLong(),
                    serviceUuids = result.scanRecord?.serviceUuids?.map { it.uuid.toString() }
                        ?: emptyList(),
                    serviceData = result.serviceData,
                ))
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
        }
    }

    override fun isBluetoothAvailable(): Boolean {
        val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ (API 31+): BLUETOOTH_CONNECT required
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // API 26-30: BLUETOOTH and BLUETOOTH_ADMIN required
            val bluetoothPerm = ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH
            ) == PackageManager.PERMISSION_GRANTED
            val adminPerm = ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_ADMIN
            ) == PackageManager.PERMISSION_GRANTED
            bluetoothPerm && adminPerm
        }
        return hasPermission && bluetoothManager.adapter.isEnabled
    }

    override fun startScan(
        serviceUuids: List<String>?,
        serviceData: Map<String, ByteArray>?,
        manufacturerData: Map<Long, ByteArray>?,
        rssi: Long?,
        options: PlatformAndroidScanOptions?
    ) {
        ensureBluetoothScanPermission()
        activeScanRssi = rssi

        val manufacturerDataFilter = manufacturerData?.entries?.firstOrNull()
        val serviceUuidFilters: List<String?> =
            serviceUuids?.ifEmpty { null } ?: listOf(null)
        val serviceDataFilters: List<Map.Entry<String, ByteArray>?> =
            serviceData?.entries?.toList()?.ifEmpty { null } ?: listOf(null)
        val hasNativeFilters =
            serviceUuids?.isNotEmpty() == true ||
                serviceData?.isNotEmpty() == true ||
                manufacturerDataFilter != null
        val filters = if (hasNativeFilters) {
            serviceUuidFilters.flatMap { serviceUuid ->
                serviceDataFilters.map { serviceDataFilter ->
                    val builder = ScanFilter.Builder()
                    serviceUuid?.let {
                        builder.setServiceUuid(ParcelUuid(it.toBluetoothUuid()))
                    }
                    serviceDataFilter?.let {
                        builder.setServiceData(
                            ParcelUuid(it.key.toBluetoothUuid()),
                            it.value
                        )
                    }
                    if (manufacturerDataFilter != null) {
                        builder.setManufacturerData(
                            manufacturerDataFilter.key.toInt(),
                            manufacturerDataFilter.value
                        )
                    }
                    builder.build()
                }
            }
        } else {
            null
        }
        val scanOptions = options ?: PlatformAndroidScanOptions(
            scanMode = PlatformAndroidScanMode.LOW_LATENCY,
            callbackType = PlatformAndroidScanCallbackType.ALL_MATCHES,
            matchMode = PlatformAndroidScanMatchMode.STICKY,
            reportDelayMillis = 0L
        )
        val settingsBuilder = ScanSettings.Builder()
            .setCallbackType(scanOptions.callbackType.toAndroidScanCallbackType())
            .setMatchMode(scanOptions.matchMode.toAndroidScanMatchMode())
            .setScanMode(scanOptions.scanMode.toAndroidScanMode())
            .setReportDelay(scanOptions.reportDelayMillis)

        scanOptions.numOfMatches?.let {
            settingsBuilder.setNumOfMatches(it.toAndroidScanNumOfMatches())
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            scanOptions.legacy?.let { settingsBuilder.setLegacy(it) }
            scanOptions.phy?.let { settingsBuilder.setPhy(it.toAndroidScanPhy()) }
        }

        val settings = settingsBuilder.build()
        bluetoothManager.adapter.bluetoothLeScanner?.startScan(filters, settings, scanCallback)
    }

    override fun stopScan() {
        activeScanRssi = null
        bluetoothManager.adapter.bluetoothLeScanner?.stopScan(scanCallback)
    }

    override fun connectedDeviceIds(serviceUuids: List<String>): List<String> {
        val connectedDeviceIds = bluetoothManager
            .getConnectedDevices(BluetoothProfile.GATT)
            .map { it.address }
            .toSet()

        if (serviceUuids.isEmpty()) {
            return connectedDeviceIds.toList()
        }

        val targetServiceUuids = serviceUuids.map { it.toBluetoothUuid() }.toSet()
        return AndroidGattBroker.connectedGatts()
            .filter { connectedDeviceIds.contains(it.device.address) }
            .filter { gatt ->
                val serviceUuidsForGatt = gatt.services.map { it.uuid }.toSet()
                serviceUuidsForGatt.containsAll(targetServiceUuids)
            }
            .map { it.device.address }
            .distinct()
    }

    override fun connect(deviceId: String) {
        ensureBluetoothConnectPermission()

        executor.execute {
            AndroidGattBroker.connect(
                this,
                context,
                bluetoothManager.adapter.getRemoteDevice(deviceId),
            )
        }
    }

    override fun disconnect(deviceId: String) {
        disableUnclaimedNotifications(AndroidGattBroker.disconnect(this, deviceId))
    }

    override fun bondState(deviceId: String): PlatformBondState {
        ensureBluetoothConnectPermission()
        return remoteDevice(deviceId).bondState.toPlatformBondState()
    }

    override fun pair(deviceId: String, callback: (Result<Unit>) -> Unit) {
        val device = try {
            ensureBluetoothConnectPermission()
            remoteDevice(deviceId)
        } catch (error: FlutterError) {
            callback(Result.failure(error))
            return
        }

        when (device.bondState) {
            BluetoothDevice.BOND_BONDED -> {
                callback(Result.success(Unit))
                return
            }
            BluetoothDevice.BOND_BONDING -> {
                synchronized(bondLock) {
                    pendingPairCallbacks.getOrPut(device.address) { mutableListOf() }
                        .add(callback)
                }
                return
            }
        }

        synchronized(bondLock) {
            pendingPairCallbacks.getOrPut(device.address) { mutableListOf() }
                .add(callback)
        }

        val started = try {
            device.createBond()
        } catch (error: Throwable) {
            synchronized(bondLock) {
                pendingPairCallbacks[device.address]?.remove(callback)
                if (pendingPairCallbacks[device.address]?.isEmpty() == true) {
                    pendingPairCallbacks.remove(device.address)
                }
            }
            callback(
                Result.failure(
                    FlutterError(
                        "BondFailed",
                        error.message ?: "Failed to start pairing for $deviceId",
                        null
                    )
                )
            )
            return
        }

        if (!started) {
            synchronized(bondLock) {
                pendingPairCallbacks[device.address]?.remove(callback)
                if (pendingPairCallbacks[device.address]?.isEmpty() == true) {
                    pendingPairCallbacks.remove(device.address)
                }
            }
            callback(
                Result.failure(
                    FlutterError(
                        "BondFailed",
                        "Failed to start pairing for $deviceId",
                        null
                    )
                )
            )
        }
    }

    override fun isCompanionAssociationSupported(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(isCompanionAssociationSupported()))
    }

    override fun companionAssociate(
        request: PlatformCompanionAssociationRequest,
        callback: (Result<PlatformCompanionAssociation?>) -> Unit
    ) {
        if (!isCompanionAssociationSupported()) {
            callback(
                Result.failure(
                    FlutterError(
                        "UnsupportedAndroidVersion",
                        "Associating companion devices requires Android API 33 or higher",
                        null
                    )
                )
            )
            return
        }

        val pairingRequestBuilder = AssociationRequest.Builder()
            .setSingleDevice(request.singleDevice)
        val filters = request.filters.flatMap(::buildBleDeviceFilters)
        if (filters.isEmpty()) {
            pairingRequestBuilder.addDeviceFilter(BluetoothLeDeviceFilter.Builder().build())
        } else {
            filters.forEach { pairingRequestBuilder.addDeviceFilter(it) }
        }
        val pairingRequest = pairingRequestBuilder.build()

        var completed = false
        fun complete(result: Result<PlatformCompanionAssociation?>) {
            if (completed) return
            completed = true
            callback(result)
        }

        companionDeviceManager.associate(
            pairingRequest,
            executor,
            object : CompanionDeviceManager.Callback() {
                override fun onAssociationPending(intentSender: IntentSender) {
                    val currentActivity = activity
                    if (currentActivity == null) {
                        complete(
                            Result.failure(
                                FlutterError(
                                    "AssociationFailed",
                                    "Companion device association requires an attached Activity",
                                    null
                                )
                            )
                        )
                        return
                    }
                    startIntentSenderForResult(
                        currentActivity,
                        intentSender, SELECT_DEVICE_REQUEST_CODE, null, 0, 0, 0, null
                    )
                }

                override fun onAssociationCreated(associationInfo: AssociationInfo) {
                    complete(
                        Result.success(
                            PlatformCompanionAssociation(
                                id = associationInfo.id.toLong(),
                                deviceId = associationInfo.deviceMacAddress?.toString(),
                                displayName = associationInfo.displayName?.toString(),
                                deviceProfile = associationInfo.deviceProfile,
                            )
                        )
                    )
                }

                override fun onFailure(errorMessage: CharSequence?) {
                    complete(
                        Result.failure(
                            FlutterError(
                                "AssociationFailed",
                                errorMessage.toString(),
                                null
                            )
                        )
                    )
                }
            }
        )
    }

    override fun companionDisassociate(associationId: Long) {
        if (!isCompanionAssociationSupported()) {
            throw FlutterError(
                "UnsupportedAndroidVersion",
                "Associating companion devices requires Android API 33 or higher",
                null
            )
        }
        companionDeviceManager.disassociate(associationId.toInt())
    }

    override fun getCompanionAssociations(): List<PlatformCompanionAssociation> {
        if (!isCompanionAssociationSupported()) {
            throw FlutterError(
                "UnsupportedAndroidVersion",
                "Associating companion devices requires Android API 33 or higher",
                null
            )
        }

        return companionDeviceManager.myAssociations.map {
            PlatformCompanionAssociation(
                id = it.id.toLong(),
                deviceId = it.deviceMacAddress?.toString(),
                displayName = it.displayName?.toString(),
                deviceProfile = it.deviceProfile,
            )
        }
    }

    private fun isCompanionAssociationSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)
    }

    private fun buildBleDeviceFilters(
        filter: PlatformBleCompanionFilter
    ): List<BluetoothLeDeviceFilter> {
        val serviceUuids: List<String?> =
            if (filter.serviceUuids.isEmpty()) listOf(null) else filter.serviceUuids
        val manufacturerDataFilters =
            filter.manufacturerData?.entries?.map { it }
                ?.ifEmpty { listOf(null) }
                ?: listOf(null)

        return serviceUuids.flatMap { serviceUuid ->
            manufacturerDataFilters.map { manufacturerDataFilter ->
                val scanFilterBuilder = ScanFilter.Builder()
                filter.deviceId?.let { scanFilterBuilder.setDeviceAddress(it) }
                serviceUuid?.let {
                    scanFilterBuilder.setServiceUuid(ParcelUuid.fromString(it))
                }
                manufacturerDataFilter?.let {
                    scanFilterBuilder.setManufacturerData(it.key.toInt(), it.value)
                }

                val deviceFilterBuilder = BluetoothLeDeviceFilter.Builder()
                    .setScanFilter(scanFilterBuilder.build())
                filter.namePattern?.let {
                    deviceFilterBuilder.setNamePattern(Pattern.compile(it))
                }
                deviceFilterBuilder.build()
            }
        }
    }

    override fun discoverServices(deviceId: String) {
        if (attachedGatt(deviceId) == null) {
            throw FlutterError("IllegalArgument", "Unknown deviceId: $deviceId", null)
        }
        AndroidGattBroker.enqueue(
            GattOperation(
                deviceId = deviceId,
                kind = GattOperationKind.DISCOVER_SERVICES,
                client = this,
                start = { it.discoverServices() },
                onStartFailed = {
                    quickBlueFlutterApi?.onServiceDiscoveryComplete(deviceId) {}
                },
            )
        )
    }

    override fun setNotifiable(
        deviceId: String,
        service: String,
        characteristic: String,
        bleInputProperty: PlatformBleInputProperty,
        callback: (Result<Unit>) -> Unit
    ) {
        // @async: report guard failures through the callback rather than
        // throwing, since the generated dispatcher does not catch synchronous
        // throws for async methods (the reply would never be sent).
        val gatt = attachedGatt(deviceId)
        if (gatt == null) {
            callback(
                Result.failure(
                    FlutterError("IllegalArgument", "Unknown deviceId: $deviceId", null)
                )
            )
            return
        }
        val gattChar = try {
            gatt.getKnownCharacteristic(service, characteristic)
        } catch (error: FlutterError) {
            callback(
                Result.failure(error)
            )
            return
        }
        val descriptor = gattChar.getDescriptor(DESC__CLIENT_CHAR_CONFIGURATION)
        if (descriptor == null) {
            callback(
                Result.failure(
                    FlutterError(
                        "IllegalArgument",
                        "Missing client characteristic configuration descriptor for $characteristic",
                        null
                    )
                )
            )
            return
        }
        val (value, enable) = when (bleInputProperty) {
            PlatformBleInputProperty.NOTIFICATION -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE to true
            PlatformBleInputProperty.INDICATION -> BluetoothGattDescriptor.ENABLE_INDICATION_VALUE to true
            else -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE to false
        }
        val notificationKey = NotificationKey(
            deviceId,
            service.toBluetoothUuid().toString(),
            characteristic.toBluetoothUuid().toString(),
        )
        val transition = AndroidGattBroker.updateNotificationClaim(
            notificationKey,
            this,
            bleInputProperty,
            enable,
        )
        val conflictingClaim = transition.conflict
        if (conflictingClaim != null) {
            callback(
                Result.failure(
                    FlutterError(
                        "InvalidState",
                        "Another Flutter engine configured $characteristic for " +
                            "${conflictingClaim.name.lowercase()}",
                        null
                    )
                )
            )
            return
        }
        if (!transition.needsNativeWrite) {
            callback(Result.success(Unit))
            return
        }

        fun restoreClaimAfterFailure() {
            AndroidGattBroker.restoreNotificationClaim(
                notificationKey,
                this,
                transition.previous,
            )
        }
        AndroidGattBroker.enqueue(
            GattOperation(
                deviceId = deviceId,
                kind = GattOperationKind.WRITE_DESCRIPTOR,
                client = this,
                start = {
                    descriptor.value = value
                    it.setCharacteristicNotification(descriptor.characteristic, enable) &&
                        it.writeDescriptor(descriptor)
                },
                onComplete = { status, _ ->
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        callback(Result.success(Unit))
                    } else {
                        restoreClaimAfterFailure()
                        callback(
                            Result.failure(
                                gattError(
                                    "Descriptor write failed for $characteristic",
                                    status
                                )
                            )
                        )
                    }
                },
                onStartFailed = {
                    restoreClaimAfterFailure()
                    callback(
                        Result.failure(
                            FlutterError(
                                "DescriptorWriteFailed",
                                "Failed to initiate descriptor write for $characteristic",
                                null
                            )
                        )
                    )
                },
                onDisconnected = {
                    restoreClaimAfterFailure()
                    callback(
                        Result.failure(
                            FlutterError(
                                "Disconnected",
                                "Connection lost before the descriptor write was acknowledged",
                                null
                            )
                        )
                    )
                },
            )
        )
    }

    override fun readValue(
        deviceId: String,
        service: String,
        characteristic: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        // @async: every terminal GATT path must complete the callback so Dart
        // never waits indefinitely for a characteristic value event.
        val gatt = attachedGatt(deviceId)
        if (gatt == null) {
            callback(
                Result.failure(
                    FlutterError("IllegalArgument", "Unknown deviceId: $deviceId", null)
                )
            )
            return
        }
        val gattChar = try {
            gatt.getKnownCharacteristic(service, characteristic)
        } catch (error: FlutterError) {
            callback(Result.failure(error))
            return
        }
        AndroidGattBroker.enqueue(
            GattOperation(
                deviceId = deviceId,
                kind = GattOperationKind.READ_CHARACTERISTIC,
                client = this,
                start = { it.readCharacteristic(gattChar) },
                onComplete = { status, value ->
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        callback(Result.success(value ?: byteArrayOf()))
                    } else {
                        callback(
                            Result.failure(
                                gattError(
                                    "Characteristic read failed for $characteristic",
                                    status
                                )
                            )
                        )
                    }
                },
                onStartFailed = {
                    callback(
                        Result.failure(
                            FlutterError(
                                "ReadFailed",
                                "Failed to initiate read from $characteristic",
                                null
                            )
                        )
                    )
                },
                onDisconnected = {
                    callback(
                        Result.failure(
                            FlutterError(
                                "Disconnected",
                                "Connection lost before the read was acknowledged",
                                null
                            )
                        )
                    )
                },
            )
        )
    }

    override fun writeValue(
        deviceId: String,
        service: String,
        characteristic: String,
        value: ByteArray,
        bleOutputProperty: PlatformBleOutputProperty,
        callback: (Result<Unit>) -> Unit
    ) {
        // @async: report guard failures through the callback rather than
        // throwing, since the generated dispatcher does not catch synchronous
        // throws for async methods (the reply would never be sent).
        val gatt = attachedGatt(deviceId)
        if (gatt == null) {
            callback(
                Result.failure(
                    FlutterError("IllegalArgument", "Unknown deviceId: $deviceId", null)
                )
            )
            return
        }
        val gattChar = try {
            gatt.getKnownCharacteristic(service, characteristic)
        } catch (error: FlutterError) {
            callback(
                Result.failure(error)
            )
            return
        }

        val writeType =
            if (bleOutputProperty == PlatformBleOutputProperty.WITHOUT_RESPONSE)
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            else
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        AndroidGattBroker.enqueue(
            GattOperation(
                deviceId = deviceId,
                kind = GattOperationKind.WRITE_CHARACTERISTIC,
                client = this,
                start = {
                    gattChar.writeType = writeType
                    gattChar.value = value
                    it.writeCharacteristic(gattChar)
                },
                onComplete = { status, _ ->
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        callback(Result.success(Unit))
                    } else {
                        callback(
                            Result.failure(
                                gattError(
                                    "Characteristic write failed for $characteristic",
                                    status
                                )
                            )
                        )
                    }
                },
                onStartFailed = {
                    callback(
                        Result.failure(
                            FlutterError(
                                "WriteFailed",
                                "Failed to initiate write to $characteristic",
                                null
                            )
                        )
                    )
                },
                onDisconnected = {
                    callback(
                        Result.failure(
                            FlutterError(
                                "Disconnected",
                                "Connection lost before the write was acknowledged",
                                null
                            )
                        )
                    )
                },
            )
        )
    }

    override fun requestMtu(deviceId: String, expectedMtu: Long): Long {
        if (attachedGatt(deviceId) == null) {
            throw FlutterError("IllegalArgument", "Unknown deviceId: $deviceId", null)
        }
        AndroidGattBroker.enqueue(
            GattOperation(
                deviceId = deviceId,
                kind = GattOperationKind.REQUEST_MTU,
                client = this,
                start = { it.requestMtu(expectedMtu.toInt()) },
                onStartFailed = {
                    mtuChangedListener.onScanError(BluetoothGatt.GATT_FAILURE)
                },
            )
        )
        return 0
    }

    override fun openL2cap(deviceId: String, psm: Long, callback: (Result<Unit>) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw FlutterError(
                "UnsupportedAndroidVersion",
                "L2CAP requires Android API 29 or higher",
                null
            )
        }

        val gatt = attachedGatt(deviceId)
            ?: throw FlutterError("IllegalArgument", "Unknown deviceId: $deviceId", null)
        val socket = gatt.device.createInsecureL2capChannel(psm.toInt())
        val delegate = L2CapStreamDelegate(socket, openedCallback = {
            callback(Result.success(Unit))
        }, closedCallback = {
            mainThreadHandler.post {
                l2CapSocketEventsListener.onScanResult(
                    PlatformL2CapSocketEvent(
                        deviceId = gatt.device.address,
                        closed = true,
                    )
                )
            }
        }, streamCallback = {
            mainThreadHandler.post {
                l2CapSocketEventsListener.onScanResult(
                    PlatformL2CapSocketEvent(
                        deviceId = gatt.device.address,
                        data = it,
                    )
                )
            }
        }, errorCallback = {
            mainThreadHandler.post {
                l2CapSocketEventsListener.onScanResult(
                    PlatformL2CapSocketEvent(
                        deviceId = gatt.device.address,
                        error = it.message ?: "",
                    )
                )
            }
        })

        streamDelegates[gatt.device.address] = delegate
    }

    override fun closeL2cap(deviceId: String) {
        val delegate = streamDelegates[deviceId]
            ?: throw FlutterError(
                "IllegalArgument",
                "No stream delegate for deviceId: $deviceId",
                null
            )
        delegate.close()
        streamDelegates.remove(deviceId)
    }

    override fun writeL2cap(deviceId: String, value: ByteArray) {
        val delegate = streamDelegates[deviceId]
            ?: throw FlutterError(
                "IllegalArgument",
                "No stream delegate for deviceId: $deviceId",
                null
            )
        delegate.write(value)
    }

    private fun ensureBluetoothScanPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }
        if (ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        throw FlutterError(
            "MissingPermission",
            "Missing Android permission: BLUETOOTH_SCAN",
            null
        )
    }

    private fun ensureBluetoothConnectPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }
        if (ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        throw FlutterError(
            "MissingPermission",
            "Missing Android permission: BLUETOOTH_CONNECT",
            null
        )
    }

    private fun remoteDevice(deviceId: String): BluetoothDevice {
        return try {
            bluetoothManager.adapter.getRemoteDevice(deviceId)
        } catch (_: IllegalArgumentException) {
            throw FlutterError("IllegalArgument", "Invalid deviceId: $deviceId", null)
        }
    }
}

private val Intent.bluetoothDeviceExtra: BluetoothDevice?
    get() {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }
    }

private fun Int.toPlatformBondState(): PlatformBondState {
    return when (this) {
        BluetoothDevice.BOND_NONE -> PlatformBondState.NOT_BONDED
        BluetoothDevice.BOND_BONDING -> PlatformBondState.BONDING
        BluetoothDevice.BOND_BONDED -> PlatformBondState.BONDED
        else -> PlatformBondState.UNKNOWN
    }
}

class L2CapStreamDelegate(
    private val socket: BluetoothSocket,
    val openedCallback: () -> Unit,
    val closedCallback: () -> Unit,
    val streamCallback: (ByteArray) -> Unit,
    val errorCallback: (Exception) -> Unit
) {

    // A single scope to manage all coroutines for this connection.
    // SupervisorJob ensures that a failure in one child doesn't cancel the entire scope.
    // Dispatchers.IO is the appropriate thread pool for network I/O.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val writeDispatcher = newSingleThreadContext("L2CapWriteThread")

    private var readJob: Job? = null



    init {
        // Launch the main connection and reading logic.
        scope.launch {
            try {
                // 1. Connect the socket
                socket.connect() // This is a blocking call, so it's run within Dispatchers.IO

                // Switch to Main thread to safely call UI-related callbacks if needed
                withContext(Dispatchers.Main) {
                    openedCallback()
                }

                // 2. Start the read loop
                startReadLoop()

            } catch (e: Exception) {
                // Catch connection errors or any other exception during setup
                handleError(e)
            }
        }
    }

    private fun startReadLoop() {
        // Launch the read loop in a separate, dedicated coroutine job.
        readJob = scope.launch {
            try {
                val buffer = ByteArray(8192) // Allocate buffer once and reuse it
                while (isActive) { // Loop until the coroutine is cancelled
                    val bytesRead = socket.inputStream.read(buffer)
                    if (bytesRead == -1) {
                        // End of stream reached, connection is closed by the peer.
                        break
                    }
                    // This copy is still required by the original callback signature.
                    // For better performance, change the callback to accept the buffer and size.
                    val data = buffer.copyOfRange(0, bytesRead)
                    withContext(Dispatchers.Main) {
                        streamCallback(data)
                    }
                }
            } catch (e: IOException) {
                // This is expected when the socket is closed, either locally or remotely.
                // We don't need to report it as an error unless we want to.
                // Log.d("L2CapStream", "Socket closed: ${e.message}")
            } catch (e: Exception) {
                // Catch any other read errors
                handleError(e)
            } finally {
                // This block executes when the loop breaks or an error occurs.
                closeConnection()
            }
        }
    }

    fun write(data: ByteArray) {
        if (!scope.isActive) return

        scope.launch(writeDispatcher) {
            try {
                socket.outputStream.write(data)
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }

    fun close() {
        closeConnection()
    }

    private fun handleError(e: Exception) {
        // Ensure error callback is on the main thread
        scope.launch(Dispatchers.Main) {
            errorCallback(e)
        }
        closeConnection()
    }

    private fun closeConnection() {
        // Cancels all coroutines started in this scope (including the read loop).
        // It's idempotent; calling it multiple times has no effect.
        scope.cancel()
        writeDispatcher.close()

        try {
            socket.close()
        } catch (e: IOException) {
            // Can be ignored, as we are cleaning up anyway.
        }

        // Use a new coroutine on the Main dispatcher to ensure the callback
        // is not called from a cancelled scope.
        CoroutineScope(Dispatchers.Main).launch {
            closedCallback()
        }
    }
}

val ScanResult.manufacturerDataHead: ByteArray?
    get() {
        val sparseArray = scanRecord?.manufacturerSpecificData ?: return null
        if (sparseArray.size() == 0) return null

        return sparseArray.keyAt(0).toShort().toByteArray() + sparseArray.valueAt(0)
    }

val ScanResult.manufacturerData: ByteArray?
    get() {
        val sparseArray = scanRecord?.manufacturerSpecificData ?: return null
        if (sparseArray.size() == 0) return null

        return sparseArray.valueAt(0)
    }

val ScanResult.serviceData: Map<String, ByteArray>
    get() {
        return scanRecord?.serviceData?.mapKeys { it.key.uuid.toString() } ?: emptyMap()
    }

fun Short.toByteArray(byteOrder: ByteOrder = ByteOrder.LITTLE_ENDIAN): ByteArray =
    ByteBuffer.allocate(2 /*Short.SIZE_BYTES*/).order(byteOrder).putShort(this).array()

fun String.toBluetoothUuid(): UUID {
    val normalized = trim().removePrefix("{").removeSuffix("}").lowercase()
    return when (normalized.length) {
        4 -> UUID.fromString("0000$normalized-0000-1000-8000-00805f9b34fb")
        8 -> UUID.fromString("$normalized-0000-1000-8000-00805f9b34fb")
        else -> UUID.fromString(normalized)
    }
}

fun BluetoothGatt.getKnownCharacteristic(
    service: String,
    characteristic: String,
): BluetoothGattCharacteristic {
    val gattChar = try {
        getService(service.toBluetoothUuid())?.getCharacteristic(characteristic.toBluetoothUuid())
    } catch (error: IllegalArgumentException) {
        throw FlutterError(
            "IllegalArgument",
            "Invalid service or characteristic UUID: ${error.message}",
            null,
        )
    }
    return gattChar ?: throw FlutterError(
        "IllegalArgument",
        "Unknown characteristic: $characteristic",
        null,
    )
}

private val DESC__CLIENT_CHAR_CONFIGURATION =
    UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

class BluetoothStateListener(
    private val context: Context,
    private val bluetoothManager: BluetoothManager,
) : BluetoothStateStreamHandler() {
    private var eventSink: PigeonEventSink<PlatformBluetoothState>? = null
    private var receiverRegistered = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                emitCurrentState()
            }
        }
    }

    override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformBluetoothState>) {
        eventSink = sink
        emitCurrentState()
        registerReceiver()
    }

    override fun onCancel(p0: Any?) {
        unregisterReceiver()
        eventSink = null
    }

    fun onEventsDone() {
        unregisterReceiver()
        eventSink?.endOfStream()
        eventSink = null
    }

    private fun emitCurrentState() {
        eventSink?.success(currentState())
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        context.registerReceiver(
            receiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
        )
        receiverRegistered = true
    }

    private fun unregisterReceiver() {
        if (!receiverRegistered) return
        context.unregisterReceiver(receiver)
        receiverRegistered = false
    }

    private fun currentState(): PlatformBluetoothState {
        val adapter = bluetoothManager.adapter ?: return PlatformBluetoothState.UNAVAILABLE
        if (!hasBluetoothPermission()) {
            return PlatformBluetoothState.UNAUTHORIZED
        }
        return when (adapter.state) {
            BluetoothAdapter.STATE_ON -> PlatformBluetoothState.POWERED_ON
            BluetoothAdapter.STATE_OFF -> PlatformBluetoothState.POWERED_OFF
            BluetoothAdapter.STATE_TURNING_ON,
            BluetoothAdapter.STATE_TURNING_OFF -> PlatformBluetoothState.UNKNOWN
            else -> PlatformBluetoothState.UNKNOWN
        }
    }

    private fun hasBluetoothPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            val bluetoothPerm = ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH
            ) == PackageManager.PERMISSION_GRANTED
            val adminPerm = ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.BLUETOOTH_ADMIN
            ) == PackageManager.PERMISSION_GRANTED
            bluetoothPerm && adminPerm
        }
    }
}

internal fun BluetoothGattCharacteristic.toPlatformCharacteristic(): PlatformCharacteristic {
    val props = properties
    return PlatformCharacteristic(
        uuid = uuid.toString(),
        canRead = props and BluetoothGattCharacteristic.PROPERTY_READ != 0,
        canWriteWithResponse = props and BluetoothGattCharacteristic.PROPERTY_WRITE != 0,
        canWriteWithoutResponse = props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0,
        canNotify = props and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0,
        canIndicate = props and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0,
    )
}

private fun PlatformAndroidScanMode.toAndroidScanMode(): Int {
    return when (this) {
        PlatformAndroidScanMode.OPPORTUNISTIC -> ScanSettings.SCAN_MODE_OPPORTUNISTIC
        PlatformAndroidScanMode.LOW_POWER -> ScanSettings.SCAN_MODE_LOW_POWER
        PlatformAndroidScanMode.BALANCED -> ScanSettings.SCAN_MODE_BALANCED
        PlatformAndroidScanMode.LOW_LATENCY -> ScanSettings.SCAN_MODE_LOW_LATENCY
    }
}

private fun PlatformAndroidScanCallbackType.toAndroidScanCallbackType(): Int {
    return when (this) {
        PlatformAndroidScanCallbackType.ALL_MATCHES -> ScanSettings.CALLBACK_TYPE_ALL_MATCHES
        PlatformAndroidScanCallbackType.FIRST_MATCH -> ScanSettings.CALLBACK_TYPE_FIRST_MATCH
        PlatformAndroidScanCallbackType.MATCH_LOST -> ScanSettings.CALLBACK_TYPE_MATCH_LOST
        PlatformAndroidScanCallbackType.FIRST_MATCH_AND_MATCH_LOST ->
            ScanSettings.CALLBACK_TYPE_FIRST_MATCH or ScanSettings.CALLBACK_TYPE_MATCH_LOST
    }
}

private fun PlatformAndroidScanMatchMode.toAndroidScanMatchMode(): Int {
    return when (this) {
        PlatformAndroidScanMatchMode.AGGRESSIVE -> ScanSettings.MATCH_MODE_AGGRESSIVE
        PlatformAndroidScanMatchMode.STICKY -> ScanSettings.MATCH_MODE_STICKY
    }
}

private fun PlatformAndroidScanNumOfMatches.toAndroidScanNumOfMatches(): Int {
    return when (this) {
        PlatformAndroidScanNumOfMatches.ONE -> ScanSettings.MATCH_NUM_ONE_ADVERTISEMENT
        PlatformAndroidScanNumOfMatches.FEW -> ScanSettings.MATCH_NUM_FEW_ADVERTISEMENT
        PlatformAndroidScanNumOfMatches.MAX -> ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT
    }
}

private fun PlatformAndroidScanPhy.toAndroidScanPhy(): Int {
    return when (this) {
        PlatformAndroidScanPhy.LE1M -> BluetoothDevice.PHY_LE_1M
        PlatformAndroidScanPhy.LE_CODED -> BluetoothDevice.PHY_LE_CODED
        PlatformAndroidScanPhy.ALL_SUPPORTED -> ScanSettings.PHY_LE_ALL_SUPPORTED
    }
}

class ScanResultListener : ScanResultsStreamHandler() {
    private var eventSink: PigeonEventSink<PlatformScanResult>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformScanResult>) {
        eventSink = sink
    }

    fun onScanResult(result: PlatformScanResult) {
        eventSink?.success(result)
    }

    fun onScanError(errorCode: Int) {
        eventSink?.error("ScanError", "Error while scanning", errorCode)
    }

    fun onEventsDone() {
        eventSink?.endOfStream()
        eventSink = null
    }
}

class BondStateChangesListener : BondStateChangesStreamHandler() {
    private var eventSink: PigeonEventSink<PlatformBondStateChange>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformBondStateChange>) {
        eventSink = sink
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
    }

    fun onBondStateChanged(stateChange: PlatformBondStateChange) {
        eventSink?.success(stateChange)
    }

    fun onEventsDone() {
        eventSink?.endOfStream()
        eventSink = null
    }
}

class MtuChangedListener : MtuChangedStreamHandler() {
    private var eventSink: PigeonEventSink<PlatformMtuChange>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformMtuChange>) {
        eventSink = sink
    }

    fun onScanResult(result: PlatformMtuChange) {
        eventSink?.success(result)
    }

    fun onScanError(errorCode: Int) {
        eventSink?.error("ScanError", "", errorCode)
    }

    fun onEventsDone() {
        eventSink?.endOfStream()
        eventSink = null
    }
}

class L2CapSocketEventsListener : L2CapSocketEventsStreamHandler() {
    private var eventSink: PigeonEventSink<PlatformL2CapSocketEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformL2CapSocketEvent>) {
        eventSink = sink
    }

    fun onScanResult(result: PlatformL2CapSocketEvent) {
        eventSink?.success(result)
    }

    fun onScanError(errorCode: Int) {
        eventSink?.error("ScanError", "", errorCode)
    }

    fun onEventsDone() {
        eventSink?.endOfStream()
        eventSink = null
    }
}
