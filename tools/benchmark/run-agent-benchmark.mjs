#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  evaluateBenchmark,
  readJson,
  validateManifest
} from "./agent-benchmark-lib.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const defaults = {
  manifest: path.join(root, "benchmarks", "agent", "manifest.json"),
  results: path.join(root, "benchmarks", "agent", "reference-results.json"),
  output: path.join(root, "build", "reports", "agent-benchmark", "report.json"),
  liveUrl: "",
  agent: "codex",
  token: "",
  includeSensitive: false,
  timeoutMs: 180_000
};

function parseArgs(argv) {
  const options = { ...defaults };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[index + 1];
    if (argument === "--manifest" && value) {
      options.manifest = path.resolve(value);
      index += 1;
    } else if (argument === "--results" && value) {
      options.results = path.resolve(value);
      index += 1;
    } else if (argument === "--output" && value) {
      options.output = path.resolve(value);
      index += 1;
    } else if (argument === "--live-url" && value) {
      options.liveUrl = value.replace(/\/+$/, "");
      index += 1;
    } else if (argument === "--agent" && value) {
      options.agent = value;
      index += 1;
    } else if (argument === "--token" && value) {
      options.token = value;
      index += 1;
    } else if (argument === "--timeout-ms" && value) {
      options.timeoutMs = Math.max(1_000, Number(value));
      index += 1;
    } else if (argument === "--include-sensitive") {
      options.includeSensitive = true;
    } else if (argument === "--help") {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown or incomplete argument: ${argument}`);
    }
  }
  return options;
}

function printHelp() {
  console.log(`GalaxySSI Agent benchmark

Usage:
  npm run benchmark:agent
  npm run benchmark:agent -- --results <captured-results.json>
  npm run benchmark:agent -- --live-url http://127.0.0.1:8765 --agent codex

Options:
  --manifest <path>       Scenario manifest
  --results <path>        Captured or replay result set
  --output <path>         Machine-readable report path
  --live-url <url>        Run safe scenarios through Desktop Agent Runtime
  --agent <id>            Live Agent adapter ID
  --token <token>         Optional Desktop API bearer token
  --timeout-ms <number>   Per-scenario live timeout
  --include-sensitive     Include scenarios marked live_safe=false
`);
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function headers(options) {
  const output = { "content-type": "application/json" };
  if (options.token) {
    output.authorization = `Bearer ${options.token}`;
  }
  return output;
}

async function requestJson(url, requestOptions) {
  const response = await fetch(url, requestOptions);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(
      `Desktop Agent Runtime returned ${response.status}: ${JSON.stringify(payload)}`
    );
  }
  return payload;
}

function terminal(state) {
  return ["cancelled", "completed", "failed", "interrupted", "partial"].includes(
    String(state || "").toLowerCase()
  );
}

function liveResult(scenario, run, events, startedAt) {
  const endedAt = Date.now();
  const checkpoint = run.checkpoint && typeof run.checkpoint === "object"
    ? run.checkpoint
    : {};
  const response = String(
    run.reply || run.result || run.response || run.error || ""
  );
  const correlation = {
    client_route_id: run.client_route_id || checkpoint.client_route_id || "",
    conversation_id: run.conversation_id || checkpoint.conversation_id || "",
    task_id: run.task_id || checkpoint.task_id || "",
    turn_id: run.turn_id || checkpoint.turn_id || ""
  };
  return {
    scenario_id: scenario.id,
    status: run.state || run.status,
    response,
    duration_ms: endedAt - startedAt,
    correlation,
    events,
    tools: events.map((event) => (
      event.tool || event.tool_id || event.tool_name
    )).filter(Boolean),
    approval: run.approval || "",
    final_response_count: response ? 1 : 0,
    recovery_count: events.filter((event) => (
      /retry|recover|fallback|replan/i.test(JSON.stringify(event))
    )).length,
    artifacts: Array.isArray(run.artifacts) ? run.artifacts : []
  };
}

async function runLiveScenario(scenario, options) {
  const startedAt = Date.now();
  const suffix = `${startedAt}-${Math.random().toString(16).slice(2, 10)}`;
  const request = scenario.request;
  const runId = `benchmark-${scenario.id}-${suffix}`;
  const body = {
    agent_id: options.agent,
    prompt: request.prompt,
    run_id: runId,
    idempotency_key: runId,
    conversation_id: request.conversation_id || `benchmark-conversation-${suffix}`,
    client_route_id: request.client_route_id || `benchmark-route-${suffix}`,
    task_id: request.task_id || runId,
    turn_id: request.turn_id || `benchmark-turn-${suffix}`,
    response_language: request.response_language || "en",
    desktop_access_profile: "restricted"
  };
  const submitted = await requestJson(
    `${options.liveUrl}/api/agent-runtime/runs`,
    {
      method: "POST",
      headers: headers(options),
      body: JSON.stringify(body)
    }
  );
  let run = submitted.run || {};
  let events = [];
  while (!terminal(run.state || run.status)) {
    if (Date.now() - startedAt > options.timeoutMs) {
      await fetch(`${options.liveUrl}/api/agent-runtime/runs/${runId}/cancel`, {
        method: "POST",
        headers: headers(options)
      }).catch(() => {});
      return {
        scenario_id: scenario.id,
        status: "failed",
        response: "Agent benchmark timed out before a terminal result.",
        duration_ms: Date.now() - startedAt,
        correlation: body,
        events,
        final_response_count: 1
      };
    }
    await sleep(500);
    const snapshot = await requestJson(
      `${options.liveUrl}/api/agent-runtime/runs/${runId}?after_cursor=0`,
      { headers: headers(options) }
    );
    run = snapshot.run || run;
    events = Array.isArray(snapshot.events) ? snapshot.events : events;
  }
  return liveResult(
    {
      ...scenario,
      request: { ...scenario.request, ...body }
    },
    run,
    events,
    startedAt
  );
}

async function collectLiveResults(manifest, options) {
  const scenarios = manifest.scenarios.filter((scenario) => (
    options.includeSensitive || scenario.live_safe === true
  ));
  if (scenarios.length === 0) {
    throw new Error("The benchmark manifest has no live-safe scenarios");
  }
  const results = [];
  for (const scenario of scenarios) {
    process.stdout.write(`Running ${scenario.id}... `);
    try {
      const result = await runLiveScenario(scenario, options);
      results.push(result);
      console.log(result.status);
    } catch (error) {
      results.push({
        scenario_id: scenario.id,
        status: "failed",
        response: `Agent benchmark transport failed: ${error.message}`,
        duration_ms: 0,
        events: [],
        final_response_count: 1
      });
      console.log("failed");
    }
  }
  return { scenarios, results };
}

function printSummary(report) {
  console.log("");
  console.log(`GalaxySSI Agent benchmark: ${(report.score * 100).toFixed(1)}%`);
  console.log(`Scenarios: ${report.passed_count}/${report.scenario_count}`);
  for (const record of report.records) {
    const failures = record.assertions
      .filter((item) => !item.passed)
      .map((item) => item.name)
      .join(", ");
    console.log(
      `${record.passed ? "PASS" : "FAIL"} ${record.id}` +
      `${failures ? ` (${failures})` : ""}`
    );
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const manifest = validateManifest(readJson(options.manifest));
  let effectiveManifest = manifest;
  let resultSet;
  let source;
  let scenarioIds = [];
  if (options.liveUrl) {
    const live = await collectLiveResults(manifest, options);
    resultSet = { results: live.results };
    scenarioIds = live.scenarios.map((scenario) => scenario.id);
    source = `live:${options.liveUrl}`;
  } else {
    resultSet = readJson(options.results);
    source = path.relative(root, options.results).replaceAll("\\", "/");
  }
  const report = {
    ...evaluateBenchmark(effectiveManifest, resultSet, { scenario_ids: scenarioIds }),
    generated_at: new Date().toISOString(),
    source
  };
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  printSummary(report);
  console.log(`Report: ${options.output}`);
  process.exitCode = report.passed ? 0 : 1;
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
