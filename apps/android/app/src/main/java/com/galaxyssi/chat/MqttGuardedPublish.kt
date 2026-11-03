package com.galaxyssi.chat

import android.util.Log
import com.galaxyssi.chat.metrics.AgentLatencyTelemetry
import com.galaxyssi.chat.metrics.AgentTransportTiming
import org.eclipse.paho.client.mqttv3.IMqttActionListener
import org.eclipse.paho.client.mqttv3.IMqttDeliveryToken
import org.eclipse.paho.client.mqttv3.IMqttToken
import org.eclipse.paho.client.mqttv3.MqttMessage

internal fun publishSafely(
    mqtt: MqttPoolTransport,
    topic: String,
    message: MqttMessage,
    purpose: String,
    timing: AgentTransportTiming.Attempt? = null,
    delivery: MqttDeliveryDispatch.Delivery? = null,
    publication: MqttPoolTransport.Publication? = null,
    raceTransientControl: Boolean = false,
    onBackpressure: (() -> Unit)? = null
): IMqttDeliveryToken? = MqttPublishGuard.attempt {
    val callback = if (timing == null) null else object : IMqttActionListener {
        override fun onSuccess(asyncActionToken: IMqttToken?) {
            AgentLatencyTelemetry.transport.broker(timing)
        }
        override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) {
            AgentLatencyTelemetry.transport.broker(timing, "failed")
        }
    }
    val token = if (raceTransientControl && delivery == null && publication != null)
        mqtt.publishTransientControl(topic, message, timing, callback, publication)
        else if (delivery == null) mqtt.publish(topic, message, timing, callback, publication)
        else mqtt.publishDelivery(topic, delivery, timing, callback)
    token.exception?.let { throw it }
    token
}.onFailure {
    AgentLatencyTelemetry.transport.broker(timing, "failed")
    if (it is MqttPoolTransport.BackpressureException) onBackpressure?.invoke()
    else Log.w("GalaxySSILink", "MQTT publish deferred purpose=$purpose", it)
}.getOrNull()
