# Android health record center

The h05 record center opens from the Health Center function menu and
from the first-use primary action. Its four native tiles open camera
capture, manual entry, the import center, and device sources. The task
queue and data/file hub remain independently reachable. The camera route
uses the encrypted retention preference and returns to the record center.

Recent eligible OCR and table jobs are shown separately from confirmed
measurements. The previews show up to four review jobs and five current
measurements for the self profile; the full task queue and record list
remain available separately. Each row uses the exact job or observation
ID and the measurement preview excludes deleted and future observations.
Queries run off the UI thread and data changes reload the visible
preview. The record center retains its scroll position on return.

Tab Active3 (SM-T575) coverage uses isolated health databases. It checks
empty and populated screens, first-use and function menu navigation,
manual/import return, selected job and record destinations, return after
intercepted camera cancellation, activity recreation, and refreshed
sections after confirmation or deletion. Camera, device and external
destination intents are intercepted; no live capture, pairing or
real-data import is part of this test.
