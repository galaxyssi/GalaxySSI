package com.galaxyssi.chat

import android.os.Bundle

internal class HealthAtlasFunctionState {
    private val selections = linkedMapOf<String, HealthAtlasFunctionStory>()
    private val phases = linkedMapOf<Pair<String, HealthAtlasFunctionStory>, Float>()

    fun current(id: String) = selections[id] ?: HealthAtlasFunctionStory.forId(id)
    fun choose(id: String, story: HealthAtlasFunctionStory) {
        if (story in HealthAtlasFunctionStory.choicesForId(id)) selections[id] = story
    }

    fun loadPhase(id: String, story: HealthAtlasFunctionStory) = phases[id to story] ?: story.entryPhase(id)
    fun savePhase(id: String, story: HealthAtlasFunctionStory, phase: Float) {
        if (story in HealthAtlasFunctionStory.choicesForId(id))
            phases[id to story] = HealthAtlasFunctionStory.safePhase(phase)
    }

    fun restore(saved: Bundle?, legacy: Bundle?) {
        if (legacy != null) for (id in legacy.keySet()) {
            HealthAtlasFunctionStory.forId(id)?.let { savePhase(id, it, legacy.getFloat(id)) }
        }
        if (saved != null) for (id in saved.keySet()) {
            val entry = saved.getBundle(id) ?: continue
            val allowed = HealthAtlasFunctionStory.choicesForId(id)
            allowed.firstOrNull { it.name == entry.getString("selected") }?.let { choose(id, it) }
            for (story in allowed) if (entry.containsKey(story.name)) savePhase(id, story, entry.getFloat(story.name))
        }
    }

    fun snapshot() = Bundle().apply {
        val saved = linkedMapOf<String, Bundle>()
        selections.forEach { (id, story) -> saved.getOrPut(id, ::Bundle).putString("selected", story.name) }
        phases.forEach { (key, phase) -> saved.getOrPut(key.first, ::Bundle).putFloat(key.second.name, phase) }
        saved.forEach { (id, entry) -> putBundle(id, entry) }
    }
}
