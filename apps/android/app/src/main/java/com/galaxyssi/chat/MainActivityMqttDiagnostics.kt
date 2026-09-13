package com.galaxyssi.chat

import android.view.View
import android.widget.LinearLayout

internal fun MainActivity.addMqttDeliveryDiagnostics() {
    val snapshot = GalaxySSIMqttClient.transportDiagnostics()
    val paths = GalaxySSIMqttClient.transportPathDiagnostics()
    addSectionTitle(getString(R.string.mqtt_diagnostics_delivery_title))
    mapOf("emqx" to "EMQX", "hivemq" to "HiveMQ", "mosquitto" to "Mosquitto").forEach { (id, name) ->
        val stats = snapshot?.verifiedDelivery?.get(id)
        val detail = if (stats == null || stats.samples == 0) {
            getString(R.string.mqtt_diagnostics_no_delivery_samples)
        } else {
            val p95 = stats.p95Ms?.let { getString(R.string.mqtt_diagnostics_milliseconds, it) }
                ?: getString(R.string.mqtt_diagnostics_insufficient_samples)
            getString(R.string.mqtt_diagnostics_delivery_detail, stats.p50Ms, p95)
        }
        val path = paths[id]
        val state = getString(when (path?.state) {
            MqttBrokerPool.PathState.CONNECTING -> R.string.mqtt_diagnostics_connecting
            MqttBrokerPool.PathState.SUBSCRIBING -> R.string.mqtt_diagnostics_subscribing
            MqttBrokerPool.PathState.RECEIVE_READY -> R.string.mqtt_diagnostics_receive_ready
            MqttBrokerPool.PathState.RECOVERING -> R.string.mqtt_diagnostics_recovering
            MqttBrokerPool.PathState.NETWORK_UNAVAILABLE -> R.string.mqtt_diagnostics_network_unavailable
            else -> R.string.mqtt_diagnostics_disconnected
        })
        val count = getString(R.string.mqtt_diagnostics_sample_count, stats?.samples ?: 0)
        val activity = getString(R.string.mqtt_diagnostics_path_activity, path?.reconnectAttempts ?: 0L,
            path?.pendingPublishes ?: 0)
        val row = featureRow(name, "$state\n$activity\n$count\n$detail", R.drawable.ic_protocol_link, "") as LinearLayout
        row.getChildAt(row.childCount - 1).visibility = View.GONE
        featureContent.addView(row)
    }
}
