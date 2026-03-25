# StarkBattery DataField — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Garmin Connect IQ DataField (separate installable package from the watch-app) that displays Stark Varg motorcycle battery SOC during activities, fetching data via BLE in a background service every 5 minutes.

**Architecture:** Three source files in `source-df/` form a self-contained package. `StarkBatteryDFApp` (AppBase) registers the BLE profile and temporal event on startup. `StarkBatteryDFService` (ServiceDelegate) performs a one-shot BLE scan → connect → read on each temporal event and writes results to `Application.Storage`. `StarkBatteryDFField` (DataField) reads storage in `onUpdate()` and renders a two-row display: main SOC value + debug info row. Three variants built (fenix7pro, instinct3amoled50mm, instinct2). The existing watch-app (`source/`) is **not touched**.

**Tech Stack:** Monkey C, Connect IQ SDK ≥ 3.2.0, `Toybox.BluetoothLowEnergy`, `Toybox.Background`, `Application.Storage`. Build: `./compile.sh` (Docker, extends existing `entrypoint.sh`). Spec: `docs/superpowers/specs/2026-03-24-starkbattery-datafield-design.md`.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `manifest_df.xml` | DataField manifest — fenix7pro, App ID `c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6` |
| Create | `manifest_df_mp.xml` | DataField manifest — instinct3amoled50mm, App ID `d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7` |
| Create | `manifest_df_km.xml` | DataField manifest — instinct2, App ID `e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8` |
| Create | `monkey_df.jungle` | Build config — fenix7pro, sourcePath = source-df |
| Create | `monkey_df_mp.jungle` | Build config — instinct3amoled50mm, sourcePath = source-df |
| Create | `monkey_df_km.jungle` | Build config — instinct2, sourcePath = source-df |
| Create | `source-df/VinConfig.mc` | Placeholder — overwritten by entrypoint.sh at build time |
| Create | `source-df/StarkBatteryDFApp.mc` | AppBase: BLE profile registration + temporal event |
| Create | `source-df/StarkBatteryDFService.mc` | ServiceDelegate: BLE state machine + System.println debug + Storage writes |
| Create | `source-df/StarkBatteryDFField.mc` | DataField: two-row display (SOC + debug panel) |
| Modify | `entrypoint.sh` | Add 3 DF compile calls after existing watch-app builds |

---

## Task 1: Manifests and jungle files

**Files:**
- Create: `manifest_df.xml`
- Create: `manifest_df_mp.xml`
- Create: `manifest_df_km.xml`
- Create: `monkey_df.jungle`
- Create: `monkey_df_mp.jungle`
- Create: `monkey_df_km.jungle`

Each manifest declares `type="datafield"`, permissions `BluetoothLowEnergy` + `Background`, and registers `StarkBatteryDFService` as the `TemporalEvent` handler. App IDs are distinct from the watch-app IDs and from each other.

- [ ] **Step 1: Create manifest_df.xml (fenix7pro)**

```xml
<?xml version="1.0"?>
<iq:manifest version="3" xmlns:iq="http://www.garmin.com/xml/connectiq">
  <iq:application entry="StarkBatteryDFApp" id="c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6"
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
      <iq:handler id="TemporalEvent" type="timer" class="StarkBatteryDFService"/>
    </iq:background>
  </iq:application>
</iq:manifest>
```

- [ ] **Step 2: Create manifest_df_mp.xml (instinct3amoled50mm)**

Same as above, with:
- `id="d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7"`
- `<iq:product id="instinct3amoled50mm"/>`

```xml
<?xml version="1.0"?>
<iq:manifest version="3" xmlns:iq="http://www.garmin.com/xml/connectiq">
  <iq:application entry="StarkBatteryDFApp" id="d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7"
    minSdkVersion="3.2.0"
    name="StarkBattery Field"
    type="datafield"
    version="1.0.0">
    <iq:products><iq:product id="instinct3amoled50mm"/></iq:products>
    <iq:permissions>
      <iq:uses-permission id="BluetoothLowEnergy"/>
      <iq:uses-permission id="Background"/>
    </iq:permissions>
    <iq:languages>
      <iq:language>pol</iq:language>
      <iq:language>eng</iq:language>
    </iq:languages>
    <iq:background>
      <iq:handler id="TemporalEvent" type="timer" class="StarkBatteryDFService"/>
    </iq:background>
  </iq:application>
</iq:manifest>
```

- [ ] **Step 3: Create manifest_df_km.xml (instinct2)**

```xml
<?xml version="1.0"?>
<iq:manifest version="3" xmlns:iq="http://www.garmin.com/xml/connectiq">
  <iq:application entry="StarkBatteryDFApp" id="e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8"
    minSdkVersion="3.2.0"
    name="StarkBattery Field"
    type="datafield"
    version="1.0.0">
    <iq:products><iq:product id="instinct2"/></iq:products>
    <iq:permissions>
      <iq:uses-permission id="BluetoothLowEnergy"/>
      <iq:uses-permission id="Background"/>
    </iq:permissions>
    <iq:languages>
      <iq:language>pol</iq:language>
      <iq:language>eng</iq:language>
    </iq:languages>
    <iq:background>
      <iq:handler id="TemporalEvent" type="timer" class="StarkBatteryDFService"/>
    </iq:background>
  </iq:application>
</iq:manifest>
```

- [ ] **Step 4: Create monkey_df.jungle**

```
project.manifest = manifest_df.xml
base.sourcePath = source-df
```

- [ ] **Step 5: Create monkey_df_mp.jungle**

```
project.manifest = manifest_df_mp.xml
base.sourcePath = source-df
```

- [ ] **Step 6: Create monkey_df_km.jungle**

```
project.manifest = manifest_df_km.xml
base.sourcePath = source-df
```

---

## Task 2: source-df/VinConfig.mc (placeholder)

**Files:**
- Create: `source-df/VinConfig.mc`

This file is a placeholder only. `entrypoint.sh` overwrites it with the correct VIN before each DF compile, exactly as it does for `source/VinConfig.mc`. The placeholder prevents IDE errors but its value is never used in a real build.

- [ ] **Step 1: Create source-df/VinConfig.mc**

```monkey-c
const STARK_VARG_VIN = "PLACEHOLDER";
```

---

## Task 3: source-df/StarkBatteryDFApp.mc

**Files:**
- Create: `source-df/StarkBatteryDFApp.mc`

Registers the BLE GATT profile and temporal event for 5-minute background polls. Both calls are wrapped in try/catch because re-registration on subsequent app starts throws but is safe to ignore. UUID constants live in `StarkBatteryDFService.mc` (module scope, visible across the whole compilation unit) — `StarkBatteryDFApp.mc` uses them but does not define them.

- [ ] **Step 1: Create source-df/StarkBatteryDFApp.mc**

```monkey-c
import Toybox.Application;
import Toybox.Background;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// UUID string constants are defined in StarkBatteryDFService.mc
// (module scope — visible here too)

class StarkBatteryDFApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {
        System.println("[DF] onStart");

        // Register BLE profile — throws if already registered; safe to ignore
        try {
            System.println("[DF] registerProfile");
            BluetoothLowEnergy.registerProfile({
                :uuid => BluetoothLowEnergy.stringToUuid(DF_BATT_SERVICE_UUID_STR),
                :characteristics => [{
                    :uuid => BluetoothLowEnergy.stringToUuid(DF_BATT_SOC_CHAR_UUID_STR),
                    :descriptors => [BluetoothLowEnergy.CCCD_UUID]
                }]
            });
            System.println("[DF] registerProfile OK");
        } catch (e instanceof Lang.Exception) {
            System.println("[DF] registerProfile exception: " + e.getErrorMessage());
        }

        // Register temporal event — re-registration is expected and deduplicated by OS
        try {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
            System.println("[DF] registerForTemporalEvent 5min");
        } catch (e instanceof Lang.Exception) {
            System.println("[DF] registerForTemporalEvent exception: " + e.getErrorMessage());
        }
    }

    function onStop(state as Lang.Dictionary?) as Void {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new StarkBatteryDFField()];
    }

    function getServiceDelegate() as [Background.ServiceDelegate] {
        return [new StarkBatteryDFService()];
    }
}
```

---

## Task 4: source-df/StarkBatteryDFService.mc

**Files:**
- Create: `source-df/StarkBatteryDFService.mc`

The background service delegate. Called by the OS every 5 minutes via TemporalEvent. Performs one-shot BLE: scan (10s wall-clock timeout) → pair → connect → CCCD write → wait for notification → store SOC. Every state transition writes `df_state` and `df_last_event` to `Application.Storage` so the DataField can display live debug info.

**Important notes for implementation:**
- `Timer.Timer` is NOT available in background — scan timeout uses wall-clock (`Time.now().value()`)
- `BluetoothLowEnergy.setScanState()` is used (not `startScan()`/`stopScan()`) — this is the background-compatible API
- `BluetoothLowEnergy.pairDevice()` connects to a scanned result
- After storing SOC, call `setScanState(SCAN_STATE_OFF)` and `BluetoothLowEnergy.setDelegate(null)` to release BLE

- [ ] **Step 1: Create source-df/StarkBatteryDFService.mc**

```monkey-c
import Toybox.Application;
import Toybox.Background;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Time;

// BLE UUID constants — defined here, used by both Service and App
const DF_BATT_SERVICE_UUID_STR  = "00006000-5374-6172-4b20-467574757265";
const DF_BATT_SOC_CHAR_UUID_STR = "00006004-5374-6172-4b20-467574757265";

class StarkBatteryDFService extends Background.ServiceDelegate {

    private var _startTime as Number = 0;

    function initialize() {
        ServiceDelegate.initialize();
    }

    // ── Entry point — called by OS every 5 minutes ──────────────────────────

    function onTemporalEvent() as Void {
        _startTime = Time.now().value();
        System.println("[DF] onTemporalEvent start ts=" + _startTime);

        try {
            // Defensive teardown of any lingering prior session
            System.println("[DF] teardown: setScanState OFF");
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);

            BluetoothLowEnergy.setDelegate(self);
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
            System.println("[DF] scan started");

            _writeState("SCN", null);
        } catch (e instanceof Lang.Exception) {
            System.println("[DF] exception: " + e.getErrorMessage());
            _writeState("ERR", "ex");
        }
    }

    // ── BLE callbacks ────────────────────────────────────────────────────────

    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        var elapsed = Time.now().value() - _startTime;

        // Wall-clock scan timeout (Timer.Timer unavailable in background)
        if (elapsed >= 10) {
            System.println("[DF] scan timeout after " + elapsed + "s — stopping");
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            BluetoothLowEnergy.setDelegate(null);
            _writeState("TO", null);
            return;
        }

        var result = scanResults.next();
        while (result != null) {
            var name = result.getDeviceName();
            System.println("[DF] scanResult name=" + (name != null ? name : "null"));

            if (name != null && name.equals(STARK_VARG_VIN)) {
                System.println("[DF] VIN match — pairing");
                BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
                BluetoothLowEnergy.pairDevice(result);
                return;
            } else {
                System.println("[DF] skip name=" + (name != null ? name : "null"));
            }
            result = scanResults.next();
        }
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device,
                                     state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            System.println("[DF] connected");
            _writeState("CON", null);
            _enableNotifications(device);
        } else {
            System.println("[DF] disconnected before notification — exit");
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            BluetoothLowEnergy.setDelegate(null);
            _writeState("DIS", "dis");
        }
    }

    function onCharacteristicChanged(char as BluetoothLowEnergy.Characteristic,
                                     value as Lang.ByteArray) as Void {
        System.println("[DF] notification raw=[" + value[0] + "," + value[1] + "]");

        var soc = (value[0] & 0xFF) | ((value[1] & 0xFF) << 8);
        if (soc > 100) { soc = 100; }

        var now = Time.now().value();
        Application.Storage.setValue("df_soc", soc);
        Application.Storage.setValue("df_soc_ts", now);
        System.println("[DF] soc=" + soc + " ts=" + now);

        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        BluetoothLowEnergy.setDelegate(null);
        // "CON" here means "last known state was connected + SOC read succeeded".
        // The spec example "CON · 3m · ok" confirms this is the correct terminal state
        // after a successful read — it is historical state, not a live-connection indicator.
        _writeState("CON", "ok");
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private function _enableNotifications(device as BluetoothLowEnergy.Device) as Void {
        var serviceUuid = BluetoothLowEnergy.stringToUuid(DF_BATT_SERVICE_UUID_STR);
        var charUuid    = BluetoothLowEnergy.stringToUuid(DF_BATT_SOC_CHAR_UUID_STR);

        var service = device.getService(serviceUuid);
        System.println("[DF] service=" + (service != null ? "found" : "NULL"));
        if (service == null) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            BluetoothLowEnergy.setDelegate(null);
            _writeState("ERR", "no-svc");
            return;
        }

        var characteristic = service.getCharacteristic(charUuid);
        System.println("[DF] char=" + (characteristic != null ? "found" : "NULL"));
        if (characteristic == null) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            BluetoothLowEnergy.setDelegate(null);
            _writeState("ERR", "no-chr");
            return;
        }

        var cccd = characteristic.getDescriptor(BluetoothLowEnergy.CCCD_UUID);
        System.println("[DF] cccd=" + (cccd != null ? "found" : "NULL"));
        if (cccd == null) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            BluetoothLowEnergy.setDelegate(null);
            _writeState("ERR", "no-ccd");
            return;
        }

        cccd.requestWrite([0x01, 0x00]b);
        System.println("[DF] CCCD write sent");
    }

    // Writes df_state always; writes df_last_event only when non-null
    private function _writeState(state as Lang.String, event as Lang.String?) as Void {
        Application.Storage.setValue("df_state", state);
        if (event != null) {
            Application.Storage.setValue("df_last_event", event);
        }
    }
}
```

---

## Task 5: source-df/StarkBatteryDFField.mc

**Files:**
- Create: `source-df/StarkBatteryDFField.mc`

Extends `WatchUi.DataField` (not `SimpleDataField`) for full drawing control. `compute()` reads storage ~1/s and stores values as instance variables; `onUpdate()` draws from those variables. This matches the spec's pseudocode which shows logic in `compute()`. Logs to `System.println` only on value change (`_lastDisplay` flag, nullable) and once on null SOC (`_socWasNull` flag). Debug row (tiny font, grey, bottom 40%) is skipped if field height < 40px.

- [ ] **Step 1: Create source-df/StarkBatteryDFField.mc**

```monkey-c
import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class StarkBatteryDFField extends WatchUi.DataField {

    // Populated by compute(), rendered by onUpdate()
    private var _displayStr as Lang.String  = "--";
    private var _debugStr   as Lang.String  = "--- · -- · ---";

    // Log-once flags
    private var _lastDisplay as Lang.String? = null;
    private var _socWasNull  as Lang.Boolean = false;

    function initialize() {
        DataField.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    // compute() is called ~1/s by the system. Reads storage, builds display strings,
    // logs on change. Return value is unused (onUpdate() does all rendering).
    function compute(info as Activity.Info) as Lang.Object or Null {
        var soc     = Application.Storage.getValue("df_soc")       as Lang.Number?;
        var socTs   = Application.Storage.getValue("df_soc_ts")    as Lang.Number?;
        var state   = Application.Storage.getValue("df_state")     as Lang.String?;
        var lastEvt = Application.Storage.getValue("df_last_event") as Lang.String?;

        // ── Main display string ───────────────────────────────────────────────
        if (soc == null || socTs == null) {
            _displayStr = "--";
            if (!_socWasNull) {
                System.println("[DF] compute soc=null");
                _socWasNull = true;
            }
        } else {
            _socWasNull = false;
            var age = Time.now().value() - socTs;
            if (age > 15 * 60) {
                _displayStr = "?" + soc.toString() + "%";
            } else {
                _displayStr = soc.toString() + "%";
            }
        }

        // Log only on change
        if (_lastDisplay == null || !_displayStr.equals(_lastDisplay)) {
            System.println("[DF] compute display=" + _displayStr);
            _lastDisplay = _displayStr;
        }

        // ── Debug string ──────────────────────────────────────────────────────
        var ageStr as Lang.String;
        if (socTs == null) {
            ageStr = "--";
        } else {
            var ageS = Time.now().value() - socTs;
            ageStr = (ageS < 60) ? ageS.toString() + "s" : (ageS / 60).toString() + "m";
        }
        var stateStr = (state   != null) ? state   : "---";
        var evtStr   = (lastEvt != null) ? lastEvt : "---";
        _debugStr = stateStr + " · " + ageStr + " · " + evtStr;

        return null;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // ── Main value (top 60%) ──────────────────────────────────────────────
        var mainY = h * 3 / 10;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, mainY, Graphics.FONT_NUMBER_MEDIUM, _displayStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Debug row (bottom 40%) — skip if field too small ──────────────────
        if (h < 40) { return; }

        var debugY = h * 8 / 10;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, debugY, Graphics.FONT_SYSTEM_XTINY, _debugStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
```

---

## Task 6: Extend entrypoint.sh + compile all variants

**Files:**
- Modify: `entrypoint.sh`

Add three DF build calls after the existing watch-app builds. Pattern is identical to existing builds: write VinConfig.mc to `source-df/`, call `monkeyc` with the DF jungle file and correct device ID.

- [ ] **Step 1: Append DF build calls to entrypoint.sh**

After the last existing `monkeyc` call (line ending `--warn` for StarkBattery_MP), append:

```bash
echo 'const STARK_VARG_VIN = "UDUEX1AE8SA005799";' > /project/source-df/VinConfig.mc
monkeyc \
    -o "$OUTPUT_DIR/StarkBatteryDF.prg" \
    -f /project/monkey_df.jungle \
    -y "$KEY_FILE" \
    -d "fenix7pro" \
    --override-devices-json "$DEVICES_DIR" \
    --warn

echo 'const STARK_VARG_VIN = "UDUEX1AE7SA005907";' > /project/source-df/VinConfig.mc
monkeyc \
    -o "$OUTPUT_DIR/StarkBatteryDF_KM.prg" \
    -f /project/monkey_df_km.jungle \
    -y "$KEY_FILE" \
    -d "instinct2" \
    --override-devices-json "$DEVICES_DIR" \
    --warn

echo 'const STARK_VARG_VIN = "UDUEX1AE9SA003348";' > /project/source-df/VinConfig.mc
monkeyc \
    -o "$OUTPUT_DIR/StarkBatteryDF_MP.prg" \
    -f /project/monkey_df_mp.jungle \
    -y "$KEY_FILE" \
    -d "instinct3amoled50mm" \
    --override-devices-json "$DEVICES_DIR" \
    --warn
```

Also update the final `echo` summary block to include the new files:

```bash
echo "  output/StarkBatteryDF.prg    (VIN: UDUEX1AE8SA005799)"
echo "  output/StarkBatteryDF_KM.prg (VIN: UDUEX1AE7SA005907)"
echo "  output/StarkBatteryDF_MP.prg (VIN: UDUEX1AE9SA003348)"
```

- [ ] **Step 2: Run full compile**

```bash
cd /home/piko/garmin_app
./compile.sh
```

Expected: all 6 `.prg` files produced, no errors. Warnings are OK.

If compile fails with a `monkeyc` error, read the error carefully:
- `"Symbol not found"` → check class/function names for typos
- `"Cannot find symbol CCCD_UUID"` → use `BluetoothLowEnergy.CCCD_UUID` (not a string)
- `"setScanState not found"` → check SDK version; try `startScan()`/`stopScan()` instead
- `"stringToUuid not found"` → SDK too old; use byte arrays instead (see watch-app `StarkVargApp.mc` for the pattern)
- Syntax errors → fix in the indicated file and line

- [ ] **Step 3: Verify output files exist**

```bash
ls -lh /home/piko/garmin_app/output/
```

Expected: 6 files — `StarkBattery.prg`, `StarkBattery_KM.prg`, `StarkBattery_MP.prg`, `StarkBatteryDF.prg`, `StarkBatteryDF_KM.prg`, `StarkBatteryDF_MP.prg` — all non-zero size.

- [ ] **Step 4: Commit**

```bash
cd /home/piko/garmin_app
git add manifest_df.xml manifest_df_mp.xml manifest_df_km.xml
git add monkey_df.jungle monkey_df_mp.jungle monkey_df_km.jungle
git add source-df/VinConfig.mc source-df/StarkBatteryDFApp.mc
git add source-df/StarkBatteryDFService.mc source-df/StarkBatteryDFField.mc
git add entrypoint.sh
git commit -m "feat: add StarkBattery DataField (iteration 1, debug build)"
```
