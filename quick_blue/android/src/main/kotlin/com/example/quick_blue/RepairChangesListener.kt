package com.example.quick_blue

internal class RepairChangesListener : RepairChangesStreamHandler() {
    private var eventSink: PigeonEventSink<PlatformRepairObservation>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformRepairObservation>) {
        eventSink = sink
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
    }

    fun onRepairChanged(observation: PlatformRepairObservation) {
        eventSink?.success(observation)
    }

    fun onEventsDone() {
        eventSink?.endOfStream()
        eventSink = null
    }
}
