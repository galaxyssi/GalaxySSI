import { UNKNOWN, digest, validatePlan } from "./lib.mjs";

export function fixtureExport(plan, corpus) {
  validatePlan(plan, corpus);
  const observed = (value) => ({ value, complete: true, evidence_ref: "FIXTURE_ONLY:not-observed" });
  return {
    schema_version: 1, evidence_kind: "fixture", plan_sha256: plan.plan_sha256,
    warning: "SYNTHETIC TEST DATA. No model, application, or device was run. Not capability evidence.",
    runs: plan.slots.map((slot) => {
      const scenario = corpus.scenarios.find((s) => s.id === slot.scenario_id);
      const runId = `fixture-${slot.slot_id}`;
      // Symmetric scripted failures and missing accounting exercise reporting, not an arm advantage.
      const failed = slot.scenario_id === corpus.scenarios[0].id && slot.repetition === 2;
      const unknownCost = slot.scenario_id === corpus.scenarios[1].id && slot.repetition === 3;
      return {
        slot_id: slot.slot_id, run_id: runId, evidence_kind: "fixture",
        result: {
          scenario_id: slot.scenario_id, run_id: runId,
          status: failed ? "timeout" : "completed",
          response: failed ? "" : JSON.stringify(scenario.answers),
          events: [], tools: [], failure_reasons: failed ? ["fixture_scripted_timeout"] : []
        },
        budget: { limits: structuredClone(plan.budget), scope: "entire_trial", enforced: true, evidence_ref: "FIXTURE_ONLY:budget" },
        controls: structuredClone(plan.controls),
        capture: { complete: true, assignment_verified: true, controls_verified: true, reset_verified: true,
          scope: "entire_trial", order: slot.order, request_sha256: digest(scenario.request), evidence_ref: "FIXTURE_ONLY:capture" },
        accounting: {
          wall_time_ms: observed(failed ? plan.budget.max_wall_time_ms : 1000 + slot.repetition * 100),
          rework_count: observed(failed ? 1 : 0), intervention_count: observed(0),
          ledger: {
            complete: true, scope: "entire_trial", evidence_ref: "FIXTURE_ONLY:ledger", participants: ["fixture-worker"],
            calls: [{
              call_id: `${runId}-call-1`, participant_id: "fixture-worker",
              total_tokens: observed(300 + slot.repetition),
              cost_micros: unknownCost ? { value: UNKNOWN, complete: false } : observed(500 + slot.repetition)
            }]
          }
        }
      };
    })
  };
}
