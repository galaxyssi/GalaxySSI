# Android default original retention for health imports

Privacy & Data stores the default for new import originals in the
existing encrypted health privacy policy. Existing policy records
without the field retain the previous default of keeping originals.
The option is independent of consent for online analysis and images.

The import center shows the current default and can override it for one
import. A file picker or camera batch receives a single resolved choice;
returning or recreating the app does not change an in-flight choice.
Unchanged import-center controls use the current default. New direct
capture, image selection, and derived crops also consult the default.
Explicit original-only import still keeps the file. Existing files and
queued review jobs are not modified by a preference change.

Review-only imports continue to use the encrypted temporary review and
release behavior, with confirmed measurements retained separately.
Policy reads are off the UI thread and a read failure does not silently
fall back to keeping originals.

Android 0.1.7.76 passed all 10 focused JVM policy tests. On Tab Active3
(SM-T575), the final app passed 62 cases in the focused instrumentation
suite, and the remaining backup UI case passed on an unlocked rerun.
New coverage uses synthetic file picker results and confirms the camera
launch parameter by intercepting the launch without opening the camera.
