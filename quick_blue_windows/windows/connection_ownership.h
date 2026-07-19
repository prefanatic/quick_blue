#ifndef QUICK_BLUE_WINDOWS_CONNECTION_OWNERSHIP_H_
#define QUICK_BLUE_WINDOWS_CONNECTION_OWNERSHIP_H_

#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <utility>
#include <vector>

namespace quick_blue_windows::internal {

// Thread-safe ownership for connections shared by multiple plugin clients.
template <typename DeviceId,
          typename Client,
          typename NotificationKey,
          typename NotificationProperty>
class ConnectionOwnership {
 public:
  struct Attachment {
    Client host;
    bool is_new;
  };

  struct DetachPlan {
    Client previous_host;
    Client new_host{};
    Client notification_host{};
    bool final_client;
    std::vector<NotificationKey> notifications_to_disable;
  };

  enum class NotificationClaimStatus {
    kAccepted,
    kConflicting,
    kNotAttached,
  };

  struct NotificationClaimUpdate {
    NotificationClaimStatus status;
    Client host{};
    bool needs_native_write = false;
  };

  Attachment Attach(const DeviceId& device_id, Client client) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto connection = connections_.find(device_id);
    if (connection == connections_.end()) {
      connections_.emplace(
          device_id,
          SharedConnection{client, std::set<Client>{client}, {}});
      return {client, true};
    }
    connection->second.clients.insert(client);
    return {connection->second.host, false};
  }

  bool Owns(const DeviceId& device_id, Client client) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto connection = connections_.find(device_id);
    return connection != connections_.end() &&
           connection->second.clients.count(client) != 0;
  }

  bool IsHost(const DeviceId& device_id, Client client) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto connection = connections_.find(device_id);
    return connection != connections_.end() &&
           connection->second.host == client;
  }

  bool Release(const DeviceId& device_id, Client host) {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto connection = connections_.find(device_id);
    if (connection == connections_.end() ||
        connection->second.host != host) {
      return false;
    }
    connections_.erase(connection);
    return true;
  }

  std::optional<DetachPlan> Detach(const DeviceId& device_id, Client client) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto connection = connections_.find(device_id);
    if (connection == connections_.end() ||
        connection->second.clients.erase(client) == 0) {
      return std::nullopt;
    }

    std::vector<NotificationKey> notifications_to_disable;
    for (auto claim = connection->second.notification_claims.begin();
         claim != connection->second.notification_claims.end();) {
      claim->second.erase(client);
      if (claim->second.empty()) {
        notifications_to_disable.push_back(claim->first);
        claim = connection->second.notification_claims.erase(claim);
      } else {
        ++claim;
      }
    }

    const auto previous_host = connection->second.host;
    Client new_host{};
    Client notification_host{};
    const bool final_client = connection->second.clients.empty();
    if (final_client) {
      connections_.erase(connection);
    } else {
      if (connection->second.host == client) {
        new_host = *connection->second.clients.begin();
        connection->second.host = new_host;
      }
      notification_host = connection->second.host;
    }
    return DetachPlan{previous_host, new_host, notification_host, final_client,
                      std::move(notifications_to_disable)};
  }

  std::vector<DeviceId> DeviceIdsFor(Client client) const {
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<DeviceId> device_ids;
    for (const auto& connection : connections_) {
      if (connection.second.clients.count(client) != 0) {
        device_ids.push_back(connection.first);
      }
    }
    return device_ids;
  }

  std::vector<Client> ClientsFor(const DeviceId& device_id) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto connection = connections_.find(device_id);
    if (connection == connections_.end()) {
      return {};
    }
    return {connection->second.clients.begin(),
            connection->second.clients.end()};
  }

  NotificationClaimUpdate UpdateNotificationClaim(
      const DeviceId& device_id,
      const NotificationKey& key,
      Client client,
      NotificationProperty property,
      NotificationProperty disabled_property) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto connection = connections_.find(device_id);
    if (connection == connections_.end() ||
        connection->second.clients.count(client) == 0) {
      return {NotificationClaimStatus::kNotAttached};
    }

    const auto host = connection->second.host;
    auto claims = connection->second.notification_claims.find(key);
    if (property == disabled_property) {
      if (claims == connection->second.notification_claims.end() ||
          claims->second.erase(client) == 0) {
        return {NotificationClaimStatus::kAccepted, host, false};
      }
      const bool needs_native_write = claims->second.empty();
      if (needs_native_write) {
        connection->second.notification_claims.erase(claims);
      }
      return {NotificationClaimStatus::kAccepted, host,
              needs_native_write};
    }

    auto& clients = connection->second.notification_claims[key];
    for (const auto& claim : clients) {
      if (claim.second != property) {
        return {NotificationClaimStatus::kConflicting, host, false};
      }
    }
    const bool needs_native_write = clients.empty();
    clients[client] = property;
    return {NotificationClaimStatus::kAccepted, host, needs_native_write};
  }

 private:
  struct SharedConnection {
    Client host;
    std::set<Client> clients;
    std::map<NotificationKey, std::map<Client, NotificationProperty>>
        notification_claims;
  };

  mutable std::mutex mutex_;
  std::map<DeviceId, SharedConnection> connections_;
};

}  // namespace quick_blue_windows::internal

#endif  // QUICK_BLUE_WINDOWS_CONNECTION_OWNERSHIP_H_
