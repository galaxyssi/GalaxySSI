package com.signalasi.chat

import android.util.Log
import org.eclipse.paho.client.mqttv3.IMqttActionListener
import org.eclipse.paho.client.mqttv3.IMqttToken
import org.eclipse.paho.client.mqttv3.MqttAsyncClient
import java.util.concurrent.ConcurrentHashMap

/** Keeps the broker subscription set equal to the current opaque receive windows. */
internal class SignalASILinkSubscriptionCoordinator(
    private val qos: Int,
    private val onAttemptCompleted: (generation: Int, succeeded: Boolean) -> Unit
) {
    private val activeTopics = ConcurrentHashMap.newKeySet<String>()

    fun reconcile(
        mqtt: MqttAsyncClient,
        links: List<SignalASILinkProtocol.ServerLink>,
        phoneTopics: Set<String>,
        rendezvousTopics: Set<String>,
        generation: Int
    ) {
        val expectedTopics = buildSet {
            links.forEach { addAll(it.routes.receiveWindow) }
            addAll(phoneTopics)
            addAll(rendezvousTopics)
        }
        unsubscribeStale(mqtt, expectedTopics)
        links.forEach { link ->
            subscribe(
                mqtt,
                link.routes.receiveWindow,
                "desktop_${link.desktopId.takeLast(8)}",
                generation
            )
        }
        if (phoneTopics.isNotEmpty()) {
            subscribe(mqtt, phoneTopics, "phone_relationships", generation)
        }
        if (rendezvousTopics.isNotEmpty()) {
            subscribe(mqtt, rendezvousTopics, "phone_rendezvous", generation)
        }
    }

    fun unsubscribe(mqtt: MqttAsyncClient, topics: Set<String>, label: String) {
        if (topics.isEmpty()) return
        runCatching {
            mqtt.unsubscribe(
                topics.toTypedArray(),
                topics,
                object : IMqttActionListener {
                    override fun onSuccess(asyncActionToken: IMqttToken?) {
                        activeTopics.removeAll(topics)
                    }

                    override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) {
                        Log.w(TAG, "Opaque mailbox unsubscribe failed scope=$label", exception)
                    }
                }
            )
        }.onFailure { Log.w(TAG, "Opaque mailbox unsubscribe could not start scope=$label", it) }
    }

    fun invalidate() {
        activeTopics.clear()
    }

    private fun subscribe(
        mqtt: MqttAsyncClient,
        topics: Set<String>,
        scope: String,
        generation: Int
    ) {
        runCatching {
            mqtt.subscribe(
                topics.toTypedArray(),
                IntArray(topics.size) { qos },
                scope,
                object : IMqttActionListener {
                    override fun onSuccess(asyncActionToken: IMqttToken?) {
                        activeTopics.addAll(topics)
                        onAttemptCompleted(generation, true)
                    }

                    override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) {
                        Log.w(TAG, "Opaque mailbox subscription failed scope=$scope", exception)
                        onAttemptCompleted(generation, false)
                    }
                }
            )
        }.onFailure {
            Log.w(TAG, "Opaque mailbox subscription could not start scope=$scope", it)
            onAttemptCompleted(generation, false)
        }
    }

    private fun unsubscribeStale(mqtt: MqttAsyncClient, expectedTopics: Set<String>) {
        unsubscribe(
            mqtt,
            activeTopics.filterNot(expectedTopics::contains).toSet(),
            "expired_rotation_window"
        )
    }

    private companion object {
        const val TAG = "SignalASILink"
    }
}
