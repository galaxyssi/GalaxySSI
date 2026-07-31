import crypto from "node:crypto";

export const VERSION_HEALTH_SCHEMA_VERSION = 1;
export const VERSION_HEALTH_DIMENSIONS = Object.freeze([
  "performance",
  "reliability",
  "security",
  "ux",
  "memory_quality",
  "automation_success_rate"
]);

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

function text(value, path) {
  const normalized = String(value ?? "").trim();
  if (!normalized) {
    throw new Error(`${path} is required`);
  }
  return normalized;
}

function finite(value, path, minimum, maximum) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < minimum || number > maximum) {
    throw new Error(`${path} must be between ${minimum} and ${maximum}`);
  }
  return number;
}

function timestamp(value, path) {
  const normalized = text(value, path);
  const milliseconds = Date.parse(normalized);
  if (!Number.isFinite(milliseconds)) {
    throw new Error(`${path} must be an ISO-8601 timestamp`);
  }
  return { normalized, milliseconds };
}

function rounded(value) {
  return Number(Number(value).toFixed(6));
}

function stableValue(value) {
  if (Array.isArray(value)) {
    return value.map(stableValue);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, stableValue(value[key])])
    );
  }
  return value;
}

export function evidenceDigest(evidence) {
  return crypto
    .createHash("sha256")
    .update(JSON.stringify(stableValue(evidence)))
    .digest("hex");
}

export function validateVersionHealthPolicy(rawPolicy) {
  const policy = object(rawPolicy, "policy");
  assertKeys(
    policy,
    new Set([
      "schema_version",
      "policy_id",
      "minimum_overall_score",
      "max_evidence_age_hours",
      "grades",
      "dimensions"
    ]),
    "policy"
  );
  if (policy.schema_version !== VERSION_HEALTH_SCHEMA_VERSION) {
    throw new Error(`policy.schema_version must be ${VERSION_HEALTH_SCHEMA_VERSION}`);
  }
  text(policy.policy_id, "policy.policy_id");
  finite(policy.minimum_overall_score, "policy.minimum_overall_score", 0, 1);
  finite(policy.max_evidence_age_hours, "policy.max_evidence_age_hours", 1, 8760);

  const grades = Array.isArray(policy.grades) ? policy.grades : [];
  if (grades.length < 2) {
    throw new Error("policy.grades must contain at least two thresholds");
  }
  let previousThreshold = Number.POSITIVE_INFINITY;
  for (const [index, rawGrade] of grades.entries()) {
    const path = `policy.grades[${index}]`;
    const grade = object(rawGrade, path);
    assertKeys(grade, new Set(["label", "minimum_score"]), path);
    text(grade.label, `${path}.label`);
    const threshold = finite(grade.minimum_score, `${path}.minimum_score`, 0, 1);
    if (threshold >= previousThreshold) {
      throw new Error("policy.grades must be ordered from highest to lowest threshold");
    }
    previousThreshold = threshold;
  }
  if (Number(grades.at(-1).minimum_score) !== 0) {
    throw new Error("policy.grades must end with a zero threshold");
  }

  const dimensions = Array.isArray(policy.dimensions) ? policy.dimensions : [];
  const identifiers = dimensions.map((dimension) => String(dimension?.id ?? ""));
  if (
    dimensions.length !== VERSION_HEALTH_DIMENSIONS.length ||
    VERSION_HEALTH_DIMENSIONS.some((identifier) => !identifiers.includes(identifier))
  ) {
    throw new Error(
      `policy.dimensions must define exactly: ${VERSION_HEALTH_DIMENSIONS.join(", ")}`
    );
  }
  if (identifiers.length !== new Set(identifiers).size) {
    throw new Error("policy.dimensions must not contain duplicate identifiers");
  }
  let dimensionWeight = 0;
  const metricIdentifiers = new Set();
  for (const [index, rawDimension] of dimensions.entries()) {
    const path = `policy.dimensions[${index}]`;
    const dimension = object(rawDimension, path);
    assertKeys(
      dimension,
      new Set(["id", "label", "weight", "minimum_score", "critical", "metrics"]),
      path
    );
    text(dimension.label, `${path}.label`);
    dimensionWeight += finite(dimension.weight, `${path}.weight`, 0.000001, 1);
    finite(dimension.minimum_score, `${path}.minimum_score`, 0, 1);
    if (typeof dimension.critical !== "boolean") {
      throw new Error(`${path}.critical must be boolean`);
    }
    const metrics = Array.isArray(dimension.metrics) ? dimension.metrics : [];
    if (metrics.length === 0 || !metrics.some((metric) => metric?.required === true)) {
      throw new Error(`${path}.metrics must include at least one required metric`);
    }
    for (const [metricIndex, rawMetric] of metrics.entries()) {
      const metricPath = `${path}.metrics[${metricIndex}]`;
      const metric = object(rawMetric, metricPath);
      assertKeys(metric, new Set(["id", "weight", "required"]), metricPath);
      const identifier = text(metric.id, `${metricPath}.id`);
      if (metricIdentifiers.has(identifier)) {
        throw new Error(`policy metric is duplicated: ${identifier}`);
      }
      metricIdentifiers.add(identifier);
      finite(metric.weight, `${metricPath}.weight`, 0.000001, 1);
      if (typeof metric.required !== "boolean") {
        throw new Error(`${metricPath}.required must be boolean`);
      }
    }
  }
  if (Math.abs(dimensionWeight - 1) > 0.000001) {
    throw new Error(`policy dimension weights must total 1, received ${dimensionWeight}`);
  }
  return policy;
}

export function validateVersionHealthEvidence(rawEvidence) {
  const evidence = object(rawEvidence, "evidence");
  assertKeys(
    evidence,
    new Set([
      "schema_version",
      "evidence_id",
      "version",
      "generated_at",
      "fixture",
      "metrics"
    ]),
    "evidence"
  );
  if (evidence.schema_version !== VERSION_HEALTH_SCHEMA_VERSION) {
    throw new Error(`evidence.schema_version must be ${VERSION_HEALTH_SCHEMA_VERSION}`);
  }
  text(evidence.evidence_id, "evidence.evidence_id");
  text(evidence.version, "evidence.version");
  timestamp(evidence.generated_at, "evidence.generated_at");
  if (typeof evidence.fixture !== "boolean") {
    throw new Error("evidence.fixture must be boolean");
  }
  const metrics = Array.isArray(evidence.metrics) ? evidence.metrics : [];
  if (metrics.length === 0) {
    throw new Error("evidence.metrics must not be empty");
  }
  const identifiers = new Set();
  for (const [index, rawMetric] of metrics.entries()) {
    const path = `evidence.metrics[${index}]`;
    const metric = object(rawMetric, path);
    assertKeys(
      metric,
      new Set(["id", "dimension", "score", "measured_at", "source", "sample_size"]),
      path
    );
    const identifier = text(metric.id, `${path}.id`);
    if (identifiers.has(identifier)) {
      throw new Error(`evidence metric is duplicated: ${identifier}`);
    }
    identifiers.add(identifier);
    text(metric.dimension, `${path}.dimension`);
    finite(metric.score, `${path}.score`, 0, 1);
    timestamp(metric.measured_at, `${path}.measured_at`);
    text(metric.source, `${path}.source`);
    finite(metric.sample_size, `${path}.sample_size`, 1, Number.MAX_SAFE_INTEGER);
  }
  return evidence;
}

function gradeFor(policy, score) {
  return policy.grades.find((grade) => score >= Number(grade.minimum_score))?.label
    ?? policy.grades.at(-1).label;
}

function resolveEvaluationTime(evidence, options) {
  if (options.now !== undefined) {
    return timestamp(options.now, "options.now").milliseconds;
  }
  if (evidence.fixture) {
    return timestamp(evidence.generated_at, "evidence.generated_at").milliseconds;
  }
  return Date.now();
}

function evaluateSingle(rawPolicy, rawEvidence, options = {}) {
  const policy = validateVersionHealthPolicy(rawPolicy);
  const evidence = validateVersionHealthEvidence(rawEvidence);
  const now = resolveEvaluationTime(evidence, options);
  const maxAgeMs = Number(policy.max_evidence_age_hours) * 60 * 60 * 1000;
  const metricEvidence = new Map(evidence.metrics.map((metric) => [metric.id, metric]));
  const usedMetricIds = new Set();
  const failures = [];
  const dimensions = policy.dimensions.map((dimension) => {
    let weightedScore = 0;
    let includedWeight = 0;
    const metricRecords = dimension.metrics.map((definition) => {
      const metric = metricEvidence.get(definition.id);
      const weight = Number(definition.weight);
      if (!metric) {
        if (definition.required) {
          includedWeight += weight;
          failures.push(`${dimension.id}:${definition.id}:missing`);
        }
        return {
          id: definition.id,
          required: definition.required,
          weight,
          status: "missing",
          score: null,
          effective_score: definition.required ? 0 : null
        };
      }
      usedMetricIds.add(metric.id);
      if (metric.dimension !== dimension.id) {
        throw new Error(
          `evidence metric ${metric.id} belongs to ${metric.dimension}, expected ${dimension.id}`
        );
      }
      const measuredAt = timestamp(
        metric.measured_at,
        `evidence metric ${metric.id}.measured_at`
      ).milliseconds;
      if (measuredAt - now > 5 * 60 * 1000) {
        throw new Error(`evidence metric ${metric.id} is dated in the future`);
      }
      const stale = now - measuredAt > maxAgeMs;
      if (stale && definition.required) {
        failures.push(`${dimension.id}:${definition.id}:stale`);
      }
      if (definition.required || !stale) {
        includedWeight += weight;
        weightedScore += (stale ? 0 : Number(metric.score)) * weight;
      }
      return {
        id: definition.id,
        required: definition.required,
        weight,
        status: stale ? "stale" : "current",
        score: rounded(metric.score),
        effective_score: stale ? 0 : rounded(metric.score),
        measured_at: metric.measured_at,
        source: metric.source,
        sample_size: Number(metric.sample_size)
      };
    });
    const score = includedWeight > 0 ? weightedScore / includedWeight : 0;
    const evidenceComplete = metricRecords.every((metric) => (
      !metric.required || metric.status === "current"
    ));
    const passed = evidenceComplete && score >= Number(dimension.minimum_score);
    if (!passed && evidenceComplete) {
      failures.push(`${dimension.id}:below_minimum`);
    }
    return {
      id: dimension.id,
      label: dimension.label,
      critical: dimension.critical,
      weight: Number(dimension.weight),
      minimum_score: Number(dimension.minimum_score),
      score: rounded(score),
      passed,
      evidence_complete: evidenceComplete,
      metrics: metricRecords
    };
  });

  const unexpectedMetrics = evidence.metrics
    .filter((metric) => !usedMetricIds.has(metric.id))
    .map((metric) => metric.id);
  if (unexpectedMetrics.length > 0) {
    throw new Error(`evidence contains metrics not declared by policy: ${unexpectedMetrics.join(", ")}`);
  }
  const overallScore = dimensions.reduce(
    (total, dimension) => total + dimension.score * dimension.weight,
    0
  );
  const overallThresholdPassed = overallScore >= Number(policy.minimum_overall_score);
  if (!overallThresholdPassed) {
    failures.push("overall:below_minimum");
  }
  const passed = overallThresholdPassed && dimensions.every((dimension) => dimension.passed);
  return {
    schema_version: VERSION_HEALTH_SCHEMA_VERSION,
    score_id: policy.policy_id,
    evidence_id: evidence.evidence_id,
    evidence_digest: evidenceDigest(evidence),
    version: evidence.version,
    generated_at: new Date(now).toISOString(),
    fixture: evidence.fixture,
    overall_score: rounded(overallScore),
    minimum_overall_score: Number(policy.minimum_overall_score),
    grade: gradeFor(policy, overallScore),
    status: passed ? "healthy" : "blocked",
    passed,
    failures,
    dimensions
  };
}

export function evaluateVersionHealth(policy, evidence, options = {}) {
  const report = evaluateSingle(policy, evidence, options);
  if (!options.previousEvidence) {
    return report;
  }
  const previous = evaluateSingle(policy, options.previousEvidence, {
    now: options.previousEvidence.generated_at
  });
  const previousDimensions = new Map(
    previous.dimensions.map((dimension) => [dimension.id, dimension.score])
  );
  return {
    ...report,
    comparison: {
      previous_version: previous.version,
      previous_overall_score: previous.overall_score,
      overall_delta: rounded(report.overall_score - previous.overall_score),
      dimension_deltas: Object.fromEntries(
        report.dimensions.map((dimension) => [
          dimension.id,
          rounded(dimension.score - previousDimensions.get(dimension.id))
        ])
      )
    }
  };
}
