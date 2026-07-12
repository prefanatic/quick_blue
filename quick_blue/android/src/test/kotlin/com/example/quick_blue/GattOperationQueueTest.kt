package com.example.quick_blue

import PlatformConnectionState
import PlatformGattStatus
import PlatformServiceDiscovered
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class GattOperationQueueTest {
    @Test
    fun `operations are serialized per device`() {
        val starts = mutableListOf<String>()
        val queue = GattOperationQueue(
            resourceProvider = { Unit },
            dispatch = { it() },
        )
        queue.enqueue(operation("device-a", GattOperationKind.READ_CHARACTERISTIC, "read", starts))
        queue.enqueue(operation("device-a", GattOperationKind.WRITE_CHARACTERISTIC, "write", starts))

        assertEquals(listOf("read"), starts)
        queue.complete("device-a", GattOperationKind.READ_CHARACTERISTIC)
        assertEquals(listOf("read", "write"), starts)
    }

    @Test
    fun `different devices can start concurrently`() {
        val starts = mutableListOf<String>()
        val queue = GattOperationQueue(
            resourceProvider = { Unit },
            dispatch = { it() },
        )

        queue.enqueue(operation("device-a", GattOperationKind.READ_CHARACTERISTIC, "a", starts))
        queue.enqueue(operation("device-b", GattOperationKind.READ_CHARACTERISTIC, "b", starts))

        assertEquals(listOf("a", "b"), starts)
    }

    @Test
    fun `mismatched callback does not advance the queue`() {
        val starts = mutableListOf<String>()
        val queue = GattOperationQueue(
            resourceProvider = { Unit },
            dispatch = { it() },
        )
        queue.enqueue(operation("device-a", GattOperationKind.READ_CHARACTERISTIC, "read", starts))
        queue.enqueue(operation("device-a", GattOperationKind.WRITE_CHARACTERISTIC, "write", starts))

        assertNull(queue.complete("device-a", GattOperationKind.WRITE_CHARACTERISTIC))
        assertEquals(listOf("read"), starts)
    }

    @Test
    fun `completion identifies the client that initiated the operation`() {
        val firstClient = TestGattClient()
        val secondClient = TestGattClient()
        val queue = GattOperationQueue<Unit>(
            resourceProvider = { Unit },
            dispatch = { it() },
        )
        queue.enqueue(
            GattOperation(
                deviceId = "device-a",
                kind = GattOperationKind.DISCOVER_SERVICES,
                client = firstClient,
                start = { true },
            )
        )
        queue.enqueue(
            GattOperation(
                deviceId = "device-a",
                kind = GattOperationKind.DISCOVER_SERVICES,
                client = secondClient,
                start = { true },
            )
        )

        assertSame(
            firstClient,
            queue.complete("device-a", GattOperationKind.DISCOVER_SERVICES)?.client,
        )
        assertSame(
            secondClient,
            queue.complete("device-a", GattOperationKind.DISCOVER_SERVICES)?.client,
        )
    }

    @Test
    fun `disconnect fails active and queued operations`() {
        val disconnected = mutableListOf<String>()
        val queue = GattOperationQueue<Unit>(
            resourceProvider = { Unit },
            dispatch = { it() },
        )
        queue.enqueue(
            GattOperation(
                deviceId = "device-a",
                kind = GattOperationKind.READ_CHARACTERISTIC,
                start = { true },
                onDisconnected = { disconnected.add("read") },
            )
        )
        queue.enqueue(
            GattOperation(
                deviceId = "device-a",
                kind = GattOperationKind.WRITE_CHARACTERISTIC,
                start = { true },
                onDisconnected = { disconnected.add("write") },
            )
        )

        queue.failPending("device-a")
        assertEquals(listOf("read", "write"), disconnected)
    }

    private fun operation(
        deviceId: String,
        kind: GattOperationKind,
        name: String,
        starts: MutableList<String>,
    ): GattOperation<Unit> = GattOperation(
        deviceId = deviceId,
        kind = kind,
        start = {
            starts.add(name)
            true
        },
    )

    private class TestGattClient : AndroidGattClient {
        override val isGattClientAttached = true

        override fun emitConnectionState(
            deviceId: String,
            state: PlatformConnectionState,
            status: PlatformGattStatus,
        ) = Unit

        override fun emitServices(
            deviceId: String,
            services: List<PlatformServiceDiscovered>,
        ) = Unit

        override fun emitMtuChanged(deviceId: String, mtu: Int, status: Int) = Unit

        override fun emitCharacteristicValue(
            deviceId: String,
            serviceId: String,
            characteristicId: String,
            value: ByteArray,
        ) = Unit

        override fun closeGattStreams(deviceId: String) = Unit
    }
}
