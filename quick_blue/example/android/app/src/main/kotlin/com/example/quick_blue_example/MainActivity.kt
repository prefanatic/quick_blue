package com.example.quick_blue_example

import android.content.Context
import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var testHarness: EngineTestHarness? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        testHarness = createDebugTestHarness()?.also { it.attach(flutterEngine) }
    }

    private fun createDebugTestHarness(): EngineTestHarness? {
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return null
        return Class.forName("com.example.quick_blue_example.MultiEngineTestHarness")
            .getDeclaredConstructor(Context::class.java)
            .newInstance(applicationContext) as EngineTestHarness
    }

    override fun onDestroy() {
        testHarness?.close()
        testHarness = null
        super.onDestroy()
    }
}

internal interface EngineTestHarness : AutoCloseable {
    fun attach(primaryEngine: FlutterEngine)
}
