package com.example.quick_blue

import org.junit.Assert.*
import org.junit.Test

/** Real generated registry; synthetic keys do not certify Flutter/JNI engine plumbing. */
class NativeAvailabilityTest {
    @Test fun pluginImplementsTheNativeAvailabilityBoundary() {
        assertTrue(QuickBlueAvailabilityApi::class.java.isAssignableFrom(QuickBluePlugin::class.java))
    }

    private class Host(private val available: Boolean) : QuickBlueAvailabilityApi {
        override fun isBluetoothAvailable() = available
    }

    private fun change(method: String, host: Host, key: Long, name: String) {
        val methodHandle = QuickBlueAvailabilityApiRegistrar::class.java.getDeclaredMethod(
            method, QuickBlueAvailabilityApi::class.java, java.lang.Long.TYPE, String::class.java)
        methodHandle.isAccessible = true
        methodHandle.invoke(QuickBlueAvailabilityApiRegistrar(), host, key, name)
    }

    @Test fun engineSpecificNameNeverBorrowsPeerAfterDetach() {
        val first = Host(true)
        val second = Host(false)
        val firstName = "quick_blue.availability.101"
        val secondName = "quick_blue.availability.202"
        change("registerWithKey", first, 101, firstName)
        change("registerWithKey", second, 202, secondName)
        val held = QuickBlueAvailabilityApiRegistrar.pigeonResolveInstance(101, Long.MIN_VALUE, firstName)!!
        try {
            assertTrue(held.isBluetoothAvailable())
            assertFalse(QuickBlueAvailabilityApiRegistrar.pigeonResolveInstance(202, Long.MIN_VALUE, secondName)!!.isBluetoothAvailable())
            change("unregisterWithKey", first, 101, firstName)
            assertNull(QuickBlueAvailabilityApiRegistrar.pigeonResolveInstance(101, 202, firstName))
            try {
                held.isBluetoothAvailable()
                fail("detached handle must not call its former host")
            } catch (error: AvailabilityError) {
                assertEquals("unregistered-instance", error.code)
            }
            assertFalse(QuickBlueAvailabilityApiRegistrar.pigeonResolveInstance(202, Long.MIN_VALUE, secondName)!!.isBluetoothAvailable())
        } finally {
            change("unregisterWithKey", first, 101, firstName)
            change("unregisterWithKey", second, 202, secondName)
        }
    }
}
