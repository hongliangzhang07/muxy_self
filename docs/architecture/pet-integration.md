# Pet Integration

## Goal

Add a lightweight Muxy pet surface that can use Codex-compatible pet packages. Muxy should ship with the existing Banana Cat package as the first bundled pet:

```text
Muxy/Resources/Pets/banana-cat/
  pet.json
  spritesheet.webp
```

The same package also exists locally as a generated Codex pet:

```text
${CODEX_HOME:-$HOME/.codex}/pets/banana-cat/
  pet.json
  spritesheet.webp
```

The first version should consume pet packages. It should not generate pets inside Muxy. Pet generation stays in Codex's `hatch-pet` workflow, and Muxy owns bundled resources, package discovery, validation, selection, animation, and state mapping.

This design is a Muxy-native modification plan. It does not depend on outside app behavior, website implementation, or third-party rendering surface. The only external contract Muxy needs to understand is the local pet package format.

## Package Contract

Use the Codex custom pet format as the input contract:

```json
{
  "id": "banana-cat",
  "displayName": "Banana Cat",
  "description": "A tiny banana-suit cat companion with a solemn little face and practical builder energy.",
  "spritesheetPath": "spritesheet.webp"
}
```

The spritesheet must be:

| Field | Value |
| --- | --- |
| Format | PNG or WebP |
| Size | `1536x1872` |
| Grid | 8 columns x 9 rows |
| Cell | `192x208` |
| Background | Transparent |
| Unused cells | Transparent |

Rows and durations:

| Row | State | Frames | Timing |
| --- | --- | ---: | --- |
| 0 | `idle` | 6 | 280, 110, 110, 140, 140, 320 ms |
| 1 | `running-right` | 8 | 120 ms each, final 220 ms |
| 2 | `running-left` | 8 | 120 ms each, final 220 ms |
| 3 | `waving` | 4 | 140 ms each, final 280 ms |
| 4 | `jumping` | 5 | 140 ms each, final 280 ms |
| 5 | `failed` | 8 | 140 ms each, final 240 ms |
| 6 | `waiting` | 6 | 150 ms each, final 260 ms |
| 7 | `running` | 6 | 120 ms each, final 220 ms |
| 8 | `review` | 6 | 150 ms each, final 280 ms |

## Existing Muxy Fit

Muxy already has most of the infrastructure needed to host this feature:

| Existing area | Useful capability |
| --- | --- |
| `ImageViewerTabState` | Confirms image files, including WebP, are loadable through AppKit. |
| `TerminalProgressStore` | Tracks per-pane progress, completion, paused, and error states. |
| `ExtensionEventEmitter` and `NotificationStore` | Provide workspace and notification signals that can later feed pet reactions. |
| `MainWindow` overlays | Already hosts floating UI like rich input, voice recording, toasts, and modal overlays. |
| `InterfaceSettingsView` | Natural home for a simple show/hide preference. |

The extension WebView system can render WebP assets, but it is not the best first implementation. Extension assets are intentionally scoped to the extension directory, and an always-visible pet should not need one `WKWebView` per surface. A native SwiftUI/AppKit renderer is simpler, lower overhead, and easier to connect to app state.

## Recommended Architecture

### `PetPackage`

Value model for one discovered package:

```text
id
displayName
description
directoryURL
spritesheetURL
source
```

`source` should distinguish `bundled`, `codexCustom`, and `muxyCustom`.

### `PetPackageStore`

An observable store responsible for:

- scanning package roots
- decoding `pet.json`
- validating `spritesheetPath`
- rejecting paths that escape the package directory
- validating atlas dimensions before exposing a package
- selecting the active package by saved preference

Recommended scan roots:

```text
Bundle resource: Resources/Pets
${CODEX_HOME:-$HOME/.codex}/pets
~/Library/Application Support/Muxy/Pets
```

The bundled root gives Muxy an out-of-the-box default pet. The Codex root lets Muxy directly use previously generated pets. The Muxy root gives the app its own long-term import location.

### `PetAnimationSpec`

Static row metadata:

```text
state
rowIndex
frameCount
durationsMs
```

This should be deterministic and testable. The frame rectangle for a state is:

```text
x = frameIndex * 192
y = rowIndex * 208
w = 192
h = 208
```

### `PetAnimationView`

Native renderer for the selected package.

Recommended behavior:

- load the spritesheet once per package
- decode WebP or PNG through ImageIO into one `CGImage`
- render the first frame immediately after the package is loaded
- crop the current `192x208` frame, never draw the whole atlas
- advance frames using the row duration table, not a fixed GIF-style delay
- reset the frame index when the package or pet state changes
- cancel the old animation loop when the state changes
- cache cropped frames per package and state when the renderer becomes hot
- use nearest-neighbor interpolation to preserve the pixel look
- keep the rendered size modest, around 96x104 or 128x139
- avoid hit testing in normal mode so terminal interactions stay natural
- respect Reduce Motion by freezing on the first `idle` frame

The important implementation detail is that Muxy must animate cells from the atlas. A static implementation usually fails because it loads `spritesheet.webp` as one image and either displays the whole sheet, displays only frame zero, or waits for SwiftUI view updates instead of owning a frame loop.

Frame rendering should follow this model:

```text
on package change:
  decode spritesheet once
  verify 1536x1872 dimensions
  clear frame cache
  render state frame 0 immediately

on state change:
  cancel previous loop
  frameIndex = 0
  render state frame 0 immediately
  start loop for the new state's duration table

loop:
  sleep currentFrameDurationMs
  frameIndex = (frameIndex + 1) % frameCount
  render cropped frame
```

Prefer a cancellable `Task` with `ContinuousClock` or a timer registered in common run-loop modes. A plain default-mode timer can pause during drags, menus, and tracking interactions, which makes the pet feel broken even if the frame math is correct.

The atlas contract treats row 0 as the top row. Keep the row-to-rectangle conversion in one test-covered place. If a rendering API interprets the crop origin differently, convert there rather than spreading flipped `y` math through the view.

Memory cost is acceptable if cropped frames are cached. The package uses 57 active frames, and `57 * 192 * 208 * 4` is under 10 MB before framework overhead. Caching avoids re-cropping on every tick and keeps CPU usage low.

### Animation Quality Plan

The pet should feel alive because the app state drives the right animation, not because random effects are layered on top.

Quality rules:

- `idle` should be quiet breathing, blinking, or a tiny bob.
- `running` should mean Muxy is working, not literal screen travel.
- `waiting` should be calmer than `running`, useful for paused or no-pane states.
- `failed` should be sticky while the error state remains active.
- `waving` and `jumping` should be short pulses that return to the ambient state after one complete animation loop.
- `running-right` and `running-left` should be reserved for user drag or future positional movement.
- state changes should reset to frame 0 so reactions read clearly.
- completion reactions should not interrupt a still-active error state.
- the pet should never cover rich input, modal controls, or terminal text that the user is actively editing.
- normal mode should not steal clicks; drag/reposition can be enabled later behind an edit affordance.

Effect rules:

- prefer pose, expression, and silhouette changes over detached effects.
- keep effects inside the `192x208` cell and attached to the pet silhouette.
- avoid wave marks, speed lines, glows, shadows, floating icons, text, and loose particles.
- preserve transparent background and nearest-neighbor scaling.
- do not scale the pet so large that the pixel art becomes noisy or the UI feels toy-like.

### Failure Modes To Avoid

Static first drafts often look bad or fail to move for predictable reasons:

| Failure | Result | Correct behavior |
| --- | --- | --- |
| Rendering `spritesheet.webp` directly | Full atlas appears or wrong crop appears | Crop one `192x208` cell |
| Only selecting the first crop | Pet never moves | Own a cancellable frame loop |
| Waiting for SwiftUI state refresh | Animation freezes between app updates | Drive frames independently |
| Using one fixed delay | Motion feels uneven or mechanical | Use each row's duration table |
| Recreating image sources every tick | High CPU and stutter | Decode once and cache frames |
| Linear interpolation | Blurry pet | Use nearest-neighbor scaling |
| Not rendering frame 0 immediately | Blank pet at launch or state change | Render before scheduling the next tick |
| Not cancelling old timers | Double speed or random jumps | One loop per renderer |
| Letting drag gestures always hit-test | Terminal clicks get stolen | Disable normal hit testing or use edit mode |

### `PetStateController`

Small state mapper that chooses the current animation from app signals.

Suggested first mapping:

| Muxy condition | Pet state |
| --- | --- |
| No active project | `idle` |
| Active pane has indeterminate or set progress | `running` |
| Active pane progress is paused | `waiting` |
| Active pane progress is error | `failed` |
| Active pane has completion pending | `waving` briefly, then `idle` |
| Active tab is source control or diff viewer | `review` |
| Project open but no active terminal pane | `waiting` |
| Default | `idle` |

Keep this mapper independent from the view so it can be unit-tested.

### `PetHostView`

Thin container mounted in `MainWindow` near the workspace overlay layer.

Recommended placement:

```text
workspace content ZStack
  terminal/editor/vcs content
  pet overlay aligned bottomTrailing
  existing rich input / modal / toast overlays above as needed
```

The pet should avoid the status bar and rich input panel. If rich input is open, lift the pet above it or hide the pet until the panel closes.

## Preferences

Add a small preference group under Interface settings:

| Key | Type | Default |
| --- | --- | --- |
| `muxy.pet.enabled` | Bool | `true` |
| `muxy.pet.selectedID` | String | `banana-cat` if bundled package is valid |
| `muxy.pet.size` | Double | `112` |

The initial version can avoid a full picker if only one package exists. Once multiple pets are found, use a picker by display name.

## Security And File Handling

Pet packages are local files owned by the current macOS user. Still validate defensively:

- only scan known roots
- resolve symlinks and reject `spritesheetPath` values outside the package directory
- require `pet.json` to be small JSON
- reject atlas files with unexpected dimensions
- cap atlas file size to a reasonable upper bound, for example 64 MB
- do not execute anything from a pet package
- do not load remote URLs from `pet.json`

External mascot artwork is not an implementation dependency. The integration should use local pet packages, such as the existing `banana-cat`, and keep Muxy's code responsible only for discovery, validation, rendering, and state mapping.

## Implementation Plan

1. Add pet models and package loading.
2. Add atlas metadata and animation frame calculation.
3. Add `PetAnimationView` and `PetHostView`.
4. Mount the host in `MainWindow`.
5. Add Interface settings for visibility and selected pet.
6. Map terminal progress and active tab type to pet states.
7. Add tests for package loading, path validation, atlas geometry, and state mapping.

Likely files:

```text
Muxy/Models/PetPackage.swift
Muxy/Models/PetAnimation.swift
Muxy/Services/PetPackageStore.swift
Muxy/Resources/Pets/banana-cat/pet.json
Muxy/Resources/Pets/banana-cat/spritesheet.webp
Muxy/Views/Pets/PetAnimationView.swift
Muxy/Views/Pets/PetHostView.swift
Muxy/Views/MainWindow.swift
Muxy/Views/Settings/InterfaceSettingsView.swift
Tests/MuxyTests/Models/PetAnimationTests.swift
Tests/MuxyTests/Services/PetPackageStoreTests.swift
```

## Test Plan

Unit tests:

- valid package loads from a temporary root
- bundled `banana-cat` package is discoverable
- missing `pet.json` is ignored
- missing `spritesheet.webp` is ignored
- `spritesheetPath` escaping the package directory is rejected
- wrong atlas dimensions are rejected
- selected pet falls back when the saved id no longer exists
- each animation state reports the expected row, frame count, and durations
- progress states map to the expected pet state

Manual checks:

- launch Muxy and confirm bundled `banana-cat` is selected by default
- confirm `${CODEX_HOME:-$HOME/.codex}/pets/banana-cat` can also be discovered as a custom package
- confirm the pet appears without blocking terminal clicks
- confirm Reduce Motion freezes the animation
- trigger terminal progress and confirm `running`
- trigger paused/error progress and confirm `waiting` or `failed`
- open source control or diff viewer and confirm `review`

## Non-Goals For First Version

- generating pets inside Muxy
- editing pet packages
- syncing pets to mobile clients
- shipping third-party mascot artwork
- adding a WebView extension just to render the pet

Those can be revisited after the native consumer path is stable.
