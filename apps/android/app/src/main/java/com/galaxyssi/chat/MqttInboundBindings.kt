package com.galaxyssi.chat

/** Topic aliases are only lookup keys. Signal serialization belongs to the configured peer identity. */
internal class MqttInboundBindings {
    @Volatile private var scopes = emptyMap<String, String>()

    fun replace(relationships: List<Pair<String, Set<String>>>, rendezvous: Set<String>) {
        val next = mutableMapOf<String, String>()
        val conflicts = mutableSetOf<String>()
        fun bind(topic: String, scope: String) {
            require(topic.isNotBlank() && topic.length <= 507 && '#' !in topic && '+' !in topic)
            val previous = next.put(topic, scope)
            if (previous != null && previous != scope) conflicts.add(topic)
        }
        relationships.forEach { (identity, topics) ->
            require(identity.isNotBlank() && identity.length <= 480)
            topics.forEach { bind(it, "signal:$identity") }
        }
        rendezvous.forEach { bind(it, "pair:$it") }
        conflicts.forEach(next::remove)
        scopes = next.toMap()
    }

    fun scope(topic: String): String? = scopes[topic]
}
