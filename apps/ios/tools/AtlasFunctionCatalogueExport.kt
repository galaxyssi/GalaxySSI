package com.galaxyssi.chat

private fun key(id: Int) = ResourceNames.keys[id - 1]
private fun quote(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r") + "\""
private fun json(value: Any?): String = when (value) {
    null -> "null"
    is String -> quote(value)
    is Number, is Boolean -> value.toString()
    is Map<*, *> -> value.entries.joinToString(",", "{", "}") { quote(it.key.toString()) + ":" + json(it.value) }
    is Iterable<*> -> value.joinToString(",", "[", "]") { json(it) }
    else -> error("Unsupported export value")
}

fun main() {
    val ownerField = HealthAtlasFunctionStory::class.java.getDeclaredField("owners").apply { isAccessible = true }
    val all = HealthAtlasFunctionStory.entries
    @Suppress("UNCHECKED_CAST")
    val owners = all.flatMap { (ownerField.get(it) as Set<String>).toList() }.distinct()
    val stories = all.map { story -> mapOf(
        "id" to story.name, "owners" to ownerField.get(story), "title" to key(story.title),
        "choiceTitle" to key(story.choiceTitle), "scope" to key(story.scope),
        "chapters" to story.chapters.map { mapOf("title" to key(it.first), "caption" to key(it.second)) },
        "references" to story.references.map { mapOf("title" to key(it.first), "url" to it.second) },
        "durationMs" to story.durationMs, "showStructurePreview" to story.showStructurePreview,
        "related" to story.relatedLessons.map { mapOf("entryID" to it.first, "storyID" to it.second.name) }
    ) }
    val routes = owners.associateWith { id -> HealthAtlasFunctionStory.choicesForId(id).map { it.name } }
    val entryPhases = owners.associateWith { id ->
        HealthAtlasFunctionStory.choicesForId(id).associate { it.name to it.entryPhase(id) }
    }
    println(json(mapOf("stories" to stories, "routes" to routes, "entryPhases" to entryPhases)))
}
