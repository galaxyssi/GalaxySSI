# Android overview source attention

The overview presents persisted source failures separately from health
changes and review tasks. It reads only selected Health Connect data types
and only unresolved, unacknowledged incidents. Source hints include the
recorded error and last successful sync time. They do not imply that the
user has a health problem or that a live connection has been checked.

Opening a hint goes to the matching data-type coverage card without
starting a sync. Incident and source-selection events refresh the overview.
Recovery and acknowledgement remove the hint; a retry without confirmed
success does not. Loading an unreadable incident marks the overview as
partial rather than reporting that there is nothing requiring attention.
Existing measurements remain available, and source issues alone do not
create metric cards for a first-use profile.

Android 0.1.7.82 passed all six focused overview-policy JVM tests. Isolated
Tab Active3 (SM-T575) tests verify the source entry and exact destination,
foreground refresh after recovery and acknowledgement, retry continuity,
and unreadable-incident handling. These tests use synthetic checkpoints
and do not prove physical Health Connect provider interruption or recovery.
