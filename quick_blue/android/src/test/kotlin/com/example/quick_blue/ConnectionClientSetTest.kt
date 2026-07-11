package com.example.quick_blue

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConnectionClientSetTest {
    @Test
    fun `connections remain attached until the final engine detaches`() {
        val clients = ConnectionClientSet<String>()

        clients.attach("device-a", "foreground")
        clients.attach("device-a", "worker")

        assertEquals(2, clients.clientCount("device-a"))
        assertFalse(clients.detach("device-a", "foreground"))
        assertTrue(clients.contains("device-a", "worker"))
        assertTrue(clients.detach("device-a", "worker"))
        assertEquals(0, clients.clientCount("device-a"))
    }

    @Test
    fun `attaching the same engine twice is idempotent`() {
        val clients = ConnectionClientSet<String>()

        clients.attach("device-a", "foreground")
        clients.attach("device-a", "foreground")

        assertEquals(1, clients.clientCount("device-a"))
    }

    @Test
    fun `engine device membership is tracked independently`() {
        val clients = ConnectionClientSet<String>()
        clients.attach("device-a", "worker")
        clients.attach("device-b", "worker")
        clients.attach("device-b", "foreground")

        assertEquals(setOf("device-a", "device-b"), clients.deviceIdsFor("worker").toSet())
        assertEquals(listOf("worker", "foreground"), clients.removeAll("device-b"))
        assertEquals(0, clients.clientCount("device-b"))
    }
}
