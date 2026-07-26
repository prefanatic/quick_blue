package com.example.quick_blue_example

import android.Manifest
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val PERMISSION_CHANNEL =
            "com.example.quick_blue_example/permissions"
        private const val RANGING_PERMISSION_REQUEST = 4101
    }

    private var testHarness: EngineTestHarness? = null
    private var pendingRangingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestRangingPermission" -> requestRangingPermission(result)
                else -> result.notImplemented()
            }
        }
        testHarness = createDebugTestHarness()?.also { it.attach(flutterEngine) }
    }

    private fun requestRangingPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.RANGING) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingRangingPermissionResult != null) {
            result.error(
                "PermissionRequestInProgress",
                "A ranging permission request is already in progress.",
                null,
            )
            return
        }

        pendingRangingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.RANGING),
            RANGING_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != RANGING_PERMISSION_REQUEST) return

        val result = pendingRangingPermissionResult
        pendingRangingPermissionResult = null
        result?.success(
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        )
    }

    private fun createDebugTestHarness(): EngineTestHarness? {
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return null
        return Class.forName("com.example.quick_blue_example.MultiEngineTestHarness")
            .getDeclaredConstructor(Context::class.java)
            .newInstance(applicationContext) as EngineTestHarness
    }

    override fun onDestroy() {
        pendingRangingPermissionResult?.error(
            "ActivityDestroyed",
            "The activity closed before the ranging permission request completed.",
            null,
        )
        pendingRangingPermissionResult = null
        testHarness?.close()
        testHarness = null
        super.onDestroy()
    }
}

internal interface EngineTestHarness : AutoCloseable {
    fun attach(primaryEngine: FlutterEngine)
}
