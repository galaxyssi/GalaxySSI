package com.galaxyssi.chat

import kotlin.math.ln
import kotlin.math.expm1
import kotlin.math.pow

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
        "https://pmc.ncbi.nlm.nih.gov/articles/PMC3485568/"),
    ELBOW_BALANCE(listOf(HealthAtlasInput("elbow-load", 0..100, 40, 10.0),
        HealthAtlasInput("elbow-load-arm", 20..50, 38), HealthAtlasInput("elbow-muscle-arm", 20..60, 40)),
        0, "N", 0.0, 2700.0,
        "https://openstax.org/books/college-physics-2e/pages/9-6-forces-and-torques-in-muscles-and-joints"),
    VESSEL_FLOW(listOf(HealthAtlasInput("vessel-pressure", 0..20, 10),
        HealthAtlasInput("vessel-radius", 50..200, 100, 1000.0), HealthAtlasInput("vessel-length", 20..100, 50),
        HealthAtlasInput("vessel-viscosity", 20..60, 35, 10.0)), 1, "mL/min", 0.0, 3.0,
        HealthAtlasVesselFlow.SOURCE, HealthAtlasVesselFlow.PROFILE_SOURCE),
    EYE_FOCUS(listOf(HealthAtlasInput("eye-distance", 25..600, 100, 100.0),
        HealthAtlasInput("eye-power", 5500..6500, 5982, 100.0)), 1, "mm", -3.0, 3.0,
        HealthAtlasEyeOptics.SOURCE),
    MIDDLE_EAR(listOf(HealthAtlasInput("ear-input-area", 35..75, 55),
        HealthAtlasInput("ear-output-area", 20..50, 32, 10.0),
        HealthAtlasInput("ear-lever", 100..160, 130, 100.0)), 0, "\u00d7", 0.0, 60.0,
        HealthAtlasMiddleEar.SOURCE, HealthAtlasMiddleEar.MEASUREMENT_SOURCE),
    VENTRICULAR_EJECTION(listOf(HealthAtlasInput("ejection-stroke", 0..180, 70),
        HealthAtlasInput("ejection-residual", 5..180, 60)), 0, "%", 0.0, 100.0,
        HealthAtlasHeartSection.EJECTION_SOURCE),
    NERVE_TRANSIT(listOf(HealthAtlasInput("nerve-distance", 10..150, 60),
        HealthAtlasInput("nerve-speed", 1..120, 50)), 0, "ms", 0.0, 1500.0,
        "https://www.ncbi.nlm.nih.gov/books/NBK10921/"),
    ALVEOLAR_SURFACE(listOf(HealthAtlasInput("alveolar-tension", 5..35, 15),
        HealthAtlasInput("alveolar-radius", 50..200, 100)), 0, "Pa", 0.0, 1400.0,
        "https://pubmed.ncbi.nlm.nih.gov/20724566/"),
    BICARBONATE_MIX(listOf(HealthAtlasInput("bicarb-flow", 0..40, 10, 10.0),
        HealthAtlasInput("bicarb-concentration", 20..120, 80)), 1, "mmol/L", 0.0, 100.0,
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-6-accessory-organs-in-digestion-the-liver-pancreas-and-gallbladder"),
    THYROID_FEEDBACK(listOf(HealthAtlasInput("feedback-drive", 20..100, 80),
        HealthAtlasInput("feedback-gain", 0..300, 100, 100.0)), 0, "%", 0.0, 100.0,
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-4-the-thyroid-gland"),
    PHOTON_CAPTURE(listOf(HealthAtlasInput("photon-mean", 0..500, 100, 100.0)), 0, "%", 0.0, 100.0,
        "https://www.itl.nist.gov/div898/handbook/eda/section3/eda366j.htm", "https://pubmed.ncbi.nlm.nih.gov/112243/"),
    SWEAT_EVAPORATION(listOf(HealthAtlasInput("sweat-mass", 0..200, 60, 10.0),
        HealthAtlasInput("sweat-evaporated", 0..100, 50)), 0, "W", 0.0, 900.0,
        "https://pubmed.ncbi.nlm.nih.gov/23459754/"),
    LYMPH_VALVE(listOf(HealthAtlasInput("lymph-pressure", -40..40, 20, 10.0),
        HealthAtlasInput("lymph-resistance", 20..200, 40, 10.0)), 0, "mL/min", 0.0, 2.0,
        "https://pmc.ncbi.nlm.nih.gov/articles/PMC4500195/"),
    VILLUS_AREA(listOf(HealthAtlasInput("villus-density", 0..24, 12),
        HealthAtlasInput("villus-radius", 25..70, 45, 1000.0),
        HealthAtlasInput("villus-height", 20..120, 60, 100.0)), 0, "\u00d7", 1.0, 14.0,
        "https://pubmed.ncbi.nlm.nih.gov/24694282/"),
    ALVEOLAR_DIFFUSION(listOf(HealthAtlasInput("diffusion-gradient", 0..200, 100, 100.0),
        HealthAtlasInput("diffusion-area", 50..200, 100, 100.0),
        HealthAtlasInput("diffusion-thickness", 50..200, 100, 100.0)), 0, "\u00d7", 0.0, 8.0,
        "https://pubmed.ncbi.nlm.nih.gov/8210754/", "https://pmc.ncbi.nlm.nih.gov/articles/PMC2106384/"),
    CARTILAGE_COMPRESSION(listOf(HealthAtlasInput("cartilage-stress", 0..64, 32),
        HealthAtlasInput("cartilage-modulus", 80..240, 160, 100.0)), 0, "%", 0.0, 8.0,
        "https://pubmed.ncbi.nlm.nih.gov/7054208/", "https://pubmed.ncbi.nlm.nih.gov/7382457/");

    val sources get() = listOfNotNull(source, extraSource) +
        if (this == VESSEL_FLOW) listOf(HealthAtlasVesselFlow.UNIT_SOURCE) else emptyList()

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
            "skeletal", "muscle", "biceps-brachii", "humerus", "radius", "ulna" -> ELBOW_BALANCE
            "blood-vessels", "arteries", "veins", "coronary-vessels" -> VESSEL_FLOW
            "eye", "lens" -> EYE_FOCUS
            "ear", "middle-ear" -> MIDDLE_EAR
            "ventricles", "right-ventricle", "left-ventricle" -> VENTRICULAR_EJECTION
            "peripheral-nerves", "spinal-nerves", "cranial-nerves" -> NERVE_TRANSIT
            "cell-type-ii-pneumocyte" -> ALVEOLAR_SURFACE
            "pancreas", "pancreatic-duct", "cell-pancreatic-ductal-cell" -> BICARBONATE_MIX
            "thyroid-gland" -> THYROID_FEEDBACK
            "cell-rod-photoreceptor" -> PHOTON_CAPTURE
            "sweat-glands" -> SWEAT_EVAPORATION
            "lymphatic-vessels" -> LYMPH_VALVE
            "small-intestine", "jejunum" -> VILLUS_AREA
            "respiratory-membrane", "pulmonary-capillaries", "tissue-alveolar-epithelium",
            "cell-type-i-pneumocyte" -> ALVEOLAR_DIFFUSION
            "cartilage", "tissue-hyaline-cartilage", "cell-chondrocyte" -> CARTILAGE_COMPRESSION
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
        HealthAtlasPhysiologyKind.ELBOW_BALANCE -> requireNotNull(elbowForces).jointDown
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> requireNotNull(vesselFlow).resistanceMmHgMinutesPerMl
        HealthAtlasPhysiologyKind.EYE_FOCUS -> requireNotNull(eyeOptics).targetPowerDiopters
        HealthAtlasPhysiologyKind.MIDDLE_EAR -> requireNotNull(middleEar).pressureGainDb
        HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION -> input(0) + input(1)
        HealthAtlasPhysiologyKind.NERVE_TRANSIT -> 100.0 / input(1)
        HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE -> result / 2.0
        HealthAtlasPhysiologyKind.BICARBONATE_MIX -> bicarbonateDelivery(input(0), input(1))
        HealthAtlasPhysiologyKind.THYROID_FEEDBACK -> input(0) - result
        HealthAtlasPhysiologyKind.PHOTON_CAPTURE -> 100.0 * kotlin.math.exp(-input(0))
        HealthAtlasPhysiologyKind.SWEAT_EVAPORATION -> evaporatedMass(input(0), input(1))
        HealthAtlasPhysiologyKind.LYMPH_VALVE -> input(0) / input(1)
        HealthAtlasPhysiologyKind.VILLUS_AREA -> result - 1.0
        HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION -> input(1) / input(2)
        HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION -> 100.0 - result
    }
    val oxygenAmounts: HealthAtlasOxygen.Amounts? get() = if (kind == HealthAtlasPhysiologyKind.OXYGEN_BINDING)
        HealthAtlasOxygen.amounts(input(0), input(1), input(2)) else null
    val renalAmounts: HealthAtlasRenal.Amounts? get() = if (kind == HealthAtlasPhysiologyKind.RENAL_EXCRETION)
        HealthAtlasRenal.amounts(input(0), input(1), input(2)) else null
    val elbowForces: HealthAtlasElbow.Forces? get() = if (kind == HealthAtlasPhysiologyKind.ELBOW_BALANCE)
        HealthAtlasElbow.forces(input(0), input(1), input(2)) else null
    val vesselFlow: HealthAtlasVesselFlow? get() = if (kind == HealthAtlasPhysiologyKind.VESSEL_FLOW)
        HealthAtlasVesselFlow(input(0), input(1), input(2), input(3)) else null
    val eyeOptics: HealthAtlasEyeOptics? get() = if (kind == HealthAtlasPhysiologyKind.EYE_FOCUS)
        HealthAtlasEyeOptics(input(0), input(1)) else null
    val middleEar: HealthAtlasMiddleEar? get() = if (kind == HealthAtlasPhysiologyKind.MIDDLE_EAR)
        HealthAtlasMiddleEar(input(0), input(1), input(2)) else null
    val plotMaximum: Double get() = when (kind) {
        HealthAtlasPhysiologyKind.ELBOW_BALANCE -> kotlin.math.ceil(resultAt(axisRange.endInclusive) / 100.0) * 100.0
        HealthAtlasPhysiologyKind.NERVE_TRANSIT -> kotlin.math.ceil(resultAt(axisRange.endInclusive) / 10.0) * 10.0
        HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE -> kotlin.math.ceil(resultAt(axisRange.endInclusive) / 100.0) * 100.0
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> {
            val peak = resultAt(axisRange.endInclusive)
            if (peak == 0.0) .01 else {
                val scale = 10.0.pow(kotlin.math.floor(kotlin.math.log10(peak)))
                kotlin.math.ceil(peak / scale) * scale
            }
        }
        else -> kind.maximum
    }
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
        HealthAtlasPhysiologyKind.ELBOW_BALANCE -> HealthAtlasElbow.forces(values[0], values[1], values[2]).muscle
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> HealthAtlasVesselFlow(values[0], values[1], values[2], values[3]).flowMlPerMinute
        HealthAtlasPhysiologyKind.EYE_FOCUS -> HealthAtlasEyeOptics(values[0], values[1]).offsetMm
        HealthAtlasPhysiologyKind.MIDDLE_EAR -> HealthAtlasMiddleEar(values[0], values[1], values[2]).pressureRatio
        HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION -> 100.0 * values[0] / (values[0] + values[1])
        HealthAtlasPhysiologyKind.NERVE_TRANSIT -> 10.0 * values[0] / values[1]
        // 2 * tension / radius, converting mN/m and micrometres to SI.
        HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE -> 2000.0 * values[0] / values[1]
        HealthAtlasPhysiologyKind.BICARBONATE_MIX -> bicarbonateDelivery(values[0], values[1]) / (1.0 + values[0])
        // Dimensionless static example: output = input - gain * output.
        HealthAtlasPhysiologyKind.THYROID_FEEDBACK -> values[0] / (1.0 + values[1])
        HealthAtlasPhysiologyKind.PHOTON_CAPTURE -> -100.0 * expm1(-values[0])
        // Convert g/min to g/s and apply the example latent heat at 30 C.
        HealthAtlasPhysiologyKind.SWEAT_EVAPORATION -> evaporatedMass(values[0], values[1]) * 2426.0 / 60.0
        HealthAtlasPhysiologyKind.LYMPH_VALVE -> maxOf(values[0], 0.0) / values[1]
        HealthAtlasPhysiologyKind.VILLUS_AREA -> 1.0 + values[0] * 2.0 * Math.PI * values[1] * values[2]
        HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION -> values[0] * values[1] / values[2]
        // Convert modulus from MPa to kPa and strain from a fraction to percent.
        HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION -> values[0] / (10.0 * values[1])
    }
    companion object {
        private fun evaporatedMass(mass: Double, fractionPercent: Double) = mass * fractionPercent / 100.0
        // 1 mL/min at 20 mmol/L delivers 20 micromoles per minute.
        private fun bicarbonateDelivery(ductFlow: Double, ductConcentration: Double) = 20.0 + ductFlow * ductConcentration
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
