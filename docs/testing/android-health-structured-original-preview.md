# Android structured original preview

The original detail screen opens CSV, XLSX, and JSON samples directly from the encrypted original. Preview does not stage an import, infer measurements, evaluate formulas, or write a plaintext scratch file.

- CSV uses the existing BOM, delimiter, and quoted-cell parsing. Duplicate or non-importable headers are still visible as source rows.
- JSON objects show keys and sampled values, and arrays show sampled entries. Nested data is summarized rather than expanded without a bound.
- XLSX opens the verified seekable archive, switches worksheets, retains worksheet row numbers, and displays formula expressions as text.
- The native preview displays at most 20 rows and 12 columns, clips each cell at 512 characters, and limits textual reads to a 2 MiB prefix. It is a sample, not a full-file import or validation. XLSX still uses its existing package and expansion checks.
- The protected window closes and clears the sample on backgrounding. The existing save action exports the original bytes only after an explicit user action; review-only originals have no save action.

`HealthStructuredPreviewDeviceTest` exercises actual encrypted files, bounded sampling, XLSX formulas and row numbers, the native original-detail route and sheet switch, and lifecycle cleanup. Run the existing CSV/JSON/XLSX import, original storage, library, and OCR review suites against the same APK. Any generated preview image is drawn only from the synthetic instrumentation fixture.
