import { createHash, randomBytes } from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import { digest } from "../team-evaluation/lib.mjs";

export { digest };
export const PROTOCOL_VERSION = 1;
export const ARMS = Object.freeze(["S0", "S1", "T00", "T10", "T01", "T11"]);
export const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
export const text = (v) => typeof v === "string" && v.trim().length > 0;
export const hash = (v) => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
export const integer = (v) => Number.isSafeInteger(v) && v >= 0;
export function requireThat(ok, message) { if (!ok) throw new Error(message); }
export function exactKeys(value, keys, name) {
  requireThat(object(value) && isDeepStrictEqual(Object.keys(value).sort(), [...keys].sort()),
    `${name}: unexpected or missing fields`);
}
function id(value, name) {
  requireThat(typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value), `${name}: invalid ID`);
}

export function armPolicy(arm, teamSize) {
  requireThat(ARMS.includes(arm), "Unknown arm");
  return {
    members: arm.startsWith("S") ? 1 : teamSize,
    communication: arm.startsWith("S") ? null : arm[1] === "1",
    persistence: arm.endsWith("1")
  };
}

export function validateConfig(config) {
  exactKeys(config, ["study_id", "evidence_kind", "team_size", "repetitions", "controls", "stream_budget", "families"], "config");
  id(config.study_id, "study_id");
  requireThat(["fixture", "actual"].includes(config.evidence_kind), "Explicit evidence_kind required");
  requireThat(integer(config.team_size) && config.team_size >= 2, "team_size must be at least two");
  requireThat(integer(config.repetitions) && config.repetitions > 0, "repetitions must be positive");
  exactKeys(config.controls, ["model_policy_sha256", "tool_policy_sha256", "permission_policy_sha256", "initial_state_sha256", "evaluator_sha256", "outage_policy_sha256"], "controls");
  for (const [key, value] of Object.entries(config.controls)) requireThat(hash(value), `Invalid control digest: ${key}`);
  exactKeys(config.stream_budget, ["max_wall_time_ms", "max_model_requests", "max_total_tokens", "max_cost_micros", "currency"], "stream_budget");
  requireThat(config.stream_budget.currency === "USD", "Cost unit is USD micro-units");
  for (const [key, value] of Object.entries(config.stream_budget)) {
    if (key !== "currency") requireThat(integer(value) && value > 0, `Invalid shared stream cap: ${key}`);
  }
  requireThat(Array.isArray(config.families) && config.families.length > 0, "At least one family required");
  const familyIds = new Set(), requests = new Set();
  for (const family of config.families) {
    exactKeys(family, ["family_id", "domain", "goals"], "family");
    id(family.family_id, "family_id"); id(family.domain, "domain");
    requireThat(!familyIds.has(family.family_id), "Duplicate family_id"); familyIds.add(family.family_id);
    requireThat(Array.isArray(family.goals) && family.goals.length >= 2, "A longitudinal stream needs at least two ordered goals");
    const goalIds = new Set();
    for (const goal of family.goals) {
      exactKeys(goal, ["goal_id", "request", "success_contract_sha256", "perturbation_sha256"], "goal");
      id(goal.goal_id, "goal_id");
      requireThat(!goalIds.has(goal.goal_id), "Duplicate goal_id in family"); goalIds.add(goal.goal_id);
      exactKeys(goal.request, ["prompt", "input_sha256"], "request");
      requireThat(text(goal.request.prompt) && hash(goal.request.input_sha256), "Invalid request");
      requireThat(hash(goal.success_contract_sha256) && hash(goal.perturbation_sha256), "Invalid goal contract digest");
      // Exact duplicates cannot silently become extra independent task families.
      const requestHash = digest(goal.request);
      requireThat(!requests.has(requestHash), "Duplicate request across scheduled goals"); requests.add(requestHash);
    }
  }
  return config;
}

function generator(seed) {
  let counter = 0;
  return (max) => {
    requireThat(Number.isSafeInteger(max) && max > 0 && max <= 0x100000000, "Invalid shuffle range");
    const threshold = Math.floor(0x100000000 / max) * max;
    let value;
    do { value = createHash("sha256").update(`${seed}:${counter++}`).digest().readUInt32BE(); }
    while (value >= threshold);
    return value % max;
  };
}
function shuffled(values, next) {
  const result = [...values];
  for (let i = result.length - 1; i > 0; i--) {
    const j = next(i + 1); [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}

function schedule(config, seed) {
  const next = generator(seed), configHash = digest(config);
  const blocks = config.families.flatMap((family) => Array.from({ length: config.repetitions }, (_, repetition) => ({ family, repetition })));
  const streams = [];
  for (const { family, repetition } of shuffled(blocks, next)) {
    const blockId = digest({ configHash, seed, family: family.family_id, repetition });
    for (const arm of shuffled(ARMS, next)) {
      const streamId = digest({ blockId, arm });
      streams.push({
        stream_id: streamId, block_id: blockId, family_id: family.family_id, domain: family.domain,
        repetition, arm, order: streams.length, policy: armPolicy(arm, config.team_size),
        state_namespace: `stream-${streamId}`,
        goals: family.goals.map((goal, index) => ({
          slot_id: digest({ streamId, index }), goal_id: goal.goal_id, index,
          request_sha256: digest(goal.request), success_contract_sha256: goal.success_contract_sha256,
          perturbation_sha256: goal.perturbation_sha256
        }))
      });
    }
  }
  return streams;
}

export function createPlan(config, seed = randomBytes(32).toString("hex")) {
  validateConfig(config);
  requireThat(hash(seed), "Randomization seed must be a 256-bit hex value");
  const plan = {
    schema_version: PROTOCOL_VERSION, protocol: "six_arm_longitudinal", evidence_kind: config.evidence_kind,
    config: structuredClone(config), randomization_seed: seed, config_sha256: digest(config), streams: schedule(config, seed)
  };
  return { ...plan, plan_sha256: digest(plan) };
}

export function validatePlan(plan) {
  exactKeys(plan, ["schema_version", "protocol", "evidence_kind", "config", "randomization_seed", "config_sha256", "streams", "plan_sha256"], "plan");
  requireThat(plan.schema_version === PROTOCOL_VERSION && plan.protocol === "six_arm_longitudinal", "Unsupported protocol version");
  validateConfig(plan.config);
  requireThat(hash(plan.randomization_seed), "Invalid randomization seed");
  requireThat(plan.evidence_kind === plan.config.evidence_kind, "Evidence kind drift");
  requireThat(plan.config_sha256 === digest(plan.config), "Config digest mismatch");
  const { plan_sha256: expected, ...payload } = plan;
  requireThat(hash(expected) && digest(payload) === expected, "Plan digest mismatch");
  requireThat(isDeepStrictEqual(plan.streams, schedule(plan.config, plan.randomization_seed)), "Frozen schedule or state namespace changed");
  return plan;
}

export function collectorRequests(plan) {
  validatePlan(plan);
  return {
    schema_version: PROTOCOL_VERSION, plan_sha256: plan.plan_sha256, evidence_kind: plan.evidence_kind,
    scope: "collector_only_not_a_blinded_reviewer_packet",
    warning: "Run one entire stream budget, including adaptation, all members, retries and finalization. Hashes do not enforce isolation or authenticate capture.",
    streams: plan.streams.map((stream) => ({
      ...structuredClone(stream), controls: structuredClone(plan.config.controls),
      shared_stream_budget: structuredClone(plan.config.stream_budget),
      goals: stream.goals.map((goal) => ({ ...goal,
        request: structuredClone(plan.config.families.find((f) => f.family_id === stream.family_id).goals[goal.index].request) }))
    }))
  };
}
