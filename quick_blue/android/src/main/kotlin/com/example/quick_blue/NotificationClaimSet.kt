package com.example.quick_blue

internal data class NotificationClaimResult<Property>(
    val previous: Property?,
    val conflict: Property?,
)

internal data class NotificationReleaseResult<Property>(
    val previous: Property?,
    val isUnclaimed: Boolean,
)

/** Tracks per-engine notification configuration for shared characteristics. */
internal class NotificationClaimSet<Key : Any, Client : Any, Property : Any> {
    private val claims = mutableMapOf<Key, MutableMap<Client, Property>>()

    fun claim(key: Key, client: Client, property: Property): NotificationClaimResult<Property> {
        val clients = claims.getOrPut(key) { mutableMapOf() }
        val previous = clients[client]
        val conflict = clients.values.firstOrNull { it != property }
        if (conflict == null) {
            clients[client] = property
        }
        return NotificationClaimResult(previous, conflict)
    }

    fun release(key: Key, client: Client): NotificationReleaseResult<Property> {
        val clients = claims[key]
            ?: return NotificationReleaseResult(previous = null, isUnclaimed = true)
        val previous = clients.remove(client)
        if (clients.isNotEmpty()) {
            return NotificationReleaseResult(previous, isUnclaimed = false)
        }
        claims.remove(key)
        return NotificationReleaseResult(previous, isUnclaimed = true)
    }

    fun restore(key: Key, client: Client, property: Property?) {
        if (property == null) {
            release(key, client)
        } else {
            claims.getOrPut(key) { mutableMapOf() }[client] = property
        }
    }

    fun removeClient(client: Client, matches: (Key) -> Boolean = { true }): List<Key> {
        val unclaimed = mutableListOf<Key>()
        claims.keys.filter(matches).toList().forEach { key ->
            if (claims[key]?.containsKey(client) == true && release(key, client).isUnclaimed) {
                unclaimed.add(key)
            }
        }
        return unclaimed
    }

    fun removeMatching(matches: (Key) -> Boolean) {
        claims.keys.filter(matches).toList().forEach(claims::remove)
    }
}
