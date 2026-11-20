package com.galaxyssi.chat

import android.content.Context
import java.text.NumberFormat

internal object HealthAtlasPhysiologyText {
    fun title(kind: HealthAtlasPhysiologyKind) = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> R.string.health_atlas_model_ventilation
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> R.string.health_atlas_model_renal
        HealthAtlasPhysiologyKind.POTASSIUM -> R.string.health_atlas_model_potassium
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> R.string.health_atlas_model_oxygen
        HealthAtlasPhysiologyKind.ELBOW_BALANCE -> R.string.health_atlas_elbow_title
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> R.string.health_atlas_vessel_title
        HealthAtlasPhysiologyKind.EYE_FOCUS -> R.string.health_atlas_eye_title
    }
    fun scope(kind: HealthAtlasPhysiologyKind) = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> R.string.health_atlas_model_ventilation_scope
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> R.string.health_atlas_model_renal_scope
        HealthAtlasPhysiologyKind.POTASSIUM -> R.string.health_atlas_model_potassium_scope
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> R.string.health_atlas_model_oxygen_scope
        HealthAtlasPhysiologyKind.ELBOW_BALANCE -> R.string.health_atlas_elbow_scope
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> R.string.health_atlas_vessel_scope
        HealthAtlasPhysiologyKind.EYE_FOCUS -> R.string.health_atlas_eye_scope
    }
    fun formula(kind: HealthAtlasPhysiologyKind) = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> R.string.health_atlas_model_ventilation_formula
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> R.string.health_atlas_model_renal_formula
        HealthAtlasPhysiologyKind.POTASSIUM -> R.string.health_atlas_model_potassium_formula
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> R.string.health_atlas_model_oxygen_formula
        HealthAtlasPhysiologyKind.ELBOW_BALANCE -> R.string.health_atlas_elbow_formula
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> R.string.health_atlas_vessel_formula
        HealthAtlasPhysiologyKind.EYE_FOCUS -> R.string.health_atlas_eye_formula
    }
    fun label(key: String) = when (key) {
        "rate" -> R.string.health_atlas_rate
        "tidal" -> R.string.health_atlas_tidal
        "dead-space" -> R.string.health_atlas_model_dead_space
        "filtered" -> R.string.health_atlas_model_filtered
        "reabsorbed" -> R.string.health_atlas_model_reabsorbed
        "secreted" -> R.string.health_atlas_model_secreted
        "outside" -> R.string.health_atlas_model_outside
        "inside" -> R.string.health_atlas_model_inside
        "oxygen-pressure" -> R.string.health_atlas_model_oxygen_pressure
        "p50" -> R.string.health_atlas_model_p50
        "hemoglobin" -> R.string.health_atlas_model_hemoglobin
        "elbow-load" -> R.string.health_atlas_elbow_load
        "elbow-load-arm" -> R.string.health_atlas_elbow_load_arm
        "elbow-muscle-arm" -> R.string.health_atlas_elbow_muscle_arm
        "vessel-pressure" -> R.string.health_atlas_vessel_pressure
        "vessel-radius" -> R.string.health_atlas_vessel_radius
        "vessel-length" -> R.string.health_atlas_vessel_length
        "vessel-viscosity" -> R.string.health_atlas_vessel_viscosity
        "eye-distance" -> R.string.health_atlas_eye_object_distance
        "eye-power" -> R.string.health_atlas_eye_power
        else -> error("Unknown physiology input: $key")
    }
    fun unit(key: String) = when (key) {
        "rate" -> "/min"
        "tidal", "dead-space" -> "mL"
        "filtered", "secreted" -> "mg/min"
        "reabsorbed" -> "%"
        "outside", "inside" -> "mmol/L"
        "oxygen-pressure", "p50" -> "mmHg"
        "hemoglobin" -> "g/L"
        "elbow-load" -> "kg"
        "elbow-load-arm" -> "cm"
        "elbow-muscle-arm" -> "mm"
        "vessel-pressure" -> "mmHg"
        "vessel-radius", "vessel-length" -> "mm"
        "vessel-viscosity" -> "mPa s"
        "eye-distance" -> "m"
        "eye-power" -> "D"
        else -> error("Unknown physiology input: $key")
    }
    fun number(value: Double, digits: Int = 2): String = NumberFormat.getNumberInstance().apply {
        maximumFractionDigits = digits
    }.format(value)
    fun result(context: Context, model: HealthAtlasPhysiology) = context.getString(title(model.kind)) +
        ": " + resultNumber(model, model.result) + " " + model.kind.unit
    fun resultNumber(model: HealthAtlasPhysiology, value: Double) = when (model.kind) {
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> number(value, 6)
        HealthAtlasPhysiologyKind.EYE_FOCUS -> HealthAtlasEyeOpticsText.offsetNumber(value)
        else -> number(value)
    }
    fun inputNumber(key: String, value: Double) = number(value, if (key == "vessel-radius") 3 else 2)
    fun companion(context: Context, model: HealthAtlasPhysiology): String {
        model.oxygenAmounts?.let {
            return context.getString(R.string.health_atlas_model_oxygen_content,
                number(it.total), number(it.bound), number(it.dissolved))
        }
        return context.getString(when (model.kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> R.string.health_atlas_model_total_ventilation
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> R.string.health_atlas_model_reabsorbed_amount
        HealthAtlasPhysiologyKind.POTASSIUM -> R.string.health_atlas_model_concentration_ratio
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> error("Oxygen amounts required")
        HealthAtlasPhysiologyKind.ELBOW_BALANCE -> R.string.health_atlas_elbow_joint
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> R.string.health_atlas_vessel_resistance
        HealthAtlasPhysiologyKind.EYE_FOCUS -> R.string.health_atlas_eye_target_power
    }, number(model.companionValue, if (model.kind == HealthAtlasPhysiologyKind.POTASSIUM) 4 else 2))
    }
    fun sourceTitle(kind: HealthAtlasPhysiologyKind, index: Int): Int = if (kind == HealthAtlasPhysiologyKind.OXYGEN_BINDING) {
        if (index == 0) R.string.health_atlas_model_oxygen_binding_source else R.string.health_atlas_model_oxygen_content_source
    } else if (kind == HealthAtlasPhysiologyKind.VESSEL_FLOW) when (index) {
        1 -> R.string.health_atlas_vessel_profile_source
        2 -> R.string.health_atlas_vessel_units_source
        else -> R.string.health_atlas_model_source
    } else R.string.health_atlas_model_source
    fun input(context: Context, model: HealthAtlasPhysiology, index: Int): String {
        val key = model.kind.inputs[index].key
        return context.getString(label(key)) + ": " + inputNumber(key, model.input(index)) + " " + unit(key)
    }
    fun context(context: Context, model: HealthAtlasPhysiology): String = buildString {
        appendLine(context.getString(R.string.health_atlas_model_synthetic))
        appendLine(context.getString(scope(model.kind)))
        model.inputs.indices.forEach { appendLine(input(context, model, it)) }
        appendLine(result(context, model)); appendLine(companion(context, model))
        model.renalAmounts?.let { appendLine(HealthAtlasRenalText.context(context, it)) }
        model.elbowForces?.let { appendLine(HealthAtlasElbowText.context(context, it)) }
        model.vesselFlow?.let { appendLine(HealthAtlasVesselFlowText.context(context, it)) }
        model.eyeOptics?.let { appendLine(HealthAtlasEyeOpticsText.context(context, it)) }
        appendLine(context.getString(formula(model.kind))); append(model.kind.sources.joinToString("\n"))
    }
}
