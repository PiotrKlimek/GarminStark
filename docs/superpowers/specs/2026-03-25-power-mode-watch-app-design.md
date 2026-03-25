# Power Mode — Watch App (iteration 1)

**Goal:** Display the Stark Varg power mode (1–5) alongside battery SOC on the connected screen of the watch app (`source/`). Power mode is read from the Bike Status BLE characteristic via notifications, in the same persistent connection session as SOC.

**Scope:** Watch app only (`source/`). DataField (`source-df/`) is not touched in this iteration.

---

## BLE Protocol

**New BLE service and characteristic:**

| | UUID string |
|---|---|
| Status Service | `00001000-5374-6172-4b20-467574757265` |
| Bike Status characteristic | `00001002-5374-6172-4b20-467574757265` |

The characteristic is notification-based (CCCD subscription required, same pattern as SOC). The power mode value sits in the lower nibble of byte 0 of the notification payload:

```
powerMode = value[0] & 0x0F   // expected: 1–5
```

Values outside 1–5 are treated as unknown — `_powerMode` is set to `null`.

---

## Architecture

Two source files change (`BleManager.mc`, `StarkVargView.mc`) plus `StarkVargApp.mc` for profile registration. Manifests are unchanged — the existing `BluetoothLowEnergy` permission covers all BLE services; no `<iq:ble-profiles>` section exists or is needed.

### StarkVargApp.mc

Add a second `registerProfile()` call for the Status Service after the existing Battery Service call. Each call is in its own `try/catch` (re-registration on subsequent app starts throws but is safe to ignore):

```monkey-c
try {
    BluetoothLowEnergy.registerProfile({
        :uuid => BluetoothLowEnergy.stringToUuid(STATUS_SERVICE_UUID_STR),
        :characteristics => [{
            :uuid => BluetoothLowEnergy.stringToUuid(STATUS_BIKE_CHAR_UUID_STR),
            :descriptors => [BluetoothLowEnergy.cccdUuid()]
        }]
    });
} catch (e instanceof Lang.Exception) {
    // Already registered — continue
}
```

### BleManager.mc

**New module-scope constants** (outside the class body — module-scope `const` is visible across the compilation unit including `StarkVargApp.mc`; do not place inside the class):

```monkey-c
const STATUS_SERVICE_UUID_STR   = "00001000-5374-6172-4b20-467574757265";
const STATUS_BIKE_CHAR_UUID_STR = "00001002-5374-6172-4b20-467574757265";
```

**New instance field:**
- `_powerMode as Number?` — initialized to `null` in `initialize()` (explicit, matching the style of existing fields); reset to `null` on disconnect.

**`getPowerMode() as Number?`** — new public accessor.

**`_enableNotifications()`** — after the existing SOC CCCD write, add an identical block for the Status Service → Bike Status characteristic. Call `BluetoothLowEnergy.stringToUuid()` inline (do not add new instance fields — module-scope constants are sufficient). Failure to find the Status service or characteristic is silent; SOC notifications are unaffected.

**`onCharacteristicChanged()` — REQUIRED BEHAVIOUR CHANGE (not just an addition):**

The existing implementation unconditionally parses every notification as SOC. This must change to dispatch on characteristic UUID. Without the dispatch, Bike Status notifications corrupt `_soc` with the power-mode byte value (e.g., mode 3 → `_soc = 3`).

`BluetoothLowEnergy.Uuid.equals()` performs reference equality in Monkey C and cannot be used for value comparison. Use `.toString().equals()`:

```monkey-c
function onCharacteristicChanged(char as BluetoothLowEnergy.Characteristic,
                                 value as Lang.ByteArray) as Void {
    try {
        var uuidStr = char.getUuid().toString();
        if (uuidStr.equals(BATT_SOC_CHAR_UUID_STR)) {
            if (value.size() >= 1) {
                var soc = value[0] & 0xFF;
                if (value.size() >= 2) { soc = soc | ((value[1] & 0xFF) << 8); }
                _soc = soc > 100 ? 100 : soc;
            }
        } else if (uuidStr.equals(STATUS_BIKE_CHAR_UUID_STR)) {
            if (value.size() >= 1) {
                var pm = value[0] & 0x0F;
                _powerMode = (pm >= 1 && pm <= 5) ? pm : null;
            }
        }
        WatchUi.requestUpdate();
    } catch (e instanceof Lang.Exception) {
        _state = STATE_BLE_UNAVAILABLE;
        _soc = 33;
        WatchUi.requestUpdate();
    }
}
```

**`onConnectedStateChanged()`** — reset `_powerMode = null` in the branch that sets `_state = STATE_RECONNECTING` (i.e., on disconnect). Do not place this in `_doScan()`, which is also called on initial scan before any connection has been made.

**`simulateNextState()`:**
- CONNECTED (first call, `_soc = 75`): also set `_powerMode = 3`
- CONNECTED (second call, `_soc = 20`): leave `_powerMode` unchanged
- RECONNECTING transition: set `_powerMode = null`
- TIMEOUT branch: pre-existing dead branch in the simulation cycle — no change needed

### StarkVargView.mc

**STATE_CONNECTED layout.** Layout is validated for Fenix 7 Pro (240×240px, `cy=120`). KM/MP builds (Instinct 2, 176px) are currently disabled; layout for those devices will be revisited when re-enabled.

| Element | Y position | Font |
|---|---|---|
| SOC text | `cy - 30` | `FONT_NUMBER_HOT` |
| Bar top | `cy + 35` | — height 14px |
| Mode text | `cy + 63` | `FONT_MEDIUM`, `COLOR_LT_GRAY` |

On Fenix 7 Pro: SOC baseline y=90, `FONT_NUMBER_HOT` ~60px tall → bottom ~150px. Bar top y=155, bottom y=169. Mode text y=183, `FONT_MEDIUM` ~22px → bottom ~205px. All within 240px.

`_powerMode == null` → display `M?`. `_powerMode` in range 1–5 → display `M1`…`M5`.

All other states (splash, scanning, reconnecting, timeout, BLE unavailable) are unchanged.

---

## Error handling

- Status service not found after connect → silent, `_powerMode` stays `null`, view shows `M?`
- Notification with unexpected size or out-of-range nibble → `_powerMode = null`
- `onCharacteristicChanged` exception → ERR:33 path covers all characteristics

---

## Out of scope

- DataField power mode display (future iteration)
- Writing power mode (read-only)
- Mapping mode numbers to names (1–5 numeric display is sufficient for now)
- Other Bike Status fields (indicators, faults, charging state)
- Instinct 2 / Instinct 3 AMOLED layout (builds currently disabled)
