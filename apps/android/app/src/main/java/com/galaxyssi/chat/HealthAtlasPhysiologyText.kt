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
        HealthAtlasPhysiologyKind.MIDDLE_EAR -> R.string.health_atlas_middle_ear_pressure_ratio
        HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION -> R.string.health_atlas_ejection_fraction
        HealthAtlasPhysiologyKind.NERVE_TRANSIT -> R.string.health_atlas_nerve_transit
        HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE -> R.string.health_atlas_alveolar_surface
        HealthAtlasPhysiologyKind.BICARBONATE_MIX -> R.string.health_atlas_digestive_bicarb_title
        HealthAtlasPhysiologyKind.THYROID_FEEDBACK -> R.string.health_atlas_endocrine_feedback_title
        HealthAtlasPhysiologyKind.PHOTON_CAPTURE -> R.string.health_atlas_sensory_photon_title
        HealthAtlasPhysiologyKind.SWEAT_EVAPORATION -> R.string.health_atlas_context_evap_title
        HealthAtlasPhysiologyKind.LYMPH_VALVE -> R.string.health_atlas_lymph_valve_model_title
    }
    fun scope(kind: HealthAtlasPhysiologyKind) = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> R.string.health_atlas_model_ventilation_scope
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> R.string.health_atlas_model_renal_scope
        HealthAtlasPhysiologyKind.POTASSIUM -> R.string.health_atlas_model_potassium_scope
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> R.string.health_atlas_model_oxygen_scope
        HealthAtlasPhysiologyKind.ELBOW_BALANCE -> R.string.health_atlas_elbow_scope
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> R.string.health_atlas_vessel_scope
        HealthAtlasPhysiologyKind.EYE_FOCUS -> R.string.health_atlas_eye_scope
        HealthAtlasPhysiologyKind.MIDDLE_EAR -> R.string.health_atlas_middle_ear_scope
        HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION -> R.string.health_atlas_ejection_scope
        HealthAtlasPhysiologyKind.NERVE_TRANSIT -> R.string.health_atlas_nerve_transit_scope
        HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE -> R.string.health_atlas_alveolar_surface_scope
        HealthAtlasPhysiologyKind.BICARBONATE_MIX -> R.string.health_atlas_digestive_bicarb_scope
        HealthAtlasPhysiologyKind.THYROID_FEEDBACK -> R.string.health_atlas_endocrine_feedback_scope
        HealthAtlasPhysiologyKind.PHOTON_CAPTURE -> R.string.health_atlas_sensory_photon_scope
        HealthAtlasPhysiologyKind.SWEAT_EVAPORATION -> R.string.health_atlas_context_evap_scope
        HealthAtlasPhysiologyKind.LYMPH_VALVE -> R.string.health_atlas_lymph_valve_model_scope
    }
    fun formula(kind: HealthAtlasPhysiologyKind) = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> R.string.health_atlas_model_ventilation_formula
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> R.string.health_atlas_model_renal_formula
        HealthAtlasPhysiologyKind.POTASSIUM -> R.string.health_atlas_model_potassium_formula
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> R.string.health_atlas_model_oxygen_formula
        HealthAtlasPhysiologyKind.ELBOW_BALANCE -> R.string.health_atlas_elbow_formula
        HealthAtlasPhysiologyKind.VESSEL_FLOW -> R.string.health_atlas_vessel_formula
        HealthAtlasPhysiologyKind.EYE_FOCUS -> R.string.health_atlas_eye_formula
        HealthAtlasPhysiologyKind.MIDDLE_EAR -> R.string.health_atlas_middle_ear_formula
        HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION -> R.string.health_atlas_ejection_formula
        HealthAtlasPhysiologyKind.NERVE_TRANSIT -> R.string.health_atlas_nerve_transit_formula
        HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE -> R.string.health_atlas_alveolar_surface_formula
        HealthAtlasPhysiologyKind.BICARBONATE_MIX -> R.string.health_atlas_digestive_bicarb_formula
        HealthAtlasPhysiologyKind.THYROID_FEEDBACK -> R.string.health_atlas_endocrine_feedback_formula
        HealthAtlasPhysiologyKind.PHOTON_CAPTURE -> R.string.health_atlas_sensory_photon_formula
        HealthAtlasPhysiologyKind.SWEAT_EVAPORATION -> R.string.health_atlas_context_evap_formula
        HealthAtlasPhysiologyKind.LYMPH_VALVE -> R.string.health_atlas_lymph_valve_model_formula
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
        "ear-input-area" -> R.string.health_atlas_middle_ear_input_area
        "ear-output-area" -> R.string.health_atlas_middle_ear_output_area
        "ear-lever" -> R.string.health_atlas_middle_ear_lever_ratio
        "ejection-stroke" -> R.string.health_atlas_ejection_stroke_volume
        "ejection-residual" -> R.string.health_atlas_ejection_residual_volume
        "nerve-distance" -> R.string.health_atlas_nerve_transit_distance
        "nerve-speed" -> R.string.health_atlas_nerve_transit_speed
        "alveolar-tension" -> R.string.health_atlas_alveolar_tension
        "alveolar-radius" -> R.string.health_atlas_alveolar_radius
        "bicarb-flow" -> R.string.health_atlas_digestive_bicarb_flow
        "bicarb-concentration" -> R.string.health_atlas_digestive_bicarb_concentration
        "feedback-drive" -> R.string.health_atlas_endocrine_feedback_drive
        "feedback-gain" -> R.string.health_atlas_endocrine_feedback_gain
        "photon-mean" -> R.string.health_atlas_sensory_photon_mean
        "sweat-mass" -> R.string.health_atlas_context_evap_rate
        "sweat-evaporated" -> R.string.health_atlas_context_evap_fraction
        "lymph-pressure" -> R.string.health_atlas_lymph_valve_pressure
        "lymph-resistance" -> R.string.health_atlas_lymph_valve_resistance
        else -> error("Unknown physiology input: $key")
    }
    fun unit(key: String) = when (key) {
        "rate" -> "/min"
        "tidal", "dead-space", "ejection-stroke", "ejection-residual" -> "mL"
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
        "ear-input-area", "ear-output-area" -> "mm\u00b2"
        "ear-lever" -> "\u00d7"
        "nerve-distance" -> "cm"
        "nerve-speed" -> "m/s"
        "alveolar-tension" -> "mN/m"
        "alveolar-radius" -> "\u03bcm"
        "bicarb-flow" -> "mL/min"
        "bicarb-concentration" -> "mmol/L"
        "feedback-drive" -> "%"
        "feedback-gain" -> "\u00d7"
        "photon-mean" -> ""
        "sweat-mass" -> "g/min"
        "sweat-evaporated" -> "%"
        "lymph-pressure" -> "mmHg"
        "lymph-resistance" -> "mmHg\u00b7min/mL"
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
        HealthAtlasPhysiologyKind.MIDDLE_EAR -> R.string.health_atlas_middle_ear_gain_db
        HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION -> R.string.health_atlas_ejection_end_diastolic
        HealthAtlasPhysiologyKind.NERVE_TRANSIT -> R.string.health_atlas_nerve_transit_over_ten
        HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE -> R.string.health_atlas_alveolar_surface_double
        HealthAtlasPhysiologyKind.BICARBONATE_MIX -> R.string.health_atlas_digestive_bicarb_companion
        HealthAtlasPhysiologyKind.THYROID_FEEDBACK -> R.string.health_atlas_endocrine_feedback_reduction
        HealthAtlasPhysiologyKind.PHOTON_CAPTURE -> R.string.health_atlas_sensory_photon_zero
        HealthAtlasPhysiologyKind.SWEAT_EVAPORATION -> R.string.health_atlas_context_evap_mass
        HealthAtlasPhysiologyKind.LYMPH_VALVE -> when {
            model.input(0) > 0.0 -> R.string.health_atlas_lymph_valve_model_forward
            model.input(0) < 0.0 -> R.string.health_atlas_lymph_valve_model_closed
            else -> R.string.health_atlas_lymph_valve_model_balance
        }
    }, number(model.companionValue, if (model.kind == HealthAtlasPhysiologyKind.POTASSIUM) 4 else 2))
    }
    fun sourceTitle(kind: HealthAtlasPhysiologyKind, index: Int): Int = if (kind == HealthAtlasPhysiologyKind.OXYGEN_BINDING) {
        if (index == 0) R.string.health_atlas_model_oxygen_binding_source else R.string.health_atlas_model_oxygen_content_source
    } else if (kind == HealthAtlasPhysiologyKind.VESSEL_FLOW) when (index) {
        1 -> R.string.health_atlas_vessel_profile_source
        2 -> R.string.health_atlas_vessel_units_source
        else -> R.string.health_atlas_model_source
    } else if (kind == HealthAtlasPhysiologyKind.MIDDLE_EAR && index == 1) R.string.health_atlas_middle_ear_measurement_source
    else if (kind == HealthAtlasPhysiologyKind.PHOTON_CAPTURE && index == 1) R.string.health_atlas_sensory_photon_photo_source
    else R.string.health_atlas_model_source
    fun input(context: Context, model: HealthAtlasPhysiology, index: Int): String {
        val key = model.kind.inputs[index].key
        val value = inputNumber(key, model.input(index))
        val displayUnit = unit(key)
        return context.getString(label(key)) + ": " + if (displayUnit.isEmpty()) value else "$value $displayUnit"
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
        model.middleEar?.let { appendLine(HealthAtlasMiddleEarText.context(context, it)) }
        appendLine(context.getString(formula(model.kind))); append(model.kind.sources.joinToString("\n"))
    }
}
