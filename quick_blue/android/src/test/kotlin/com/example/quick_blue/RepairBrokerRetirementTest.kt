package com.example.quick_blue

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.content.Context
import android.os.Handler
import org.junit.Assert.*
import org.junit.Test
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyBoolean
import org.mockito.Mockito.*

/** Real broker/plugin/observer wiring with only Android IO mocked. No radio proof. */
class RepairBrokerRetirementTest {
    @Test fun `held retiring close cannot invalidate replacement repair`() {
        val deviceId = "retirement-test"
        val device = mock(BluetoothDevice::class.java)
        val context = mock(Context::class.java)
        val oldGatt = mock(BluetoothGatt::class.java)
        val newGatt = mock(BluetoothGatt::class.java)
        val observer = AndroidRepairObserver()
        val plugin = plugin(deviceId, observer)
        `when`(device.address).thenReturn(deviceId)
        `when`(oldGatt.device).thenReturn(device)
        `when`(newGatt.device).thenReturn(device)
        var callback: BluetoothGattCallback? = null
        `when`(device.connectGatt(any(Context::class.java), anyBoolean(),
            any(BluetoothGattCallback::class.java), anyInt())).thenAnswer {
            callback = it.getArgument(2)
            oldGatt
        }.thenReturn(newGatt)
        // Match the original facade's pre-connect observation, too.
        observer.connect(deviceId)
        AndroidGattBroker.connect(plugin, context, device)
        val retiringToken = observer.connectionToken(deviceId)
        var reachedClose = false
        doAnswer {
            reachedClose = true
            // The old registry entry has gone; this is the actual broker gap.
            // New connect must establish fresh observation even with delivery held.
            AndroidGattBroker.connect(plugin, context, device)
            observer.dispatch(37, deviceId, RepairBroadcast.PAIRING_REQUEST,
                RepairBroadcast.REPAIRING, RepairBroadcast.LE, 0, true)
            null
        }.`when`(oldGatt).close()
        try {
            callback!!.onConnectionStateChange(oldGatt, BluetoothGatt.GATT_SUCCESS,
                BluetoothGatt.STATE_DISCONNECTED)
            assertTrue(reachedClose)
            assertNotEquals(retiringToken, observer.connectionToken(deviceId))
            assertEquals(PlatformRepairState.IN_PROGRESS, observer.snapshot(deviceId).state)
            // A duplicate retired callback must also leave the new observation live.
            callback!!.onConnectionStateChange(oldGatt, BluetoothGatt.GATT_SUCCESS,
                BluetoothGatt.STATE_DISCONNECTED)
            assertEquals(PlatformRepairState.IN_PROGRESS, observer.snapshot(deviceId).state)
            // Current disconnection still clears eligibility before queued delivery.
            callback!!.onConnectionStateChange(newGatt, BluetoothGatt.GATT_SUCCESS,
                BluetoothGatt.STATE_DISCONNECTED)
            assertNull(observer.connectionToken(deviceId))
        } finally {
            AndroidGattBroker.detach(plugin)
        }
    }

    @Test fun `failed connect has no observation and shared detach preserves peer repair`() {
        val deviceId = "retirement-peer-test"
        val device = mock(BluetoothDevice::class.java)
        val context = mock(Context::class.java)
        val gatt = mock(BluetoothGatt::class.java)
        val first = AndroidRepairObserver()
        val peer = AndroidRepairObserver()
        val client = plugin(deviceId, first)
        val peerClient = plugin(deviceId, peer)
        `when`(device.address).thenReturn(deviceId)
        `when`(gatt.device).thenReturn(device)
        `when`(device.connectGatt(any(Context::class.java), anyBoolean(),
            any(BluetoothGattCallback::class.java), anyInt()))
            .thenThrow(IllegalStateException("connect refused")).thenReturn(gatt)
        try {
            try {
                AndroidGattBroker.connect(client, context, device)
                fail("failed native connect must throw")
            } catch (expected: IllegalStateException) {
                assertEquals("connect refused", expected.message)
            }
            assertNull(first.connectionToken(deviceId))
            AndroidGattBroker.connect(client, context, device)
            assertNotNull(first.connectionToken(deviceId))
            AndroidGattBroker.connect(peerClient, context, device)
            val token = peer.connectionToken(deviceId)
            assertNotNull(token)
            peer.dispatch(37, deviceId, RepairBroadcast.PAIRING_REQUEST,
                RepairBroadcast.REPAIRING, RepairBroadcast.LE, 0, true)
            AndroidGattBroker.connect(peerClient, context, device)
            assertEquals(token, peer.connectionToken(deviceId))
            AndroidGattBroker.disconnect(client, deviceId)
            assertNull(first.connectionToken(deviceId))
            assertEquals(PlatformRepairState.IN_PROGRESS, peer.snapshot(deviceId).state)
            verify(gatt, never()).disconnect()
            verify(gatt, never()).close()
            AndroidGattBroker.detach(peerClient)
            assertNull(peer.connectionToken(deviceId))
            verify(gatt).disconnect()
            verify(gatt).close()
        } finally {
            AndroidGattBroker.detach(client)
            AndroidGattBroker.detach(peerClient)
        }
    }

    private fun plugin(deviceId: String, observer: AndroidRepairObserver): QuickBluePlugin {
        // No Flutter engine is constructed. Run real plugin methods while mocking
        // only Android IO and stream closure unrelated to repair observation.
        val plugin = mock(QuickBluePlugin::class.java, CALLS_REAL_METHODS)
        fun field(name: String, value: Any) {
            QuickBluePlugin::class.java.getDeclaredField(name).apply {
                isAccessible = true
                set(plugin, value)
            }
        }
        field("repairObserver", observer)
        field("isAttachedToEngine", true)
        // Hold all main-thread delivery; invalidation cannot depend on draining it.
        field("mainThreadHandler", mock(Handler::class.java))
        doNothing().`when`(plugin).closeGattStreams(deviceId)
        return plugin
    }
}
