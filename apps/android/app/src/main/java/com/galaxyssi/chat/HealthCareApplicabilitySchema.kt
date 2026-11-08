package com.galaxyssi.chat

internal object HealthCareApplicabilitySchema {
    private val check = AgentNativeJsonSchema.objectSchema(properties = mapOf(
        "field" to AgentNativeJsonSchema.string(enumValues = HealthCareApplicabilityField.entries.map { it.name }),
        "operator" to AgentNativeJsonSchema.string(enumValues = HealthCareApplicabilityOperator.entries.map { it.name },
            description = "EQUALS for all fields; AT_LEAST/AT_MOST only for fasting hours."),
        "expected" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 80,
            description = "Source-required value, not a guessed patient value. Truth fields: YES/NO; specimen: LAB_PLASMA/HOME_CAPILLARY/INTERSTITIAL; fasting: integer hours. Use snapshot spellings for metric/unit/collection_condition. Never UNKNOWN."),
        "source_index" to AgentNativeJsonSchema.integer(minimum = 0, maximum = 7,
            description = "Source whose exact quoted passage supports this required condition. Add a separate cited passage if necessary.")
    ), required = setOf("field", "operator", "expected", "source_index"), additionalProperties = false)
    private val conflict = AgentNativeJsonSchema.objectSchema(properties = mapOf(
        "source_indices" to AgentNativeJsonSchema.array(AgentNativeJsonSchema.integer(minimum = 0, maximum = 7), minItems = 2, maxItems = 8),
        "detail" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 1000, description = "Explain the actual conflicting recommendation or population/version difference, not just different URLs."),
        "next_step" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 1000, description = "How to resolve the conflict, including professional review where needed. Do not silently average conflicting thresholds or intervals.")
    ), required = setOf("source_indices", "detail", "next_step"), additionalProperties = false)
    val schema = AgentNativeJsonSchema.objectSchema(properties = mapOf(
        "mode" to AgentNativeJsonSchema.string(enumValues = HealthCareApplicabilityMode.entries.map { it.name },
            description = "DISCUSSION_ONLY is only for CONTEXT/CLINICIAN_DISCUSSION, not adoption of treatment/testing guidance. INDIVIDUALIZED is required for LIFESTYLE/RECHECK."),
        "checks" to AgentNativeJsonSchema.array(check, maxItems = 12,
            description = "List source-supported applicability requirements. The phone compares them with current confirmed context; the model cannot supply actual values or mark checks verified."),
        "missing_information" to AgentNativeJsonSchema.array(AgentNativeJsonSchema.string(minLength = 1, maxLength = 500), maxItems = 8,
            description = "Unresolved factors, exclusions, contraindications or applicability criteria not captured by supported fields. Empty only if none is identified; never omit known gaps to enable confirmation."),
        "conflicts" to AgentNativeJsonSchema.array(conflict, maxItems = 8,
            description = "Remaining material source conflicts for this action. Include every cited conflicting source and its original passage in sources. Empty does not mean all medical literature agrees.")
    ), required = setOf("mode", "checks", "missing_information", "conflicts"), additionalProperties = false)
}
