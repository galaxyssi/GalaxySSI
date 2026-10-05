import { isDeepStrictEqual } from "node:util";
import { ARMS, digest, exactKeys, hash, integer, requireThat, text, validatePlan } from "./protocol.mjs";

const TERMINAL = ["completed", "failed", "cancelled", "resource_exhausted", "unattempted_after_exhaustion"];
const STATUS = [...TERMINAL, "running", "waiting", "paused"];
function provenance(ref, kind) {
  requireThat(text(ref), "Missing local evidence reference");
  requireThat(kind !== "actual" || !/^FIXTURE_ONLY(?:[:_\s-]|$)/i.test(ref.trim()), "Fixture provenance is not actual evidence");
}

export function inspectCapture(plan, capture) {
  validatePlan(plan);
  exactKeys(capture, ["schema_version", "plan_sha256", "evidence_kind", "collection", "streams"], "capture");
  requireThat(capture.schema_version === 1 && capture.plan_sha256 === plan.plan_sha256, "Capture plan mismatch");
  requireThat(capture.evidence_kind === plan.evidence_kind, "Capture evidence kind mismatch");
  exactKeys(capture.collection, ["status", "evidence_ref"], "collection");
  requireThat(["open", "closed"].includes(capture.collection.status), "Invalid collection status");
  provenance(capture.collection.evidence_ref, capture.evidence_kind);
  requireThat(Array.isArray(capture.streams), "Capture streams must be an array");
  const seenStreams = new Set(), seenRuns = new Set(), seenAttempts = new Set(), seenNamespaces = new Set();
  const seenGroups = new Set(), seenLedgers = new Set();
  const expected = new Map(plan.streams.map((s) => [s.stream_id, s])), observed = new Map();
  for (const stream of capture.streams) {
    exactKeys(stream, ["stream_id", "order", "group_id", "state_namespace", "policy", "controls_sha256", "budget", "evidence_ref", "goals"], "captured stream");
    requireThat(expected.has(stream.stream_id) && !seenStreams.has(stream.stream_id), "Unknown or duplicate stream");
    seenStreams.add(stream.stream_id);
    requireThat(text(stream.group_id) && !seenGroups.has(stream.group_id), "Missing or reused group ID across streams"); seenGroups.add(stream.group_id);
    requireThat(text(stream.state_namespace) && !seenNamespaces.has(stream.state_namespace), "Missing or reused state namespace"); seenNamespaces.add(stream.state_namespace);
    requireThat(integer(stream.order), "Invalid capture order"); provenance(stream.evidence_ref, capture.evidence_kind);
    exactKeys(stream.budget, ["scope", "ledger_id", "limits", "enforced", "evidence_ref"], "budget");
    requireThat(text(stream.budget.ledger_id) && !seenLedgers.has(stream.budget.ledger_id), "Missing or reused stream ledger"); seenLedgers.add(stream.budget.ledger_id);
    requireThat(typeof stream.budget.enforced === "boolean", "Budget enforcement must be boolean"); provenance(stream.budget.evidence_ref, capture.evidence_kind);
    requireThat(Array.isArray(stream.goals), "Captured goals must be an array");
    const goalIds = new Set();
    for (const goal of stream.goals) {
      exactKeys(goal, ["slot_id", "goal_id", "index", "run_id", "attempt_ids", "status", "request_sha256", "state", "communication", "exhaustion_ref", "evidence_ref"], "captured goal");
      requireThat(expected.get(stream.stream_id).goals.some((g) => g.slot_id === goal.slot_id) && !goalIds.has(goal.slot_id), "Unknown or duplicate goal; retries stay inside the assigned slot"); goalIds.add(goal.slot_id);
      requireThat(STATUS.includes(goal.status) && integer(goal.index), "Invalid goal lifecycle");
      if (goal.status === "unattempted_after_exhaustion") requireThat(goal.run_id === null, "Unattempted goal must not invent a run ID");
      else {
        requireThat(text(goal.run_id) && !seenRuns.has(goal.run_id), "Missing or reused original run ID"); seenRuns.add(goal.run_id);
      }
      requireThat(Array.isArray(goal.attempt_ids), "Attempt IDs must be an array");
      for (const attempt of goal.attempt_ids) {
        requireThat(text(attempt) && !seenAttempts.has(attempt), "Missing or reused attempt ID"); seenAttempts.add(attempt);
      }
      requireThat(goal.status === "unattempted_after_exhaustion" ? goal.attempt_ids.length === 0 : goal.attempt_ids.length > 0,
        "Unattempted goals need zero attempts; attempted goals need their original attempts");
      requireThat(goal.exhaustion_ref === null || text(goal.exhaustion_ref), "Invalid exhaustion reference");
      if (["resource_exhausted", "unattempted_after_exhaustion"].includes(goal.status)) provenance(goal.exhaustion_ref, capture.evidence_kind);
      exactKeys(goal.state, ["input_sha256", "output_sha256", "read_namespaces", "write_namespace", "reset_ref"], "state");
      requireThat(hash(goal.state.input_sha256), "Invalid input state digest");
      requireThat(goal.state.output_sha256 === null || hash(goal.state.output_sha256), "Invalid output state digest");
      requireThat(Array.isArray(goal.state.read_namespaces) && goal.state.read_namespaces.every(text), "Invalid read namespaces");
      requireThat(text(goal.state.write_namespace), "Missing write namespace");
      requireThat(goal.state.reset_ref === null || text(goal.state.reset_ref), "Invalid reset evidence");
      if (goal.state.reset_ref !== null) provenance(goal.state.reset_ref, capture.evidence_kind);
      exactKeys(goal.communication, ["during_task_peer_messages", "finalization_peer_messages", "evidence_ref"], "communication");
      requireThat(integer(goal.communication.during_task_peer_messages) && integer(goal.communication.finalization_peer_messages), "Invalid communication counters");
      provenance(goal.communication.evidence_ref, capture.evidence_kind); provenance(goal.evidence_ref, capture.evidence_kind);
    }
    observed.set(stream.stream_id, stream);
  }
  const rows = plan.streams.map((assigned) => {
    const stream = observed.get(assigned.stream_id), issues = [];
    if (!stream) issues.push("missing_stream");
    if (stream) {
      if (stream.order !== assigned.order) issues.push("stream_order_mismatch");
      if (stream.state_namespace !== assigned.state_namespace) issues.push("state_namespace_mismatch");
      if (!isDeepStrictEqual(stream.policy, assigned.policy)) issues.push("arm_policy_mismatch");
      if (stream.controls_sha256 !== digest(plan.config.controls)) issues.push("controlled_policy_mismatch");
      if (stream.budget.scope !== "whole_stream" || stream.budget.enforced !== true) issues.push("shared_stream_budget_unverified");
      if (!isDeepStrictEqual(stream.budget.limits, plan.config.stream_budget)) issues.push("shared_stream_budget_changed");
      const order = stream.goals.map((g) => g.index);
      if (order.some((v, i) => i > 0 && order[i - 1] >= v)) issues.push("goal_capture_order_mismatch");
    }
    const bySlot = new Map((stream?.goals || []).map((goal) => [goal.slot_id, goal]));
    const exhaustionIndex = assigned.goals.findIndex((slot) =>
      ["resource_exhausted", "unattempted_after_exhaustion"].includes(bySlot.get(slot.slot_id)?.status));
    const goals = assigned.goals.map((slot) => {
      const goal = bySlot.get(slot.slot_id), problems = [];
      if (!goal) problems.push("missing_goal");
      else {
        if (goal.goal_id !== slot.goal_id || goal.index !== slot.index) problems.push("goal_identity_mismatch");
        if (goal.request_sha256 !== slot.request_sha256) problems.push("request_mismatch");
        if (exhaustionIndex >= 0 && slot.index > exhaustionIndex && goal.status !== "unattempted_after_exhaustion") problems.push("work_after_stream_exhaustion");
        if (goal.status === "unattempted_after_exhaustion") {
          if (goal.state.output_sha256 !== goal.state.input_sha256) problems.push("unattempted_state_changed");
          if (goal.communication.during_task_peer_messages > 0 || goal.communication.finalization_peer_messages > 0) problems.push("unattempted_peer_communication");
        }
        if (goal.state.write_namespace !== assigned.state_namespace ||
            goal.state.read_namespaces.some((ns) => ns !== assigned.state_namespace)) problems.push("cross_stream_state_access");
        if (slot.index === 0 || !assigned.policy.persistence) {
          if (goal.state.input_sha256 !== plan.config.controls.initial_state_sha256) problems.push("initial_state_not_restored");
          if (!text(goal.state.reset_ref)) problems.push("reset_unverified");
        } else {
          const previous = bySlot.get(assigned.goals[slot.index - 1].slot_id);
          if (!previous || !TERMINAL.includes(previous.status) || !hash(previous.state.output_sha256)) problems.push("predecessor_state_unverified");
          else if (goal.state.input_sha256 !== previous.state.output_sha256) problems.push("persistent_state_chain_broken");
        }
        if (TERMINAL.includes(goal.status) && !hash(goal.state.output_sha256)) problems.push("terminal_state_missing");
        if (assigned.policy.communication !== true && goal.communication.during_task_peer_messages > 0) problems.push("forbidden_during_task_communication");
        if (assigned.policy.members === 1 && goal.communication.finalization_peer_messages > 0) problems.push("single_arm_peer_communication");
        if (slot.index > 0) {
          const previous = bySlot.get(assigned.goals[slot.index - 1].slot_id);
          if (!previous || !TERMINAL.includes(previous.status)) problems.push("ordered_predecessor_not_terminal");
        }
      }
      return { ...slot, status: goal?.status || "missing", terminal: Boolean(goal && TERMINAL.includes(goal.status)),
        attempt_count: goal?.attempt_ids.length ?? null, issues: [...new Set(problems)] };
    });
    return {
      stream_id: assigned.stream_id, block_id: assigned.block_id, family_id: assigned.family_id,
      domain: assigned.domain, repetition: assigned.repetition, arm: assigned.arm, order: assigned.order,
      issues, goals, terminal_goals: goals.filter((g) => g.terminal).length,
      contract_consistent: issues.length === 0 && goals.every((g) => g.issues.length === 0)
    };
  });
  const allTerminal = rows.every((row) => row.terminal_goals === row.goals.length), allConsistent = rows.every((row) => row.contract_consistent);
  const closed = capture.collection.status === "closed";
  return {
    schema_version: 1, analysis: "longitudinal_capture_contract_only", evidence_kind: capture.evidence_kind,
    plan_sha256: plan.plan_sha256, capture_sha256: digest(capture), collection_status: capture.collection.status,
    all_assigned_slots_terminal: allTerminal, all_capture_contracts_consistent: allConsistent,
    verdict: !allConsistent ? "INCOMPLETE_OR_PROTOCOL_VIOLATION" : !closed || !allTerminal ? "COLLECTION_NOT_CLOSED_OR_NOT_TERMINAL" : "CAPTURE_CONTRACT_CONSISTENT_NOT_EFFICACY",
    cluster_unit: "family_id", declared_family_count: plan.config.families.length,
    assigned_streams: rows.length, assigned_goals: rows.reduce((n, row) => n + row.goals.length, 0),
    by_arm: Object.fromEntries(ARMS.map((arm) => {
      const selected = rows.filter((row) => row.arm === arm), goals = selected.flatMap((row) => row.goals);
      return [arm, { assigned_streams: selected.length, assigned_goals: goals.length,
        observed_goals: goals.filter((g) => g.status !== "missing").length, terminal_goals: goals.filter((g) => g.terminal).length,
        status_counts: Object.fromEntries([...STATUS, "missing"].map((s) => [s, goals.filter((g) => g.status === s).length])) }];
    })),
    limits: ["Collector declarations are not authenticated execution or physical isolation.",
      "No answer grading, billing completeness, statistical inference or capability improvement is established.",
      "Repetitions, goals, agents and checkpoints do not increase the independent family count.",
      "Family IDs declare clusters; content disjointness and statistical independence require external audit.",
      "Missing or nonterminal rows remain visible; collection closure never converts them to failures or successes."],
    streams: rows
  };
}
