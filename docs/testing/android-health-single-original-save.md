# Android single-original save

Both the original detail action and the preview download icon show the
same confirmation before opening the system document picker. The preview
lists the file name, original MIME type and size. It distinguishes the
single external copy from a separate measurement export and warns that
app encryption does not protect the saved copy.

The picker result is bound to the reviewed original and stream IDs.
The app rejects a missing original, review-only material, or a stream
replaced after review. A confirmed save copies the authenticated source
stream and checks the byte count and SHA-256 of the destination readback
before showing success. Failed writes or readbacks request best-effort
cleanup if writing started. The encrypted privacy history records the
scope and outcome without a file name, digest, ID, or destination URI.

On Tab Active3 (SM-T575), Android 0.1.7.80 verified the confirmation from
both entry points, cancellation before and at the picker, and byte-exact
save into an isolated content provider. The test intercepts the system
picker intent and does not claim acceptance of every document provider.
Isolated cases reject same-length destination corruption and reject a
review-only or reimported original before opening the destination.
