#include "include/quick_blue_windows/quick_blue_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

#include "messages.g.h"

#define GUID_FORMAT "%08x-%04hx-%04hx-%02hhx%02hhx-%02hhx%02hhx%02hhx%02hhx%02hhx%02hhx"
#define GUID_ARG(guid) guid.Data1, guid.Data2, guid.Data3, guid.Data4[0], guid.Data4[1], guid.Data4[2], guid.Data4[3], guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7]

namespace {

using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Foundation::Collections;
using namespace winrt::Windows::Storage::Streams;
using namespace winrt::Windows::Devices::Radios;
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;

using flutter::CustomEncodableValue;
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

using quick_blue_windows::ErrorOr;
using quick_blue_windows::FlutterError;
using quick_blue_windows::PlatformBleInputProperty;
using quick_blue_windows::PlatformBleOutputProperty;
using quick_blue_windows::PlatformCharacteristic;
using quick_blue_windows::PlatformCharacteristicValueChanged;
using quick_blue_windows::PlatformConnectionState;
using quick_blue_windows::PlatformConnectionStateChange;
using quick_blue_windows::PlatformGattStatus;
using quick_blue_windows::PlatformServiceDiscovered;
using quick_blue_windows::PlatformWindowsScanMode;
using quick_blue_windows::PlatformWindowsScanOptions;
using quick_blue_windows::PlatformWindowsSignalStrengthFilter;
using quick_blue_windows::QuickBlueApi;
using quick_blue_windows::QuickBlueFlutterApi;

constexpr uint8_t kServiceData16BitUuid = 0x16;
constexpr uint8_t kServiceData32BitUuid = 0x20;
constexpr uint8_t kServiceData128BitUuid = 0x21;
constexpr uint8_t kManufacturerSpecificData = 0xff;

std::vector<uint8_t> to_bytevc(IBuffer buffer) {
  auto reader = DataReader::FromBuffer(buffer);
  auto result = std::vector<uint8_t>(reader.UnconsumedBufferLength());
  reader.ReadBytes(result);
  return result;
}

IBuffer from_bytevc(const std::vector<uint8_t>& bytes) {
  auto writer = DataWriter();
  writer.WriteBytes(bytes);
  return writer.DetachBuffer();
}

std::string to_uuidstr(winrt::guid guid) {
  char chars[36 + 1];
  sprintf_s(chars, GUID_FORMAT, GUID_ARG(guid));
  return std::string{chars};
}

std::string to_lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return value;
}

std::string normalize_bluetooth_uuid(std::string uuid) {
  uuid = to_lower(uuid);
  if (uuid.size() >= 2 && uuid.front() == '{' && uuid.back() == '}') {
    uuid = uuid.substr(1, uuid.size() - 2);
  }
  if (uuid.size() == 4) {
    return "0000" + uuid + "-0000-1000-8000-00805f9b34fb";
  }
  if (uuid.size() == 8) {
    return uuid + "-0000-1000-8000-00805f9b34fb";
  }
  return uuid;
}

std::string bluetooth_base_uuid_from_little_endian(uint32_t value) {
  char chars[36 + 1];
  sprintf_s(chars, "%08x-0000-1000-8000-00805f9b34fb", value);
  return std::string{chars};
}

bool has_property(GattCharacteristicProperties properties,
                  GattCharacteristicProperties property) {
  return (static_cast<uint32_t>(properties) & static_cast<uint32_t>(property)) !=
         0;
}

PlatformCharacteristic to_characteristic_info(GattCharacteristic characteristic) {
  auto properties = characteristic.CharacteristicProperties();
  return PlatformCharacteristic(
      to_uuidstr(characteristic.Uuid()),
      has_property(properties, GattCharacteristicProperties::Read),
      has_property(properties, GattCharacteristicProperties::Write),
      has_property(properties, GattCharacteristicProperties::WriteWithoutResponse),
      has_property(properties, GattCharacteristicProperties::Notify),
      has_property(properties, GattCharacteristicProperties::Indicate));
}

BluetoothLEScanningMode to_bluetooth_le_scanning_mode(
    PlatformWindowsScanMode mode) {
  switch (mode) {
    case PlatformWindowsScanMode::kPassive:
      return BluetoothLEScanningMode::Passive;
    case PlatformWindowsScanMode::kActive:
      return BluetoothLEScanningMode::Active;
    case PlatformWindowsScanMode::kNone:
      return BluetoothLEScanningMode::None;
  }
  return BluetoothLEScanningMode::Passive;
}

TimeSpan milliseconds_to_timespan(int64_t milliseconds) {
  return std::chrono::milliseconds(milliseconds);
}

void apply_signal_strength_filter(
    BluetoothLEAdvertisementWatcher watcher,
    const PlatformWindowsSignalStrengthFilter& filter) {
  auto native_filter = BluetoothSignalStrengthFilter();
  if (const auto* value = filter.in_range_threshold_in_d_bm()) {
    native_filter.InRangeThresholdInDBm(static_cast<int16_t>(*value));
  }
  if (const auto* value = filter.out_of_range_threshold_in_d_bm()) {
    native_filter.OutOfRangeThresholdInDBm(static_cast<int16_t>(*value));
  }
  if (const auto* value = filter.out_of_range_timeout_millis()) {
    native_filter.OutOfRangeTimeout(milliseconds_to_timespan(*value));
  }
  if (const auto* value = filter.sampling_interval_millis()) {
    native_filter.SamplingInterval(milliseconds_to_timespan(*value));
  }
  watcher.SignalStrengthFilter(native_filter);
}

void apply_scan_options(BluetoothLEAdvertisementWatcher watcher,
                        const PlatformWindowsScanOptions* options) {
  if (!options) {
    return;
  }
  if (const auto* scanning_mode = options->scanning_mode()) {
    watcher.ScanningMode(to_bluetooth_le_scanning_mode(*scanning_mode));
  }
  if (const auto* signal_strength_filter = options->signal_strength_filter()) {
    apply_signal_strength_filter(watcher, *signal_strength_filter);
  }
}

std::string characteristic_cache_key(const std::string& service,
                                     const std::string& characteristic) {
  return normalize_bluetooth_uuid(service) + "|" +
         normalize_bluetooth_uuid(characteristic);
}

std::vector<uint8_t> parse_manufacturer_data(
    BluetoothLEManufacturerData manufacturer_data) {
  std::vector<uint8_t> result;
  auto company_id = manufacturer_data.CompanyId();
  result.push_back(static_cast<uint8_t>(company_id & 0xff));
  result.push_back(static_cast<uint8_t>((company_id >> 8) & 0xff));
  auto data = to_bytevc(manufacturer_data.Data());
  result.insert(result.end(), data.begin(), data.end());
  return result;
}

std::vector<uint8_t> parse_manufacturer_data_head(
    BluetoothLEAdvertisement advertisement) {
  if (advertisement.ManufacturerData().Size() == 0) {
    return std::vector<uint8_t>();
  }
  return parse_manufacturer_data(advertisement.ManufacturerData().GetAt(0));
}

EncodableList parse_service_uuids(BluetoothLEAdvertisement advertisement) {
  EncodableList service_uuids;
  for (const auto& uuid : advertisement.ServiceUuids()) {
    service_uuids.push_back(EncodableValue(to_uuidstr(uuid)));
  }
  return service_uuids;
}

EncodableMap parse_service_data(BluetoothLEAdvertisement advertisement) {
  EncodableMap service_data;
  for (const auto& section : advertisement.DataSections()) {
    auto bytes = to_bytevc(section.Data());
    std::string uuid;
    size_t value_start = 0;

    if (section.DataType() == kServiceData16BitUuid && bytes.size() >= 2) {
      const auto value = static_cast<uint32_t>(bytes[0]) |
                         (static_cast<uint32_t>(bytes[1]) << 8);
      uuid = bluetooth_base_uuid_from_little_endian(value);
      value_start = 2;
    } else if (section.DataType() == kServiceData32BitUuid &&
               bytes.size() >= 4) {
      const auto value = static_cast<uint32_t>(bytes[0]) |
                         (static_cast<uint32_t>(bytes[1]) << 8) |
                         (static_cast<uint32_t>(bytes[2]) << 16) |
                         (static_cast<uint32_t>(bytes[3]) << 24);
      uuid = bluetooth_base_uuid_from_little_endian(value);
      value_start = 4;
    } else if (section.DataType() == kServiceData128BitUuid &&
               bytes.size() >= 16) {
      winrt::guid guid;
      guid.Data1 = static_cast<uint32_t>(bytes[3]) |
                   (static_cast<uint32_t>(bytes[2]) << 8) |
                   (static_cast<uint32_t>(bytes[1]) << 16) |
                   (static_cast<uint32_t>(bytes[0]) << 24);
      guid.Data2 = static_cast<uint16_t>(bytes[5]) |
                   (static_cast<uint16_t>(bytes[4]) << 8);
      guid.Data3 = static_cast<uint16_t>(bytes[7]) |
                   (static_cast<uint16_t>(bytes[6]) << 8);
      std::copy(bytes.begin() + 8, bytes.begin() + 16, guid.Data4);
      uuid = to_uuidstr(guid);
      value_start = 16;
    }

    if (!uuid.empty()) {
      service_data.insert_or_assign(
          EncodableValue(uuid),
          EncodableValue(std::vector<uint8_t>(bytes.begin() + value_start,
                                              bytes.end())));
    }
  }
  return service_data;
}

uint64_t parse_bluetooth_address(const std::string& device_id) {
  size_t parsed = 0;
  auto address = std::stoull(device_id, &parsed);
  if (parsed != device_id.size()) {
    throw std::invalid_argument("Invalid deviceId: " + device_id);
  }
  return address;
}

FlutterError illegal_argument(const std::string& message) {
  return FlutterError("IllegalArgument", message);
}

FlutterError gatt_error(const std::string& operation,
                        GattCommunicationStatus status) {
  return FlutterError(operation + "Failed",
                      operation + " failed with GATT status " +
                          std::to_string(static_cast<int32_t>(status)) + ".");
}

struct BluetoothDeviceAgent {
  BluetoothLEDevice device;
  GattSession gattSession{nullptr};
  winrt::event_token connnectionStatusChangedToken;
  std::map<std::string, GattDeviceService> gattServices;
  std::map<std::string, GattCharacteristic> gattCharacteristics;
  std::map<std::string, winrt::event_token> valueChangedTokens;

  BluetoothDeviceAgent(BluetoothLEDevice device,
                       GattSession gattSession,
                       winrt::event_token connnectionStatusChangedToken)
      : device(device),
        gattSession(gattSession),
        connnectionStatusChangedToken(connnectionStatusChangedToken) {}

  ~BluetoothDeviceAgent() { device = nullptr; }

  IAsyncOperation<GattDeviceService> GetServiceAsync(std::string service) {
    service = normalize_bluetooth_uuid(service);
    auto cached = gattServices.find(service);
    if (cached != gattServices.end()) {
      co_return cached->second;
    }

    auto serviceResult = co_await device.GetGattServicesAsync();
    if (serviceResult.Status() != GattCommunicationStatus::Success) {
      co_return nullptr;
    }

    for (auto s : serviceResult.Services()) {
      if (to_uuidstr(s.Uuid()) == service) {
        gattServices.insert(std::make_pair(service, s));
        co_return s;
      }
    }
    co_return nullptr;
  }

  IAsyncOperation<GattCharacteristic> GetCharacteristicAsync(
      std::string service, std::string characteristic) {
    service = normalize_bluetooth_uuid(service);
    characteristic = normalize_bluetooth_uuid(characteristic);
    const auto cache_key = characteristic_cache_key(service, characteristic);
    auto cached = gattCharacteristics.find(cache_key);
    if (cached != gattCharacteristics.end()) {
      co_return cached->second;
    }

    auto gattService = co_await GetServiceAsync(service);
    if (!gattService) {
      co_return nullptr;
    }

    auto characteristicResult = co_await gattService.GetCharacteristicsAsync();
    if (characteristicResult.Status() != GattCommunicationStatus::Success) {
      co_return nullptr;
    }

    for (auto c : characteristicResult.Characteristics()) {
      if (to_uuidstr(c.Uuid()) == characteristic) {
        gattCharacteristics.insert(std::make_pair(cache_key, c));
        co_return c;
      }
    }
    co_return nullptr;
  }
};

class QuickBlueWindowsPlugin : public flutter::Plugin,
                               public flutter::StreamHandler<EncodableValue>,
                               public QuickBlueApi {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit QuickBlueWindowsPlugin(flutter::BinaryMessenger* binary_messenger);

  virtual ~QuickBlueWindowsPlugin();

 private:
  winrt::fire_and_forget InitializeAsync();

  ErrorOr<bool> IsBluetoothAvailable() override;
  std::optional<FlutterError> StartScan(
      const EncodableList* service_uuids,
      const EncodableMap* manufacturer_data,
      const int64_t* rssi,
      const PlatformWindowsScanOptions* options) override;
  std::optional<FlutterError> StopScan() override;
  ErrorOr<EncodableList> ConnectedDeviceIds(
      const EncodableList& service_uuids) override;
  std::optional<FlutterError> Connect(const std::string& device_id) override;
  std::optional<FlutterError> Disconnect(const std::string& device_id) override;
  void DiscoverServices(
      const std::string& device_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void SetNotifiable(
      const std::string& device_id,
      const std::string& service,
      const std::string& characteristic,
      const PlatformBleInputProperty& ble_input_property,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ReadValue(const std::string& device_id,
                 const std::string& service,
                 const std::string& characteristic,
                 std::function<void(std::optional<FlutterError> reply)> result)
      override;
  void WriteValue(const std::string& device_id,
                  const std::string& service,
                  const std::string& characteristic,
                  const std::vector<uint8_t>& value,
                  const PlatformBleOutputProperty& ble_output_property,
                  std::function<void(std::optional<FlutterError> reply)> result)
      override;
  void RequestMtu(const std::string& device_id,
                  int64_t expected_mtu,
                  std::function<void(ErrorOr<int64_t> reply)> result) override;

  std::unique_ptr<flutter::StreamHandlerError<>> OnListenInternal(
      const EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<>>&& events) override;
  std::unique_ptr<flutter::StreamHandlerError<>> OnCancelInternal(
      const EncodableValue* arguments) override;

  flutter::BinaryMessenger* binary_messenger_;
  std::unique_ptr<QuickBlueFlutterApi> flutter_api_;

  std::unique_ptr<flutter::EventSink<EncodableValue>> scan_result_sink_;

  Radio bluetoothRadio{nullptr};

  BluetoothLEAdvertisementWatcher bluetoothLEWatcher{nullptr};
  winrt::event_token bluetoothLEWatcherReceivedToken;
  std::set<std::string> serviceUuidFilter;
  std::map<uint16_t, std::vector<uint8_t>> manufacturerDataFilter;
  std::optional<int64_t> rssiFilter;
  void BluetoothLEWatcher_Received(BluetoothLEAdvertisementWatcher sender,
                                   BluetoothLEAdvertisementReceivedEventArgs args);
  bool MatchesScanFilters(BluetoothLEAdvertisementReceivedEventArgs args);
  void SendScanResult(BluetoothLEAdvertisementReceivedEventArgs args);

  std::map<uint64_t, std::unique_ptr<BluetoothDeviceAgent>> connectedDevices{};

  BluetoothDeviceAgent* FindConnectedDevice(const std::string& device_id);
  winrt::fire_and_forget ConnectAsync(uint64_t bluetoothAddress);
  void BluetoothLEDevice_ConnectionStatusChanged(BluetoothLEDevice sender,
                                                 IInspectable args);
  bool CleanConnection(uint64_t bluetoothAddress);
  winrt::fire_and_forget DiscoverServicesAsync(
      BluetoothDeviceAgent& bluetoothDeviceAgent,
      std::function<void(std::optional<FlutterError> reply)> result);
  winrt::fire_and_forget SetNotifiableAsync(
      BluetoothDeviceAgent& bluetoothDeviceAgent,
      std::string service,
      std::string characteristic,
      PlatformBleInputProperty bleInputProperty,
      std::function<void(std::optional<FlutterError> reply)> result);
  winrt::fire_and_forget RequestMtuAsync(
      BluetoothDeviceAgent& bluetoothDeviceAgent,
      std::function<void(ErrorOr<int64_t> reply)> result);
  winrt::fire_and_forget ReadValueAsync(
      BluetoothDeviceAgent& bluetoothDeviceAgent,
      std::string service,
      std::string characteristic,
      std::function<void(std::optional<FlutterError> reply)> result);
  winrt::fire_and_forget WriteValueAsync(
      BluetoothDeviceAgent& bluetoothDeviceAgent,
      std::string service,
      std::string characteristic,
      std::vector<uint8_t> value,
      PlatformBleOutputProperty bleOutputProperty,
      std::function<void(std::optional<FlutterError> reply)> result);
  void GattCharacteristic_ValueChanged(GattCharacteristic sender,
                                       GattValueChangedEventArgs args);

  void SendConnectionState(std::string deviceId,
                           PlatformConnectionState state,
                           PlatformGattStatus status);
  void SendServiceDiscovered(std::string deviceId,
                             std::string serviceUuid,
                             EncodableList characteristics);
  void SendServiceDiscoveryComplete(std::string deviceId);
  void SendCharacteristicValue(std::string deviceId,
                               std::string serviceUuid,
                               std::string characteristicId,
                               std::vector<uint8_t> value);
};

void QuickBlueWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto event_scan_result =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), "quick_blue/event.scanResult",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin =
      std::make_unique<QuickBlueWindowsPlugin>(registrar->messenger());

  QuickBlueApi::SetUp(registrar->messenger(), plugin.get());

  auto handler = std::make_unique<flutter::StreamHandlerFunctions<>>(
      [plugin_pointer = plugin.get()](
          const EncodableValue* arguments,
          std::unique_ptr<flutter::EventSink<>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnListen(arguments, std::move(events));
      },
      [plugin_pointer = plugin.get()](const EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnCancel(arguments);
      });
  event_scan_result->SetStreamHandler(std::move(handler));

  registrar->AddPlugin(std::move(plugin));
}

QuickBlueWindowsPlugin::QuickBlueWindowsPlugin(
    flutter::BinaryMessenger* binary_messenger)
    : binary_messenger_(binary_messenger),
      flutter_api_(std::make_unique<QuickBlueFlutterApi>(binary_messenger)) {
  InitializeAsync();
}

QuickBlueWindowsPlugin::~QuickBlueWindowsPlugin() {
  StopScan();
  QuickBlueApi::SetUp(binary_messenger_, nullptr);
}

winrt::fire_and_forget QuickBlueWindowsPlugin::InitializeAsync() {
  try {
    auto bluetoothAdapter = co_await BluetoothAdapter::GetDefaultAsync();
    if (!bluetoothAdapter) {
      co_return;
    }
    bluetoothRadio = co_await bluetoothAdapter.GetRadioAsync();
  } catch (const winrt::hresult_error&) {
    bluetoothRadio = nullptr;
  }
}

ErrorOr<bool> QuickBlueWindowsPlugin::IsBluetoothAvailable() {
  return bluetoothRadio && bluetoothRadio.State() == RadioState::On;
}

std::optional<FlutterError> QuickBlueWindowsPlugin::StartScan(
    const EncodableList* service_uuids,
    const EncodableMap* manufacturer_data,
    const int64_t* rssi,
    const PlatformWindowsScanOptions* options) {
  StopScan();

  serviceUuidFilter.clear();
  manufacturerDataFilter.clear();
  rssiFilter = rssi ? std::optional<int64_t>(*rssi) : std::nullopt;

  if (service_uuids) {
    for (const auto& service_uuid : *service_uuids) {
      serviceUuidFilter.insert(
          normalize_bluetooth_uuid(std::get<std::string>(service_uuid)));
    }
  }

  if (manufacturer_data) {
    for (const auto& item : *manufacturer_data) {
      uint16_t company_id = 0;
      if (const auto* id64 = std::get_if<int64_t>(&item.first)) {
        company_id = static_cast<uint16_t>(*id64);
      } else if (const auto* id32 = std::get_if<int32_t>(&item.first)) {
        company_id = static_cast<uint16_t>(*id32);
      } else {
        continue;
      }
      manufacturerDataFilter[company_id] =
          std::get<std::vector<uint8_t>>(item.second);
    }
  }

  bluetoothLEWatcher = BluetoothLEAdvertisementWatcher();
  apply_scan_options(bluetoothLEWatcher, options);
  for (const auto& filter : manufacturerDataFilter) {
    std::vector<uint8_t> pattern;
    pattern.push_back(static_cast<uint8_t>(filter.first & 0xff));
    pattern.push_back(static_cast<uint8_t>((filter.first >> 8) & 0xff));
    pattern.insert(pattern.end(), filter.second.begin(), filter.second.end());
    bluetoothLEWatcher.AdvertisementFilter().BytePatterns().Append(
        BluetoothLEAdvertisementBytePattern(kManufacturerSpecificData, 0,
                                            from_bytevc(pattern)));
  }
  bluetoothLEWatcherReceivedToken = bluetoothLEWatcher.Received(
      {this, &QuickBlueWindowsPlugin::BluetoothLEWatcher_Received});
  bluetoothLEWatcher.Start();
  return std::nullopt;
}

std::optional<FlutterError> QuickBlueWindowsPlugin::StopScan() {
  if (bluetoothLEWatcher) {
    bluetoothLEWatcher.Stop();
    bluetoothLEWatcher.Received(bluetoothLEWatcherReceivedToken);
  }
  bluetoothLEWatcher = nullptr;
  rssiFilter = std::nullopt;
  return std::nullopt;
}

ErrorOr<EncodableList> QuickBlueWindowsPlugin::ConnectedDeviceIds(
    const EncodableList& service_uuids) {
  std::set<std::string> normalizedServiceUuids;
  for (const auto& service_uuid : service_uuids) {
    normalizedServiceUuids.insert(
        normalize_bluetooth_uuid(std::get<std::string>(service_uuid)));
  }

  EncodableList deviceIds;
  for (const auto& device : connectedDevices) {
    if (!normalizedServiceUuids.empty()) {
      std::set<std::string> connectedServiceUuids;
      for (const auto& service : device.second->gattServices) {
        connectedServiceUuids.insert(service.first);
      }
      if (!std::includes(connectedServiceUuids.begin(),
                         connectedServiceUuids.end(),
                         normalizedServiceUuids.begin(),
                         normalizedServiceUuids.end())) {
        continue;
      }
    }

    deviceIds.push_back(EncodableValue(std::to_string(device.first)));
  }
  return deviceIds;
}

std::optional<FlutterError> QuickBlueWindowsPlugin::Connect(
    const std::string& device_id) {
  try {
    ConnectAsync(parse_bluetooth_address(device_id));
    return std::nullopt;
  } catch (const std::exception& error) {
    return illegal_argument(error.what());
  }
}

std::optional<FlutterError> QuickBlueWindowsPlugin::Disconnect(
    const std::string& device_id) {
  try {
    const auto address = parse_bluetooth_address(device_id);
    const auto disconnected = CleanConnection(address);
    if (!disconnected) {
      return illegal_argument("Unknown deviceId: " + device_id);
    }
    SendConnectionState(device_id, PlatformConnectionState::kDisconnected,
                        PlatformGattStatus::kSuccess);
    return std::nullopt;
  } catch (const std::exception& error) {
    return illegal_argument(error.what());
  }
}

BluetoothDeviceAgent* QuickBlueWindowsPlugin::FindConnectedDevice(
    const std::string& device_id) {
  auto it = connectedDevices.find(parse_bluetooth_address(device_id));
  if (it == connectedDevices.end()) {
    return nullptr;
  }
  return it->second.get();
}

void QuickBlueWindowsPlugin::DiscoverServices(
    const std::string& device_id,
    std::function<void(std::optional<FlutterError> reply)> result) {
  try {
    auto* device = FindConnectedDevice(device_id);
    if (!device) {
      result(illegal_argument("Unknown deviceId: " + device_id));
      return;
    }
    DiscoverServicesAsync(*device, std::move(result));
  } catch (const std::exception& error) {
    result(illegal_argument(error.what()));
  }
}

void QuickBlueWindowsPlugin::SetNotifiable(
    const std::string& device_id,
    const std::string& service,
    const std::string& characteristic,
    const PlatformBleInputProperty& ble_input_property,
    std::function<void(std::optional<FlutterError> reply)> result) {
  try {
    auto* device = FindConnectedDevice(device_id);
    if (!device) {
      result(illegal_argument("Unknown deviceId: " + device_id));
      return;
    }
    SetNotifiableAsync(*device, service, characteristic, ble_input_property,
                       std::move(result));
  } catch (const std::exception& error) {
    result(illegal_argument(error.what()));
  }
}

void QuickBlueWindowsPlugin::ReadValue(
    const std::string& device_id,
    const std::string& service,
    const std::string& characteristic,
    std::function<void(std::optional<FlutterError> reply)> result) {
  try {
    auto* device = FindConnectedDevice(device_id);
    if (!device) {
      result(illegal_argument("Unknown deviceId: " + device_id));
      return;
    }
    ReadValueAsync(*device, service, characteristic, std::move(result));
  } catch (const std::exception& error) {
    result(illegal_argument(error.what()));
  }
}

void QuickBlueWindowsPlugin::WriteValue(
    const std::string& device_id,
    const std::string& service,
    const std::string& characteristic,
    const std::vector<uint8_t>& value,
    const PlatformBleOutputProperty& ble_output_property,
    std::function<void(std::optional<FlutterError> reply)> result) {
  try {
    auto* device = FindConnectedDevice(device_id);
    if (!device) {
      result(illegal_argument("Unknown deviceId: " + device_id));
      return;
    }
    WriteValueAsync(*device, service, characteristic, value, ble_output_property,
                    std::move(result));
  } catch (const std::exception& error) {
    result(illegal_argument(error.what()));
  }
}

void QuickBlueWindowsPlugin::RequestMtu(
    const std::string& device_id,
    int64_t expected_mtu,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  (void)expected_mtu;
  try {
    auto* device = FindConnectedDevice(device_id);
    if (!device) {
      result(illegal_argument("Unknown deviceId: " + device_id));
      return;
    }
    RequestMtuAsync(*device, std::move(result));
  } catch (const std::exception& error) {
    result(illegal_argument(error.what()));
  }
}

bool QuickBlueWindowsPlugin::MatchesScanFilters(
    BluetoothLEAdvertisementReceivedEventArgs args) {
  if (rssiFilter && args.RawSignalStrengthInDBm() < *rssiFilter) {
    return false;
  }

  if (!serviceUuidFilter.empty()) {
    bool matched = false;
    for (const auto& service_uuid : args.Advertisement().ServiceUuids()) {
      if (serviceUuidFilter.count(normalize_bluetooth_uuid(to_uuidstr(service_uuid))) >
          0) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      return false;
    }
  }

  for (const auto& filter : manufacturerDataFilter) {
    bool matched = false;
    for (const auto& manufacturer_data : args.Advertisement().ManufacturerData()) {
      if (manufacturer_data.CompanyId() != filter.first) {
        continue;
      }
      auto data = to_bytevc(manufacturer_data.Data());
      matched = filter.second.empty() ||
                (data.size() >= filter.second.size() &&
                 std::equal(filter.second.begin(), filter.second.end(),
                            data.begin()));
      if (matched) {
        break;
      }
    }
    if (!matched) {
      return false;
    }
  }

  return true;
}

void QuickBlueWindowsPlugin::BluetoothLEWatcher_Received(
    BluetoothLEAdvertisementWatcher sender,
    BluetoothLEAdvertisementReceivedEventArgs args) {
  (void)sender;
  if (MatchesScanFilters(args)) {
    SendScanResult(args);
  }
}

void QuickBlueWindowsPlugin::SendScanResult(
    BluetoothLEAdvertisementReceivedEventArgs args) {
  try {
    if (scan_result_sink_) {
      const auto manufacturer_data = parse_manufacturer_data_head(args.Advertisement());
      scan_result_sink_->Success(EncodableMap{
          {"name", winrt::to_string(args.Advertisement().LocalName())},
          {"deviceId", std::to_string(args.BluetoothAddress())},
          {"manufacturerDataHead", manufacturer_data},
          {"manufacturerData", manufacturer_data},
          {"serviceUuids", parse_service_uuids(args.Advertisement())},
          {"serviceData", parse_service_data(args.Advertisement())},
          {"rssi", args.RawSignalStrengthInDBm()},
      });
    }
  } catch (const winrt::hresult_error&) {
  }
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
QuickBlueWindowsPlugin::OnListenInternal(
    const EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) {
  if (arguments == nullptr) {
    return nullptr;
  }
  auto args = std::get<EncodableMap>(*arguments);
  auto name = std::get<std::string>(args[EncodableValue("name")]);
  if (name.compare("scanResult") == 0) {
    scan_result_sink_ = std::move(events);
  }
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
QuickBlueWindowsPlugin::OnCancelInternal(const EncodableValue* arguments) {
  if (arguments == nullptr) {
    return nullptr;
  }
  auto args = std::get<EncodableMap>(*arguments);
  auto name = std::get<std::string>(args[EncodableValue("name")]);
  if (name.compare("scanResult") == 0) {
    scan_result_sink_ = nullptr;
  }
  return nullptr;
}

winrt::fire_and_forget QuickBlueWindowsPlugin::ConnectAsync(
    uint64_t bluetoothAddress) {
  try {
    auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(
        bluetoothAddress);
    if (!device) {
      SendConnectionState(std::to_string(bluetoothAddress),
                          PlatformConnectionState::kDisconnected,
                          PlatformGattStatus::kFailure);
      co_return;
    }

    auto gattSession = co_await GattSession::FromDeviceIdAsync(
        device.BluetoothDeviceId());
    if (gattSession) {
      gattSession.MaintainConnection(true);
    }

    auto servicesResult = co_await device.GetGattServicesAsync();
    if (servicesResult.Status() != GattCommunicationStatus::Success) {
      if (gattSession) {
        gattSession.MaintainConnection(false);
      }
      SendConnectionState(std::to_string(bluetoothAddress),
                          PlatformConnectionState::kDisconnected,
                          PlatformGattStatus::kFailure);
      co_return;
    }

    auto connnectionStatusChangedToken = device.ConnectionStatusChanged(
        {this, &QuickBlueWindowsPlugin::BluetoothLEDevice_ConnectionStatusChanged});
    connectedDevices[bluetoothAddress] = std::make_unique<BluetoothDeviceAgent>(
        device, gattSession, connnectionStatusChangedToken);

    SendConnectionState(std::to_string(bluetoothAddress),
                        PlatformConnectionState::kConnected,
                        PlatformGattStatus::kSuccess);
  } catch (const winrt::hresult_error&) {
    SendConnectionState(std::to_string(bluetoothAddress),
                        PlatformConnectionState::kDisconnected,
                        PlatformGattStatus::kFailure);
  }
}

void QuickBlueWindowsPlugin::BluetoothLEDevice_ConnectionStatusChanged(
    BluetoothLEDevice sender, IInspectable args) {
  (void)args;
  if (sender.ConnectionStatus() == BluetoothConnectionStatus::Disconnected) {
    CleanConnection(sender.BluetoothAddress());
    SendConnectionState(std::to_string(sender.BluetoothAddress()),
                        PlatformConnectionState::kDisconnected,
                        PlatformGattStatus::kSuccess);
  }
}

bool QuickBlueWindowsPlugin::CleanConnection(uint64_t bluetoothAddress) {
  auto node = connectedDevices.extract(bluetoothAddress);
  if (node.empty()) {
    return false;
  }

  auto deviceAgent = std::move(node.mapped());
  if (deviceAgent->gattSession) {
    deviceAgent->gattSession.MaintainConnection(false);
  }
  deviceAgent->device.ConnectionStatusChanged(
      deviceAgent->connnectionStatusChangedToken);
  for (auto& tokenPair : deviceAgent->valueChangedTokens) {
    auto characteristic = deviceAgent->gattCharacteristics.find(tokenPair.first);
    if (characteristic != deviceAgent->gattCharacteristics.end()) {
      characteristic->second.ValueChanged(tokenPair.second);
    }
  }
  return true;
}

winrt::fire_and_forget QuickBlueWindowsPlugin::DiscoverServicesAsync(
    BluetoothDeviceAgent& bluetoothDeviceAgent,
    std::function<void(std::optional<FlutterError> reply)> result) {
  try {
    auto serviceResult = co_await bluetoothDeviceAgent.device.GetGattServicesAsync();
    if (serviceResult.Status() != GattCommunicationStatus::Success) {
      result(gatt_error("DiscoverServices", serviceResult.Status()));
      co_return;
    }

    for (auto s : serviceResult.Services()) {
      bluetoothDeviceAgent.gattServices.insert_or_assign(to_uuidstr(s.Uuid()), s);
      auto characteristicResult = co_await s.GetCharacteristicsAsync();
      EncodableList characteristics;
      if (characteristicResult.Status() == GattCommunicationStatus::Success) {
        for (auto c : characteristicResult.Characteristics()) {
          characteristics.push_back(EncodableValue(
              CustomEncodableValue(to_characteristic_info(c))));
        }
      } else {
        result(gatt_error("DiscoverCharacteristics", characteristicResult.Status()));
        co_return;
      }
      SendServiceDiscovered(
          std::to_string(bluetoothDeviceAgent.device.BluetoothAddress()),
          to_uuidstr(s.Uuid()), characteristics);
    }

    SendServiceDiscoveryComplete(
        std::to_string(bluetoothDeviceAgent.device.BluetoothAddress()));
    result(std::nullopt);
  } catch (const winrt::hresult_error&) {
    result(FlutterError("DiscoverServicesFailed", "Service discovery failed."));
  }
}

winrt::fire_and_forget QuickBlueWindowsPlugin::RequestMtuAsync(
    BluetoothDeviceAgent& bluetoothDeviceAgent,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  try {
    auto gattSession = bluetoothDeviceAgent.gattSession;
    if (!gattSession) {
      gattSession = co_await GattSession::FromDeviceIdAsync(
          bluetoothDeviceAgent.device.BluetoothDeviceId());
    }
    if (!gattSession) {
      result(FlutterError("RequestMtuFailed", "Unable to create GATT session."));
      co_return;
    }
    result(static_cast<int64_t>(gattSession.MaxPduSize()));
  } catch (const winrt::hresult_error& error) {
    result(FlutterError("RequestMtuFailed", winrt::to_string(error.message())));
  }
}

winrt::fire_and_forget QuickBlueWindowsPlugin::SetNotifiableAsync(
    BluetoothDeviceAgent& bluetoothDeviceAgent,
    std::string service,
    std::string characteristic,
    PlatformBleInputProperty bleInputProperty,
    std::function<void(std::optional<FlutterError> reply)> result) {
  try {
    auto gattCharacteristic = co_await bluetoothDeviceAgent.GetCharacteristicAsync(
        service, characteristic);
    if (!gattCharacteristic) {
      result(illegal_argument("Unknown characteristic: " + characteristic));
      co_return;
    }

    auto descriptorValue =
        bleInputProperty == PlatformBleInputProperty::kNotification
            ? GattClientCharacteristicConfigurationDescriptorValue::Notify
            : bleInputProperty == PlatformBleInputProperty::kIndication
                  ? GattClientCharacteristicConfigurationDescriptorValue::Indicate
                  : GattClientCharacteristicConfigurationDescriptorValue::None;
    auto writeDescriptorStatus =
        co_await gattCharacteristic
            .WriteClientCharacteristicConfigurationDescriptorAsync(descriptorValue);
    if (writeDescriptorStatus != GattCommunicationStatus::Success) {
      OutputDebugString((L"WriteClientCharacteristicConfigurationDescriptorAsync " +
                         winrt::to_hstring((int32_t)writeDescriptorStatus) +
                         L"\n")
                            .c_str());
      result(gatt_error("SetNotifiable", writeDescriptorStatus));
      co_return;
    }

    const auto cache_key = characteristic_cache_key(service, characteristic);
    if (bleInputProperty != PlatformBleInputProperty::kDisabled) {
      bluetoothDeviceAgent.valueChangedTokens[cache_key] =
          gattCharacteristic.ValueChanged(
              {this, &QuickBlueWindowsPlugin::GattCharacteristic_ValueChanged});
    } else {
      auto token = bluetoothDeviceAgent.valueChangedTokens.find(cache_key);
      if (token != bluetoothDeviceAgent.valueChangedTokens.end()) {
        gattCharacteristic.ValueChanged(token->second);
        bluetoothDeviceAgent.valueChangedTokens.erase(token);
      }
    }
    result(std::nullopt);
  } catch (const winrt::hresult_error& error) {
    result(FlutterError("SetNotifiableFailed", winrt::to_string(error.message())));
  }
}

winrt::fire_and_forget QuickBlueWindowsPlugin::ReadValueAsync(
    BluetoothDeviceAgent& bluetoothDeviceAgent,
    std::string service,
    std::string characteristic,
    std::function<void(std::optional<FlutterError> reply)> result) {
  try {
    auto gattCharacteristic = co_await bluetoothDeviceAgent.GetCharacteristicAsync(
        service, characteristic);
    if (!gattCharacteristic) {
      result(illegal_argument("Unknown characteristic: " + characteristic));
      co_return;
    }

    auto readValueResult = co_await gattCharacteristic.ReadValueAsync();
    if (readValueResult.Status() != GattCommunicationStatus::Success) {
      result(gatt_error("ReadValue", readValueResult.Status()));
      co_return;
    }
    SendCharacteristicValue(
        std::to_string(gattCharacteristic.Service().Device().BluetoothAddress()),
        to_uuidstr(gattCharacteristic.Service().Uuid()),
        to_uuidstr(gattCharacteristic.Uuid()), to_bytevc(readValueResult.Value()));
    result(std::nullopt);
  } catch (const winrt::hresult_error& error) {
    result(FlutterError("ReadValueFailed", winrt::to_string(error.message())));
  }
}

winrt::fire_and_forget QuickBlueWindowsPlugin::WriteValueAsync(
    BluetoothDeviceAgent& bluetoothDeviceAgent,
    std::string service,
    std::string characteristic,
    std::vector<uint8_t> value,
    PlatformBleOutputProperty bleOutputProperty,
    std::function<void(std::optional<FlutterError> reply)> result) {
  try {
    auto gattCharacteristic = co_await bluetoothDeviceAgent.GetCharacteristicAsync(
        service, characteristic);
    if (!gattCharacteristic) {
      result(illegal_argument("Unknown characteristic: " + characteristic));
      co_return;
    }

    auto writeOption = bleOutputProperty == PlatformBleOutputProperty::kWithoutResponse
                           ? GattWriteOption::WriteWithoutResponse
                           : GattWriteOption::WriteWithResponse;
    auto writeValueStatus =
        co_await gattCharacteristic.WriteValueAsync(from_bytevc(value), writeOption);
    if (writeValueStatus != GattCommunicationStatus::Success) {
      result(gatt_error("WriteValue", writeValueStatus));
      co_return;
    }
    result(std::nullopt);
  } catch (const winrt::hresult_error& error) {
    result(FlutterError("WriteValueFailed", winrt::to_string(error.message())));
  }
}

void QuickBlueWindowsPlugin::GattCharacteristic_ValueChanged(
    GattCharacteristic sender, GattValueChangedEventArgs args) {
  SendCharacteristicValue(
      std::to_string(sender.Service().Device().BluetoothAddress()),
      to_uuidstr(sender.Service().Uuid()), to_uuidstr(sender.Uuid()),
      to_bytevc(args.CharacteristicValue()));
}

void QuickBlueWindowsPlugin::SendConnectionState(
    std::string deviceId,
    PlatformConnectionState state,
    PlatformGattStatus status) {
  flutter_api_->OnConnectionStateChange(
      PlatformConnectionStateChange(deviceId, state, status), []() {},
      [](const FlutterError&) {});
}

void QuickBlueWindowsPlugin::SendServiceDiscovered(
    std::string deviceId,
    std::string serviceUuid,
    EncodableList characteristics) {
  flutter_api_->OnServiceDiscovered(
      PlatformServiceDiscovered(deviceId, serviceUuid, characteristics), []() {},
      [](const FlutterError&) {});
}

void QuickBlueWindowsPlugin::SendServiceDiscoveryComplete(std::string deviceId) {
  flutter_api_->OnServiceDiscoveryComplete(deviceId, []() {},
                                           [](const FlutterError&) {});
}

void QuickBlueWindowsPlugin::SendCharacteristicValue(
    std::string deviceId,
    std::string serviceUuid,
    std::string characteristicId,
    std::vector<uint8_t> value) {
  flutter_api_->OnCharacteristicValueChanged(
      PlatformCharacteristicValueChanged(deviceId, serviceUuid, characteristicId,
                                         value),
      []() {}, [](const FlutterError&) {});
}

}  // namespace

void QuickBlueWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  QuickBlueWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
