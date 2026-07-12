package com.example.quick_blue

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationClaimSetTest {
    @Test
    fun `one engine cannot release another engine's notification`() {
        val claims = NotificationClaimSet<String, String, String>()
        claims.claim("characteristic", "foreground", "notification")
        claims.claim("characteristic", "worker", "notification")

        val firstRelease = claims.release("characteristic", "foreground")
        assertFalse(firstRelease.isUnclaimed)
        assertEquals("notification", firstRelease.previous)

        val finalRelease = claims.release("characteristic", "worker")
        assertTrue(finalRelease.isUnclaimed)
    }

    @Test
    fun `conflicting indication claim leaves existing notification intact`() {
        val claims = NotificationClaimSet<String, String, String>()
        claims.claim("characteristic", "foreground", "notification")

        val conflict = claims.claim("characteristic", "worker", "indication")
        assertEquals("notification", conflict.conflict)
        assertNull(conflict.previous)
        assertTrue(claims.release("characteristic", "worker").isUnclaimed.not())
    }

    @Test
    fun `failed transition can restore the previous claim`() {
        val claims = NotificationClaimSet<String, String, String>()
        claims.claim("characteristic", "worker", "notification")
        val transition = claims.release("characteristic", "worker")
        claims.restore("characteristic", "worker", transition.previous)

        val restored = claims.release("characteristic", "worker")
        assertTrue(restored.isUnclaimed)
        assertEquals("notification", restored.previous)
        assertNull(claims.release("characteristic", "worker").previous)
    }

    @Test
    fun `removing an engine reports only newly unclaimed characteristics`() {
        val claims = NotificationClaimSet<String, String, String>()
        claims.claim("shared", "foreground", "notification")
        claims.claim("shared", "worker", "notification")
        claims.claim("worker-only", "worker", "notification")

        assertEquals(listOf("worker-only"), claims.removeClient("worker"))
    }
}
