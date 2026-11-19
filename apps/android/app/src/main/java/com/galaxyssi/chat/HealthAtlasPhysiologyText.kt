package com.galaxyssi.chat

import android.content.Context
import java.text.NumberFormat

internal object HealthAtlasPhysiologyText {
    fun title(kind: HealthAtlasPhysiologyKind) = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> R.string.health_atlas_model_ventilation
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> R.string.health_atlas_model_renal
        HealthAtlasPhysiologyKind.POTASSIUM -> R.string.health_atlas_model_potassium
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> R.string.health_atlas_model_oxygen
    }
    fun scope(kind: HealthAtlasPhysiologyKind) = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> R.string.health_atlas_model_ventilation_scope
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> R.string.health_atlas_model_renal_scope
        HealthAtlasPhysiologyKind.POTASSIUM -> R.string.health_atlas_model_potassium_scope
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> R.string.health_atlas_model_oxygen_scope
    }
    fun formula(kind: HealthAtlasPhysiologyKind) = when (kind) {
        HealthAtlasPhysiologyKind.VENTILATION -> R.string.health_atlas_model_ventilation_formula
        HealthAtlasPhysiologyKind.RENAL_EXCRETION -> R.string.health_atlas_model_renal_formula
        HealthAtlasPhysiologyKind.POTASSIUM -> R.string.health_atlas_model_potassium_formula
        HealthAtlasPhysiologyKind.OXYGEN_BINDING -> R.string.health_atlas_model_oxygen_formula
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
        else -> error("Unknown physiology input: $key")
    }
    fun number(value: Double, digits: Int = 2): String = NumberFormat.getNumberInstance().apply {
        maximumFractionDigits = digits
    }.format(value)
    fun result(context: Context, model: HealthAtlasPhysiology) = context.getString(title(model.kind)) +
        ": " + number(model.result) + " " + model.kind.unit
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
    }, number(model.companionValue, if (model.kind == HealthAtlasPhysiologyKind.POTASSIUM) 4 else 2))
    }
    fun sourceTitle(kind: HealthAtlasPhysiologyKind, index: Int): Int = if (kind == HealthAtlasPhysiologyKind.OXYGEN_BINDING) {
        if (index == 0) R.string.health_atlas_model_oxygen_binding_source else R.string.health_atlas_model_oxygen_content_source
    } else R.string.health_atlas_model_source
    fun input(context: Context, model: HealthAtlasPhysiology, index: Int): String {
        val key = model.kind.inputs[index].key
        return context.getString(label(key)) + ": " + number(model.input(index)) + " " + unit(key)
    }
    fun context(context: Context, model: HealthAtlasPhysiology): String = buildString {
        appendLine(context.getString(R.string.health_atlas_model_synthetic))
        appendLine(context.getString(scope(model.kind)))
        model.inputs.indices.forEach { appendLine(input(context, model, it)) }
        appendLine(result(context, model)); appendLine(companion(context, model))
        model.renalAmounts?.let { appendLine(HealthAtlasRenalText.context(context, it)) }
        appendLine(context.getString(formula(model.kind))); append(model.kind.sources.joinToString("\n"))
    }
}
