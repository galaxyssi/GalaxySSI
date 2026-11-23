# iOS parity: Android #4338 ideal vessel flow

Base: main. Android source: #4338, merge 5c84bf205b5eecfdfa1096aba4f656f627159c07.

## Scope

- Add the same bounded Poiseuille teaching model for blood-vessels, arteries,
  veins and coronary-vessels only. Do not apply it to capillaries or cells.
- Convert mmHg, mm and mPa s to SI before calculating flow, independent
  hydraulic resistance, mean/centre speed and wall shear.
- Include four independently restored controls, a radius response curve,
  nonzero zero-pressure plot scale and a normalized no-slip velocity profile.
- Keep radius precision at three decimals, flow at six and profile values
  at four. Include the complete geometry, values, limitations and three
  references in the existing public teaching-only Agent context.
- Import all 16 English and Simplified Chinese strings from Android.
- Add XCTest source covering Android fixtures, scaling, zero pressure,
  annular integration, finite bounds, restoration, precision and context.

## Verification

- iOS project structure check passed.
- Swift grammar audit passed with conditional branches enabled and disabled.
- git diff --check passed.
- XCTest source added but not executed, as requested.
- Windows cannot provide Xcode type checking, simulator screenshots or device
  acceptance. No IPA or native build is claimed.

This PR changes iOS only and does not duplicate the microscopic models from
the preceding Android #4337 port.
