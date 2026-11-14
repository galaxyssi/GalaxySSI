package com.galaxyssi.chat

import java.text.Normalizer
import java.util.Locale

internal enum class HealthMetricGroup { CARDIOVASCULAR, METABOLIC, SLEEP, ACTIVITY, BODY, BLOOD, LIVER, KIDNEY, THYROID, URINE }
internal data class HealthMetricEntry(val metric: HealthMetric, val group: HealthMetricGroup, val laboratory: Boolean,
    val english: String, val chinese: String, val aliases: List<String> = emptyList())

internal object HealthMetricCatalog {
    private fun entry(m: HealthMetric, g: HealthMetricGroup, lab: Boolean, en: String, zh: String, vararg aliases: String) =
        HealthMetricEntry(m, g, lab, en, zh, aliases.toList())
    val entries = listOf(
        entry(HealthMetric.BLOOD_PRESSURE, HealthMetricGroup.CARDIOVASCULAR, false, "Blood pressure", "\u8840\u538b", "BP", "systolic", "diastolic"),
        entry(HealthMetric.GLUCOSE, HealthMetricGroup.METABOLIC, true, "Blood glucose", "\u8840\u7cd6", "GLU", "FPG", "fasting glucose", "\u8461\u8404\u7cd6", "\u7a7a\u8179\u8840\u7cd6"),
        entry(HealthMetric.WEIGHT, HealthMetricGroup.BODY, false, "Weight", "\u4f53\u91cd", "body weight"),
        entry(HealthMetric.HEART_RATE, HealthMetricGroup.CARDIOVASCULAR, false, "Heart rate", "\u5fc3\u7387", "HR", "pulse", "\u8109\u640f"),
        entry(HealthMetric.CHOLESTEROL, HealthMetricGroup.METABOLIC, true, "Total cholesterol", "\u603b\u80c6\u56fa\u9187", "TC", "CHOL"),
        entry(HealthMetric.HEMOGLOBIN, HealthMetricGroup.BLOOD, true, "Hemoglobin", "\u8840\u7ea2\u86cb\u767d", "HGB", "Hb"),
        entry(HealthMetric.RESTING_HEART_RATE, HealthMetricGroup.CARDIOVASCULAR, false, "Resting heart rate", "\u9759\u606f\u5fc3\u7387", "RHR", "resting pulse"),
        entry(HealthMetric.SLEEP_DURATION, HealthMetricGroup.SLEEP, false, "Sleep duration", "\u7761\u7720\u65f6\u957f", "sleep", "\u7761\u7720"),
        entry(HealthMetric.STEPS, HealthMetricGroup.ACTIVITY, false, "Step count", "\u6b65\u6570", "steps", "\u6b65\u884c"),
        entry(HealthMetric.TEMPERATURE, HealthMetricGroup.BODY, false, "Body temperature", "\u4f53\u6e29", "temperature", "temp"),
        entry(HealthMetric.OXYGEN_SATURATION, HealthMetricGroup.CARDIOVASCULAR, false, "Oxygen saturation", "\u8840\u6c27\u9971\u548c\u5ea6", "SpO2", "\u8840\u6c27"),
        entry(HealthMetric.HEIGHT, HealthMetricGroup.BODY, false, "Height", "\u8eab\u9ad8"),
        entry(HealthMetric.WAIST, HealthMetricGroup.BODY, false, "Waist circumference", "\u8170\u56f4", "waist"),
        entry(HealthMetric.BODY_FAT, HealthMetricGroup.BODY, false, "Body fat percentage", "\u4f53\u8102\u7387", "body fat"),
        entry(HealthMetric.LDL, HealthMetricGroup.METABOLIC, true, "LDL cholesterol", "\u4f4e\u5bc6\u5ea6\u8102\u86cb\u767d\u80c6\u56fa\u9187", "LDL-C", "LDLC"),
        entry(HealthMetric.HDL, HealthMetricGroup.METABOLIC, true, "HDL cholesterol", "\u9ad8\u5bc6\u5ea6\u8102\u86cb\u767d\u80c6\u56fa\u9187", "HDL-C", "HDLC"),
        entry(HealthMetric.TRIGLYCERIDES, HealthMetricGroup.METABOLIC, true, "Triglycerides", "\u7518\u6cb9\u4e09\u916f", "TG", "TRIG"),
        entry(HealthMetric.HBA1C, HealthMetricGroup.METABOLIC, true, "Glycated hemoglobin", "\u7cd6\u5316\u8840\u7ea2\u86cb\u767d", "HbA1c", "A1C"),
        entry(HealthMetric.WHITE_BLOOD_CELLS, HealthMetricGroup.BLOOD, true, "White blood cells", "\u767d\u7ec6\u80de\u8ba1\u6570", "WBC", "leukocytes", "\u767d\u7ec6\u80de"),
        entry(HealthMetric.PLATELETS, HealthMetricGroup.BLOOD, true, "Platelet count", "\u8840\u5c0f\u677f\u8ba1\u6570", "PLT", "platelets", "\u8840\u5c0f\u677f"),
        entry(HealthMetric.ALT, HealthMetricGroup.LIVER, true, "Alanine aminotransferase", "\u4e19\u6c28\u9178\u6c28\u57fa\u8f6c\u79fb\u9176", "ALT", "GPT", "\u8c37\u4e19\u8f6c\u6c28\u9176"),
        entry(HealthMetric.AST, HealthMetricGroup.LIVER, true, "Aspartate aminotransferase", "\u5929\u95e8\u51ac\u6c28\u9178\u6c28\u57fa\u8f6c\u79fb\u9176", "AST", "GOT", "\u8c37\u8349\u8f6c\u6c28\u9176"),
        entry(HealthMetric.CREATININE, HealthMetricGroup.KIDNEY, true, "Creatinine", "\u808c\u9150", "CREA", "Cr"),
        entry(HealthMetric.URIC_ACID, HealthMetricGroup.KIDNEY, true, "Uric acid", "\u5c3f\u9178", "UA", "urate"),
        entry(HealthMetric.CRP, HealthMetricGroup.BLOOD, true, "C-reactive protein", "C\u53cd\u5e94\u86cb\u767d", "CRP", "hs-CRP"),
        entry(HealthMetric.TSH, HealthMetricGroup.THYROID, true, "Thyroid stimulating hormone", "\u4fc3\u7532\u72b6\u817a\u6fc0\u7d20", "TSH", "thyrotropin"),
        entry(HealthMetric.URINE_PROTEIN, HealthMetricGroup.URINE, true, "Urine protein screen", "\u5c3f\u86cb\u767d\u5b9a\u6027", "PRO", "urine protein", "\u5c3f\u86cb\u767d"),
        entry(HealthMetric.RED_BLOOD_CELLS, HealthMetricGroup.BLOOD, true, "Red blood cell count", "\u7ea2\u7ec6\u80de\u8ba1\u6570", "RBC", "erythrocytes", "\u7ea2\u7ec6\u80de"),
        entry(HealthMetric.HEMATOCRIT, HealthMetricGroup.BLOOD, true, "Hematocrit", "\u7ea2\u7ec6\u80de\u538b\u79ef", "HCT", "hematocrit fraction", "\u7ea2\u7ec6\u80de\u6bd4\u5bb9"),
        entry(HealthMetric.MEAN_CORPUSCULAR_VOLUME, HealthMetricGroup.BLOOD, true, "Mean corpuscular volume", "\u5e73\u5747\u7ea2\u7ec6\u80de\u4f53\u79ef", "MCV"),
        entry(HealthMetric.MEAN_CORPUSCULAR_HEMOGLOBIN, HealthMetricGroup.BLOOD, true, "Mean corpuscular hemoglobin", "\u5e73\u5747\u7ea2\u7ec6\u80de\u8840\u7ea2\u86cb\u767d\u91cf", "MCH"),
        entry(HealthMetric.MEAN_CORPUSCULAR_HEMOGLOBIN_CONCENTRATION, HealthMetricGroup.BLOOD, true, "Mean corpuscular hemoglobin concentration", "\u5e73\u5747\u7ea2\u7ec6\u80de\u8840\u7ea2\u86cb\u767d\u6d53\u5ea6", "MCHC"),
        entry(HealthMetric.RED_CELL_DISTRIBUTION_WIDTH_CV, HealthMetricGroup.BLOOD, true, "Red cell distribution width CV", "\u7ea2\u7ec6\u80de\u5206\u5e03\u5bbd\u5ea6\u53d8\u5f02\u7cfb\u6570", "RDW-CV"),
        entry(HealthMetric.RED_CELL_DISTRIBUTION_WIDTH_SD, HealthMetricGroup.BLOOD, true, "Red cell distribution width SD", "\u7ea2\u7ec6\u80de\u5206\u5e03\u5bbd\u5ea6\u6807\u51c6\u5dee", "RDW-SD"),
        entry(HealthMetric.MEAN_PLATELET_VOLUME, HealthMetricGroup.BLOOD, true, "Mean platelet volume", "\u5e73\u5747\u8840\u5c0f\u677f\u4f53\u79ef", "MPV"),
        entry(HealthMetric.NEUTROPHIL_COUNT, HealthMetricGroup.BLOOD, true, "Absolute neutrophil count", "\u4e2d\u6027\u7c92\u7ec6\u80de\u8ba1\u6570", "NEUT#", "ANC", "\u4e2d\u6027\u7c92\u7ec6\u80de\u7edd\u5bf9\u503c"),
        entry(HealthMetric.NEUTROPHIL_PERCENT, HealthMetricGroup.BLOOD, true, "Neutrophil percentage", "\u4e2d\u6027\u7c92\u7ec6\u80de\u767e\u5206\u6bd4", "NEUT%"),
        entry(HealthMetric.LYMPHOCYTE_COUNT, HealthMetricGroup.BLOOD, true, "Absolute lymphocyte count", "\u6dcb\u5df4\u7ec6\u80de\u8ba1\u6570", "LYM#", "LYMPH#", "\u6dcb\u5df4\u7ec6\u80de\u7edd\u5bf9\u503c"),
        entry(HealthMetric.LYMPHOCYTE_PERCENT, HealthMetricGroup.BLOOD, true, "Lymphocyte percentage", "\u6dcb\u5df4\u7ec6\u80de\u767e\u5206\u6bd4", "LYM%", "LYMPH%"),
        entry(HealthMetric.ALBUMIN, HealthMetricGroup.LIVER, true, "Serum or plasma albumin", "\u8840\u6e05\uff0f\u8840\u6d46\u767d\u86cb\u767d", "serum albumin", "plasma albumin", "ALB", "\u767d\u86cb\u767d"),
        entry(HealthMetric.TOTAL_PROTEIN, HealthMetricGroup.LIVER, true, "Serum or plasma total protein", "\u8840\u6e05\uff0f\u8840\u6d46\u603b\u86cb\u767d", "serum total protein", "plasma total protein", "TP", "\u603b\u86cb\u767d"),
        entry(HealthMetric.TOTAL_BILIRUBIN, HealthMetricGroup.LIVER, true, "Total bilirubin", "\u603b\u80c6\u7ea2\u7d20", "TBIL", "TBili"),
        entry(HealthMetric.DIRECT_BILIRUBIN, HealthMetricGroup.LIVER, true, "Direct bilirubin", "\u76f4\u63a5\u80c6\u7ea2\u7d20", "DBIL", "DBili"),
        entry(HealthMetric.ALKALINE_PHOSPHATASE, HealthMetricGroup.LIVER, true, "Alkaline phosphatase", "\u78b1\u6027\u78f7\u9178\u9176", "ALP"),
        entry(HealthMetric.GAMMA_GLUTAMYL_TRANSFERASE, HealthMetricGroup.LIVER, true, "Gamma-glutamyl transferase", "\u03b3-\u8c37\u6c28\u9170\u8f6c\u79fb\u9176", "GGT", "gamma-GT", "\u8c37\u6c28\u9170\u8f6c\u80bd\u9176"),
        entry(HealthMetric.UREA, HealthMetricGroup.KIDNEY, true, "Serum or plasma urea", "\u8840\u6e05\uff0f\u8840\u6d46\u5c3f\u7d20", "serum urea", "plasma urea", "\u5c3f\u7d20"),
        entry(HealthMetric.BLOOD_UREA_NITROGEN, HealthMetricGroup.KIDNEY, true, "Blood urea nitrogen", "\u5c3f\u7d20\u6c2e", "BUN", "\u8840\u5c3f\u7d20\u6c2e")
    )
    private fun normalized(value: String) = Normalizer.normalize(value, Normalizer.Form.NFKC).lowercase(Locale.ROOT).filter(Char::isLetterOrDigit)
    fun search(query: String, laboratory: Boolean? = null, group: HealthMetricGroup? = null): List<HealthMetricEntry> {
        val terms = query.trim().split(Regex("\\s+")).map(::normalized).filter(String::isNotBlank)
        return entries.filter { entry -> (laboratory == null || if (laboratory) entry.laboratory else !entry.laboratory || entry.metric == HealthMetric.GLUCOSE) && (group == null || entry.group == group) &&
            terms.all { term -> (listOf(entry.english, entry.chinese, entry.metric.name) + entry.aliases + entry.metric.units).any { normalized(it).contains(term) } } }
    }
    fun aliases(metric: HealthMetric) = entries.single { it.metric == metric }.let { listOf(it.english, it.chinese) + it.aliases + metric.fields }
}
