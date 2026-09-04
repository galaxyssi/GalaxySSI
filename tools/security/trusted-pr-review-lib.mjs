const POLICY_SCHEMA = "galaxyssi.trusted-pr-review.v1";

function clean(value) {
  return String(value ?? "").trim();
}

function normalized(value) {
  return clean(value).toLowerCase();
}

function uniqueStrings(values, label) {
  if (!Array.isArray(values)) {
    throw new Error(`${label} must be an array`);
  }
  const result = [...new Set(values.map(normalized).filter(Boolean))];
  if (result.length === 0) {
    throw new Error(`${label} must not be empty`);
  }
  return result;
}

export function validateTrustedReviewPolicy(value) {
  if (!value || typeof value !== "object" || value.schema !== POLICY_SCHEMA) {
    throw new Error(`Trusted review policy must use schema ${POLICY_SCHEMA}`);
  }
  return {
    schema: POLICY_SCHEMA,
    trusted_bot_logins: uniqueStrings(value.trusted_bot_logins, "trusted_bot_logins"),
    required_checks: uniqueStrings(value.required_checks, "required_checks"),
    passing_conclusions: uniqueStrings(value.passing_conclusions, "passing_conclusions"),
    ignored_checks: Array.isArray(value.ignored_checks)
      ? [...new Set(value.ignored_checks.map(normalized).filter(Boolean))]
      : [],
    require_current_head: value.require_current_head !== false
  };
}

export function evaluateCiState(policyValue, checkRuns = [], statuses = []) {
  const policy = validateTrustedReviewPolicy(policyValue);
  const passing = new Set(policy.passing_conclusions);
  const ignored = new Set(policy.ignored_checks);
  const observedRuns = (Array.isArray(checkRuns) ? checkRuns : [])
    .filter((run) => !ignored.has(normalized(run?.name)));
  const observedStatuses = (Array.isArray(statuses) ? statuses : [])
    .filter((status) => !ignored.has(normalized(status?.context)));
  const missing = [];
  const pending = [];
  const failing = [];

  for (const requiredName of policy.required_checks) {
    const matching = observedRuns.filter((run) => normalized(run?.name) === requiredName);
    if (matching.length === 0) {
      missing.push(requiredName);
    }
  }

  for (const run of observedRuns) {
    const name = clean(run?.name) || "unnamed-check";
    const status = normalized(run?.status);
    const conclusion = normalized(run?.conclusion);
    if (status !== "completed" || !conclusion) {
      pending.push(name);
    } else if (!passing.has(conclusion)) {
      failing.push(`${name}:${conclusion}`);
    }
  }

  for (const status of observedStatuses) {
    const name = clean(status?.context) || "unnamed-status";
    const state = normalized(status?.state);
    if (state === "pending" || !state) {
      pending.push(name);
    } else if (state !== "success") {
      failing.push(`${name}:${state}`);
    }
  }

  return {
    green: missing.length === 0 && pending.length === 0 && failing.length === 0,
    missing: [...new Set(missing)].sort(),
    pending: [...new Set(pending)].sort(),
    failing: [...new Set(failing)].sort(),
    observed_checks: observedRuns.length + observedStatuses.length
  };
}

export function evaluateTrustedAutomationReview({
  policy: policyValue,
  review,
  pullRequest,
  checkRuns = [],
  statuses = []
}) {
  const policy = validateTrustedReviewPolicy(policyValue);
  const state = normalized(review?.state);
  const login = normalized(review?.user?.login);
  const actorType = clean(review?.user?.type);

  if (state !== "approved") {
    return {
      applicable: false,
      allowed: true,
      code: "review_not_approved",
      reviewer: login,
      ci: null
    };
  }
  if (actorType !== "Bot") {
    return {
      applicable: false,
      allowed: true,
      code: "human_review",
      reviewer: login,
      ci: null
    };
  }
  if (!policy.trusted_bot_logins.includes(login)) {
    return {
      applicable: true,
      allowed: false,
      code: "untrusted_bot",
      reviewer: login,
      ci: null
    };
  }

  const reviewCommit = normalized(review?.commit_id);
  const headCommit = normalized(pullRequest?.head?.sha);
  if (policy.require_current_head && (!reviewCommit || !headCommit || reviewCommit !== headCommit)) {
    return {
      applicable: true,
      allowed: false,
      code: "stale_review",
      reviewer: login,
      ci: null
    };
  }

  const ci = evaluateCiState(policy, checkRuns, statuses);
  return {
    applicable: true,
    allowed: ci.green,
    code: ci.green ? "trusted_review" : "ci_not_green",
    reviewer: login,
    ci
  };
}
