package com.galaxyssi.chat

private fun key(id: Int) = ResourceNames.keys[id - 1]
private fun quote(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r") + "\""
private fun json(value: Any?): String = when (value) {
    null -> "null"
    is String -> quote(value)
    is Number, is Boolean -> value.toString()
    is Map<*, *> -> value.entries.joinToString(",", "{", "}") { quote(it.key.toString()) + ":" + json(it.value) }
    is Iterable<*> -> value.joinToString(",", "[", "]") { json(it) }
    else -> error("Unsupported structure export value")
}
private fun marker(value: HealthAtlasMarker) = mapOf(
    "id" to value.id, "x" to value.x.toDouble(), "y" to value.y.toDouble()
)
fun main() {
    val plates = HealthAtlasTissueContextPlates.all.map { plate ->
        mapOf(
            "id" to requireNotNull(plate.owner), "owner" to plate.owner,
            "drawableName" to DrawableNames.keys[plate.drawable - 1],
            "viewLabel" to key(plate.viewLabel),
            "markers" to plate.markers.map(::marker),
            "source" to plate.source, "viewKey" to plate.viewKey,
            "selectorLabel" to plate.selectorLabel?.let(::key),
            "splitCallouts" to plate.splitCallouts,
            "features" to plate.features.map { mapOf(
                "marker" to marker(it.marker), "title" to key(it.title), "explanation" to key(it.explanation)
            ) }
        )
    }
    println(json(plates))
}
