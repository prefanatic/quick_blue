import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    input: 'pigeons/availability.dart',
    appDirectory: 'example/',
    dartOut: 'lib/src/availability.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/example/quick_blue/Availability.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.example.quick_blue',
      useJni: true,
      errorClassName: 'AvailabilityError',
    ),
  ),
)
@HostApi()
abstract class QuickBlueAvailabilityApi {
  bool isBluetoothAvailable();
}
