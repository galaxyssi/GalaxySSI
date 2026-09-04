import { evaluateBenchmark } from "./agent-benchmark-lib.mjs";

export const AGENT_REGRESSION_DSL_VERSION = "galaxyssi.agent-regression.v1";

const PHASES = new Set([
  "plan",
  "act",
  "observe",
  "replan",
  "verify",
  "finalize",
  "learn"
]);
const APPROVAL_STATES = new Set([
  "not_required",
  "required",
  "approved",
  "denied"
]);

function normalized(value) {
  return String(value ?? "").trim();
}

function array(value) {
  return Array.isArray(value) ? value : [];
}

function object(value, path) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${path} must be an object`);
  }
  return value;
}

function assertKeys(value, allowed, path) {
  const unknown = Object.keys(value).filter((key) => !allowed.has(key));
  if (unknown.length > 0) {
    throw new Error(`${path} has unknown fields: ${unknown.join(", ")}`);
  }
}

function uniqueStrings(value, path) {
  const values = array(value).map(normalized).filter(Boolean);
  if (values.length !== new Set(values).size) {
    throw new Error(`${path} must not contain duplicates`);
  }
  return values;
}

export function validateRegressionSuite(rawSuite) {
  const suite = object(rawSuite, "suite");
  assertKeys(
    suite,
    new Set(["dsl_version", "suite_id", "minimum_score", "cases"]),
    "suite"
  );
  if (suite.dsl_version !== AGENT_REGRESSION_DSL_VERSION) {
    throw new Error(`suite.dsl_version must be ${AGENT_REGRESSION_DSL_VERSION}`);
  }
  if (!normalized(suite.suite_id)) {
    throw new Error("suite.suite_id is required");
  }
  if (!Number.isFinite(Number(suite.minimum_score))) {
    throw new Error("suite.minimum_score must be numeric");
  }
  const cases = array(suite.cases);
  if (cases.length === 0 || cases.length > 500) {
    throw new Error("suite.cases must contain 1 to 500 cases");
  }
  const identifiers = new Set();
  for (const [index, rawCase] of cases.entries()) {
    const path = `suite.cases[${index}]`;
    const regressionCase = object(rawCase, path);
    assertKeys(
      regressionCase,
      new Set([
        "id",
        "category",
        "description",
        "weight",
        "live_safe",
        "input",
        "expect"
      ]),
      path
    );
    const identifier = normalized(regressionCase.id);
    if (!identifier || identifiers.has(identifier)) {
      throw new Error(`${path}.id is missing or duplicated: ${identifier}`);
    }
    identifiers.add(identifier);
    if (!normalized(regressionCase.category)) {
      throw new Error(`${path}.category is required`);
    }
    const input = object(regressionCase.input, `${path}.input`);
    assertKeys(
      input,
      new Set([
        "prompt",
        "response_language",
        "client_route_id",
        "conversation_id",
        "task_id",
        "turn_id",
        "attachments",
        "context"
      ]),
      `${path}.input`
    );
    if (!normalized(input.prompt)) {
      throw new Error(`${path}.input.prompt is required`);
    }
    const expect = object(regressionCase.expect, `${path}.expect`);
    assertKeys(
      expect,
      new Set(["plan", "tools", "result", "safety", "isolation", "timeline"]),
      `${path}.expect`
    );
    const plan = object(expect.plan ?? {}, `${path}.expect.plan`);
    assertKeys(
      plan,
      new Set(["ordered_phases", "required_steps"]),
      `${path}.expect.plan`
    );
    const phases = uniqueStrings(
      plan.ordered_phases,
      `${path}.expect.plan.ordered_phases`
    );
    const invalidPhases = phases.filter((phase) => !PHASES.has(phase));
    if (invalidPhases.length > 0) {
      throw new Error(`${path}.expect.plan has invalid phases: ${invalidPhases.join(", ")}`);
    }
    uniqueStrings(plan.required_steps, `${path}.expect.plan.required_steps`);

    const tools = object(expect.tools ?? {}, `${path}.expect.tools`);
    assertKeys(
      tools,
      new Set(["required", "forbidden", "ordered"]),
      `${path}.expect.tools`
    );
    const requiredTools = uniqueStrings(tools.required, `${path}.expect.tools.required`);
    const forbiddenTools = uniqueStrings(tools.forbidden, `${path}.expect.tools.forbidden`);
    const overlap = requiredTools.filter((tool) => forbiddenTools.includes(tool));
    if (overlap.length > 0) {
      throw new Error(`${path}.expect.tools required/forbidden overlap: ${overlap.join(", ")}`);
    }
    const orderedTools = uniqueStrings(tools.ordered, `${path}.expect.tools.ordered`);
    const undeclaredOrderedTools = orderedTools.filter((tool) => !requiredTools.includes(tool));
    if (undeclaredOrderedTools.length > 0) {
      throw new Error(
        `${path}.expect.tools.ordered must also be required: ${undeclaredOrderedTools.join(", ")}`
      );
    }

    const result = object(expect.result, `${path}.expect.result`);
    assertKeys(
      result,
      new Set([
        "terminal_states",
        "response",
        "max_final_responses",
        "max_duration_ms",
        "latency_is_critical",
        "min_recoveries",
        "min_artifacts"
      ]),
      `${path}.expect.result`
    );
    if (uniqueStrings(result.terminal_states, `${path}.expect.result.terminal_states`).length === 0) {
      throw new Error(`${path}.expect.result.terminal_states is required`);
    }
    const response = object(result.response ?? {}, `${path}.expect.result.response`);
    assertKeys(
      response,
      new Set(["min_chars", "max_chars", "required_all", "required_any", "forbidden"]),
      `${path}.expect.result.response`
    );

    const safety = object(expect.safety ?? {}, `${path}.expect.safety`);
    assertKeys(safety, new Set(["approval"]), `${path}.expect.safety`);
    if (
      safety.approval !== undefined &&
      !APPROVAL_STATES.has(normalized(safety.approval))
    ) {
      throw new Error(`${path}.expect.safety.approval is invalid`);
    }
    const isolation = object(expect.isolation ?? {}, `${path}.expect.isolation`);
    assertKeys(isolation, new Set(["correlation"]), `${path}.expect.isolation`);
    const timeline = object(expect.timeline ?? {}, `${path}.expect.timeline`);
    assertKeys(timeline, new Set(["monotonic"]), `${path}.expect.timeline`);
  }
  return suite;
}

export function compileRegressionSuite(rawSuite) {
  const suite = validateRegressionSuite(rawSuite);
  return {
    schema_version: 1,
    benchmark_id: suite.suite_id,
    minimum_score: Number(suite.minimum_score),
    required_categories: [...new Set(suite.cases.map((item) => item.category))],
    scenarios: suite.cases.map((item) => {
      const plan = item.expect.plan ?? {};
      const tools = item.expect.tools ?? {};
      const result = item.expect.result;
      return {
        id: item.id,
        category: item.category,
        description: item.description ?? "",
        weight: Number(item.weight ?? 1),
        live_safe: Boolean(item.live_safe),
        request: { ...item.input },
        minimum_score: 1,
        expect: {
          terminal_states: array(result.terminal_states),
          required_phases: array(plan.ordered_phases),
          ordered_phases: array(plan.ordered_phases),
          required_plan_steps: array(plan.required_steps),
          required_tools: array(tools.required),
          forbidden_tools: array(tools.forbidden),
          ordered_tools: array(tools.ordered),
          response: { ...(result.response ?? {}) },
          approval: item.expect.safety?.approval,
          correlation: item.expect.isolation?.correlation === true,
          monotonic_timeline: item.expect.timeline?.monotonic === true,
          max_final_responses: result.max_final_responses,
          max_duration_ms: result.max_duration_ms,
          latency_is_critical: result.latency_is_critical,
          min_recoveries: result.min_recoveries,
          min_artifacts: result.min_artifacts
        }
      };
    })
  };
}

export function evaluateRegressionSuite(suite, results, options = {}) {
  const compiled = compileRegressionSuite(suite);
  const report = evaluateBenchmark(compiled, results, {
    minimum_score: options.minimum_score ?? compiled.minimum_score
  });
  return {
    ...report,
    dsl_version: AGENT_REGRESSION_DSL_VERSION,
    suite_id: compiled.benchmark_id
  };
}
