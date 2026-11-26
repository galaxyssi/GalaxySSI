# Android #3007: special-use address classification follow-up

## Implementation

Reference: `65655f0c79c6ab04121150229a65b089180f82f2`,
`AgentWebMediaNativeTools.kt`, `AgentPublicAddressPolicy`. Base:
`f2b671fa9a9728bfc6e1c94697bec0bdf89c943e`.

The shared iOS classifier now also blocks Android's `192.0.0.0/24`,
`192.0.2.0/24`, `192.88.99.0/24`, `198.51.100.0/24`, `203.0.113.0/24`
and `2001:db8::/32`. This follows Android's actual whole-subnet policy, not
individual globally reachable exceptions or a newly invented routing policy.
Existing mapped-IPv4 and well-known NAT64 /96 recursion inherits the IPv4
restrictions. Adjacent ranges, normal hostnames and public DNS64 destinations
retain their existing classification. Existing private, loopback, multicast,
legacy-numeric and scoped-IPv6 rejection remains unchanged.

No consumer, transport or permission code changes: static URL validation and
redirect validation, WebKit navigation/subresource validation, image URL checks
and crawl URL admission already use the shared classifier. Historical source
guards normalize only these declared classifier additions before comparing their
older HTTP/crawl baselines. The new guard independently checks the complete
classifier and freezes all those consumers against this actual main base.

## Verification Limits

Six XCTest methods were added to the existing registered renderer test file.
They cover whole subnet edges, adjacent addresses, mapped/NAT64 forms, renderer
and image policies, initial registry requests rejected before injected transport,
and redirects rejected before a second transport call. These are authored test
sources, NOT executed XCTest or Swift compilation evidence.

This is not full special-purpose address classification, DNS-to-connection
pinning, DNS-rebinding prevention, remote renderer isolation or live network
acceptance. System DNS resolution and platform networking remain unchanged.
No native build/typecheck, XCTest execution, CI monitoring or IPA is included.
Android #3007 and the full Android parity backlog remain incomplete.

The special-use, shared public-address and crawl source checks passed, as did
iOS project structure, changed JavaScript syntax and diff whitespace checks.
The historical encoded-request guard still fails at its older
`AgentIOSWebIntelligenceCache` baseline. Loading the exact current-main guard and
classifier in memory reproduces that same failure without any working-tree
writes. This change preserves that cache implementation exactly; the historical
failure is not reported as a passing check or hidden by changing its assertions.
