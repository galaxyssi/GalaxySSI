package com.galaxyssi.chat

import kotlin.math.ln

internal data class HealthAtlasInput(val key: String, val range: IntRange, val initial: Int, val scale: Double = 1.0)

internal enum class HealthAtlasPhysiologyKind(val inputs: List<HealthAtlasInput>, val axis: Int, val unit: String,
    val minimum: Double, val maximum: Double, val source: String, val extraSource: String? = null) {
    VENTILATION(listOf(HealthAtlasInput("rate", 6..30, 12), HealthAtlasInput("tidal", 200..900, 500),
        HealthAtlasInput("dead-space", 0..200, 150)), 1, "L/min", 0.0, 27.0,
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-3-the-process-of-breathing"),
    RENAL_EXCRETION(listOf(HealthAtlasInput("filtered", 0..200, 100), HealthAtlasInput("reabsorbed", 0..100, 90),
        HealthAtlasInput("secreted", 0..100, 10)), 1, "mg/min", 0.0, 300.0,
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-6-tubular-reabsorption"),
    POTASSIUM(listOf(HealthAtlasInput("outside", 10..200, 40, 10.0), HealthAtlasInput("inside", 50..200, 140)),
        0, "mV", -150.0, 0.0, "https://neurotext.library.stonybrook.edu/C2/C2_4/C2_4.html"),
    OXYGEN_BINDING(listOf(HealthAtlasInput("oxygen-pressure", 0..150, 100),
        HealthAtlasInput("p50", 150..400, 268, 10.0), HealthAtlasInput("hemoglobin", 50..200, 150)),
        0, "%", 0.0, 100.0, "https://pmc.ncbi.nlm.nih.gov/articles/PMC2862600/",
        "https://pmc.ncbi.nlm.nih.gov/articles/PMC3485568/");

    val sources get() = listOfNotNull(source, extraSource)

    companion object {
        // These are associated whole-process models, not claims that every selected structure performs all steps.
        fun forItem(id: String): HealthAtlasPhysiologyKind? = when (id) {
            "respiratory", "lungs", "alveoli" -> VENTILATION
            "urinary", "kidneys", "nephron", "renal-tubules", "collecting-ducts",
            "proximal-tubule", "nephron-loop", "distal-tubule",
            "cell-proximal-tubular-cell", "cell-distal-tubular-cell",
            "cell-collecting-duct-principal-cell", "cell-collecting-duct-intercalated-cell" -> RENAL_EXCRETION
            "nervous", "brain", "spinal-cord", "cell-neuron", "cell-olfactory-receptor-neuron" -> POTASSIUM
            "blood", "cell-erythrocyte" -> OXYGEN_BINDING
            else -> null
        }
    }
}

/** Synthetic inputs only. These identities neither read records nor estimate patient physiology. */
internal data class HealthAtlasPhysiology(val kind: HealthAtlasPhysiologyKind,
    val inputs: List<Int> = kind.inputs.map { it.initial }) {
    init { require(inputs.size == kind.inputs.size && inputs.indices.all { inputs[it] in kind.inputs[it].range }) }
    fun withInput(index: Int, value: Int): HealthAtlasPhysiology {
        require(index in inputs.indices)
        return copy(inputs = inputs.toMutableList().apply { this[index] = value })
    }
    fun input(index: Int) = inputs[index] / kind.inputs[index].scale
    val result: Double get() = evaluate(inputs.mapIndexed { index, _ -> input(index) })
    val companionValue: Double get() = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> input(0) * input(1) / 1000.0
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> requireNotNull(renalAmounts).reabsorbed
        HealthAtlasPhysiologyKind.POTASSIUM -> input(0) / input(1)
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> requireNotNull(oxygenAmounts).total
    }
    val oxygenAmounts: HealthAtlasOxygen.Amounts? get() = if (kind == HealthAtlasPhysiologyKind.OXYGEN_BINDING)
        HealthAtlasOxygen.amounts(input(0), input(1), input(2)) else null
    val renalAmounts: HealthAtlasRenal.Amounts? get() = if (kind == HealthAtlasPhysiologyKind.RENAL_EXCRETION)
        HealthAtlasRenal.amounts(input(0), input(1), input(2)) else null
    val axisRange get() = kind.inputs[kind.axis].let { it.range.first / it.scale..it.range.last / it.scale }
    fun resultAt(x: Double): Double {
        require(x.isFinite() && x in axisRange)
        return evaluate(inputs.mapIndexed { index, _ -> if (index == kind.axis) x else input(index) })
    }
    private fun evaluate(values: List<Double>): Double = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> values[0] * (values[1] - values[2]) / 1000.0
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> HealthAtlasRenal.amounts(values[0], values[1], values[2]).excreted
        HealthAtlasPhysiologyKind.POTASSIUM -> potassiumPotential(values[0], values[1])
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> 100.0 * HealthAtlasOxygen.saturation(values[0], values[1])
    }
    companion object {
        fun potassiumPotential(outside: Double, inside: Double): Double {
            require(outside.isFinite() && outside > 0 && inside.isFinite() && inside > 0)
            // Nernst, z = +1, T = 310.15 K. Convert volts to millivolts.
            return 8.31446261815324 * 310.15 / 96485.33212 * 1000 * (ln(outside) - ln(inside))
        }
        fun restore(id: String, values: IntArray?): HealthAtlasPhysiology? {
            val kind = HealthAtlasPhysiologyKind.forItem(id) ?: return null
            return values?.let { runCatching { HealthAtlasPhysiology(kind, it.toList()) }.getOrNull() }
        }
    }
}
