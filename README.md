# Feng Shui

Scan a room with an iPhone or iPad, view it as an editable 3D model, and get checks and advice for typhoons, fire, power outages, cooling and energy, air quality and infestation. A home-quality score is shown by three pets (Safety, Energy, Pests).

> Status: written without access to a device. None of it has been run on an iPhone or in a browser yet, so expect to fix small things on first run.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole app UI: 3D room, editor, DLC tabs, score and pets. One file, loaded inside the iOS app. |
| `RoomScanCaptureView.swift` | The iOS scan screen (RoomPlan), local saving, share sheet, and the embedded web view that loads `index.html`. Also contains `ContentView`. |
| `DeviceMarker.swift` | Lets you tap an AC, ceiling fan or floor fan in the live camera view during a scan (RoomPlan does not detect them). |

Your own app entry file (`le_rat_is_in_da_houseApp.swift`) only needs to show `ContentView()`.

## Requirements

- A LiDAR device: iPhone 12 Pro or later Pro model, or an iPad Pro. The Simulator cannot scan.
- iOS 16.4 or later (RoomPlan needs 16.0; the page uses an import map, which needs 16.4).
- Xcode, and a signing team (a free Apple ID works for your own device; the install expires after about 7 days).

## iOS setup

1. Add `RoomScanCaptureView.swift` and `DeviceMarker.swift` to the project, with your app target ticked.
2. Add `index.html` as a resource and check it appears under Build Phases, Copy Bundle Resources.
3. In Target, Info, add:
   - Privacy - Camera Usage Description (for example "Used to scan your room in 3D.")
   - Application supports iTunes file sharing: YES
   - Supports opening documents in place: YES
4. Set Minimum Deployments to iOS 16.4 or later.
5. Run on a physical device. If the app stops while attached to Xcode with a Metal "Draw Errors Validation" message, untick Metal API Validation in Product, Scheme, Edit Scheme, Run, Diagnostics, or run the app without Xcode attached.

## Using it

1. **Scan.** Tap Start Scan and walk the room slowly. The counters show walls, openings and objects found.
2. **Mark devices (optional).** While scanning, pick a mark type above the Start/Finish buttons, then tap in the camera view:
   - **AC:** tap one corner of the unit, then the opposite corner (gives its real size). The page snaps it flat to the nearest wall.
   - **Ceiling fan:** point up and tap the ceiling under its center.
   - **Floor fan:** tap the floor where it stands.
   - Undo removes the last mark or cancels a half-finished AC. Mark before tapping Finish.
3. **Finish Scan.** The scan is saved in the app's Documents folder as `RoomScan-<time>.usdz` and `.json`. The marks are saved in the JSON under `devices`.
4. **View in Home Guardian.** Opens the page inside the app and imports the scan. "Share Scan Files" exports the `.usdz` and `.json`.

You can also open `index.html` in a desktop browser, use "Import scan (.json)", or use "Load demo living room" to try it without a scan.

## The page (`index.html`)

### Layout
- **Score popup** (top right of the 3D view, minimizable): overall percent, the three pets, and concern icons. Tapping an icon opens the tab it belongs to and shows its reason, with Mark done where it applies. Tapping a pet filters the icons to that area. "Change pets" picks a shape or re-rolls.
- **Objects button** (round, top left): opens the list of every object with the same editing functions.
- **Tabs** (icons, same size): Air, Energy, Cooling, Infestation, Fire, Typhoon, Power outage.
- Orbit, pan and zoom the 3D view. Tap an object to select it: it glows and its row in the Objects list is pressed in.

### Room and objects
- All sizes are real meters. The 0.3 m grid is only a guide.
- The importer reads RoomPlan JSON, auto-aligns the room's rotation, and builds walls, doors, windows, openings and objects from it.
- Every object can be re-typed at any time, resized, moved, rotated, deleted, or added ("Add to room").
- Types: wall, door, window, opening, sofa, chair, table, bed, cabinet, fridge, stove, oven, sink, dishwasher, washer/dryer, toilet, bathtub, TV, fireplace, stairs, heater, air conditioner, fan, ceiling fan, other.
- Models are built from primitives with generated wood, fabric and metal textures. `MODEL_URLS` near the top of the script can point a type at a `.glb` file instead.

### Devices
Fridge, oven, dishwasher, washer/dryer, heater, TV, AC, fan and ceiling fan have device state: on/off, power (W) and hours per day. An AC also has a set temperature, aim angle and swing. A fan has an aim angle and oscillate. These feed the Energy and Cooling checks and the airflow drawing.

### Tabs
- **Air:** indoor air (PM2.5) from the live air box, and a simulator.
- **Energy:** live power use, kWh and cost, and the simulator.
- **Cooling:** west-window sun gain with shading options, scenarios A/B/C/D, suggested AC and fan placement, and a devices card (state, kWh per day, airflow coverage, setpoint saving, cross-ventilation).
- **Infestation:** risk conditions read from the model: hidden gaps behind furniture, food area near doors, moisture, entry points, where to put monitors. It does not detect pests.
- **Fire:** air box requirement and recommended wall spot, a manual spot picker, "No, another spot", live readings, local alarm sound, and push alerts.
- **Typhoon:** windows ranked by size with board or tape advice, large doors flagged, and a demo switch for an active warning.
- **Power outage:** a six-item checklist, where to keep the emergency kit, fridge and freezer hold times, heavy devices to switch off, and heat and light tips.

### Score and pets
Safety, Energy and Pests each get a percent; the overall score is the lowest of the three. Each area has a pet shape whose face shows the score: joyful (90+), happy (80+), so-so (60+), sad (40+), alarmed (below 40), asleep (no data). The arc over each pet fills with the score.

### Airflow and suggestions
- Animated streaks are drawn from every running AC and fan, and stop at tall furniture and walls. A faint ghost stream shows a suggested device before you place it, and a faint line shows the cross-breeze path between the two farthest-apart windows. The air box ball turns orange when airflow hits it.
- AC and fan suggestions can be placed ("Place it") or skipped ("No, another"). Skipping shows the change against the skipped option; other options are listed with both numbers. A slider re-ranks between placement clearance and energy saved.
- Energy figures are indicative estimates, not a simulation.

### Language and saved settings
The page has English and Traditional Chinese. It stores three small values in the browser: the pet choices, the language, and the push topic name.

### Hooks for the host app
- `window.importScanJSONBase64(b64)` and `window.importScanJSONText(text)` import a scan.
- `window.setDevice(id, {on, w, dir, ...})` updates a device.
- `window.notify(level, message)` posts `{type:'notify', level, message}` to the native bridge. The page also posts `{type:'scanImported', walls, objects}`.

## Scan JSON

The saved `.json` is RoomPlan's encoded `CapturedRoom` plus an optional `devices` array:

```json
"devices": [
  { "type": "ac", "position": [x, y, z], "normal": [x, y, z], "size": [width, height] },
  { "type": "ceilingFan", "position": [x, y, z], "normal": [x, y, z] },
  { "type": "fan", "position": [x, y, z], "normal": [x, y, z] }
]
```

Positions are in meters in the scan session's world space.

## Live air box data and network use

- `three.js` and its add-ons (OrbitControls, GLTFLoader) and `mqtt.js` load from the jsDelivr CDN, so the page needs internet.
- Live readings come over MQTT from the public broker `wss://broker.emqx.io:8084/mqtt`, topic `home-guardian/demo/sensor`, as JSON with `temp`, `co2`, `hum`, `pm25` and `power`. This is a public demo broker: anyone can read or publish to that topic.
- Push alerts post to `https://ntfy.sh/` using a topic name stored in the browser.
- The simulator can generate normal, stuffy, possible fire, pollution and power overload readings without a sensor.
- Everything else (scan, saving, scoring) stays on the device.

## Known limits

- One room per scan.
- RoomPlan does not detect AC, fans or ceiling items; use the marks or add them in Objects.
- The coordinate match between the marks and the exported room has not been confirmed. The page warns when a marked AC is not near a wall.
- Scores and savings are rules of thumb, not measurements. The app does not replace certified smoke or fire alarms.
- Sun gain uses an illustrative west-facing day, not measured weather. Window orientation is ticked by hand.
…]()
