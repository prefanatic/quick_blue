package com.example.quick_blue

import org.junit.Assert.*
import org.junit.Test

class AndroidRepairObserverTest {
    private val observer = AndroidRepairObserver().also { it.connect("a"); it.connect("b") }

    private fun event(
        action: String = RepairBroadcast.PAIRING_REQUEST,
        context: Int? = RepairBroadcast.REPAIRING,
        sdk: Int = 37,
        device: String = "a",
        transport: Int? = RepairBroadcast.LE,
        status: Int? = 0,
        enabled: Boolean? = true,
        bondState: PlatformBondState? = null,
        previousBondState: PlatformBondState? = null,
    ) = observer.dispatch(sdk, device, action, context, transport, status, enabled, bondState, previousBondState)

    @Test fun `older versions cannot establish repair even with context`() {
        for (sdk in listOf(26, 35, 36)) {
            assertNull(event(sdk = sdk))
            assertNull(event(action = RepairBroadcast.KEY_MISSING, sdk = sdk))
            assertEquals(PlatformRepairState.UNKNOWN, observer.snapshot("a").state)
        }
    }

    @Test fun `missing or ordinary context preserves fresh rejection`() {
        assertNull(event(context = null))
        assertNull(event(context = 0))
        assertNull(event(context = 1))
        assertEquals(PlatformRepairState.FAILED, observer.bondPairOutcome("a", PlatformBondState.NOT_BONDED))
        assertEquals(PlatformRepairState.SUCCEEDED, observer.bondPairOutcome("a", PlatformBondState.BONDED))
    }

    @Test fun `retained bond and intermediate NONE are not repair proof`() {
        assertEquals(PlatformRepairState.IN_PROGRESS, event()!!.state)
        assertEquals(PlatformRepairState.UNKNOWN, observer.bondPairOutcome("a", PlatformBondState.BONDED))
        assertEquals(PlatformRepairState.UNKNOWN, observer.bondPairOutcome("a", PlatformBondState.NOT_BONDED))
        assertNull(event(action = RepairBroadcast.BOND_CHANGED, context = null))
        assertEquals(PlatformRepairState.IN_PROGRESS, observer.snapshot("a").state)
    }

    @Test fun `contextual transition into bonding also starts repair`() {
        assertEquals(PlatformRepairState.IN_PROGRESS, event(
            action = RepairBroadcast.BOND_CHANGED,
            bondState = PlatformBondState.BONDING,
            previousBondState = PlatformBondState.BONDED,
        )!!.state)
        val generation = observer.snapshot("a").generation
        assertNull(event())
        assertEquals(generation, observer.snapshot("a").generation)
    }

    @Test fun `only successful enabled LE encryption after context proves success`() {
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE))
        val start = event()!!
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE, status = null))
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE, enabled = null))
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE, transport = null))
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE, transport = 1))
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE, status = 5))
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE, enabled = false))
        val success = event(action = RepairBroadcast.ENCRYPTION_CHANGE)!!
        assertEquals(PlatformRepairState.SUCCEEDED, success.state)
        assertEquals(start.generation, success.generation)
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE))
    }

    @Test fun `KEY_MISSING is terminal failure only after observed context`() {
        assertNull(event(action = RepairBroadcast.KEY_MISSING))
        event()
        assertEquals(PlatformRepairState.FAILED, event(action = RepairBroadcast.KEY_MISSING)!!.state)
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE))
    }

    @Test fun `devices do not contaminate each other`() {
        event()
        assertNull(event(device = "b", action = RepairBroadcast.ENCRYPTION_CHANGE))
        assertEquals(PlatformRepairState.UNKNOWN, observer.snapshot("b").state)
        assertEquals(PlatformRepairState.IN_PROGRESS, observer.snapshot("a").state)
    }

    @Test fun `disconnect invalidates late terminal events and reconnect generation`() {
        val old = event()!!
        assertTrue(observer.disconnect("a").generation > old.generation)
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE))
        assertNull(event())
        observer.connect("a")
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE))
        val fresh = event()!!
        assertTrue(fresh.generation > old.generation)
    }

    @Test fun `detach clears eligibility and terminal state`() {
        event()
        observer.clear()
        assertEquals(PlatformRepairState.UNKNOWN, observer.snapshot("a").state)
        assertNull(event(action = RepairBroadcast.KEY_MISSING))
        assertNull(event())
        observer.connect("a")
        assertNull(event(action = RepairBroadcast.ENCRYPTION_CHANGE))
    }

    @Test fun `queued old disconnect cannot erase a reconnected repair`() {
        val oldToken = observer.connectionToken("a")
        observer.disconnect("a")
        observer.connect("a")
        event()
        assertNull(observer.disconnectIfCurrent("a", oldToken))
        assertEquals(PlatformRepairState.IN_PROGRESS, observer.snapshot("a").state)
        assertNotNull(observer.disconnectIfCurrent("a", observer.connectionToken("a")))
        assertEquals(PlatformRepairState.UNKNOWN, observer.snapshot("a").state)
    }

    @Test fun `new repair after terminal uses new generation`() {
        val old = event()!!
        event(action = RepairBroadcast.KEY_MISSING)
        assertTrue(event()!!.generation > old.generation)
    }

    @Test fun `successful encryption then contextual bonded cannot reopen repair`() {
        event()
        val terminal = event(action = RepairBroadcast.ENCRYPTION_CHANGE)!!
        assertNull(event(action = RepairBroadcast.BOND_CHANGED,
            bondState = PlatformBondState.BONDED, previousBondState = PlatformBondState.BONDING))
        assertEquals(terminal, observer.snapshot("a"))
        // The pair dispatch is no longer suppressed by a phantom active repair.
        assertEquals(PlatformRepairState.SUCCEEDED, observer.bondPairOutcome("a", PlatformBondState.BONDED))
    }

    @Test fun `key missing then contextual none preserves failure and fresh pairing eligibility`() {
        event()
        val terminal = event(action = RepairBroadcast.KEY_MISSING)!!
        assertNull(event(action = RepairBroadcast.BOND_CHANGED,
            bondState = PlatformBondState.NOT_BONDED, previousBondState = PlatformBondState.BONDING))
        assertEquals(terminal, observer.snapshot("a"))
        assertEquals(PlatformRepairState.FAILED, observer.bondPairOutcome("a", PlatformBondState.NOT_BONDED))
        val fresh = event(action = RepairBroadcast.BOND_CHANGED,
            bondState = PlatformBondState.BONDING, previousBondState = PlatformBondState.NOT_BONDED)!!
        assertEquals(PlatformRepairState.IN_PROGRESS, fresh.state)
        assertTrue(fresh.generation > terminal.generation)
    }

    @Test fun `terminal or incomplete bond context cannot establish repair`() {
        for (state in listOf(null, PlatformBondState.BONDED, PlatformBondState.NOT_BONDED)) {
            assertNull(event(action = RepairBroadcast.BOND_CHANGED, bondState = state,
                previousBondState = PlatformBondState.BONDING))
        }
        assertNull(event(action = RepairBroadcast.BOND_CHANGED, bondState = PlatformBondState.BONDING))
        assertNull(event(action = RepairBroadcast.BOND_CHANGED, bondState = PlatformBondState.BONDING,
            previousBondState = PlatformBondState.UNKNOWN))
        assertNull(event(action = RepairBroadcast.BOND_CHANGED, bondState = PlatformBondState.BONDING,
            previousBondState = PlatformBondState.BONDING))
        assertNull(event(action = RepairBroadcast.BOND_CHANGED, context = null,
            bondState = PlatformBondState.BONDING, previousBondState = PlatformBondState.NOT_BONDED))
        assertEquals(PlatformRepairState.UNKNOWN, observer.snapshot("a").state)
    }
}
