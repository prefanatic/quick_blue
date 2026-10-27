package com.example.quick_blue

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM state-machine characterization, not BluetoothGatt or hardware evidence.
 * All advancement is explicit; a missing callback is modeled by not calling complete.
 * complete returns an operation: delivery belongs to the broker, not the queue.
 * These assertions preserve current hazards, rather than claiming they are fixed.
 */
class GattQueueStallCharacterizationTest {
    private val read = GattOperationKind.READ_CHARACTERISTIC
    private val write = GattOperationKind.WRITE_CHARACTERISTIC

    private class Harness {
        var resource: Any? = Any()
        val starts = mutableListOf<String>()
        val events = mutableListOf<String>()
        val resources = mutableListOf<Any>()
        val queue = GattOperationQueue(resourceProvider = { resource }, dispatch = { it() })

        fun operation(
            name: String,
            kind: GattOperationKind,
            client: AndroidGattClient? = null,
            accepted: Boolean = true,
        ) = GattOperation<Any>(
            deviceId = "device",
            kind = kind,
            client = client,
            start = { resources.add(it); starts.add(name); accepted },
            onComplete = { _, _ -> events.add("$name:complete") },
            onStartFailed = { events.add("$name:refused") },
            onDisconnected = { events.add("$name:disconnected") },
        )
    }

    @Test
    fun `missing callback keeps accepted read and queued write pending`() {
        val h = Harness()
        h.queue.enqueue(h.operation("read", read))
        h.queue.enqueue(h.operation("write", write))
        assertEquals(listOf("read"), h.starts)
        assertTrue(h.events.isEmpty())
        // No timer or simulated elapsed time: teardown is the explicit external event.
        h.queue.failPending("device")
        assertEquals(listOf("read:disconnected", "write:disconnected"), h.events)
        assertEquals(listOf("read"), h.starts)
        assertNull(h.queue.complete("device", read))
        assertNull(h.queue.complete("device", write))
    }

    @Test
    fun `late matching completion returns operation once and admits next before delivery`() {
        val h = Harness()
        val first = h.operation("read", read)
        val second = h.operation("write", write)
        h.queue.enqueue(first)
        h.queue.enqueue(second)
        val completed = h.queue.complete("device", read)
        assertSame(first, completed)
        assertEquals(listOf("read", "write"), h.starts)
        assertTrue(h.events.isEmpty())
        completed!!.onComplete(0, null) // Explicit broker-like delivery, not queue behavior.
        assertNull(h.queue.complete("device", read))
        assertEquals(listOf("read:complete"), h.events)
        assertSame(second, h.queue.complete("device", write))
        assertNull(h.queue.complete("device", write))
    }

    @Test
    fun `three operations are admitted FIFO one completion at a time`() {
        val h = Harness()
        val a = h.operation("a", read)
        val b = h.operation("b", write)
        val c = h.operation("c", GattOperationKind.REQUEST_MTU)
        listOf(a, b, c).forEach(h.queue::enqueue)
        assertEquals(listOf("a"), h.starts)
        assertSame(a, h.queue.complete("device", a.kind))
        assertEquals(listOf("a", "b"), h.starts)
        assertSame(b, h.queue.complete("device", b.kind))
        assertEquals(listOf("a", "b", "c"), h.starts)
        assertSame(c, h.queue.complete("device", c.kind))
        assertTrue(h.events.isEmpty())
    }

    @Test
    fun `queued start refusal settles and advances without a native callback`() {
        val h = Harness()
        h.queue.enqueue(h.operation("active", read))
        h.queue.enqueue(h.operation("refused", write, accepted = false))
        val next = h.operation("next", read)
        h.queue.enqueue(next)
        h.queue.complete("device", read)
        assertEquals(listOf("active", "refused", "next"), h.starts)
        assertEquals(listOf("refused:refused"), h.events)
        assertNull(h.queue.complete("device", write))
        assertSame(next, h.queue.complete("device", read))
    }

    @Test
    fun `resource loss drains queued operations with recursive reverse delivery order`() {
        val h = Harness()
        h.queue.enqueue(h.operation("active", read))
        h.queue.enqueue(h.operation("b", write))
        h.queue.enqueue(h.operation("c", read))
        h.resource = null
        h.queue.complete("device", read)
        assertEquals(listOf("active"), h.starts)
        // complete calls startNext before dispatching the disconnected callback.
        assertEquals(listOf("c:disconnected", "b:disconnected"), h.events)
        assertNull(h.queue.complete("device", read))
        assertNull(h.queue.complete("device", write))
        h.queue.failPending("device")
        assertEquals(2, h.events.size)
    }

    @Test
    fun `detached queued client is silently dropped at admission but next starts`() {
        val h = Harness()
        val client = TestClient()
        h.queue.enqueue(h.operation("active", read))
        h.queue.enqueue(h.operation("detached", write, client))
        val next = h.operation("next", read)
        h.queue.enqueue(next)
        client.isGattClientAttached = false
        h.queue.complete("device", read)
        assertEquals(listOf("active", "next"), h.starts)
        assertTrue(h.events.isEmpty())
        assertNull(h.queue.complete("device", write))
        assertSame(next, h.queue.complete("device", read))
        h.queue.failPending("device")
        assertTrue(h.events.isEmpty())
    }

    @Test
    fun `teardown silently drops detached active and queued clients and clears state`() {
        val h = Harness()
        val client = TestClient()
        h.queue.enqueue(h.operation("active", read, client))
        h.queue.enqueue(h.operation("queued", write, client))
        client.isGattClientAttached = false
        h.queue.failPending("device")
        assertEquals(listOf("active"), h.starts)
        assertTrue(h.events.isEmpty())
        assertNull(h.queue.complete("device", read))
        assertNull(h.queue.complete("device", write))
        val replacement = h.operation("replacement", read)
        h.queue.enqueue(replacement)
        assertEquals(listOf("active", "replacement"), h.starts)
        assertSame(replacement, h.queue.complete("device", read))
    }

    @Test
    fun `null client fire and forget defaults permit refusal and teardown without delivery`() {
        val h = Harness()
        val refused = GattOperation<Any>("device", write, start = { h.starts.add("refused"); false })
        assertTrue(refused.canDeliver())
        h.queue.enqueue(refused)
        assertNull(h.queue.complete("device", write))
        val active = GattOperation<Any>("device", read, start = { h.starts.add("active"); true })
        h.queue.enqueue(active)
        h.queue.failPending("device")
        assertEquals(listOf("refused", "active"), h.starts)
        assertTrue(h.events.isEmpty())
        assertNull(h.queue.complete("device", read))
    }

    @Test
    fun `queue alone cannot distinguish retired callback from replacement same kind`() {
        val h = Harness()
        val oldResource = h.resource
        h.queue.enqueue(h.operation("old", read))
        h.queue.enqueue(h.operation("old-queued", write))
        h.queue.failPending("device")
        assertNull(h.queue.complete("device", read)) // Late callback before reconnect.
        h.resource = Any()
        val replacement = h.operation("replacement", read)
        h.queue.enqueue(replacement)
        assertSame(oldResource, h.resources[0])
        assertSame(h.resource, h.resources[1])
        assertEquals(listOf("old", "replacement"), h.starts)
        assertEquals(listOf("old:disconnected", "old-queued:disconnected"), h.events)
        // This deliberately bypasses the broker's isCurrentGatt gate. No identity
        // argument exists here; it is NOT evidence an old BluetoothGatt reaches it.
        assertSame(replacement, h.queue.complete("device", read))
        assertNull(h.queue.complete("device", read))
        assertEquals(listOf("old:disconnected", "old-queued:disconnected"), h.events)
    }

    private class TestClient : AndroidGattClient {
        override var isGattClientAttached = true

        override fun emitConnectionState(
            deviceId: String,
            state: PlatformConnectionState,
            status: PlatformGattStatus,
            nativeStatus: Int,
        ) = Unit

        override fun emitServices(deviceId: String, services: List<PlatformServiceDiscovered>) = Unit
        override fun emitGattServicesChanged(deviceId: String) = Unit
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
