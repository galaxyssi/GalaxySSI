const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../src/renderer/workspace.js"), "utf8");
const renderSource = source.slice(source.indexOf("function renderTurn(task)"), source.indexOf("function renderConversation("));
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const context = vm.createContext({
  TERMINAL_STATES: new Set(["completed", "failed", "cancelled", "timed_out"]),
  escapeHtml, t: (value) => value, renderMarkdown: escapeHtml,
  renderTaskOutput: (_task, text) => escapeHtml(text), renderArtifacts: () => "",
  renderRecoveryActions: () => "", renderLatencySummary: () => "", renderTaskEvent: () => "",
  taskExecutionView: () => ({}), agentName: () => "Codex", statusLabel: (status) => status,
  taskStatusLabel: (task) => task.status, formatDuration: () => "1s", taskElapsed: () => 1,
});
vm.runInContext(renderSource, context);

test("running turn renders user-visible output before completion without final controls", () => {
  const html = context.renderTurn({ task_id: "a", status: "running", partial_result: { user_visible: true, text: "Early answer" } });
  assert.match(html, /partial-answer/);
  assert.match(html, /Early answer/);
  assert.doesNotMatch(html, /data-speak-task|Task completed/);
});

test("final and failed outcomes replace partial output", () => {
  for (const status of ["completed", "failed", "cancelled", "timed_out"]) {
    const html = context.renderTurn({ task_id: "a", status, result: "Final answer", partial_result: { user_visible: true, text: "Old draft" } });
    assert.match(html, /Final answer/);
    assert.doesNotMatch(html, /Old draft|partial-answer/);
  }
});

test("private progress is not rendered as an answer", () => {
  const html = context.renderTurn({ task_id: "a", status: "running", partial_result: { user_visible: false, text: "Internal data" } });
  assert.doesNotMatch(html, /Internal data|partial-answer/);
});

test("partial output uses existing safe renderer and participates in refresh signature", () => {
  const html = context.renderTurn({ task_id: "a", status: "running", partial_result: { user_visible: true, text: "<script>bad</script>" } });
  assert.doesNotMatch(html, /<script>/);
  const signature = source.slice(source.indexOf("const signature = JSON.stringify(tasks.map"));
  assert.match(signature, /task\.partial_result\?\.sequence/);
  assert.match(signature, /task\.partial_result\?\.text/);
});
