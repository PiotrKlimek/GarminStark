# Stark Varg Battery Monitor — Garmin Watch App Design

**Date:** 2026-03-19
**Platform:** Garmin Connect IQ (Monkey C)
**Target device:** Fenix 7 Pro Solar
**Iteration:** 1 — standalone foreground app, direct BLE

---

## Goal

Display the Stark Varg electric motorcycle's battery state of charge (SOC) directly on a Garmin Fenix 7 Pro Solar watch. The watch connects to the motorcycle via Bluetooth Low Energy without any phone or intermediate service.

---

## Reference

Protocol derived from [svag-mini](https://github.com/b1naryth1ef/svag-mini) — an ESP32 firmware that connects to the same BLE interface. This app replicates the BLE client logic in Monkey C.

---

## Architecture

```
StarkVargApp (AppBase)
├── MainView         — renders current state (scanning / connected / disconnected / timeout)
├── BleManager       — BLE profile declaration, scan, connect, GATT notifications
└── InputDelegate    — BACK exits the app; ENTER/SELECT retries scan in timeout state
```

The app is a standard Connect IQ `watch-app`. No background service, no glances, no complications in this iteration.

### App state

`BleManager` owns a single state variable:

```monkey-c
enum {
    STATE_SCANNING,      // scanning for motorcycle
    STATE_CONNECTED,     // BLE connected, receiving notifications
    STATE_RECONNECTING,  // connection lost, scanning again
    STATE_TIMEOUT        // scan ran 30s without finding the device
}
```

`MainView` reads this state (plus the last SOC value) on every `onUpdate()` call to decide what to render.

---

## BLE Protocol

### Device identification

The Stark Varg advertises via BLE with its VIN as the device name (e.g. `UDUEX1AE3SA000588`). The app scans for a device whose name matches the configured VIN constant.

### Profile

All UUIDs use the Stark Future 128-bit base. Full 32-hex-digit UUIDs (required by Connect IQ):

| Role            | UUID (128-bit, full form)                    |
|-----------------|----------------------------------------------|
| Battery Service | `00006000-5374-6172-4b20-467574757265`       |
| Battery SOC     | `00006004-5374-6172-4b20-467574757265`       |

Battery SOC characteristic:
- Mode: NOTIFY
- Format: 2 bytes, uint16 little-endian
- Value: raw SOC as received from device. Based on the reference implementation (svag-mini) the value arrives as a percentage integer (0–100). The app must clamp defensively: `soc = soc > 100 ? 100 : soc` before display, to guard against unexpected raw values.

### Connect IQ BLE lifecycle (correct order)

Connect IQ requires GATT client profiles to be declared before scanning begins. The correct sequence:

1. **App init** (`onStart`) → declare GATT client profile via `BluetoothLowEnergy.registerProfile()`, providing service UUID, characteristic UUID, and NOTIFY property. This tells the Connect IQ BLE subsystem which UUIDs to watch for — it does NOT create a GATT server.
2. Start scan → `BluetoothLowEnergy.startScan()`
3. `onScanResults()` callback → compare each result's device name to the VIN constant
4. Match found → `BluetoothLowEnergy.connect(device)`
5. `onConnectedStateChanged()` → enable notifications on the SOC characteristic (write CCCD)
6. `onCharacteristicChanged()` → parse 2 bytes little-endian → clamp → store SOC → trigger view refresh
7. Disconnected (any reason) → restart scan, set state to `STATE_RECONNECTING`

---

## VIN configuration

For iteration 1, VIN is a hardcoded constant in source:

```monkey-c
const STARK_VARG_VIN = "YOUR_VIN_HERE";
```

The user replaces `YOUR_VIN_HERE` with their actual VIN before compiling.

---

## UI — screen states

Target: Fenix 7 Pro Solar, round display 260×260px.
Font: Fenix 7 Pro supports Polish diacritics (ą, ę, ó, ś, etc.) — Polish strings in `strings.xml` are safe.

### State 1: Scanning (`STATE_SCANNING`)
- Title: `STARK VARG` (top, small font)
- Body: `Szukam motocykla...` (center)

### State 2: Connected (`STATE_CONNECTED`)
- Title: `STARK VARG` (top, small font)
- Body: large SOC percentage, e.g. `87%` (center)
- Bar: full-width horizontal rectangle below the percentage. Green when SOC > 20%, red at 20% or below.

### State 3: Reconnecting (`STATE_RECONNECTING`)
- Title: `STARK VARG` (top, small font)
- Body: `Rozłączono` + `Szukam...` (center)

### State 4: Scan timeout (`STATE_TIMEOUT`)
- Body: `Nie znaleziono motocykla` (center)
- Hint: `Naciśnij START, aby spróbować ponownie` (small, below)
- ENTER/SELECT button restarts the scan (transitions back to `STATE_SCANNING`)

### Input
- BACK button → exit the app (all states)
- ENTER/SELECT → retry scan (only in `STATE_TIMEOUT`)

---

## Error handling

| Situation                   | Behavior                                           |
|-----------------------------|----------------------------------------------------|
| Motorcycle not in range     | Stay in `STATE_SCANNING`                           |
| Connection dropped          | Transition to `STATE_RECONNECTING`, restart scan   |
| Scan timeout (30s)          | Transition to `STATE_TIMEOUT`, wait for user retry |
| BLE not available on device | Show `BLE niedostępne`, exit gracefully            |
| SOC value out of range      | Clamp to 100 before display                        |

---

## Files

```
source/
  StarkVargApp.mc       — AppBase, entry point, registers BLE profile on start
  StarkVargView.mc      — MainView, renders all four states
  StarkVargDelegate.mc  — InputDelegate, BACK and ENTER/SELECT handling
  BleManager.mc         — scan, connect, notifications, state machine, 30s timer
resources/
  layouts/layout.xml    — main layout
  strings/strings.xml   — UI strings (PL + EN)
  drawables/            — launcher icon (reuse existing)
manifest.xml            — permissions: <uses-permission id="com.garmin.permission.BLUETOOTH_LOW_ENERGY"/>
                          products: fenix7pro only (iteration 1)
```

---

## Out of scope (iteration 1)

- Background BLE / glances / complications
- VIN settings UI (Connect IQ app settings)
- Speed, status, or other BLE characteristics
- Multiple watch model support beyond fenix7pro
- Auto-start on Bluetooth connection event
