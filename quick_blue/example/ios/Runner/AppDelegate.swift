import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  #if DEBUG
    private var multiEngineTestHarness: IOSMultiEngineTestHarness?
  #endif

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    #if DEBUG
      multiEngineTestHarness = IOSMultiEngineTestHarness(
        primaryMessenger: engineBridge.applicationRegistrar.messenger()
      )
    #endif
  }
}

#if DEBUG
  /// Starts a real headless iOS FlutterEngine like background-task plugins do.
  private final class IOSMultiEngineTestHarness {
    private static let controlChannelName =
      "quick_blue.example/multi_engine_control"
    private static let workerChannelName =
      "quick_blue.example/multi_engine_worker"
    private static let workerEntrypoint = "multiEngineWorkerMain"
    private static let workerLibraryURI =
      "package:quick_blue_example/multi_engine_worker.dart"

    private let controlChannel: FlutterMethodChannel
    private var secondaryEngine: FlutterEngine?
    private var secondaryChannel: FlutterMethodChannel?
    private var pendingSecondaryStart: FlutterResult?

    init(primaryMessenger: FlutterBinaryMessenger) {
      controlChannel = FlutterMethodChannel(
        name: Self.controlChannelName,
        binaryMessenger: primaryMessenger
      )
      controlChannel.setMethodCallHandler { [weak self] call, result in
        self?.handleControlCall(call, result: result)
      }
    }

    deinit {
      stopSecondaryEngine()
      controlChannel.setMethodCallHandler(nil)
    }

    private func handleControlCall(
      _ call: FlutterMethodCall,
      result: @escaping FlutterResult
    ) {
      switch call.method {
      case "startSecondary":
        startSecondaryEngine(result: result)
      case "callSecondary":
        guard
          let arguments = call.arguments as? [String: Any],
          let method = arguments["method"] as? String,
          let secondaryChannel
        else {
          result(
            FlutterError(
              code: "InvalidState",
              message: "The secondary Flutter engine is not running",
              details: nil
            )
          )
          return
        }
        secondaryChannel.invokeMethod(
          method,
          arguments: arguments["arguments"],
          result: result
        )
      case "stopSecondary":
        stopSecondaryEngine()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    private func startSecondaryEngine(result: @escaping FlutterResult) {
      if secondaryEngine != nil {
        result(nil)
        return
      }

      let engine = FlutterEngine(
        name: "quick-blue-multi-engine-worker",
        project: nil,
        allowHeadlessExecution: true
      )
      pendingSecondaryStart = result
      secondaryEngine = engine
      guard
        engine.run(
          withEntrypoint: Self.workerEntrypoint,
          libraryURI: Self.workerLibraryURI
        )
      else {
        pendingSecondaryStart = nil
        secondaryChannel = nil
        secondaryEngine = nil
        result(
          FlutterError(
            code: "EngineStartFailed",
            message: "Unable to start the secondary Flutter engine",
            details: nil
          )
        )
        return
      }
      GeneratedPluginRegistrant.register(with: engine)
      let channel = FlutterMethodChannel(
        name: Self.workerChannelName,
        binaryMessenger: engine.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, reply in
        guard call.method == "ready" else {
          reply(FlutterMethodNotImplemented)
          return
        }
        self?.pendingSecondaryStart?(nil)
        self?.pendingSecondaryStart = nil
        reply(nil)
      }
      secondaryChannel = channel
    }

    private func stopSecondaryEngine() {
      pendingSecondaryStart?(
        FlutterError(
          code: "Cancelled",
          message: "The secondary engine stopped before becoming ready",
          details: nil
        )
      )
      pendingSecondaryStart = nil
      secondaryChannel?.setMethodCallHandler(nil)
      secondaryChannel = nil
      secondaryEngine?.destroyContext()
      secondaryEngine = nil
    }
  }
#endif
