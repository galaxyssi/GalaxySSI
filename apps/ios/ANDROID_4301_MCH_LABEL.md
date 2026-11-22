# Android #4301: common Chinese MCH label

Reference: galaxyssi/GalaxySSI#4301, merge
`fa76931dc26cd23dc87bd5ff9ecb2f02634dfa23`.

Add the common Chinese MCH label to the existing localized metric aliases.
Shared catalog search, local OCR and the model transcription instructions all
consume this alias; no separate matching rule or raw UI string is introduced.
MCH remains distinct from hemoglobin and HbA1c and retains the pg unit.

Add one XCTest source method covering the English title, abbreviation and
Chinese alias, plus hemoglobin/HbA1c separation. This is iOS-only, builds on
the separate #4300 catalog port and does not change Android version metadata.
Windows static checks do not establish Xcode/XCTest or device verification;
Android device results from the source PR are not iOS test evidence.
