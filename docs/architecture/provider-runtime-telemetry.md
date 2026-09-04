# Provider Runtime Telemetry

GalaxySSI separates declared Provider capabilities from observed runtime performance.

## Profile data

Provider profiles declare:

- context and output token limits
- tool, streaming, and background support
- location and trust boundary
- concurrency and failure domain
- configured per-token pricing when the operator supplies it

Pricing is never inferred from a model name. If both input and output prices are not
configured, a run remains explicitly unpriced.

## Runtime observations

Each executed Provider run records aggregate values:

- attempts, successes, failures, and consecutive failures
- last, average, EWMA, minimum, maximum, P50, and P95 latency
- input and output token estimates
- maximum observed input and context utilization
- priced and unpriced attempts, total cost, and average cost
- tool calls and tool failures when the adapter reports them

Latency percentiles use a bounded rolling sample of the latest 128 runs. Lifetime
counters remain cumulative.

## Privacy boundary

The telemetry store never records prompts, replies, credentials, endpoint secrets,
tool arguments, or error bodies. Usage inferred from text is marked as estimated.
Durable replay receipts do not count as new Provider executions.

The public Provider Profile endpoint exposes only aggregate statistics and declared
capabilities. Routing can consume these values without receiving conversation data.
