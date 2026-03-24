# StarkBattery DataField — Garmin Connect IQ Design

**Date:** 2026-03-24
**Platform:** Garmin Connect IQ (Monkey C)
**Target devices:** Fenix 7 Pro Solar, Instinct 3 AMOLED 50mm, KM variant
**Iteration:** 1 — standalone data field with background BLE

---

## Goal

Create a Garmin Connect IQ **data field** that displays the Stark Varg electric motorcycle's battery state of charge (SOC) during activities (cycling, running, etc.). The data field must work independently — no other app needs to be running.

The existing StarkBattery watch-app is **not modified** in any way. The data field is a separate installable package.

---

## Architecture

### Package structure

```
New package: StarkBatteryDF.iq
├── manifest_df.xml          — type="datafield", fenix7pro, new App ID
├── manifest_df_mp.xml       — type="datafield", instinct3amoled50mm, new App ID
├── manifest_df_km.xml       — type="datafield", KM device, new App ID
├── monkey_df.jungle         — build target for fenix7pro
├── monkey_df_mp.jungle      — build target for instinct3amoled50mm
├── monkey_df_km.jungle      — build target for KM variant
└── source-df/
    ├── StarkBatteryDFApp.mc     — AppBase entry point, registers temporal event
    ├── StarkBatteryDFField.mc   — SimpleDataField, compute() reads SOC from storage
    └── StarkBatteryDFService.mc — ServiceDelegate, BLE scan → read SOC → store
```

Existing files (`source/`, `manifest.xml`, `monkey.jungle`, etc.) are untouched.

`VinConfig.mc` — the VIN constant — is reused via the build system (included in both the existing app and the new data field sources). No duplication.

---

## App ID

Each variant (fenix7pro, mp, km) of the data field gets its own App ID, distinct from the existing watch-app IDs. Shared `Application.Storage` is scoped per App ID, so there is no cross-contamination with the watch-app's storage.

---

## BLE approach

`ServiceDelegate` has full BLE access in Connect IQ. The data field registers a temporal background event; when it fires, the service delegate performs a short BLE session:

1. Scan for device matching `STARK_VARG_VIN` (same UUID constants as existing app)
2. Connect → enable notifications on SOC characteristic
3. Receive one notification → store SOC + timestamp → disconnect
4. Release all BLE resources

The BLE logic mirrors the existing `BleManager.mc` but is simplified for a one-shot read pattern (no persistent connection, no reconnect loop). Scan timeout is 10 seconds (shorter than the 30s in the watch-app — background time is limited).

### BLE constants (same as existing app)

| Role            | UUID                                           |
|-----------------|------------------------------------------------|
| Battery Service | `00006000-5374-6172-4b20-467574757265`         |
| Battery SOC     | `00006004-5374-6172-4b20-467574757265`         |

Format: uint16 little-endian, value 0–100 (clamped defensively).

---

## Data flow

```
Every ~5 minutes (TemporalEvent):
  StarkBatteryDFService.onTemporalEvent()
    → BLE scan (max 10s)
    → if found: connect → read SOC characteristic notification
    → Application.Storage.setValue("soc", socValue)
    → Application.Storage.setValue("soc_ts", Time.now().value())
    → disconnect, release BLE

StarkBatteryDFField.compute() [called ~1/s during activity]:
    → soc = Application.Storage.getValue("soc")
    → ts  = Application.Storage.getValue("soc_ts")
    → if soc == null        → return "--"
    → if age > 15 minutes   → return "?" + soc + "%"
    → return soc + "%"
```

---

## UI — data field output

Connect IQ data fields return a value; the watch OS controls layout and font based on the user's activity screen configuration. `StarkBatteryDFField` extends `SimpleDataField`.

| Situation | Displayed value |
|-----------|-----------------|
| Connected, fresh data (≤15 min old) | `87%` |
| Stale data (>15 min old) | `?87%` |
| No data ever received | `--` |

The `?` prefix on stale data signals the user that the value is not current without needing a separate error state.

---

## Entry point — AppBase

`StarkBatteryDFApp` extends `AppBase`. In `onStart()`:

```monkey-c
Background.registerForTemporalEvent(new Time.Duration(5 * 60));
```

This registers the 5-minute background wake-up. Connect IQ persists this registration, so it fires even when the data field is not actively displayed.

The data field registers its `ServiceDelegate` in the manifest (required for background execution).

---

## Manifest structure

Each manifest declares:
- `type="datafield"`
- `entry="StarkBatteryDFApp"`
- Permission: `BluetoothLowEnergy`
- Permission: `Background`
- `<background>` element listing `StarkBatteryDFService` as the service delegate and `temporal-event` as the trigger

Example (`manifest_df.xml`):

```xml
<iq:application entry="StarkBatteryDFApp" id="<new-uuid>"
  type="datafield" minSdkVersion="3.2.0" ...>
  <iq:products><iq:product id="fenix7pro"/></iq:products>
  <iq:permissions>
    <iq:uses-permission id="BluetoothLowEnergy"/>
    <iq:uses-permission id="Background"/>
  </iq:permissions>
  <iq:background>
    <iq:handler id="TemporalEvent" type="timer"
                class="StarkBatteryDFService"/>
  </iq:background>
</iq:application>
```

---

## VIN configuration

`STARK_VARG_VIN` is defined in `VinConfig.mc` (already per-variant via the jungle build system). The new jungle files for the data field include the same `source-vin-*` directories as the existing builds, so the VIN constant is automatically picked up — no duplication, no new user-facing configuration step.

---

## Error handling

| Situation | Behavior |
|-----------|----------|
| Motorcycle not in range | Scan times out after 10s, storage unchanged, field shows last known value or `--` |
| BLE unavailable | Exception caught silently, no crash, field shows `--` |
| SOC value out of range | Clamped to 100 before storage |
| Data older than 15 min | Displayed with `?` prefix |
| Never connected | Displays `--` |

---

## Files summary

```
New files:
  manifest_df.xml
  manifest_df_mp.xml
  manifest_df_km.xml
  monkey_df.jungle
  monkey_df_mp.jungle
  monkey_df_km.jungle
  source-df/StarkBatteryDFApp.mc
  source-df/StarkBatteryDFField.mc
  source-df/StarkBatteryDFService.mc

Unchanged:
  (everything in source/, manifest.xml, monkey.jungle, etc.)
```

---

## Out of scope (iteration 1)

- Real-time BLE connection during activity (requires persistent connection, higher battery drain)
- Colour coding in the data field (SimpleDataField returns a string only)
- Settings UI for VIN in the data field (VIN remains a compile-time constant)
- Additional BLE characteristics beyond SOC
