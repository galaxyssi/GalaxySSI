package com.galaxyssi.chat

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject

/** Replays a pure expression on preserved cases. It does not certify how reference values were obtained. */
internal object CollaborationNumericModelValidator : CollaborationQualifiedValidator {
    override val id = "numeric_model_cases.v1"
    override val verification = "computational"
    const val REQUIREMENT = "Verify the saved numeric model on exactly the registered test cases; this does not establish generalization or physical validity."
    private const val MAX_CASES = 4096
    private const val MAX_NODES = 2048
    private const val MAX_DEPTH = 48
    private const val MAX_OPERATIONS = 2_000_000L
    private val name = Regex("[A-Za-z][A-Za-z0-9_]{0,63}")
    private val unary = setOf("neg", "abs", "exp", "expm1", "log", "log1p", "sqrt", "sin", "cos")
    private val binary = setOf("add", "sub", "mul", "div", "pow", "min", "max")

    private data class Case(val id: String, val input: Map<String, Double>, val expected: BigDecimal, val tolerance: BigDecimal)
    private data class Cases(val variables: Set<String>, val rows: List<Case>)
    private data class Expression(val nodes: Int, val evaluate: (Map<String, Double>) -> Double)

    override fun binding(spec: JSONObject): List<String> {
        cases(spec)
        return listOf(id, fingerprint(spec))
    }

    override fun validateRequirement(criterion: JSONObject) {
        require(criterion.opt("requirement") == REQUIREMENT) {
            "Numeric case verification cannot qualify a broader scientific, physical or generalization requirement"
        }
    }

    override fun validate(criterion: JSONObject, body: JSONObject) {
        validateRequirement(criterion)
        val computation = requireNotNull(body.optJSONObject("computation")) { "Save body.computation with the numeric model" }
        val report = evaluate(criterion.getJSONObject(CollaborationQualifiedValidation.FIELD), computation)
        require(report.getBoolean("passed")) {
            "Numeric model failed ${report.getInt("failed_cases")}/${report.getInt("case_count")} registered cases; " +
                "worst_case=${report.getJSONObject("worst_case")}. Revise the saved model using this counterexample; preserve all test inputs and tolerances."
        }
    }

    fun evaluate(spec: JSONObject, computation: JSONObject): JSONObject {
        val cases = cases(spec)
        keys(computation, setOf("validator_id", "model"), "computation")
        require(computation.opt("validator_id") == id) { "Numeric model validator_id mismatch" }
        val model = requireNotNull(computation.optJSONObject("model")) { "Numeric model must be an expression object, not executable source" }
        val expression = compile(model, cases.variables)
        require(expression.nodes.toLong() * cases.rows.size <= MAX_OPERATIONS) {
            "Numeric replay exceeds the local operation envelope; use a smaller scoped verification plan, not weaker test values"
        }
        var failed = 0
        var finiteCases = 0
        var maxError = BigDecimal.ZERO
        var largestExcess: BigDecimal? = null
        var worst: JSONObject? = null
        var domainFailure: JSONObject? = null
        val checks = JSONArray()
        for (case in cases.rows) {
            val actual = runCatching { finite(expression.evaluate(case.input), "model result") }
            if (actual.isFailure) {
                failed++
                val failure = JSONObject().put("id", case.id).put("passed", false)
                    .put("error", actual.exceptionOrNull()?.message ?: "Numeric domain error")
                checks.put(failure)
                if (domainFailure == null) domainFailure = failure
                continue
            }
            finiteCases++
            val value = BigDecimal.valueOf(actual.getOrThrow())
            val error = (value - case.expected).abs()
            val excess = error - case.tolerance
            checks.put(JSONObject().put("id", case.id).put("passed", excess.signum() <= 0)
                .put("actual", value.toString()).put("absolute_error", error.toString()))
            if (excess.signum() > 0) failed++
            if (error > maxError) maxError = error
            if (largestExcess == null || excess > largestExcess) {
                largestExcess = excess
                worst = JSONObject().put("id", case.id).put("actual", value.toString()).put("expected", case.expected.toString())
                    .put("absolute_error", error.toString()).put("absolute_tolerance", case.tolerance.toString())
            }
        }
        return JSONObject().put("validator_id", id).put("passed", failed == 0).put("case_count", cases.rows.size)
            .put("failed_cases", failed).put("finite_cases", finiteCases).put("domain_error_cases", cases.rows.size - finiteCases)
            .put("checks", checks).put("max_absolute_error_on_finite_cases", if (finiteCases == 0) JSONObject.NULL else maxError.toString())
            .put("worst_case", domainFailure ?: worst ?: JSONObject.NULL)
            .put("spec_sha256", fingerprint(spec))
            .put("model_sha256", fingerprint(model))
            .put("meaning", "host_float64_replay_on_supplied_cases_not_independent_reference_truth_or_generalization")
    }

    private fun cases(spec: JSONObject): Cases {
        keys(spec, setOf("id", "variables", "cases"), "validator")
        require(spec.opt("id") == id) { "Unsupported numeric model specification" }
        val variables = requireNotNull(spec.optJSONArray("variables")) { "variables must be an array" }
        require(variables.length() in 1..64) { "Numeric replay supports 1..64 named variables" }
        val names = (0 until variables.length()).map {
            require(variables.opt(it) is String && variables.getString(it).matches(name)) { "Invalid numeric variable name" }
            variables.getString(it)
        }
        require(names.distinct().size == names.size) { "Duplicate numeric variables" }
        val rows = requireNotNull(spec.optJSONArray("cases")) { "cases must be an array" }
        require(rows.length() in 1..MAX_CASES) { "Numeric replay supports 1..$MAX_CASES cases per preserved plan" }
        val seen = hashSetOf<String>()
        val allowed = names.toSet()
        return Cases(allowed, (0 until rows.length()).map { index ->
            val case = requireNotNull(rows.optJSONObject(index)) { "cases[$index] must be an object" }
            keys(case, setOf("id", "input", "expected", "absolute_tolerance"), "cases[$index]")
            val caseId = case.opt("id")
            require(caseId is String && caseId.isNotBlank() && caseId.length <= 128 && seen.add(caseId)) { "Invalid or duplicate numeric case ID" }
            val input = requireNotNull(case.optJSONObject("input")) { "cases[$index].input must be an object" }
            keys(input, allowed, "cases[$index].input")
            val tolerance = decimal(case, "absolute_tolerance")
            require(tolerance.signum() >= 0) { "Absolute tolerance cannot be negative" }
            Case(caseId, allowed.associateWith { finite(decimal(input, it).toDouble(), "input $it") }, decimal(case, "expected"), tolerance)
        })
    }

    private fun compile(root: JSONObject, variables: Set<String>): Expression {
        var visited = 0
        fun node(value: JSONObject, depth: Int): (Map<String, Double>) -> Double {
            require(depth <= MAX_DEPTH && ++visited <= MAX_NODES) { "Numeric model exceeds expression depth/node envelope" }
            if (value.has("constant")) {
                keys(value, setOf("constant"), "constant expression")
                val constant = finite(decimal(value, "constant").toDouble(), "constant")
                return { constant }
            }
            if (value.has("variable")) {
                keys(value, setOf("variable"), "variable expression")
                val variable = value.opt("variable")
                require(variable is String && variable in variables) { "Expression uses an unregistered variable" }
                return { it.getValue(variable) }
            }
            keys(value, setOf("op", "args"), "operation expression")
            val operation = value.opt("op")
            require(operation is String && (operation in unary || operation in binary)) { "Unsupported numeric operation" }
            val args = requireNotNull(value.optJSONArray("args")) { "Operation args must be an array" }
            require(args.length() == if (operation in unary) 1 else 2) { "Wrong argument count for $operation" }
            val first = node(requireNotNull(args.optJSONObject(0)) { "Argument must be an expression object" }, depth + 1)
            val second = if (args.length() == 2) node(requireNotNull(args.optJSONObject(1)) { "Argument must be an expression object" }, depth + 1) else null
            return { input ->
                val a = finite(first(input), "$operation input")
                val b = second?.let { finite(it(input), "$operation input") }
                finite(when (operation) {
                    "neg" -> -a
                    "abs" -> StrictMath.abs(a)
                    "exp" -> StrictMath.exp(a)
                    "expm1" -> StrictMath.expm1(a)
                    "log" -> StrictMath.log(a)
                    "log1p" -> StrictMath.log1p(a)
                    "sqrt" -> StrictMath.sqrt(a)
                    "sin" -> StrictMath.sin(a)
                    "cos" -> StrictMath.cos(a)
                    "add" -> a + b!!
                    "sub" -> a - b!!
                    "mul" -> a * b!!
                    "div" -> { require(b != 0.0) { "Division by zero" }; a / b!! }
                    "pow" -> StrictMath.pow(a, b!!)
                    "min" -> StrictMath.min(a, b!!)
                    "max" -> StrictMath.max(a, b!!)
                    else -> error("Unreachable numeric operation")
                }, operation)
            }
        }
        val evaluate = node(root, 1)
        return Expression(visited, evaluate)
    }

    private fun fingerprint(value: JSONObject): String {
        // JSONObject persistence removes insignificant numeric zeroes; bind values, not JVM Number subclasses.
        fun canonical(item: Any?): Any? = when (item) {
            null, JSONObject.NULL -> null
            is JSONObject -> item.keys().asSequence().associateWith { canonical(item.get(it)) }
            is JSONArray -> (0 until item.length()).map { canonical(item.get(it)) }
            is Number -> BigDecimal(item.toString()).stripTrailingZeros()
            else -> item
        }
        return AgentNativeJsonCodec.sha256(canonical(value))
    }

    private fun keys(value: JSONObject, expected: Set<String>, path: String) = require(value.keys().asSequence().toSet() == expected) {
        "$path fields must be exactly ${expected.sorted().joinToString()}"
    }
    private fun decimal(value: JSONObject, key: String) = CollaborationEvolutionExperiment.decimal(value, key)
    private fun finite(value: Double, field: String): Double = value.also { require(it.isFinite()) { "$field is outside the finite numeric domain" } }
}
