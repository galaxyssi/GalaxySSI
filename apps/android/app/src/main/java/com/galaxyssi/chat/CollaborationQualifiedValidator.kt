package com.galaxyssi.chat

import java.math.BigInteger
import org.json.JSONObject

/** Closed host registry: a model cannot register a validator or enlarge its qualification. */
internal sealed interface CollaborationQualifiedValidator {
    val id: String
    val verification: String
    fun binding(spec: JSONObject): List<String>
    fun validate(criterion: JSONObject, body: JSONObject)
}

/** A deliberately narrow, side-effect-free computational fixture, never physical evidence. */
internal object CollaborationExactIntegerSumValidator : CollaborationQualifiedValidator {
    override val id = "exact_integer_sum.v1"
    override val verification = "computational"
    private val integer = Regex("0|-?[1-9][0-9]{0,255}")

    fun operands(spec: JSONObject): List<String> {
        require(spec.keys().asSequence().toSet() == setOf("id", "operands") && spec.opt("id") == id) {
            "Unsupported validator specification; only exact_integer_sum.v1 with operands is qualified"
        }
        val values = requireNotNull(spec.optJSONArray("operands")) { "Exact integer operands must be an array" }
        require(values.length() in 2..32) { "Exact integer sum requires 2..32 operands" }
        return (0 until values.length()).map { index ->
            require(values.opt(index) is String && values.getString(index).matches(integer)) {
                "Operands must be canonical decimal strings of at most 256 digits"
            }
            values.getString(index)
        }
    }

    fun requirement(operands: List<String>) = "Compute the exact integer sum: ${operands.joinToString(" + ")}."

    override fun binding(spec: JSONObject) = listOf(id) + operands(spec)

    override fun validate(criterion: JSONObject, body: JSONObject) {
        val values = operands(criterion.getJSONObject(CollaborationQualifiedValidation.FIELD))
        require(criterion.opt("requirement") == requirement(values)) {
            "Exact integer sum cannot qualify a broader computational or scientific requirement"
        }
        val result = requireNotNull(body.optJSONObject("computation")) { "Save body.computation with the exact result" }
        require(result.keys().asSequence().toSet() == setOf("validator_id", "result") && result.opt("validator_id") == id &&
            result.opt("result") is String) { "Invalid exact integer sum result" }
        val expected = values.fold(BigInteger.ZERO) { sum, value -> sum + BigInteger(value) }.toString()
        require(result.getString("result") == expected) { "Saved result disagrees with host exact integer recomputation" }
    }
}

internal object CollaborationQualifiedValidation {
    const val FIELD = "validator"
    private val qualified = listOf(CollaborationExactIntegerSumValidator, CollaborationNumericModelValidator).associateBy { it.id }

    private fun validator(spec: JSONObject): CollaborationQualifiedValidator = requireNotNull(qualified[spec.optString("id")]) {
        "Unknown qualified validator; registered validators: ${qualified.keys.sorted().joinToString()}. " +
            "Preserve the requirement and use an available verification route"
    }

    fun binding(criterion: JSONObject): List<String>? {
        if (!criterion.has(FIELD)) return null
        val spec = requireNotNull(criterion.optJSONObject(FIELD)) { "validator must be a qualified specification object" }
        return validator(spec).binding(spec)
    }

    fun preserved(before: JSONObject, after: JSONObject?): Boolean = after != null && runCatching {
        binding(before) == binding(after)
    }.getOrDefault(false)

    fun validate(criterion: JSONObject, body: JSONObject) {
        require(criterion.optString("evidence_kind") == "observed") {
            "Proposals and simulations cannot satisfy observed acceptance"
        }
        when (criterion.optString("verification")) {
            "documentary" -> require(!criterion.has(FIELD)) { "A computational validator cannot be relabeled documentary" }
            "computational" -> {
                require(binding(criterion) != null) { "Computational acceptance requires a qualified host validator" }
                val selected = validator(criterion.getJSONObject(FIELD))
                require(selected.verification == "computational")
                selected.validate(criterion, body)
            }
            else -> throw IllegalArgumentException("No qualified validator for this domain; simulations never certify physical results")
        }
    }
}
