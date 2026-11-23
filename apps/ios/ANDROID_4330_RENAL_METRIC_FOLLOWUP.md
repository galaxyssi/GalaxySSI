# iOS parity follow-up: Android #4330 renal metric routes

The #4450 nephron port added structures and teaching mechanisms, but its metric
association switch omitted seven Android routes. This focused follow-up adds
renal-cortex, renal-medulla, renal-pelvis, bowmans-capsule, proximal-tubule,
nephron-loop and distal-tubule to the existing creatinine/urea/urine-protein group.

Reference: Android #4330, merge 8ecbef31c, HealthBodyAtlas.kt metric mapping.

No new health metric, observation or inferred organ-function value is created.
The existing values screen and consent-gated personal data flow are unchanged.
Added XCTest source checks all 14 renal associations and unrelated-cell exclusions;
it was not executed. iOS structure and whitespace checks passed. No native
compile, device acceptance or IPA is claimed.

This formal main-based PR is a correction to the previous #4330 port, not another
copy of its nephron artwork or physiology implementation.
