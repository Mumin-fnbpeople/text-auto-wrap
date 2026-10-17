# Changelog

## 0.1.1 - 2026-10-14

- Apply semantic breaks at whitespace boundaries without rejecting preserved source spaces.
- Report painted source ranges and widths while keeping trimmed calculation layouts in diagnostics.
- Preserve native geometry when a calculated selection reuses the native break offsets.
- Keep native fallback for added soft wraps, invalid measurements, and overflowing painted lines.

## 0.1.0 - 2026-09-12

- Initial release of model-driven semantic wrapping for plain and rich Flutter text.
- Added experimental Korean and English title presets with automatic or explicit selection.
- Added custom predictor, aggregation, layout, and selection APIs.
- Added `WidgetSpan`, Unicode-safe offset, accessibility, controller diagnostics, and bounded caching support.
