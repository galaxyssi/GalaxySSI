package com.galaxyssi.chat

import android.view.View
import android.widget.LinearLayout

internal fun MainActivity.addMqttDeliveryDiagnostics() {
    val snapshot = GalaxySSIMqttClient.transportDiagnostics()
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
        val count = getString(R.string.mqtt_diagnostics_sample_count, stats?.samples ?: 0)
        val row = featureRow(name, "$count\n$detail", R.drawable.ic_protocol_link, "") as LinearLayout
        row.getChildAt(row.childCount - 1).visibility = View.GONE
        featureContent.addView(row)
    }
}
