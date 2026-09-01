const assert = require("node:assert/strict");
const test = require("node:test");
const { cases } = require("./android-agent-model-reply-cases");

test("SM-G9880 live Agent catalog contains 100 distinct targeted cases", () => {
  assert.equal(cases.length, 100);
  assert.equal(new Set(cases.map(item => item.id)).size, 100);
  assert.equal(new Set(cases.map(item => item.marker)).size, 100);
  assert.equal(new Set(cases.map(item => item.prompt)).size, 100);
  assert.deepEqual(
    [...new Set(cases.map(item => item.category))].sort(),
    [
      "coding",
      "conversation",
      "format",
      "instruction",
      "language",
      "planning",
      "reasoning",
      "robustness",
      "safety",
      "understanding",
      "web_search",
    ],
  );
  const webCases = cases.filter(item => item.category === "web_search");
  assert.equal(webCases.length, 6);
  for (const item of webCases) {
    assert.match(item.prompt, /必须联网/);
    assert.match(item.prompt, /(?:来源|链接)/);
  }
  for (const item of cases) {
    assert.match(item.id, /^\d{3}$/);
    assert.ok(item.prompt.includes(item.marker));
    assert.ok(item.prompt.length >= 35);
    assert.ok(item.requiredAny.length >= 1);
  }
});
