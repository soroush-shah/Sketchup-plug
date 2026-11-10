# Banian Profile Builder · بانیان پروفایل بیلدر

Fast parametric profiles, assemblies and quantities for SketchUp 2017+ (Windows & macOS).
Bilingual panel (English / فارسی); SketchUp menus, toolbar and icons in English.

- **Install:** `dist/banian_profile_builder_v1.1.0.rbz` → *Extensions › Extension Manager › Install Extension*
- **Guide (فارسی):** [docs/GUIDE_FA.md](docs/GUIDE_FA.md)

## Features

- 14 parametric profiles: lumber, round/half-round, box tube, pipe, angle, channel, IPE, T, Z, baseboard, crown, chair rail, gutter, plus custom profiles saved from any face.
- Draw tool with live wireframe preview, typed lengths, arrow-key axis lock, right-click / Enter / double-click to finish, click first point to close.
- Build on selected edges, arcs (chained automatically) or faces (closed loop).
- Assemblies with continuous and repeated parts, presets for railings, fences, walls, partitions, trim and pergolas, openings that cut and trim parts and add jambs.
- Live editing of selected objects (one undo step), "update identical" option, Extend / Trim tool (`500`, `-200`, `3000s`), Rotate 90°, Flip.
- Your own profiles in two clicks (pick any face), live shape editing in place that updates every member and assembly part using the profile, library import/export.
- Direct path editing (drag / add / delete points), eyedropper, build the same object on another path, move an object to a new path.
- Your own SketchUp components as repeated assembly parts; 15 assembly presets incl. 9 railings, with elevation thumbnails.
- Instant quantity and cost report with CSV export (UTF-8, opens in Excel).

## Performance design

- Own sweep engine: mitred rings are computed in pure Ruby and inserted with one `PolygonMesh` per solid (no Follow Me).
- Repeated pieces share one `ComponentDefinition` model-wide; unused ones are purged.
- Edits rebuild only the edited object inside a UI-disabled operation; consecutive edits merge into one undo step.
- Quantities are cached on objects, so the report does not touch geometry.
- `HtmlDialog` with debounced, batched JSON messages; light selection observer.

## Development

```
src/banian_profile_builder.rb          loader
src/banian_profile_builder/core/       pure Ruby geometry (testable without SketchUp)
src/banian_profile_builder/su/         SketchUp layer (builder, panel controller, quantities, library)
src/banian_profile_builder/tools/      Draw and Extend tools
src/banian_profile_builder/ui/         panel (HTML/CSS/JS, bilingual)
src/banian_profile_builder/icons/      SVG (Windows) + PNG (macOS) icons
```

Run the tests:

```bash
ruby tests/test_core.rb
```

```bash
ruby tests/test_su_layer.rb
```

Build the package:

```bash
python3 tools/build_rbz.py
```
