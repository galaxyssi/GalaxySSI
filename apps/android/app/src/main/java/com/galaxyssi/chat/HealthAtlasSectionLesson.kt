package com.galaxyssi.chat

import android.graphics.Path

internal typealias HealthAtlasSectionTrack = () -> Path

internal fun atlasSectionTrack(x: Float, y: Float, build: Path.() -> Unit): HealthAtlasSectionTrack =
    { Path().apply { moveTo(x, y); build() } }

internal data class HealthAtlasSectionLesson(val plate: HealthAtlasPlate, val stageFeatures: List<Int>,
    val tracks: List<HealthAtlasSectionTrack>, val notes: List<Int>, val artWidth: Int = 360) {
    val owner get() = requireNotNull(plate.owner)
    init {
        require(artWidth > 0)
        require(stageFeatures.size == 4 && stageFeatures.all { it in plate.features.indices })
        require(tracks.isEmpty() || tracks.size == stageFeatures.size)
    }

    companion object {
        fun forId(id: String?) = HealthAtlasLymphOrgans[id] ?: HealthAtlasGutSections[id] ?: HealthAtlasSensorySections[id]
    }
}
