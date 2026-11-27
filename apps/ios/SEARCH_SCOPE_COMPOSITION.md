# Search Scope Composition

Base: main `c6bad3465c673dfb2dcecb23b095185c129c7447`.
This changes iOS source-check tooling only, not application or Android code.

Historical automatic-routing, mixed-media and exact-response-cache guards failed
on main because their retained-provider chain did not recognize the original-page
asset method merged in `5e6167ab76ee808fa271504fb324c879916bb86b`.
The encoded-request guard also did not apply the existing cache-size normalizer
for the later merged SQLite response-size change.

At the shared encoded-request retention entry point, normalize only the complete
exact approved original-page method. Its signature must be unique, and any body
change fails the equality assertion. Do not strip arbitrary methods by section
boundaries. Unrelated provider changes remain visible to the existing complete
snapshot assertions. Cache sizing uses the existing size-specific normalizer;
no duplicate policy or replacement of an entire cache is introduced.

The new guard proves the original approved commit added only this method, checks
the current body, rejects ten synthetic mutations covering permissions, consent,
deadlines, cancellation, validation, byte bounds, partial bodies and MIME policy,
and preserves an unrelated mutation. It also compares the complete historical
encoded-request checker with main, allowing only the two added normalization
lines. No existing assertion is removed or bypassed.

Focused source checks: original-page retention, automatic search routing, mixed
media, exact response cache, Baidu request scope and encoded request scope.
Also JS syntax, `npm run check:ios` and `git diff --check`.
No Swift compilation, native tests, network/device acceptance, full check, CI
monitoring, IPA, evidence upload or claim of full backlog completion.
