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

`StarkBatteryDFField` extends `SimpleDataField`. Connect IQ controls layout and font size based on the user's activity screen configuration; the field returns only a string.

| Situation | Displayed value | Max chars |
|-----------|-----------------|-----------|
| Connected, fresh data (≤15 min) | `87%` | 4 (`100%`) |
| Stale data (>15 min old) | `?87%` | 5 (`?100%`) |
| No data or missing timestamp | `--` | 2 |

The `?` prefix signals a stale reading without requiring a separate error state. Maximum 5 characters; all three target devices render this correctly in standard data field widths.

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

## Out of scope (iteration 1)

- Real-time BLE connection during activity (persistent connection, higher battery drain)
- Colour coding in the data field (SimpleDataField returns a string only)
- Settings UI for VIN (VIN remains a compile-time constant in `VinConfig.mc`)
- Additional BLE characteristics beyond SOC
- Multiple watch model support beyond the three existing variants
