import assert from "node:assert/strict";
import test from "node:test";
import { buildPr2627To2633Corpus, profiles, suites } from "./pr2627-2633-regression-corpus.mjs";

test("PR 2627-2633 corpus contains 1000 targeted and traceable cases", () => {
  const corpus = buildPr2627To2633Corpus();
  const cases = corpus.cases;

  assert.equal(cases.length, 1000);
  assert.equal(corpus.exact_conversation_count, 1000);
  assert.equal(suites.length, 50);
  assert.equal(profiles.length, 20);
  assert.equal(new Set(cases.map((item) => item.id)).size, cases.length);
  assert.equal(new Set(cases.map((item) => item.title)).size, cases.length);
  assert.equal(new Set(cases.map((item) => item.risk)).size, cases.length);
  assert.equal(new Set(cases.map((item) => item.risk_id)).size, cases.length);
  assert.equal(new Set(cases.map((item) => item.risk_zh)).size, cases.length);
  assert.equal(new Set(cases.map((item) => item.conversation_id)).size, cases.length);
  assert.equal(new Set(cases.map((item) => item.title_zh)).size, cases.length);
  assert.deepEqual(cases.map((item) => item.ordinal), Array.from({ length: 1000 }, (_, index) => index + 1));
  assert.deepEqual(
    [...new Set(cases.map((item) => item.pr))].sort(),
    [2627, 2628, 2629, 2630, 2631, 2632, 2633]
  );
  assert.ok(new Set(cases.map((item) => item.category)).size >= 20);
  assert.ok(new Set(cases.map((item) => item.oracle)).size >= 15);
  assert.ok(cases.every((item) => item.steps.length === 3));
  assert.ok(cases.every((item) => item.expected.length === 3));
  assert.ok(cases.every((item) => item.preconditions_zh.length === 3));
  assert.ok(cases.every((item) => item.steps_zh.length === 3));
  assert.ok(cases.every((item) => item.expected_zh.length === 3));
  assert.ok(cases.every((item) => item.verification.automated === true));
});

test("every risk suite is exercised by all non-equivalent profiles", () => {
  const cases = buildPr2627To2633Corpus().cases;
  for (const suite of suites) {
    const selected = cases.filter((item) => item.suite_id === suite.id);
    assert.equal(selected.length, 20, suite.id);
    assert.equal(new Set(selected.map((item) => item.profile_id)).size, 20, suite.id);
    assert.equal(new Set(selected.map((item) => item.expected.join("\n"))).size, 20, suite.id);
  }
});
