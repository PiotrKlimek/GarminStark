# StarkBattery DataField — Garmin Connect IQ Design

**Date:** 2026-03-24
**Platform:** Garmin Connect IQ (Monkey C)
**Target devices:** Fenix 7 Pro Solar, Instinct 3 AMOLED 50mm, Instinct 2 (KM variant)
**minSdkVersion:** 3.2.0 (covers `Background`, `ServiceDelegate`, and BLE in background context)
**Iteration:** 1 — standalone data field with background BLE

---

## Goal

Create a Garmin Connect IQ **data field** that displays the Stark Varg electric motorcycle's battery state of charge (SOC) during activities (cycling, running, etc.). The data field must work independently — no other app needs to be running.

The existing StarkBattery watch-app is **not modified in any way** — not its source files, not its jungle files, not its manifests. The data field is a completely separate installable package.

---

## Architecture

### Self-contained source directory

The data field lives entirely in `source-df/`. It does **not** include any files from `source/` (the watch-app directory). Doing so would pull in `StarkVargApp.mc`, `StarkVargView.mc`, and `BleManager.mc`, all of which import `Toybox.WatchUi` and `Toybox.Timer` — APIs unavailable in background execution contexts.

Instead, `source-df/` is fully self-contained:

- `VinConfig.mc` is a one-line file with the VIN constant. It is duplicated in `source-df/` (identical content to `source/VinConfig.mc`). This is intentional: keeping the two packages completely independent is cleaner than introducing a shared directory that would require changing the existing watch-app jungle files.
- BLE UUID constants are defined directly in `StarkBatteryDFService.mc` (two lines). No shared file needed.

### Package structure

```
New files (data field package):
  manifest_df.xml              — type="datafield", fenix7pro, new App ID
  manifest_df_mp.xml           — type="datafield", instinct3amoled50mm, new App ID
  manifest_df_km.xml           — type="datafield", instinct2, new App ID
  monkey_df.jungle             — build target for fenix7pro
  monkey_df_mp.jungle          — build target for instinct3amoled50mm
  monkey_df_km.jungle          — build target for instinct2 (KM variant)
  source-df/
    VinConfig.mc               — const STARK_VARG_VIN = "..." (same value as source/VinConfig.mc)
    StarkBatteryDFApp.mc       — AppBase, registers BLE profile + temporal event in onStart()
    StarkBatteryDFField.mc     — SimpleDataField, compute() reads SOC from storage
    StarkBatteryDFService.mc   — ServiceDelegate, one-shot BLE read → storage

Unchanged (zero modifications):
  source/                      — all existing watch-app source files
  manifest.xml, manifest_mp.xml, manifest_km.xml
  monkey.jungle, monkey_mp.jungle, monkey_km.jungle
  (everything else)
```

### Jungle files

Each data field jungle file references only `source-df/`:

```
# monkey_df.jungle (example)
project.manifest = manifest_df.xml
base.sourcePath = source-df
```

### App IDs

Each variant's data field manifest uses a new, unique App ID (distinct from the corresponding watch-app variant). `Application.Storage` is scoped per App ID, so there is no cross-contamination with the watch-app's storage.

---

## BLE lifecycle

### Profile registration

`BluetoothLowEnergy.registerProfile()` must be called once per app start before any scan or GATT operation. It is called in `StarkBatteryDFApp.onStart()`. The call is wrapped in try/catch because Connect IQ throws if the profile is already registered from a previous launch — the exception is safe to ignore. `Background.registerForTemporalEvent()` is also called in `onStart()` on every launch; this is the required pattern in Connect IQ (re-registration is expected and deduplicated by the OS).

### One-shot read pattern

The service delegate performs a minimal, single-use BLE session on each temporal event:

1. **Defensive teardown**: call `BluetoothLowEnergy.setScanState(SCAN_STATE_OFF)` to clear any lingering state from the prior session.
2. `BluetoothLowEnergy.setDelegate(self)` — register the delegate.
3. `BluetoothLowEnergy.setScanState(SCAN_STATE_SCANNING)` — start scan.
4. `onScanResults()` — match device name against `STARK_VARG_VIN`; record start time; if elapsed > 10 s, stop and exit (see scan timeout below); if found, call `BluetoothLowEnergy.pairDevice(result)` and stop scan.
5. `onConnectedStateChanged(CONNECTED)` — call `_enableNotifications(device)` (write CCCD 0x0001, same as existing app).
5a. `onConnectedStateChanged(DISCONNECTED)` — silent exit: teardown and return. No reconnect. Storage unchanged.
6. `onCharacteristicChanged()` — parse SOC (uint16 LE, clamp 0–100), write to `Application.Storage`, then disconnect: `setScanState(OFF)`, set delegate to null.

**No reconnect loop.** If the motorcycle is not found or connection fails, the session ends silently; stored value is unchanged.

### Scan timeout (no `Timer.Timer`)

`Timer.Timer` is not available in background execution contexts. The scan limit is enforced by wall-clock check: record `Time.now().value()` at the start of `onTemporalEvent()`; check elapsed time on each `onScanResults()` invocation; if elapsed ≥ 10 seconds, call `setScanState(OFF)` and exit.

### Background time budget

The Connect IQ OS grants background service delegates approximately 30 seconds. Estimated budget:
- Defensive teardown + scan start: < 1 s
- Scan: up to 10 s
- Connect + GATT negotiation + notification: up to 14 s
- Storage write + teardown: < 1 s
- **Total: ~26 s** — within the ~30 s OS limit.

### BLE constants (defined in `StarkBatteryDFService.mc`)

```monkey-c
const DF_BATT_SERVICE_UUID_STR  = "00006000-5374-6172-4b20-467574757265";
const DF_BATT_SOC_CHAR_UUID_STR = "00006004-5374-6172-4b20-467574757265";
```

Format: uint16 little-endian, value 0–100 (clamped defensively).

---

## Data flow

```
StarkBatteryDFApp.onStart():
    BluetoothLowEnergy.registerProfile({...})          // wrapped in try/catch
    Background.registerForTemporalEvent(new Time.Duration(5 * 60))

Every ~5 minutes (TemporalEvent):
  StarkBatteryDFService.onTemporalEvent()
    → record startTime = Time.now().value()
    → defensive teardown (setScanState OFF)
    → setDelegate(self)
    → setScanState(SCANNING)

  onScanResults():
    → if Time.now().value() - startTime >= 10: stop, exit
    → if name matches VIN: pairDevice, setScanState(OFF)

  onConnectedStateChanged(CONNECTED):
    → look up service + characteristic + CCCD descriptor
    → if any lookup returns null: setScanState(OFF), delegate = null, exit silently
    → write CCCD 0x0001 to enable notifications

  onConnectedStateChanged(DISCONNECTED before notification):
    → setScanState(OFF), delegate = null, exit silently

  onCharacteristicChanged():
    → parse uint16 LE, clamp to 100
    → Application.Storage.setValue("df_soc", socValue)
    → Application.Storage.setValue("df_soc_ts", Time.now().value())
    → setScanState(OFF), delegate = null

StarkBatteryDFField.compute() [called ~1/s during activity]:
    soc = Application.Storage.getValue("df_soc")    // Number or null
    ts  = Application.Storage.getValue("df_soc_ts") // Epoch seconds or null
    if soc == null or ts == null → return "--"
    age = Time.now().value() - ts
    if age > 15 * 60 → return "?" + soc.toString() + "%"
    return soc.toString() + "%"
```

`compute()` returns `Lang.String`. Integer SOC is converted via `.toString()` before concatenation. Both `soc` and `ts` are null-checked before use.

---

## UI — data field output

### Iteration 1: full `DataField` with in-field debug panel

In iteration 1, `StarkBatteryDFField` extends **`WatchUi.DataField`** (not `SimpleDataField`) and implements `onUpdate(dc)` directly. This gives full drawing control and allows a compact debug panel to be shown inside the field — no logs needed for basic diagnostics.

The field is split into two rows:

```
┌──────────────────────────┐
│  87%                     │  ← main value, large font
│  CON · 3m ago · ok       │  ← debug row, tiny font, grey
└──────────────────────────┘
```

**Main value row** (top ~60% of field height, `FONT_NUMBER_MEDIUM` or largest that fits):

| Situation | Displayed |
|-----------|-----------|
| Fresh SOC (≤15 min) | `87%` |
| Stale SOC (>15 min) | `?87%` |
| No data | `--` |

**Debug row** (bottom ~40%, `FONT_SYSTEM_XTINY`, `COLOR_LT_GRAY`):

Format: `<state> · <age> · <last-event>`

| Field | Values |
|-------|--------|
| `<state>` | `SCN` scanning \| `CON` connected \| `TO` scan timeout \| `DIS` disconnected \| `ERR` exception |
| `<age>` | `Xs` / `Xm` since last successful SOC write, or `--` if never |
| `<last-event>` | last notable thing that happened: `ok` (SOC stored), `no-svc` (service not found), `no-chr` (characteristic not found), `no-ccd` (CCCD not found), `dis` (disconnected before notification), `ex` (exception) |

Examples:
- `CON · 3m · ok` — connected 3 minutes ago, everything worked
- `SCN · 12m · ok` — scanning now, last read was 12 min ago
- `TO · 2m · ok` — scan timed out, last read was 2 min ago
- `SCN · -- · no-svc` — scanning, never had good data, last failure was "service not found"
- `ERR · -- · ex` — exception thrown

**State is stored in `Application.Storage`** alongside SOC, so the debug row survives between background sessions and field reloads:
- `"df_state"` — String: `"SCN"` / `"CON"` / `"TO"` / `"DIS"` / `"ERR"`
- `"df_last_event"` — String: `"ok"` / `"no-svc"` / `"no-chr"` / `"no-ccd"` / `"dis"` / `"ex"`
- `"df_soc"` — Number (existing)
- `"df_soc_ts"` — Number epoch seconds (existing)

`StarkBatteryDFService` writes `df_state` and `df_last_event` at every notable transition (same points as `System.println` log lines). `StarkBatteryDFField.onUpdate()` reads all four keys and renders both rows.

**Drawing notes:**
- Use `dc.getWidth()` / `dc.getHeight()` for layout — field size varies by device and user configuration.
- Background: `COLOR_BLACK`, clear with `dc.clear()`.
- Main value: centered horizontally, vertically centered in top 60%.
- Debug row: centered horizontally, vertically centered in bottom 40%.
- If field height < 40px (very small config), skip the debug row entirely and fall back to main value only.

### Iteration 2 (cleanup): simplify to `SimpleDataField`

Once BLE flow is confirmed working on real hardware, `StarkBatteryDFField` is rewritten to extend `SimpleDataField`. The `compute()` method returns only the main value string (`87%`, `?87%`, `--`). The `df_state` and `df_last_event` storage keys are removed. The debug row, `onUpdate()`, and all drawing code are deleted.

---

## Manifest structure

Each manifest declares `type="datafield"`, the `Background` permission, and registers the service delegate for temporal events.

Example (`manifest_df.xml`):

```xml
<?xml version="1.0"?>
<iq:manifest version="3" xmlns:iq="http://www.garmin.com/xml/connectiq">
  <iq:application entry="StarkBatteryDFApp" id="<new-uuid-fenix7pro-df>"
    minSdkVersion="3.2.0"
    name="StarkBattery Field"
    type="datafield"
    version="1.0.0">
    <iq:products><iq:product id="fenix7pro"/></iq:products>
    <iq:permissions>
      <iq:uses-permission id="BluetoothLowEnergy"/>
      <iq:uses-permission id="Background"/>
    </iq:permissions>
    <iq:languages>
      <iq:language>pol</iq:language>
      <iq:language>eng</iq:language>
    </iq:languages>
    <iq:background>
      <iq:handler id="TemporalEvent" type="timer"
                  class="StarkBatteryDFService"/>
    </iq:background>
  </iq:application>
</iq:manifest>
```

Device IDs per variant:

| Manifest | Device ID |
|----------|-----------|
| `manifest_df.xml` | `fenix7pro` |
| `manifest_df_mp.xml` | `instinct3amoled50mm` |
| `manifest_df_km.xml` | `instinct2` |

---

## Error handling

| Situation | Behavior |
|-----------|----------|
| Motorcycle not in range | Scan times out after 10s (wall-clock), storage unchanged, field shows last known value or `--` |
| BLE unavailable | Exception caught in `onStart()` and `onTemporalEvent()`, no crash, field shows `--` |
| Background session re-entry (prior session lingering) | Defensive `setScanState(OFF)` at start of every `onTemporalEvent()` |
| Disconnect before notification received | Silent exit, storage unchanged, no reconnect |
| GATT service or characteristic not found | Silent exit: setScanState(OFF), delegate = null, storage unchanged |
| SOC value out of range | Clamped to 100 before storage write |
| Data older than 15 min | Displayed with `?` prefix |
| `soc` set but `ts` missing in storage | Treated as no data, displays `--` |
| Never connected | Displays `--` |
| Background time budget exceeded | OS terminates session; storage holds last successfully written value |

---

## Debug logging (iteration 1 requirement)

### Rationale

Background service delegates run without a screen and are hard to observe. Rich logging from the first build eliminates guesswork during hardware testing and avoids multiple "flash → wonder what happened → fix blind" cycles.

### Mechanism: `System.println`

Connect IQ's `System.println(value)` writes to the **device log**, readable via:
- **Garmin Express** → device log export
- **adb logcat** (Android + sideload) — lines tagged `MonkeyC`
- **Connect IQ simulator** — console pane

`System.println` is available in both foreground (AppBase, DataField) and background (ServiceDelegate) contexts. It accepts any value; complex objects should be converted with `.toString()` or concatenated inline.

### What to log — `StarkBatteryDFService` (background)

Log every state transition and decision point. Each line must include a short prefix so grep works:

| Event | Log line (example) |
|-------|--------------------|
| `onTemporalEvent()` entered | `"[DF] onTemporalEvent start ts=" + startTime` |
| Defensive teardown executed | `"[DF] teardown: setScanState OFF"` |
| Scan started | `"[DF] scan started"` |
| Scan result received | `"[DF] scanResult name=" + (name != null ? name : "null")` |
| VIN matched | `"[DF] VIN match — pairing"` |
| VIN not matched (each result) | `"[DF] skip name=" + name` |
| Scan timeout hit | `"[DF] scan timeout after " + elapsed + "s — stopping"` |
| Connected | `"[DF] connected"` |
| Disconnected (before notification) | `"[DF] disconnected before notification — exit"` |
| Service lookup result | `"[DF] service=" + (service != null ? "found" : "NULL")` |
| Characteristic lookup result | `"[DF] char=" + (char != null ? "found" : "NULL")` |
| CCCD descriptor lookup result | `"[DF] cccd=" + (cccd != null ? "found" : "NULL")` |
| CCCD write sent | `"[DF] CCCD write sent"` |
| Notification received | `"[DF] notification raw=[" + value[0] + "," + value[1] + "]"` |
| SOC parsed and stored | `"[DF] soc=" + soc + " ts=" + Time.now().value()` |
| Exception caught (any) | `"[DF] exception: " + e.getErrorMessage()` |

### What to log — `StarkBatteryDFApp` (foreground, onStart)

| Event | Log line |
|-------|----------|
| `onStart()` entered | `"[DF] onStart"` |
| BLE profile registration attempted | `"[DF] registerProfile"` |
| BLE profile registration succeeded | `"[DF] registerProfile OK"` |
| BLE profile registration threw | `"[DF] registerProfile exception: " + e.getErrorMessage()` |
| Temporal event registered | `"[DF] registerForTemporalEvent 5min"` |

### What to log — `StarkBatteryDFField` (foreground, compute)

`compute()` is called ~1/s — do **not** log on every call. Log only when the displayed value changes:

| Event | Log line |
|-------|----------|
| Value changed | `"[DF] compute display=" + displayStr` |
| Storage returned null | `"[DF] compute soc=null"` (log once, not every second — use a flag) |

### Log-once flag for `compute()`

To avoid flooding the log, `StarkBatteryDFField` must keep a `_lastDisplay` instance variable (initialized to `null`). Only call `System.println` when the new display string differs from `_lastDisplay`, then update `_lastDisplay`.

```monkey-c
// sketch — exact implementation follows spec
if (!displayStr.equals(_lastDisplay)) {
    System.println("[DF] compute display=" + displayStr);
    _lastDisplay = displayStr;
}
```

### No stripping in iteration 1

Debug log lines are **not** removed or conditionally compiled in iteration 1. They remain in the shipped build. Removal is deferred to a future iteration once the BLE flow has been confirmed working on real hardware.

---



- Real-time BLE connection during activity (persistent connection, higher battery drain)
- Colour coding in the data field (SimpleDataField returns a string only)
- Settings UI for VIN (VIN remains a compile-time constant in `VinConfig.mc`)
- Additional BLE characteristics beyond SOC
- Multiple watch model support beyond the three existing variants
