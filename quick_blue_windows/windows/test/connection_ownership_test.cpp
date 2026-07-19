#include "../connection_ownership.h"

#include <cassert>
#include <string>

namespace {

enum class NotificationProperty {
  kDisabled,
  kNotification,
  kIndication,
};

struct Client {};

using Ownership = quick_blue_windows::internal::ConnectionOwnership<
    int,
    Client*,
    std::string,
    NotificationProperty>;

void TestAttachAndHostTransfer() {
  Ownership ownership;
  Client first;
  Client second;

  const auto first_attachment = ownership.Attach(1, &first);
  const auto second_attachment = ownership.Attach(1, &second);

  assert(first_attachment.is_new);
  assert(first_attachment.host == &first);
  assert(!second_attachment.is_new);
  assert(second_attachment.host == &first);
  assert(ownership.Owns(1, &second));

  const auto plan = ownership.Detach(1, &first);
  assert(plan.has_value());
  assert(!plan->final_client);
  assert(plan->previous_host == &first);
  assert(plan->new_host == &second);
  assert(plan->notification_host == &second);
  assert(ownership.IsHost(1, &second));
}

void TestNotificationClaimsAndFinalDetach() {
  Ownership ownership;
  Client first;
  Client second;
  ownership.Attach(1, &first);
  ownership.Attach(1, &second);

  const auto first_claim = ownership.UpdateNotificationClaim(
      1, "service|value", &first, NotificationProperty::kNotification,
      NotificationProperty::kDisabled);
  const auto second_claim = ownership.UpdateNotificationClaim(
      1, "service|value", &second, NotificationProperty::kNotification,
      NotificationProperty::kDisabled);
  const auto conflicting_claim = ownership.UpdateNotificationClaim(
      1, "service|value", &second, NotificationProperty::kIndication,
      NotificationProperty::kDisabled);

  assert(first_claim.status ==
         Ownership::NotificationClaimStatus::kAccepted);
  assert(first_claim.needs_native_write);
  assert(!second_claim.needs_native_write);
  assert(conflicting_claim.status ==
         Ownership::NotificationClaimStatus::kConflicting);

  const auto first_plan = ownership.Detach(1, &first);
  assert(first_plan.has_value());
  assert(first_plan->notifications_to_disable.empty());

  const auto second_plan = ownership.Detach(1, &second);
  assert(second_plan.has_value());
  assert(second_plan->final_client);
  assert(second_plan->notifications_to_disable.size() == 1);
  assert(second_plan->notifications_to_disable.front() == "service|value");
}

void TestRejectsClaimsFromDetachedClients() {
  Ownership ownership;
  Client client;

  const auto claim = ownership.UpdateNotificationClaim(
      1, "service|value", &client, NotificationProperty::kNotification,
      NotificationProperty::kDisabled);

  assert(claim.status == Ownership::NotificationClaimStatus::kNotAttached);
}

}  // namespace

int main() {
  TestAttachAndHostTransfer();
  TestNotificationClaimsAndFinalDetach();
  TestRejectsClaimsFromDetachedClients();
  return 0;
}
