function asArray(value) {
  return Array.isArray(value) ? value : [];
}

export function evaluateMemoryLoCoMo(raw, minimumScore = 0.95) {
  if (!raw || Number(raw.schema_version) !== 1) {
    throw new Error("Memory LoCoMo result must use schema_version 1");
  }
  const results = asArray(raw.results);
  if (results.length === 0) {
    throw new Error("Memory LoCoMo result has no queries");
  }
  const assertions = results.flatMap((result) => (
    asArray(result.assertions).map((item) => ({
      ...item,
      query_id: result.query_id,
      category: result.category
    }))
  ));
  const passedAssertions = assertions.filter((item) => item.passed === true).length;
  const score = assertions.length > 0 ? passedAssertions / assertions.length : 0;
  const exclusionAssertions = assertions.filter((item) => item.type === "exclude");
  const emptyAssertions = assertions.filter((item) => item.type === "empty");
  const privacyResults = results.filter((item) => item.category === "privacy");
  const categoryScores = Object.fromEntries(
    [...new Set(results.map((result) => result.category))].map((category) => {
      const categoryAssertions = assertions.filter((item) => item.category === category);
      const passed = categoryAssertions.filter((item) => item.passed === true).length;
      return [category, categoryAssertions.length > 0 ? passed / categoryAssertions.length : 0];
    })
  );
  const criticalFailures = assertions
    .filter((item) => item.passed !== true)
    .filter((item) => (
      item.type === "exclude" ||
      item.type === "empty" ||
      item.category === "privacy" ||
      item.category === "conversation_scope"
    ))
    .map((item) => `${item.query_id}:${item.type}`);
  return {
    schema_version: 1,
    benchmark_id: raw.benchmark_id,
    scenario_count: results.length,
    passed_scenarios: results.filter((result) => result.passed === true).length,
    score,
    minimum_score: minimumScore,
    retrieval_recall: scoreFor(assertions.filter((item) => item.type === "include")),
    contamination_avoidance: scoreFor(exclusionAssertions),
    abstention_accuracy: scoreFor(emptyAssertions),
    privacy_accuracy: scoreFor(
      privacyResults.flatMap((result) => asArray(result.assertions))
    ),
    temporal_accuracy: averageCategories(categoryScores, ["temporal", "correction"]),
    category_scores: categoryScores,
    critical_failures: criticalFailures,
    passed: score >= minimumScore && criticalFailures.length === 0,
    results
  };
}

function scoreFor(assertions) {
  return assertions.length > 0
    ? assertions.filter((item) => item.passed === true).length / assertions.length
    : 1;
}

function averageCategories(scores, categories) {
  const values = categories.filter((category) => category in scores).map((category) => scores[category]);
  return values.length > 0
    ? values.reduce((total, value) => total + value, 0) / values.length
    : 1;
}
