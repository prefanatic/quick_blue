package com.example.quick_blue

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingDisconnectReconcilerTest {
    @Test
    fun `missing callback expires the pending disconnect once`() {
        val scheduled = mutableListOf<() -> Unit>()
        val expired = mutableListOf<Any>()
        val reconciler = PendingDisconnectReconciler<Any>(
            timeoutMilliseconds = 2_000,
            schedule = { _, action -> scheduled.add(action) },
        )
        val gatt = Any()

        reconciler.start("device-a", gatt, expired::add)
        scheduled.single().invoke()
        scheduled.single().invoke()

        assertEquals(1, expired.size)
        assertSame(gatt, expired.single())
        assertFalse(reconciler.finish("device-a", gatt))
    }

    @Test
    fun `terminal callback cancels missing-callback reconciliation`() {
        val scheduled = mutableListOf<() -> Unit>()
        var expirationCount = 0
        val reconciler = PendingDisconnectReconciler<Any>(
            timeoutMilliseconds = 2_000,
            schedule = { _, action -> scheduled.add(action) },
        )
        val gatt = Any()

        reconciler.start("device-a", gatt) { expirationCount += 1 }

        assertTrue(reconciler.finish("device-a", gatt))
        scheduled.single().invoke()
        assertEquals(0, expirationCount)
    }

    @Test
    fun `late callback cannot finish a replacement disconnect`() {
        val scheduled = mutableListOf<() -> Unit>()
        val reconciler = PendingDisconnectReconciler<Any>(
            timeoutMilliseconds = 2_000,
            schedule = { _, action -> scheduled.add(action) },
        )
        val retiredGatt = Any()
        val replacementGatt = Any()

        reconciler.start("device-a", retiredGatt) {}
        reconciler.start("device-a", replacementGatt) {}

        scheduled.first().invoke()
        assertFalse(reconciler.finish("device-a", retiredGatt))
        assertTrue(reconciler.finish("device-a", replacementGatt))
    }
}

class IdentityResourceRegistryTest {
    @Test
    fun `late callback after reconciliation cannot duplicate terminal event`() {
        val registry = IdentityResourceRegistry<Any>()
        val gatt = Any()
        var terminalEventCount = 0
        registry["device-a"] = gatt

        if (registry.removeIfCurrent("device-a", gatt)) {
            terminalEventCount += 1
        }
        if (registry.removeIfCurrent("device-a", gatt)) {
            terminalEventCount += 1
        }

        assertEquals(1, terminalEventCount)
    }

    @Test
    fun `late callback cannot remove a successful replacement connection`() {
        val registry = IdentityResourceRegistry<Any>()
        val retiredGatt = Any()
        val replacementGatt = Any()
        registry["device-a"] = retiredGatt
        assertTrue(registry.removeIfCurrent("device-a", retiredGatt))

        registry["device-a"] = replacementGatt

        assertFalse(registry.removeIfCurrent("device-a", retiredGatt))
        assertSame(replacementGatt, registry["device-a"])
    }
}
