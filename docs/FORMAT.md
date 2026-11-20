# OpenExhibit project format 1

A project folder contains project.oes.json (UTF-8 JSON) and project-relative assets. A .oex package is a ZIP containing that same tree and a SHA-256 integrity manifest. IDs are stable, case-sensitive ASCII identifiers. Scene objects are ordered from back to front. Coordinates use a top-left origin with positive y downward. Display indices start at zero.

| Field | Meaning |
| --- | --- |
| format, version, title, canvas, start | File kind, integer schema revision, exhibit title, logical canvas dimensions and first scene. |
| assets | Dictionary keyed by asset ID. Each entry includes a relative path and SHA-256 digest. |
| scenes | Ordered array of scenes, each with id, name, background and objects. Each object has an id, kind and rect [x,y,width,height]. |
| variables, rules | Initial visitor state and event-condition-action definitions. |
| timelines | Named tracks of timed actions and numeric property keyframes. Time is measured in seconds. |
| installation | Preset name, surfaces with physical dimensions, output assignments, optical geometry and warp parameters. |
| devices | Logical devices and channel descriptors. Host credentials belong outside the project. |
| settings | Visitor idle timeout and startup behaviour. |
| extensions | Namespaced data preserved in saves for external tools. |

Current examples provide complete documents, including fields for individual component types. Unknown top-level metadata is preserved. A newer schema revision requires a compatible player. The engine rejects invalid local asset paths and missing scene targets. See the machine-readable schema and the player validation for precise supported operations.

## Events and values

A rule has a unique id, event, optional if dictionary and ordered actions. The if dictionary accepts op, left and right. Missing left uses the incoming value. A literal string beginning with $ reads a variable. $value refers to the input payload. Text uses {variable} interpolation. The default action value is $value. Actions include set, add, mul, toggle, random, append, clear, goto, emit, play, pause, output and reset. Action targets refer to variable names, scene IDs, timelines, events or gateway channels according to the operation.

The runtime uses one visitor session per exhibit computer. Variables declared in the file are initial values. Output arming never serializes into the project. Reset restores variables and disarms outputs. Event histories and sensor plots retain at most 160 entries per trace or channel. A single dispatch chain has a 256-step budget and repeated identical event/payload pairs are suppressed and traced.

## Calibration and timelines

A display assignment’s view is [u0,v0,width,height]. Warp stores normalized TL,TR,BR,BL in display space. An optional mesh stores nine normalized destination points row by row in the corner-corrected raster. Each cell divides along its upper-left to lower-right diagonal. Blend is [left,right,top,bottom]. Gamma and blend_power are exponents, gain is an RGB triple, and black lifts the digital floor. Camera coordinates and surface formulae are documented in MAPPING.md.

A timeline contains duration, loop, cues and keys. Each cue has an at time and an action. Each numeric key has at, scene, object, property, value and optional curve. Object IDs are unique within their scene. Named devices contain channel descriptors. The gateway pairs physical ports and logical device IDs in a separate operator-controlled configuration.

## Package and compatibility

Project assets must be beneath assets/ with portable relative names. Their digests use lowercase SHA-256. The .oex ZIP includes project.oes.json, the referenced files, and manifest.json mapping each other member to its SHA-256. Archives use an ordinary single-disk central directory, no ZIP64, no archive comment and no directory entries. The reader caps the unpacked archive at 512 MiB and individual assets at 256 MiB. Folder-based projects are the practical choice for larger media installations. Checksums detect changes; they do not establish the identity of the exhibit publisher.

When extending the schema, preserve unrecognized metadata and use namespaced keys under extensions. A future incompatible format requires a higher version and an explicit migration.


## Version 1 audience and optical extensions

A project can carry a quiz deck in `extensions.contest`. Its shape matches `tools/contest/museum.quiz.json`. Participant names, tokens and answers stay in a separate SQLite event database. Adding a scene object with `kind: "contest"` renders the scoreboard in the editor preview and standalone player. Earlier version 1 projects open without modification.

A green-screen booth lives in `extensions.greenscreen`: `backgrounds` is a list of `{asset, name, fit}` (fit `cover` or `contain`; assets are WebM/MP4 videos or PNG/JPEG/WebP pictures), `overlay` an optional PNG asset id, plus `title`, `photo`, `clip`, `clip_seconds`, `countdown`, `keep_minutes`, `cycle_seconds`, `mirror`, `camera`, `key` (`color`, `tolerance`, `softness`, `spill`) and `person` (`scale`, `x`, `y`, `crop`). `tools/booth/config.py` gives the defaults and clamps every value. Visitors' captures are never stored in the project.

A sphere or dome may set `source_layout` to `cubemap_cross` or `equirectangular`. An output can supply an `up` vector to preserve surveyed roll. A measured planar warp may carry a `capture_check` summary, and calibration reports use separately versioned JSON. The operator-selected room URL is a runtime option. [Calibration formats](CALIBRATION.md)
