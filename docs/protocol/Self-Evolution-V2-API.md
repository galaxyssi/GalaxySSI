# Self-Evolution V2 API

The V2 control API is available only from Desktop loopback under `/api/evolution/v2`. Existing V1
`/api/evolution/tasks` endpoints continue to execute scoped candidate tasks.

## Environment and policy

- `GET /health`
- `GET /preflight`
- `GET /policy`
- `GET /tasks/{task_id}/metadata`

## Technology radar

- `POST /research/runs`
- `GET /research/runs?limit=50`
- `GET /research/runs/{run_id}`

```json
{
  "query": "MCP Agent Skills coding agent",
  "trusted_only": true,
  "limit": 40,
  "create_proposals": true
}
```

Radar collection stores metadata and proposals only. It does not execute discovered source.

## Roadmaps and proposals

- `POST /roadmaps`
- `GET /roadmaps?limit=50`
- `GET /roadmaps/{roadmap_id}`
- `GET /proposals?limit=100`
- `POST /proposals/{proposal_id}/materialize`

```json
{
  "agent_id": "auto",
  "max_attempts": 5,
  "start": false
}
```

`materialize` creates a V1 task. Keeping `start` false lets the user inspect scope, acceptance
criteria, and effective risk first. `agent_id` defaults to `auto`; a configured local/custom CLI
identifier is a preference with health-based failover, not a hard requirement.

`GET /preflight` includes an `implementation-agents` check with every eligible Agent and the
selected candidate. It exposes identifiers, kind, health, and required capabilities, but never
command lines or credentials. Task metadata includes the pinned `source_commit`.

## Issue signals

- `POST /issues/scan?create_proposals=true`
- `POST /issues/ingest`
- `GET /issues?limit=200`

```json
{
  "text": "duplicate MQTT replay caused processing stuck",
  "source": "manual-test",
  "create_proposals": true
}
```

## Campaigns

- `POST /campaigns`
- `GET /campaigns?limit=100`
- `POST /campaigns/{campaign_id}/tick`

```json
{
  "name": "Interoperability rollout",
  "objective": "Introduce protocol-neutral adapters",
  "auto_start_safe_nodes": false,
  "nodes": [
    {"node_id": "registry", "proposal_id": "proposal-a", "depends_on": []},
    {"node_id": "mcp", "proposal_id": "proposal-b", "depends_on": ["registry"]}
  ]
}
```

A campaign advances only nodes whose dependencies completed. Every candidate still stops at its
approval and pull-request boundary.

## Audit, scheduler, and GitHub checks

- `GET /audit?limit=200`
- `GET /audit/verify`
- `GET /scheduler`
- `POST /scheduler/config`
- `POST /scheduler/tick?force=true`
- `POST /scheduler/tick?evolution_only=true`
- `GET /github/checks?target=<pull-request-url-or-number>`

```json
{
  "enabled": true,
  "evolutions_per_day": 24,
  "execution_mode": "parallel",
  "max_parallel_evolutions": 2
}
```

The scheduler accepts 1 to 96 runs per day. `serial` waits for the current evolution to finish.
`parallel` starts on cadence while fewer than two to four configured slots are active. The
settings persist in the local state directory. Verified candidates may be published as pull
requests; automatic merge is always disabled. `evolution_only=true` starts the next available
proposal without refreshing research first. If no proposal exists, diagnostics and research run
once to discover one.
