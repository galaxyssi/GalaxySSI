package com.galaxyssi.chat

internal data class HealthAtlasTeachingInput(
    val control: HealthAtlasInput,
    val label: Int,
    val unit: String,
    val digits: Int = 2,
) {
    init {
        require(control.key.isNotBlank() && control.range.first < control.range.last)
        require(control.initial in control.range && control.scale.isFinite() && control.scale > 0)
        require(digits in 0..6)
    }
}

internal data class HealthAtlasTeachingModelSpec(
    val inputs: List<HealthAtlasTeachingInput>,
    val axis: Int,
    val unit: String,
    val minimum: Double,
    val maximum: Double,
    val source: String,
    val title: Int,
    val scope: Int,
    val formula: Int,
    val companionTitle: Int,
    val entryIds: Set<String>,
    val evaluate: (List<Double>) -> Double,
    val companionValue: (List<Double>) -> Double,
    val extraSource: String? = null,
    val digits: Int = 2,
) {
    init {
        require(axis in inputs.indices && inputs.map { it.control.key }.distinct().size == inputs.size)
        require(minimum.isFinite() && maximum.isFinite() && minimum < maximum)
        require(source.startsWith("https://") && extraSource?.startsWith("https://") != false)
        require(entryIds.isNotEmpty() && entryIds.none(String::isBlank))
        require(digits in 0..6)
    }
}
