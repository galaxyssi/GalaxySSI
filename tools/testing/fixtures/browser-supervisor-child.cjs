'use strict';

const { BrowserServiceMonitorClient } = require(process.env.PUBLIC_MONITOR_MODULE);
const client = new BrowserServiceMonitorClient();
const binding = JSON.parse(process.env.PUBLIC_MONITOR_BINDING);
const state = JSON.parse(process.env.PUBLIC_MONITOR_STATE);
const lease = process.env.PUBLIC_MONITOR_LEASE;
void (async () => {
  await client.request('arm', { lease, binding, state });
  process.send({ public_probe: 'armed' });
  process.on('message', async message => {
    if (message?.public_probe !== 'retire') return;
    await client.request('disarm', { lease });
    process.send({ public_probe: 'retired' });
    client.close(); process.disconnect();
  });
})().catch(() => { process.exitCode = 1; client.close(); if (process.connected) process.disconnect(); });
