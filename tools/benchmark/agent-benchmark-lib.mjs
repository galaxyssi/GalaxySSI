import fs from "node:fs";

const TERMINAL_STATES = new Set([
  "cancelled",
  "completed",
  "failed",
  "interrupted",
  "partial"
]);

const PHASE_PATTERNS = new Map([
  ["plan", /\b(plan|planning|intent|route|queued)\b/i],
  ["act", /\b(act|acting|execute|executing|run|running|tool|started)\b/i],
  ["observe", /\b(observe|observing|observation|result|evidence)\b/i],
  ["replan", /\b(replan|retry|recover|fallback|reroute)\b/i],
  ["verify", /\b(verify|verifying|validation|validated|check)\b/i],
  ["finalize", /\b(final|finalize|finalizing|complete|completed|report)\b/i],
  ["learn", /\b(learn|learning|memory|skill)\b/i]
]);

function normalized(value) {
  return String(value ?? "").trim();
}

function normalizedLower(value) {
  return normalized(value).toLowerCase();
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function eventSearchText(event) {
  return [
    event.phase,
    event.type,
    event.kind,
    event.name,
    event.status,
    event.state,
    event.message
  ].map(normalized).filter(Boolean).join(" ");
}

export function canonicalEventPhase(event) {
  const explicit = normalizedLower(event?.phase);
  if (PHASE_PATTERNS.has(explicit)) {
    return explicit;
  }
  const text = eventSearchText(event || {});
  for (const [phase, pattern] of PHASE_PATTERNS) {
    if (pattern.test(text)) {
      return phase;
    }
  }
  return "";
}

function resultStatus(result) {
  return normalizedLower(result.status || result.state);
}

function resultResponse(result) {
  return normalized(
    result.response ??
    result.reply ??
    result.result ??
    result.final_response
  );
}

function resultDuration(result) {
  const direct = Number(result.duration_ms);
  if (Number.isFinite(direct) && direct >= 0) {
    return direct;
  }
  const started = Number(result.started_at_ms);
  const ended = Number(result.ended_at_ms);
  return Number.isFinite(started) && Number.isFinite(ended) && ended >= started
    ? ended - started
    : Number.POSITIVE_INFINITY;
}

function resultEvents(result) {
  return asArray(result.events).map((event) => (
    event && typeof event === "object" ? event : {}
  ));
}

function resultTools(result) {
  const explicit = asArray(result.tools).map((tool) => (
    typeof tool === "string" ? tool : tool?.name || tool?.tool_id || tool?.id
  ));
  const fromEvents = resultEvents(result).map((event) => (
    event.tool || event.tool_name || event.tool_id
  ));
  return new Set([...explicit, ...fromEvents].map(normalizedLower).filter(Boolean));
}

function resultToolSequence(result) {
  const fromEvents = resultEvents(result)
    .map((event) => event.tool || event.tool_name || event.tool_id)
    .map(normalizedLower)
    .filter(Boolean);
  if (fromEvents.length > 0) {
    return fromEvents;
  }
  return asArray(result.tools)
    .map((tool) => (
      typeof tool === "string" ? tool : tool?.name || tool?.tool_id || tool?.id
    ))
    .map(normalizedLower)
    .filter(Boolean);
}

function resultPlanText(result) {
  const explicit = Array.isArray(result.plan)
    ? result.plan
    : asArray(result.plan?.steps);
  const planRows = explicit.map((step) => (
    typeof step === "string"
      ? step
      : step?.title || step?.description || step?.action || step?.name
  ));
  const eventRows = resultEvents(result)
    .filter((event) => canonicalEventPhase(event) === "plan")
    .map((event) => event.message || event.title || event.name || event.action);
  return [...planRows, ...eventRows].map(normalizedLower).filter(Boolean).join("\n");
}

function isOrderedSubsequence(actual, expected) {
  let cursor = 0;
  for (const value of actual) {
    if (value === expected[cursor]) {
      cursor += 1;
      if (cursor === expected.length) {
        return true;
      }
    }
  }
  return expected.length === 0;
}

function resultArtifacts(result) {
  return asArray(result.artifacts).filter((artifact) => (
    artifact && typeof artifact === "object"
  ));
}

function resultApproval(result) {
  const direct = normalizedLower(result.approval);
  if (direct) {
    return direct;
  }
  for (const event of resultEvents(result)) {
    const candidate = normalizedLower(
      event.approval || event.approval_state || event.status
    );
    if (candidate.includes("approval") || candidate === "required" || candidate === "approved") {
      return candidate;
    }
  }
  return "";
}

function countFinalResponses(result) {
  const explicit = Number(result.final_response_count);
  if (Number.isInteger(explicit) && explicit >= 0) {
    return explicit;
  }
  return resultEvents(result).filter((event) => {
    const text = eventSearchText(event);
    return /\b(final_response|final answer|reply_published)\b/i.test(text);
  }).length || (resultResponse(result) ? 1 : 0);
}

function timelineIsMonotonic(events) {
  const timestamps = events
    .map((event) => Number(event.timestamp_ms ?? event.at_ms ?? event.created_at_ms))
    .filter(Number.isFinite);
  return timestamps.every((timestamp, index) => (
    index === 0 || timestamp >= timestamps[index - 1]
  ));
}

function assertion(name, passed, detail, critical = true) {
  return { name, passed: Boolean(passed), critical: Boolean(critical), detail };
}

function textMatches(response, expectation) {
  const lower = response.toLowerCase();
  const requiredAll = asArray(expectation.required_all).map(normalizedLower).filter(Boolean);
  const requiredAny = asArray(expectation.required_any).map(normalizedLower).filter(Boolean);
  const forbidden = asArray(expectation.forbidden).map(normalizedLower).filter(Boolean);
  return {
    all: requiredAll.every((token) => lower.includes(token)),
    any: requiredAny.length === 0 || requiredAny.some((token) => lower.includes(token)),
    forbidden: forbidden.filter((token) => lower.includes(token))
  };
}

function correlationMatches(request, result) {
  const correlation = result.correlation || result.scope || {};
  const fields = ["client_route_id", "conversation_id", "task_id", "turn_id"];
  const expected = fields.filter((field) => normalized(request[field]));
  const mismatches = expected.filter((field) => (
    normalized(correlation[field] ?? result[field]) !== normalized(request[field])
  ));
  return { expected, mismatches };
}

export function validateManifest(manifest) {
  if (!manifest || Number(manifest.schema_version) !== 1) {
    throw new Error("Agent benchmark manifest must use schema_version 1");
  }
  const scenarios = asArray(manifest.scenarios);
  if (scenarios.length === 0) {
    throw new Error("Agent benchmark manifest has no scenarios");
  }
  const identifiers = new Set();
  for (const scenario of scenarios) {
    const identifier = normalized(scenario.id);
    if (!identifier || identifiers.has(identifier)) {
      throw new Error(`Agent benchmark scenario ID is missing or duplicated: ${identifier}`);
    }
    identifiers.add(identifier);
    if (!normalized(scenario.category)) {
      throw new Error(`Agent benchmark scenario has no category: ${identifier}`);
    }
    if (!normalized(scenario.request?.prompt)) {
      throw new Error(`Agent benchmark scenario has no prompt: ${identifier}`);
    }
  }
  const categories = new Set(scenarios.map((scenario) => normalized(scenario.category)));
  const missing = asArray(manifest.required_categories).filter((category) => (
    !categories.has(normalized(category))
  ));
  if (missing.length > 0) {
    throw new Error(`Agent benchmark categories are missing: ${missing.join(", ")}`);
  }
  return manifest;
}

export function evaluateScenario(scenario, rawResult) {
  const result = rawResult || {};
  const expectation = scenario.expect || {};
  const response = resultResponse(result);
  const events = resultEvents(result);
  const phases = new Set(events.map(canonicalEventPhase).filter(Boolean));
  const phaseSequence = events.map(canonicalEventPhase).filter(Boolean);
  const tools = resultTools(result);
  const toolSequence = resultToolSequence(result);
  const artifacts = resultArtifacts(result);
  const assertions = [];

  const acceptedStates = asArray(expectation.terminal_states).map(normalizedLower);
  if (acceptedStates.length > 0) {
    const actual = resultStatus(result);
    assertions.push(assertion(
      "terminal_status",
      acceptedStates.includes(actual),
      `expected ${acceptedStates.join("|")}, received ${actual || "missing"}`
    ));
  }

  const responseExpectation = expectation.response || {};
  const minChars = Number(responseExpectation.min_chars ?? 0);
  const maxChars = Number(responseExpectation.max_chars ?? Number.POSITIVE_INFINITY);
  assertions.push(assertion(
    "response_length",
    response.length >= minChars && response.length <= maxChars,
    `${response.length} characters, expected ${minChars}-${Number.isFinite(maxChars) ? maxChars : "unbounded"}`
  ));
  const matches = textMatches(response, responseExpectation);
  assertions.push(assertion(
    "response_contract",
    matches.all && matches.any && matches.forbidden.length === 0,
    matches.forbidden.length > 0
      ? `forbidden text: ${matches.forbidden.join(", ")}`
      : "required and forbidden text rules"
  ));

  const requiredPhases = asArray(expectation.required_phases).map(normalizedLower);
  if (requiredPhases.length > 0) {
    const missing = requiredPhases.filter((phase) => !phases.has(phase));
    assertions.push(assertion(
      "run_phases",
      missing.length === 0,
      missing.length > 0 ? `missing ${missing.join(", ")}` : requiredPhases.join(", ")
    ));
  }

  const orderedPhases = asArray(expectation.ordered_phases).map(normalizedLower);
  if (orderedPhases.length > 0) {
    assertions.push(assertion(
      "phase_order",
      isOrderedSubsequence(phaseSequence, orderedPhases),
      `expected ${orderedPhases.join(" -> ")}, received ${phaseSequence.join(" -> ")}`
    ));
  }

  const requiredPlanSteps = asArray(expectation.required_plan_steps)
    .map(normalizedLower)
    .filter(Boolean);
  if (requiredPlanSteps.length > 0) {
    const planText = resultPlanText(result);
    const missing = requiredPlanSteps.filter((step) => !planText.includes(step));
    assertions.push(assertion(
      "plan_contract",
      missing.length === 0,
      missing.length > 0 ? `missing ${missing.join(", ")}` : requiredPlanSteps.join(", ")
    ));
  }

  const requiredTools = asArray(expectation.required_tools).map(normalizedLower);
  if (requiredTools.length > 0) {
    const missing = requiredTools.filter((tool) => !tools.has(tool));
    assertions.push(assertion(
      "required_tools",
      missing.length === 0,
      missing.length > 0 ? `missing ${missing.join(", ")}` : requiredTools.join(", ")
    ));
  }

  const forbiddenTools = asArray(expectation.forbidden_tools).map(normalizedLower);
  if (forbiddenTools.length > 0) {
    const found = forbiddenTools.filter((tool) => tools.has(tool));
    assertions.push(assertion(
      "forbidden_tools",
      found.length === 0,
      found.length > 0 ? `used ${found.join(", ")}` : "none used"
    ));
  }

  const orderedTools = asArray(expectation.ordered_tools).map(normalizedLower);
  if (orderedTools.length > 0) {
    assertions.push(assertion(
      "tool_order",
      isOrderedSubsequence(toolSequence, orderedTools),
      `expected ${orderedTools.join(" -> ")}, received ${toolSequence.join(" -> ")}`
    ));
  }

  if (expectation.approval) {
    const actual = resultApproval(result);
    const expected = normalizedLower(expectation.approval);
    assertions.push(assertion(
      "approval_policy",
      actual === expected,
      `expected ${expected}, received ${actual || "missing"}`
    ));
  }

  if (expectation.correlation === true) {
    const correlation = correlationMatches(scenario.request || {}, result);
    assertions.push(assertion(
      "correlation_isolation",
      correlation.expected.length > 0 && correlation.mismatches.length === 0,
      correlation.mismatches.length > 0
        ? `mismatched ${correlation.mismatches.join(", ")}`
        : correlation.expected.join(", ")
    ));
  }

  if (expectation.monotonic_timeline === true) {
    assertions.push(assertion(
      "timeline_order",
      events.length > 0 && timelineIsMonotonic(events),
      `${events.length} ordered events`
    ));
  }

  if (Number.isFinite(Number(expectation.max_final_responses))) {
    const actual = countFinalResponses(result);
    const maximum = Number(expectation.max_final_responses);
    assertions.push(assertion(
      "single_final_response",
      actual <= maximum,
      `${actual} final responses, maximum ${maximum}`
    ));
  }

  if (Number.isFinite(Number(expectation.max_duration_ms))) {
    const actual = resultDuration(result);
    const maximum = Number(expectation.max_duration_ms);
    assertions.push(assertion(
      "latency_budget",
      actual <= maximum,
      `${actual}ms, maximum ${maximum}ms`,
      Boolean(expectation.latency_is_critical)
    ));
  }

  if (Number.isFinite(Number(expectation.min_recoveries))) {
    const actual = Number(result.recovery_count ?? 0);
    const minimum = Number(expectation.min_recoveries);
    assertions.push(assertion(
      "recovery_path",
      actual >= minimum,
      `${actual} recoveries, minimum ${minimum}`
    ));
  }

  if (Number.isFinite(Number(expectation.min_artifacts))) {
    const minimum = Number(expectation.min_artifacts);
    assertions.push(assertion(
      "artifact_delivery",
      artifacts.length >= minimum && artifacts.every((artifact) => (
        normalized(artifact.name || artifact.path) &&
        normalized(artifact.sha256).length === 64
      )),
      `${artifacts.length} integrity-addressed artifacts, minimum ${minimum}`
    ));
  }

  const passedCount = assertions.filter((item) => item.passed).length;
  const score = assertions.length > 0 ? passedCount / assertions.length : 0;
  const criticalFailures = assertions.filter((item) => item.critical && !item.passed);
  return {
    id: scenario.id,
    category: scenario.category,
    score,
    passed: criticalFailures.length === 0 && score >= Number(scenario.minimum_score ?? 1),
    duration_ms: resultDuration(result),
    assertions
  };
}

export function evaluateBenchmark(manifestInput, resultInput, options = {}) {
  const manifest = validateManifest(manifestInput);
  const requestedIds = new Set(asArray(options.scenario_ids).map(normalized).filter(Boolean));
  const scenarios = requestedIds.size > 0
    ? manifest.scenarios.filter((scenario) => requestedIds.has(scenario.id))
    : manifest.scenarios;
  const results = new Map(asArray(resultInput.results ?? resultInput).map((result) => [
    normalized(result.scenario_id || result.id),
    result
  ]));
  const records = scenarios.map((scenario) => evaluateScenario(
    scenario,
    results.get(scenario.id)
  ));
  const weighted = records.reduce((total, record) => {
    const scenario = scenarios.find((item) => item.id === record.id);
    return total + record.score * Number(scenario?.weight ?? 1);
  }, 0);
  const weights = scenarios.reduce((total, scenario) => total + Number(scenario.weight ?? 1), 0);
  const score = weights > 0 ? weighted / weights : 0;
  const criticalFailures = records.flatMap((record) => (
    record.assertions
      .filter((item) => item.critical && !item.passed)
      .map((item) => `${record.id}:${item.name}`)
  ));
  const minimumScore = Number(options.minimum_score ?? manifest.minimum_score ?? 1);
  return {
    schema_version: 1,
    benchmark_id: manifest.benchmark_id,
    scenario_count: records.length,
    passed_count: records.filter((record) => record.passed).length,
    score,
    minimum_score: minimumScore,
    passed: score >= minimumScore && criticalFailures.length === 0,
    critical_failures: criticalFailures,
    category_scores: Object.fromEntries(
      [...new Set(records.map((record) => record.category))].map((category) => {
        const categoryRecords = records.filter((record) => record.category === category);
        return [
          category,
          categoryRecords.reduce((total, record) => total + record.score, 0) /
            categoryRecords.length
        ];
      })
    ),
    records
  };
}

export function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}
