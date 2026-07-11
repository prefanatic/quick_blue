package com.example.quick_blue

/** Tracks the Flutter-engine clients attached to each shared native connection. */
internal class ConnectionClientSet<Client : Any> {
    private val clientsByDevice = mutableMapOf<String, MutableSet<Client>>()

    fun attach(deviceId: String, client: Client) {
        clientsByDevice.getOrPut(deviceId) { mutableSetOf() }.add(client)
    }

    fun contains(deviceId: String, client: Client): Boolean =
        clientsByDevice[deviceId]?.contains(client) == true

    fun clients(deviceId: String): List<Client> =
        clientsByDevice[deviceId]?.toList() ?: emptyList()

    fun clientCount(deviceId: String): Int = clientsByDevice[deviceId]?.size ?: 0

    /** Removes [client], returning true when no clients remain for [deviceId]. */
    fun detach(deviceId: String, client: Client): Boolean {
        val clients = clientsByDevice[deviceId] ?: return true
        clients.remove(client)
        if (clients.isNotEmpty()) return false
        clientsByDevice.remove(deviceId)
        return true
    }

    fun deviceIdsFor(client: Client): List<String> =
        clientsByDevice.entries
            .filter { client in it.value }
            .map { it.key }

    fun removeAll(deviceId: String): List<Client> =
        clientsByDevice.remove(deviceId)?.toList() ?: emptyList()
}
