# Model-visible structured inference

Private evolution uses the literal-loopback `infer_local_plan` transport for
structured file actions and independent candidate acceptance. A JSON Schema in
`response_format` constrains decoding, but does not itself tell a llama.cpp model
the expected response structure. The upstream
[GBNF guide](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md#json-schemas--gbnf)
explicitly distinguishes schema-constrained decoding from prompt visibility.

When `response_schema` is provided, the shared transport now:

1. Copies message envelopes without modifying the caller's history.
2. Appends a compact schema explanation to an existing textual system message,
   or inserts one system message when none is available.
3. States that the schema describes response format, not additional task requirements.
4. Retains the same schema in `response_format`, plus existing streaming,
   literal-loopback validation, proxy bypass, and no-redirect behavior.

No schema is added to ordinary unstructured planning requests. Repeated tool
turns do not accumulate schema instructions in the saved conversation. The
request is not retried through a cloud provider when schema support is absent.
Host-side action and acceptance validators remain authoritative; producing
schema-valid JSON does not prove that the content is correct or the task done.

## Verification

Transport tests capture the actual local HTTP request and check visible schema,
decoder schema, nested required fields, Unicode, empty/system-less histories,
immutable observations, repeated calls, and unchanged unstructured requests.
Existing SSE, local tool, read-revision, proxy, and redirect tests remain in scope.

A read-only comparison used the same immutable candidate and original Chinese
goal with Qwen3-4B-Instruct-2507 Q8_0 on llama.cpp b10839 CPU (4 threads, 8192
context, non-thinking mode). Without a visible schema, two calls took 123.26 and
113.68 seconds and misclassified a named section as a text containment check.
With the same schema visible in the prompt, it correctly emitted a heading
check; two calls took 85.60 and 56.71 seconds. These are individual diagnostic
observations, not a statistically valid throughput or latency benchmark.

Both variants still invented additional literal requirements and failed the
independent verifier. The candidate, original goal, campaign state, and model
configuration were not modified, and no candidate was published. This patch
fixes a missing request contract, not general model reasoning quality or the
complete autonomous goal-to-PR workflow. A decoder-disabled comparison took
63.03 and 65.14 seconds and still invented literal requirements, so disabling
the grammar did not resolve the semantic problem. This production change keeps
decoder constraints enabled. Shorter contract instructions are being evaluated
separately and are not part of this transport change.
