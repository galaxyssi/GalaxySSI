import { digest, requireThat, validatePlan } from "./protocol.mjs";

export function fixtureConfig() {
  return {
    study_id: "synthetic-longitudinal-example", evidence_kind: "fixture", team_size: 8, repetitions: 2,
    controls: Object.fromEntries(["model_policy", "tool_policy", "permission_policy", "initial_state", "evaluator", "outage_policy"]
      .map((key) => [`${key}_sha256`, digest(`FIXTURE_ONLY:${key}`)])),
    stream_budget: { max_wall_time_ms: 60000, max_model_requests: 30, max_total_tokens: 10000, max_cost_micros: 100000, currency: "USD" },
    families: ["alpha", "beta"].map((name) => ({ family_id: name, domain: "synthetic",
      goals: [0, 1, 2].map((index) => ({ goal_id: `goal-${index}`, request: {
        prompt: `FIXTURE_ONLY ${name} goal ${index}; not a real experiment`, input_sha256: digest({ name, index })
      }, success_contract_sha256: digest(`FIXTURE_ONLY:contract:${name}:${index}`), perturbation_sha256: digest("FIXTURE_ONLY:no-perturbation") }))
    }))
  };
}

export function fixtureCapture(plan) {
  validatePlan(plan);
  requireThat(plan.evidence_kind === "fixture", "Fixture capture cannot fabricate actual evidence");
  return {
    schema_version: 1, plan_sha256: plan.plan_sha256, evidence_kind: "fixture",
    collection: { status: "closed", evidence_ref: "FIXTURE_ONLY:collection" },
    streams: plan.streams.map((stream) => {
      let previous = plan.config.controls.initial_state_sha256;
      return {
        stream_id: stream.stream_id, order: stream.order, group_id: `fixture-group-${stream.stream_id}`,
        state_namespace: stream.state_namespace, policy: structuredClone(stream.policy),
        controls_sha256: digest(plan.config.controls),
        budget: { scope: "whole_stream", ledger_id: `fixture-ledger-${stream.stream_id}`,
          limits: structuredClone(plan.config.stream_budget), enforced: true, evidence_ref: "FIXTURE_ONLY:budget" },
        evidence_ref: "FIXTURE_ONLY:stream",
        goals: stream.goals.map((goal) => {
          const reset = goal.index === 0 || !stream.policy.persistence;
          const input = reset ? plan.config.controls.initial_state_sha256 : previous;
          const output = digest({ fixture_state: goal.slot_id }); previous = output;
          return { ...Object.fromEntries(["slot_id", "goal_id", "index", "request_sha256"].map((key) => [key, goal[key]])),
            run_id: `fixture-run-${goal.slot_id}`, attempt_ids: [`fixture-attempt-${goal.slot_id}`],
            status: goal.index === 1 && stream.order === 0 ? "failed" : "completed", exhaustion_ref: null,
            state: { input_sha256: input, output_sha256: output, read_namespaces: [stream.state_namespace],
              write_namespace: stream.state_namespace, reset_ref: reset ? "FIXTURE_ONLY:reset" : null },
            communication: { during_task_peer_messages: stream.policy.communication === true ? 2 : 0,
              finalization_peer_messages: stream.policy.members > 1 ? 1 : 0, evidence_ref: "FIXTURE_ONLY:communication" },
            evidence_ref: "FIXTURE_ONLY:goal" };
        })
      };
    })
  };
}
