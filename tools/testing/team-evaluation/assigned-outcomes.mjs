const UNKNOWN = "UNKNOWN";
const RESOURCES = ["wall_time_ms", "total_tokens", "cost_micros", "rework_count", "intervention_count"];
const ACCOUNTING_REASONS = new Set(["total_budget_enforcement_unverified",
  ...RESOURCES.flatMap((key) => [`unknown_${key}`, `over_budget_${key}`])]);

function bounded(value, reason) {
  return { value, lower: value === UNKNOWN ? 0 : value, upper: value === UNKNOWN ? 1 : value, reason };
}

// This is an observed policy endpoint, not a counterfactual estimate of what a
// trial that exceeded its cap could have achieved with less computation.
export function assignedOutcome(record) {
  const reasons = record.exclusion_reasons;
  if (reasons.some((reason) => !ACCOUNTING_REASONS.has(reason))) {
    return bounded(UNKNOWN, "outcome_or_assignment_unverified");
  }
  if (record.quality.passed === false) return bounded(0, "verified_noncompletion");
  if (record.quality.passed !== true) return bounded(UNKNOWN, "outcome_unverified");
  if (reasons.some((reason) => reason.startsWith("over_budget_"))) {
    return bounded(0, "completed_outside_assigned_budget");
  }
  if (reasons.length) return bounded(UNKNOWN, "budget_compliance_unverified");
  return bounded(1, "verified_completion_within_budget");
}

function summarize(outcomes) {
  const count = outcomes.length;
  const sum = (key) => outcomes.reduce((total, outcome) => total + outcome[key], 0);
  const unknown = outcomes.filter((outcome) => outcome.value === UNKNOWN).length;
  return {
    scheduled: count, known: count - unknown, unknown,
    mean: count && !unknown ? sum("lower") / count : UNKNOWN,
    lower: count ? sum("lower") / count : UNKNOWN,
    upper: count ? sum("upper") / count : UNKNOWN
  };
}

export function assignedSummary(records, pairs) {
  const bySlot = new Map(records.map((record) => [record.slot_id, assignedOutcome(record)]));
  const arms = Object.fromEntries(["A", "B"].map((arm) => {
    const outcomes = records.filter((record) => record.arm_label === arm).map((record) => bySlot.get(record.slot_id));
    return [arm, { ...summarize(outcomes),
      verified_successes: outcomes.filter((outcome) => outcome.value === 1).length,
      verified_policy_failures: outcomes.filter((outcome) => outcome.value === 0).length }];
  }));
  const paired = pairs.map((pair) => {
    const a = bySlot.get(pair.slot_A);
    const b = bySlot.get(pair.slot_B);
    return { pair_id: pair.pair_id,
      value: a.value === UNKNOWN || b.value === UNKNOWN ? UNKNOWN : b.value - a.value,
      lower: b.lower - a.upper, upper: b.upper - a.lower };
  });
  return {
    endpoint: "verified_completion_within_assigned_budget",
    denominator: "all_scheduled_slots_per_arm",
    bounds_kind: "worst_case_missing_outcome_bounds_not_confidence_intervals",
    point_estimate_requires_all_outcomes_known: true,
    arms, paired_delta_B_minus_A: summarize(paired),
    outcomes: records.map((record) => ({ slot_id: record.slot_id, ...bySlot.get(record.slot_id) })),
    pairs: paired
  };
}
