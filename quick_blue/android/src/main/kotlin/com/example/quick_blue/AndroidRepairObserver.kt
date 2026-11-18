package com.example.quick_blue

/** Public broadcast names introduced in API 36/37, kept as wire constants so
 * consumers can still compile the plugin with SDK 35. No hidden APIs are used. */
internal object RepairBroadcast {
    const val PAIRING_REQUEST = "android.bluetooth.device.action.PAIRING_REQUEST"
    const val BOND_CHANGED = "android.bluetooth.device.action.BOND_STATE_CHANGED"
    const val KEY_MISSING = "android.bluetooth.device.action.KEY_MISSING"
    const val ENCRYPTION_CHANGE = "android.bluetooth.device.action.ENCRYPTION_CHANGE"
    const val PAIRING_CONTEXT = "android.bluetooth.device.extra.PAIRING_CONTEXT"
    const val ENCRYPTION_STATUS = "android.bluetooth.device.extra.ENCRYPTION_STATUS"
    const val ENCRYPTION_ENABLED = "android.bluetooth.device.extra.ENCRYPTION_ENABLED"
    const val TRANSPORT = "android.bluetooth.device.extra.TRANSPORT"
    const val REPAIRING = 2
    const val LE = 2
}

/** Passive, connection-scoped dispatch seam. Only explicit repair context starts
 * observation; neither retained BONDED nor BOND_NONE proves repair or key loss.
 * A terminal encryption event is accepted only for LE after that context.
 * Android broadcasts have no connection token: disconnect clears eligibility,
 * and a new connection needs new context before any terminal event can count.
 */
internal class AndroidRepairObserver {
    private var nextGeneration = 0L
    private val observations = mutableMapOf<String, PlatformRepairObservation>()
    private val connections = mutableMapOf<String, Long>()

    @Synchronized
    fun connect(deviceId: String) {
        if (deviceId !in observations) {
            observations[deviceId] = unknown(deviceId)
            connections[deviceId] = nextGeneration
        }
    }

    @Synchronized
    fun connectionToken(deviceId: String): Long? = connections[deviceId]

    @Synchronized
    fun snapshot(deviceId: String): PlatformRepairObservation =
        observations[deviceId] ?: PlatformRepairObservation(deviceId, 0, PlatformRepairState.UNKNOWN)

    @Synchronized
    fun disconnect(deviceId: String): PlatformRepairObservation {
        observations.remove(deviceId)
        connections.remove(deviceId)
        return unknown(deviceId)
    }

    @Synchronized
    fun disconnectIfCurrent(deviceId: String, token: Long?): PlatformRepairObservation? =
        if (token != null && connections[deviceId] == token) disconnect(deviceId) else null

    @Synchronized
    fun clear() {
        observations.clear()
        connections.clear()
    }

    fun bondPairOutcome(deviceId: String, state: PlatformBondState): PlatformRepairState =
        if (snapshot(deviceId).state == PlatformRepairState.IN_PROGRESS) PlatformRepairState.UNKNOWN
        else when (state) {
            PlatformBondState.BONDED -> PlatformRepairState.SUCCEEDED
            PlatformBondState.NOT_BONDED -> PlatformRepairState.FAILED
            else -> PlatformRepairState.UNKNOWN
        }

    private fun unknown(deviceId: String) =
        PlatformRepairObservation(deviceId, ++nextGeneration, PlatformRepairState.UNKNOWN)

    @Synchronized
    fun dispatch(
        sdk: Int,
        deviceId: String,
        action: String?,
        pairingContext: Int?,
        transport: Int?,
        encryptionStatus: Int?,
        encryptionEnabled: Boolean?,
        bondState: PlatformBondState? = null,
        previousBondState: PlatformBondState? = null,
    ): PlatformRepairObservation? {
        val current = observations[deviceId] ?: return null
        if (sdk < 37) return null
        val state = when {
            // Repair context also appears on terminal bond broadcasts. Only a
            // pairing request or an actual transition into BONDING starts an
            // attempt; late BONDED/NONE must retain terminal state/generation.
            (action == RepairBroadcast.PAIRING_REQUEST ||
                (action == RepairBroadcast.BOND_CHANGED && bondState == PlatformBondState.BONDING &&
                    (previousBondState == PlatformBondState.BONDED ||
                        previousBondState == PlatformBondState.NOT_BONDED))) &&
                pairingContext == RepairBroadcast.REPAIRING -> PlatformRepairState.IN_PROGRESS
            current.state != PlatformRepairState.IN_PROGRESS -> return null
            action == RepairBroadcast.KEY_MISSING -> PlatformRepairState.FAILED
            action == RepairBroadcast.ENCRYPTION_CHANGE && transport == RepairBroadcast.LE &&
                encryptionStatus == 0 && encryptionEnabled == true -> PlatformRepairState.SUCCEEDED
            else -> return null
        }
        if (state == current.state) return null
        val generation = if (state == PlatformRepairState.IN_PROGRESS) ++nextGeneration else current.generation
        return PlatformRepairObservation(deviceId, generation, state).also {
            observations[deviceId] = it
        }
    }
}
