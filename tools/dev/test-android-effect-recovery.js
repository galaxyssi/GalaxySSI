#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const http = require('node:http');
const { spawn } = require('node:child_process');
const { randomUUID } = require('node:crypto');

function option(name) {
  const index = process.argv.indexOf(name);
  return index < 0 ? undefined : process.argv[index + 1];
}

async function main() {
  const serial = option('--serial');
  assert.ok(serial && /^[a-zA-Z0-9_.:-]+$/.test(serial), 'Provide the explicit ADB serial with --serial');
  const adb = option('--adb') || process.env.ADB || 'adb';
  const token = randomUUID().replaceAll('-', '');
  let submissions = 0;
  let observations = 0;
  const operations = new Map();
  const server = http.createServer((request, response) => {
    const match = request.url?.match(new RegExp(`^/${token}/effect/([a-f0-9]{64})$`));
    if (!match || !['GET', 'POST'].includes(request.method)) { response.writeHead(404); response.end(); return; }
    const id = match[1];
    if (request.method === 'POST') {
      submissions++;
      operations.set(id, (operations.get(id) || 0) + 1);
    } else observations++;
    request.resume();
    response.setHeader('Content-Type', 'application/json');
    response.end(JSON.stringify({ ok: true, result: { request_id: id,
      state: operations.has(id) ? 'completed' : 'unknown', submissions: operations.get(id) || 0,
      business_success_verified: false, verification_required: true } }));
  });
  function run(args) {
    return new Promise((resolve, reject) => {
      // Keep the event loop live: the phone reaches the HTTP server during instrumentation.
      const child = spawn(adb, ['-s', serial, ...args], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
      let stdout = '', stderr = '';
      child.stdout.on('data', chunk => { stdout += chunk; });
      child.stderr.on('data', chunk => { stderr += chunk; });
      child.once('error', reject);
      child.once('close', code => code === 0 ? resolve({ stdout, stderr }) : reject(new Error(
        `ADB command failed (${code}): ${stderr.slice(-1000)}`)));
    });
  }
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port;
  let reverseInstalled = false;
  try {
    await run(['reverse', '--no-rebind', `tcp:${port}`, `tcp:${port}`]);
    reverseInstalled = true;
    const instrument = phase => run(['shell', 'am', 'instrument', '-w', '-r',
      '-e', 'class', 'com.galaxyssi.chat.AgentEffectRecoveryQueryDeviceTest',
      '-e', 'effectRecoveryPhase', phase, '-e', 'effectRecoveryToken', token,
      '-e', 'effectRecoveryUrl', `http://127.0.0.1:${port}`,
      'com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner']);
    const crashed = await instrument('crash');
    assert.match(crashed.stdout, /Process crashed/, 'The first process must die after its external effect');
    assert.equal(submissions, 1, 'The external server must observe one mutation before process death');
    assert.equal(observations, 0);
    const recovered = await instrument('recover');
    assert.match(recovered.stdout, /OK \(1 test\)/, recovered.stdout);
    assert.equal(submissions, 1, 'Recovery must never submit the external mutation again');
    assert.equal(observations, 1, 'Recovery must query the original operation');
    assert.equal(operations.size, 1);
    assert.deepEqual([...operations.values()], [1]);
    process.stdout.write(`${JSON.stringify({ scenario: 'process-death-after-external-effect-before-commit',
      serial, token, submissions, observations, distinctOperationIds: operations.size,
      processDeathObserved: true, recoveryPassed: true })}\n`);
  } finally {
    if (reverseInstalled) await run(['reverse', '--remove', `tcp:${port}`]).catch(() => {});
    await new Promise(resolve => server.close(resolve));
  }
}

void main().catch(error => { process.stderr.write(`${error.stack}\n`); process.exitCode = 1; });
