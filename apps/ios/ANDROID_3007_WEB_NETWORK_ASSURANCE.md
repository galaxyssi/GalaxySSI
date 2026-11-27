# Android #3007: truthful iOS provider network assurance

Android #3007 merge: `65655f0c79c6ab04121150229a65b089180f82f2`.
iOS comparison base: `8a794e82ebe8f09790e41139295ffb7ac1ee9701`.

## Scope

Android's OkHttp transport supplies validated addresses through its DNS adapter.
iOS URLSession address preflight and redirect revalidation are not equivalent
to pinning the addresses used by the eventual connection. The concrete iOS
URLSession provider already reports `public_https_urlsession_revalidated_v1`.

This change removes three unsupported `public_https_pinned_dns_v1` defaults
from catalog provenance and successful execution metadata for other providers.
An adapter without a declared policy now reports
`provider_network_policy_unspecified`. An explicitly supplied result policy is
preserved. No new security grant, transport implementation, URL classification,
cookie behavior, renderer behavior or download behavior is introduced.

The existing synthetic catalog/executor fixture now covers the unspecified
catalog defaults, unspecified result fallback and explicit result preservation.
It is authored but not executed. This is a metadata truthfulness correction,
not completion of Android #3007 or native connection-level DNS pinning.

## Source checks

The new `check-web-network-assurance-scope.cjs` verifies that the complete
production adapter differs from the comparison base only in these three
defaults, preserves the explicit-policy fallback, bounds the fixture changes,
and retains the transport, renderer, address, crawl and evidence-pack sources.
Six historical scope guards receive read-normalization hooks; their original
assertions remain intact and the new guard checks those exact hook changes.

Passing: the new guard, special-use-address guard, public-address-policy guard,
search-result-capacity guard and `npm run check:ios` project checks.

Three historical guards fail at the same assertions on both this branch and
the unmodified comparison base: image-search-fusion (image adapter hook count),
encoded-web-request (`AgentIOSWebIntelligenceCache`), and public-search-parsing
(`GalaxySSIHealthCareTaskRuntime retained`). These are not reported as passes
or disabled by this change.

No Swift compilation, XCTest execution, live networking, device acceptance,
CI acceptance or IPA build is claimed.
