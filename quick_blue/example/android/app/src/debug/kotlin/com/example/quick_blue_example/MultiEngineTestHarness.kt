package com.example.quick_blue_example

import android.content.Context
import com.example.quick_blue.QuickBluePlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Debug-only native controller used by android_multi_engine_test.dart. */
internal class MultiEngineTestHarness(private val context: Context) : EngineTestHarness {
    private var secondaryEngine: FlutterEngine? = null
    private var secondaryChannel: MethodChannel? = null
    private var pendingSecondaryStart: MethodChannel.Result? = null

    override fun attach(primaryEngine: FlutterEngine) {
        MethodChannel(
            primaryEngine.dartExecutor.binaryMessenger,
            MULTI_ENGINE_CONTROL_CHANNEL,
        ).setMethodCallHandler(::handleControlCall)
    }

    private fun handleControlCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startSecondary" -> startSecondaryEngine(result)
            "callSecondary" -> callSecondaryEngine(call, result)
            "stopSecondary" -> {
                stopSecondaryEngine()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startSecondaryEngine(result: MethodChannel.Result) {
        if (secondaryEngine != null) {
            result.success(null)
            return
        }

        val engine = FlutterEngine(context)
        if (!engine.plugins.has(QuickBluePlugin::class.java)) {
            engine.plugins.add(QuickBluePlugin())
        }
        val channel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            MULTI_ENGINE_WORKER_CHANNEL,
        )
        pendingSecondaryStart = result
        channel.setMethodCallHandler { call, reply ->
            if (call.method == "ready") {
                pendingSecondaryStart?.success(null)
                pendingSecondaryStart = null
                reply.success(null)
            } else {
                reply.notImplemented()
            }
        }
        secondaryEngine = engine
        secondaryChannel = channel

        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context)
        loader.ensureInitializationComplete(context, null)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:quick_blue_example/multi_engine_worker.dart",
                "multiEngineWorkerMain",
            )
        )
    }

    private fun callSecondaryEngine(call: MethodCall, result: MethodChannel.Result) {
        val method = call.argument<String>("method")
        if (method == null) {
            result.error("InvalidArgument", "Missing secondary method", null)
            return
        }
        val channel = secondaryChannel
        if (channel == null) {
            result.error("InvalidState", "The secondary engine is not running", null)
            return
        }
        channel.invokeMethod(
            method,
            call.argument<Any>("arguments"),
            object : MethodChannel.Result {
                override fun success(value: Any?) = result.success(value)
                override fun error(code: String, message: String?, details: Any?) =
                    result.error(code, message, details)
                override fun notImplemented() = result.notImplemented()
            },
        )
    }

    private fun stopSecondaryEngine() {
        pendingSecondaryStart?.error(
            "Cancelled",
            "The secondary engine stopped before becoming ready",
            null,
        )
        pendingSecondaryStart = null
        secondaryChannel?.setMethodCallHandler(null)
        secondaryChannel = null
        secondaryEngine?.destroy()
        secondaryEngine = null
    }

    override fun close() {
        stopSecondaryEngine()
    }

    companion object {
        private const val MULTI_ENGINE_CONTROL_CHANNEL =
            "quick_blue.example/multi_engine_control"
        private const val MULTI_ENGINE_WORKER_CHANNEL =
            "quick_blue.example/multi_engine_worker"
    }
}
