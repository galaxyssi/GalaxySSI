# Android #4437: One Physiology Location And Targeted Research

Pinned Android merge: `dbbd6554d7cd632c6eb99f705e5a4b38ff42a3cb`.

## Dependency And Scope

Formal iOS PR with base `main`; depends on unmerged #4513 and predecessors.
Exact incremental base: `9018d27befa6e393330b3502a8020b176a538b70`.
The full main diff is cumulative, not an independent #4437-only patch.
All 19 original changed files have hashes and individual dispositions.
No Android/Desktop edits, iOS version bump, build or IPA.

## Native Changes

- System/organ physiology lives only in Function > Models and parameters.
  That panel opts into mechanism-first ordering and contains the mechanism's
  source link. Remove the duplicate outer Function source link.
- Targeted research has Drug Pathways and Aging only, with semantic topic
  identities and the exact bilingual title. Opening it selects Drugs. Cell,
  tissue and fragment research retain Physiology, Drugs and Aging.
- Persist active research presentation and a bounded return offset separately
  from the topic preference. Active saved physiological research for systems
  and organs migrates to expanded Function without changing model or lesson
  inputs. Mere topic preferences do not move ordinary Structure pages.
- Existing iOS caches did not store active research presentation or return
  pixels, so that missing historical state cannot be reconstructed. New state
  persists it; old physiological views redirect if reached explicitly.
- Pause/snapshot before opening research. Return restores the Function scroll
  position, expanded state and entry-specific lesson/model inputs. iOS 15 uses
  an inert background UIView observing the containing UIScrollView, not a
  replacement delegate or nested diagram zoom view. Restore waits for content
  size/layout, clamps to native extents, cancels when the user scrolls, and
  invalidates observations when dismantled. Capture itself does not publish
  SwiftUI updates on every scroll event. Ordinary tab switches start at top.
- Retain numerical kernels, original illustrations, lesson clock, cumulative
  comparison, drug/aging modules, Agent confirmation and personal measurements.

## Verification Boundary

Scoped source checks verify all original files, topic filtering/tags, active
destination migration, native scroll wiring/cleanup, source placement and
unchanged model/prompt/measurement modules. They reproduce the exact bilingual
label and chain predecessor contracts. Added Swift fixture sources cover all
catalogue topics, active-versus-preference migration, entry-scoped round trips,
bounded offsets and capture/restoration revision behavior. Fixtures are not run.

Grammar parsing and project/resource checks do not prove Swift type correctness,
an iOS build, UIKit scroll pixels, actual Back/recreation behavior, view identity,
tap timing, VoiceOver, XCTest or native acceptance. Android's reported tests are
reference evidence only, not iOS execution. No IPA or native tests are requested.
