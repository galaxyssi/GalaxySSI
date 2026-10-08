package com.galaxyssi.chat

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationExecutableTool.TOOL
import com.galaxyssi.chat.CollaborationExecutableTool.TEST
import com.galaxyssi.chat.CollaborationExecutableTool.RELEASE

/** Qualifies observed executions on a preserved suite, not arbitrary claims about generated code. */
internal object CollaborationExecutableAcceptance : CollaborationQualifiedValidator {
    override val id = "executable_tool_cases.v1"
    override val verification = "computational"
    const val REQUIREMENT = "Verify a saved executable tool on all preserved test cases in the declared environment; this does not establish general correctness, reference truth or physical validity."
    private val fields = setOf("environment", "purpose", "oracle_basis", "coverage_gaps", "cases")

    override fun binding(spec: JSONObject): List<String> {
        require(spec.keys().asSequence().toSet() == fields + "id" && spec.opt("id") == id) {
            "Executable verification needs id, environment, purpose, oracle_basis, coverage_gaps and cases"
        }
        (fields - "cases").forEach { key ->
            require(spec.opt(key) is String && spec.getString(key).isNotBlank()) { "validator.$key must be nonblank text" }
        }
        val cases = requireNotNull(spec.optJSONArray("cases")) { "validator.cases must be an array" }
        val ids = hashSetOf<String>()
        val purposes = hashSetOf<String>()
        repeat(cases.length()) { index ->
            val row = requireNotNull(cases.optJSONObject(index)) { "validator.cases[$index] must be an object" }
            require(row.keys().asSequence().toSet() == setOf("id", "purpose", "reason", "input", "expected")) {
                "Each preserved case needs exactly id, purpose, reason, input and expected"
            }
            listOf("id", "purpose", "reason").forEach { key ->
                require(row.opt(key) is String && row.getString(key).isNotBlank()) { "case.$key must be nonblank text" }
            }
            require(ids.add(row.getString("id"))) { "Preserved test IDs must be unique" }
            require(row.getString("purpose") in setOf("target", "edge", "regression")) { "Unknown preserved case purpose" }
            purposes += row.getString("purpose")
            require(row.optJSONObject("input") != null) { "Each preserved case input must be a JSON object" }
        }
        require(purposes.containsAll(setOf("target", "regression"))) { "Preserve target and regression cases" }
        return listOf(id, fingerprint(contract(spec)))
    }

    override fun validate(criterion: JSONObject, body: JSONObject) {
        throw IllegalArgumentException("Executable verification requires host-resolved workspace and original runtime evidence")
    }

    override fun validateRecorded(criterion: JSONObject, body: JSONObject, evidence: CollaborationValidationEvidence?) {
        require(criterion.opt("requirement") == REQUIREMENT) {
            "Executed cases cannot qualify broader generalization, scientific or physical claims"
        }
        val host = requireNotNull(evidence) { "Executable verification requires host evidence resolvers" }
        val specification = criterion.getJSONObject(CollaborationQualifiedValidation.FIELD)
        binding(specification)
        val computation = requireNotNull(body.optJSONObject("computation")) { "Save body.computation with the exact tool release" }
        require(computation.keys().asSequence().toSet() == setOf("validator_id", RELEASE) && computation.opt("validator_id") == id) {
            "Executable computation accepts only validator_id and tool_release"
        }
        val release = host.exact(computation.getJSONObject(RELEASE), RELEASE)
        val value = release.getJSONObject("body").getJSONObject(RELEASE)
        val plan = host.exact(value.getJSONObject(TEST), TEST)
        val planSpec = plan.getJSONObject("body").getJSONObject(TEST)
        require(fingerprint(contract(planSpec)) == fingerprint(contract(specification))) {
            "Executed test plan differs from the preserved environment, cases or oracle contract"
        }
        val toolRef = planSpec.getJSONObject(TOOL)
        val authors = host.contributors(toolRef)
        require(release.getString("person_id") !in authors && host.review.getString("person_id") !in authors) {
            "A tool contributor cannot independently release or accept their own execution"
        }
        val selected = value.getJSONObject("observation")
        val original = requireNotNull(host.original(selected)) { "Original executable test evidence is missing or isolated" }
        require(listOf("group_id", "run_id", "turn_id").all { original.getString(it) == host.delivery.getString(it) }) {
            "Historical tests are not a current goal execution; test the exact candidate in this goal"
        }
        listOf(host.delivery, host.review).forEach { revision ->
            val refs = revision.getJSONArray("host_observations")
            require((0 until refs.length()).any { at -> refs.getJSONObject(at).let {
                it.optString("evidence_id") == selected.getString("evidence_id") && it.optString("sha256") == selected.getString("sha256")
            } }) { "Both delivery and acceptance review must cite the original executable test observation" }
        }
        host.requireReadCoverage(host.review)
        // Revalidate the original receipt/harness and every expected/actual value; do not trust a cached 'passed'.
        CollaborationExecutableTool.release(value, release, release.getString("person_id"),
            { ref, kinds -> host.exact(ref, kinds.single()) }, host.original, host.requireReadCoverage)
    }

    private fun contract(value: JSONObject) = JSONObject().apply { fields.forEach { put(it, value.get(it)) } }

    private fun fingerprint(value: Any?): String {
        fun canonical(item: Any?): Any? = when (item) {
            null, JSONObject.NULL -> null
            is JSONObject -> item.keys().asSequence().associateWith { canonical(item.get(it)) }
            is JSONArray -> (0 until item.length()).map { canonical(item.get(it)) }
            is Number -> BigDecimal(item.toString()).stripTrailingZeros()
            else -> item
        }
        return AgentNativeJsonCodec.sha256(canonical(value))
    }

    fun rules() = """
        executable_tool_cases.v1 connects generated Python tools to finite-case goal acceptance using the existing native runtime.
        In the preserved criterion set verification=computational, evidence_kind=observed, requirement exactly:
        "$REQUIREMENT"
        validator:{id:"$id",environment,purpose,oracle_basis,coverage_gaps,cases:[{id,purpose:"target|edge|regression",reason,input:{...},expected:<JSON>}]}.
        Establish this contract before completion. Cases and oracle metadata are immutable; code candidates may be revised.
        Publish executable_tool and tool_test_plan copying those preserved fields exactly, then execute the plan with
        galaxyssi.runtime.execute collaboration_tool mode=test, or remote Codex collaboration_test_tool mode=start with
        a stable execution_id, exact tool_test_plan and timeout_ms. Remote start returns admission, not test success;
        query mode=status using the same execution_id, then read the complete original native evidence receipt.
        A separate member reads the complete original receipt and
        reviews source, oracle and limitations to publish tool_release. Save an artifact body with content and
        computation:{validator_id:"$id",tool_release:<exact ref>}. Delivery AND its independent acceptance_review must cite
        the original native test observation; the reviewer must read all pages before publication. The host rechecks the
        saved source, harness, environment, dispatch, case coverage and actual values without executing code during acceptance.
        Only this goal's actual native execution qualifies. A Desktop shell claim, model-written receipt, old successful run,
        or reading peer prose is not equivalent. Remote testing uses the originating App runtime, not a Desktop shell;
        inspect capability availability first. This route adds no permissions, background execution or general scientific validator.
        Oracle truth, unseen-task transfer, broad correctness and physical experiments remain separate unmet requirements
        until supported by their appropriate evidence; never substitute this finite-suite requirement for the original goal.
    """.trimIndent()
}
