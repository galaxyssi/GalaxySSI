package com.galaxyssi.chat

/** Async consumers keep their lease until durable completion or an explicit retry. */
internal class MqttInboxDispatchGate(private val capacity: Int = 128) {
    private val active = mutableSetOf<String>()

    init { require(capacity > 0) }

    @Synchronized fun acquire(key: String): Boolean =
        key.isNotBlank() && active.size < capacity && active.add(key)

    @Synchronized fun release(key: String) { active.remove(key) }

    @Synchronized fun clear() { active.clear() }
}
