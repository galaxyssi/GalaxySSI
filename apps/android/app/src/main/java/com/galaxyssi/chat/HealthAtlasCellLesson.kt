package com.galaxyssi.chat

internal interface HealthAtlasCellLesson {
    val owners: Set<String>
    val title: Int
    val scope: Int
    val choice: Int get() = title
    val chapters: List<Pair<Int, Int>>
    val references: List<Pair<Int, String>>
    val durationMs: Long
    val showStructurePreview: Boolean get() = true
}
