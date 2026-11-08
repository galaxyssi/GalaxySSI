package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Reuse saved answers only for their exact measurement revision, without inventing missing answers. */
internal object HealthCareClarificationContext {
    fun current(value: HealthCareConcern): HealthCareContext? = value.context?.takeIf {
        value.assessment.record != null && it.record == value.assessment.record
    }

    fun snapshot(value: HealthCareConcern): JSONObject {
        val context = current(value)
        val known = JSONObject()
        val missing = JSONArray()
        fun truth(key: String, answer: HealthCareTruth?) {
            if (answer == null || answer == HealthCareTruth.UNKNOWN) missing.put(key)
            else known.put(key, answer.name)
        }
        if (value.metric == HealthMetric.GLUCOSE && value.assessment.record != null) {
            truth("adult", context?.adult)
            truth("pregnant", context?.pregnant)
            truth("diagnosed_diabetes", context?.diagnosedDiabetes)
            val specimen = context?.specimen
            if (specimen == null || specimen == HealthCareSpecimen.UNKNOWN) missing.put("specimen")
            else known.put("specimen", specimen.name)
            if (context?.fastingHours == null) missing.put("fasting_hours")
            else known.put("fasting_hours", context.fastingHours)
            truth("illness_or_glucose_affecting_medication", context?.illnessOrMedication)
        }
        return JSONObject().put("source", "saved_health_center")
            .put("record", value.assessment.record?.json() ?: JSONObject.NULL)
            .put("measured_at", value.assessment.measuredAt)
            .put("confirmed_at", context?.confirmedAt ?: JSONObject.NULL)
            .put("context_status", when {
                context != null -> "CURRENT_RECORD"
                value.context != null -> "OTHER_RECORD_OR_REVISION"
                else -> "NOT_CONFIRMED"
            })
            .put("known_answers", known).put("unconfirmed_fields", missing)
            .put("recorded_condition", value.assessment.sample?.condition ?: JSONObject.NULL)
            .put("condition_label_confirms_fasting_hours", false)
            .put("unconfirmed_fields_are_mandatory_questions", false)
            .put("separate_profile_included", false)
            .put("current_symptoms_assessed", false)
    }
}
