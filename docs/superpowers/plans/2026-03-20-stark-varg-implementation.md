# Stark Varg Battery Monitor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Hello World skeleton with a working Garmin Connect IQ app that connects to a Stark Varg e-motorcycle via BLE and displays battery state of charge on a Fenix 7 Pro Solar.

**Architecture:** `StarkVargApp` (entry point) creates a `BleManager` instance and passes it to `StarkVargView` and `StarkVargDelegate`. `BleManager` owns the BLE state machine and fires `WatchUi.requestUpdate()` on state changes. `StarkVargView` reads state from `BleManager` on every `onUpdate()` and draws directly to the canvas (no layout XML).

**Tech Stack:** Monkey C, Connect IQ SDK (latest), Garmin Fenix 7 Pro Solar, BluetoothLowEnergy module, Timer module. Build: `./compile.sh` (Docker). Spec: `docs/superpowers/specs/2026-03-19-stark-varg-watch-battery-design.md`.

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Modify | `manifest.xml` | entry point → StarkVargApp, BLE permission, fenix7pro only |
| Modify | `resources/strings/strings.xml` | Polish + English UI strings |
| Modify | `resources/layouts/layout.xml` | empty (drawing is done directly in View) |
| Create | `source/StarkVargApp.mc` | AppBase, BLE profile registration, wires view/delegate |
| Create | `source/BleManager.mc` | BLE delegate, scan/connect/notify state machine, 30s timer |
| Create | `source/StarkVargView.mc` | renders 5 states directly via dc |
| Create | `source/StarkVargDelegate.mc` | BACK = exit, ENTER = retry scan (in TIMEOUT only) |
| Delete | `source/HelloWorldApp.mc` | replaced by StarkVargApp.mc |
| Delete | `source/HelloWorldView.mc` | replaced by StarkVargView.mc |
| Delete | `source/HelloWorldDelegate.mc` | replaced by StarkVargDelegate.mc |

---

## Task 1: manifest.xml + strings.xml

**Files:**
- Modify: `manifest.xml`
- Modify: `resources/strings/strings.xml`
- Modify: `resources/layouts/layout.xml`

- [ ] **Step 1: Update manifest.xml**

Replace entire file with:

```xml
<?xml version="1.0"?>
<iq:manifest version="3" xmlns:iq="http://www.garmin.com/xml/connectiq">
  <iq:application entry="StarkVargApp" id="a3421feed289106a538cb9547ab12095"
    launcherIcon="@Drawables.LauncherIcon"
    minSdkVersion="3.2.0"
    name="@Strings.AppName"
    type="watch-app"
    version="1.0.0">
    <iq:products>
      <iq:product id="fenix7pro"/>
    </iq:products>
    <iq:permissions>
      <iq:uses-permission id="com.garmin.permission.BLUETOOTH_LOW_ENERGY"/>
    </iq:permissions>
    <iq:languages>
      <iq:language>pol</iq:language>
      <iq:language>eng</iq:language>
    </iq:languages>
  </iq:application>
</iq:manifest>
```

- [ ] **Step 2: Update strings.xml**

Replace entire file with:

```xml
<?xml version="1.0"?>
<strings>
  <string id="AppName">Stark Varg</string>
  <string id="Scanning">Szukam motocykla...</string>
  <string id="Disconnected">Rozłączono</string>
  <string id="Searching">Szukam...</string>
  <string id="NotFound">Nie znaleziono motocykla</string>
  <string id="RetryHint1">Naciśnij START,</string>
  <string id="RetryHint2">aby spróbować ponownie</string>
  <string id="BleUnavailable">BLE niedostępne</string>
</strings>
```

- [ ] **Step 3: Simplify layout.xml (drawing is done in code)**

Replace entire file with:

```xml
<?xml version="1.0"?>
<layouts>
  <layout id="MainLayout">
  </layout>
</layouts>
```

---

## Task 2: StarkVargApp.mc (entry point)

Registers the BLE GATT client profile (tells Connect IQ which UUIDs to track), creates `BleManager`, sets it as BLE delegate, starts scanning. View and delegate both receive a reference to `BleManager`.

**Note on UUIDs:** UUID constants are defined here as raw `Array<Number>` (big-endian bytes). Connect IQ's `registerProfile`, `getService`, and `getCharacteristic` accept byte arrays directly — confirmed by Connect IQ SDK docs for 128-bit UUIDs.

**Files:**
- Create: `source/StarkVargApp.mc`

- [ ] **Step 1: Create source/StarkVargApp.mc**

```monkey-c
import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.WatchUi;

// UUIDs — Stark Future 128-bit base (big-endian byte arrays)
// Battery Service:  00006000-5374-6172-4b20-467574757265
// Battery SOC char: 00006004-5374-6172-4b20-467574757265
const BATT_SERVICE_UUID = [0x00, 0x00, 0x60, 0x00,
                            0x53, 0x74, 0x61, 0x72,
                            0x4b, 0x20, 0x46, 0x75,
                            0x74, 0x75, 0x72, 0x65];

const BATT_SOC_CHAR_UUID = [0x00, 0x00, 0x60, 0x04,
                             0x53, 0x74, 0x61, 0x72,
                             0x4b, 0x20, 0x46, 0x75,
                             0x74, 0x75, 0x72, 0x65];

class StarkVargApp extends Application.AppBase {

    var bleManager as BleManager;

    function initialize() {
        AppBase.initialize();
        bleManager = new BleManager();
    }

    function onStart(state as Lang.Dictionary?) as Void {
        BluetoothLowEnergy.registerProfile({
            :uuid => BATT_SERVICE_UUID,
            :characteristics => [{
                :uuid => BATT_SOC_CHAR_UUID,
                :descriptors => [BluetoothLowEnergy.CCCD_UUID]
            }]
        });
        BluetoothLowEnergy.setDelegate(bleManager);
        bleManager.startScan();
    }

    function onStop(state as Lang.Dictionary?) as Void {
        bleManager.stop();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new StarkVargView(bleManager), new StarkVargDelegate(bleManager)];
    }
}

function getApp() as StarkVargApp {
    return Application.getApp() as StarkVargApp;
}
```

- [ ] **Step 2: Compile to verify syntax**

```bash
cd /home/piko/garmin_app
./compile.sh
```

Expected: compiler errors about missing `StarkVargView`, `StarkVargDelegate`, `BleManager` — fine. Those are the only missing pieces.

---

## Task 3: BleManager.mc (state machine + BLE)

Owns all BLE logic: scan → connect → enable notifications → parse SOC. Uses a 30-second `Timer` to detect scan timeout. Exposes `getState()`, `getSoc()`, `startScan()`, `stop()`.

**Scan API:** Uses `BluetoothLowEnergy.startScan()` / `BluetoothLowEnergy.stopScan()` per the Connect IQ spec. If the SDK version used in Docker does not have `startScan()`/`stopScan()` and instead uses `setScanState(SCAN_STATE_SCANNING/OFF)`, substitute those calls — the compile step will tell you immediately.

**BLE unavailable:** If `startScan()` throws (BLE not available on device), `BleManager` sets `STATE_BLE_UNAVAILABLE` and the view renders an error message before the user can exit.

**Timer callback note:** `_onScanTimeout` must NOT be declared `private` — `method(:_onScanTimeout)` requires the symbol to be accessible by the runtime timer callback mechanism.

**Files:**
- Create: `source/BleManager.mc`

- [ ] **Step 1: Create source/BleManager.mc**

```monkey-c
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Replace with your actual VIN before flashing to the watch
const STARK_VARG_VIN = "YOUR_VIN_HERE";

const SCAN_TIMEOUT_MS = 30000;

enum {
    STATE_SCANNING,
    STATE_CONNECTED,
    STATE_RECONNECTING,
    STATE_TIMEOUT,
    STATE_BLE_UNAVAILABLE
}

class BleManager extends BluetoothLowEnergy.BleDelegate {

    private var _state as Number;
    private var _soc as Number;
    private var _timer as Timer.Timer?;

    function initialize() {
        BleDelegate.initialize();
        _state = STATE_SCANNING;
        _soc = 0;
        _timer = null;
    }

    // ── public API ─────────────────────────────────────────────────────────

    function getState() as Number {
        return _state;
    }

    function getSoc() as Number {
        return _soc;
    }

    function startScan() as Void {
        _state = STATE_SCANNING;
        try {
            BluetoothLowEnergy.startScan();
        } catch (e instanceof Lang.Exception) {
            _state = STATE_BLE_UNAVAILABLE;
            WatchUi.requestUpdate();
            return;
        }
        _startTimer();
        WatchUi.requestUpdate();
    }

    function stop() as Void {
        _stopTimer();
        BluetoothLowEnergy.stopScan();
    }

    // ── BleDelegate callbacks ───────────────────────────────────────────────

    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        var result = scanResults.next();
        while (result != null) {
            var name = result.getDeviceName();
            if (name != null && name.equals(STARK_VARG_VIN)) {
                _stopTimer();
                BluetoothLowEnergy.stopScan();
                BluetoothLowEnergy.connect(result);
                return;
            }
            result = scanResults.next();
        }
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device,
                                     state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            _state = STATE_CONNECTED;
            _enableNotifications(device);
        } else {
            _state = STATE_RECONNECTING;
            startScan();
        }
        WatchUi.requestUpdate();
    }

    // Only parses if this is the SOC characteristic (guards against future multi-char setups)
    function onCharacteristicChanged(char as BluetoothLowEnergy.Characteristic,
                                     value as Lang.ByteArray) as Void {
        var charUuid = char.getUuid();
        if (charUuid != null && charUuid.equals(BATT_SOC_CHAR_UUID) && value.size() >= 2) {
            var soc = (value[0] & 0xFF) | ((value[1] & 0xFF) << 8); // uint16 little-endian
            _soc = soc > 100 ? 100 : soc;
            WatchUi.requestUpdate();
        }
    }

    // ── private ────────────────────────────────────────────────────────────

    private function _enableNotifications(device as BluetoothLowEnergy.Device) as Void {
        var service = device.getService(BATT_SERVICE_UUID);
        if (service == null) { return; }
        var characteristic = service.getCharacteristic(BATT_SOC_CHAR_UUID);
        if (characteristic == null) { return; }
        characteristic.setNotifications(true);
    }

    private function _startTimer() as Void {
        _stopTimer();
        _timer = new Timer.Timer();
        // NOTE: _onScanTimeout must NOT be private — Timer callback needs symbol access
        _timer.start(method(:_onScanTimeout), SCAN_TIMEOUT_MS, false);
    }

    private function _stopTimer() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    // NOT private — must be accessible as a Timer callback via method(:_onScanTimeout)
    function _onScanTimeout() as Void {
        BluetoothLowEnergy.stopScan();
        _state = STATE_TIMEOUT;
        WatchUi.requestUpdate();
    }
}
```

- [ ] **Step 2: Compile to verify**

```bash
cd /home/piko/garmin_app
./compile.sh
```

Expected: still errors about missing `StarkVargView` / `StarkVargDelegate` only. No errors from `BleManager.mc` or `StarkVargApp.mc`.

> **If compile fails with "startScan not found" / "stopScan not found":** The Docker SDK uses `setScanState`. Replace:
> - `BluetoothLowEnergy.startScan()` → `BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING)`
> - `BluetoothLowEnergy.stopScan()` → `BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF)`
>
> Then recompile.

---

## Task 4: StarkVargView.mc (renders 5 states)

Draws everything directly using `dc` — no layout XML. Fenix 7 Pro Solar: 260×260px round display.

**Files:**
- Create: `source/StarkVargView.mc`

- [ ] **Step 1: Create source/StarkVargView.mc**

```monkey-c
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class StarkVargView extends WatchUi.View {

    private var _bleManager as BleManager;

    function initialize(bleManager as BleManager) {
        View.initialize();
        _bleManager = bleManager;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // No layout file — all drawing is done in onUpdate
    }

    function onShow() as Void {
    }

    function onHide() as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        // Background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var state = _bleManager.getState();

        // BLE unavailable — error only, no title
        if (state == STATE_BLE_UNAVAILABLE) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_MEDIUM,
                        WatchUi.loadResource(Rez.Strings.BleUnavailable),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Title (all other states)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 30, Graphics.FONT_SMALL,
                    "STARK VARG", Graphics.TEXT_JUSTIFY_CENTER);

        if (state == STATE_SCANNING) {
            dc.drawText(cx, cy, Graphics.FONT_MEDIUM,
                        WatchUi.loadResource(Rez.Strings.Scanning),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        } else if (state == STATE_CONNECTED) {
            var soc = _bleManager.getSoc();
            var socStr = soc.toString() + "%";

            dc.drawText(cx, cy - 20, Graphics.FONT_NUMBER_HOT,
                        socStr,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var barX = 20;
            var barY = cy + 50;
            var barMaxW = w - 40;
            var barH = 14;

            // Bar background (dark grey)
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, barY, barMaxW, barH);

            // Bar fill — green > 20%, red at 20% or below
            var barColor = soc > 20 ? Graphics.COLOR_GREEN : Graphics.COLOR_RED;
            var fillW = barMaxW * soc / 100;
            if (fillW < 1) { fillW = 1; }
            dc.setColor(barColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, barY, fillW, barH);

        } else if (state == STATE_RECONNECTING) {
            dc.drawText(cx, cy - 15, Graphics.FONT_MEDIUM,
                        WatchUi.loadResource(Rez.Strings.Disconnected),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, cy + 15, Graphics.FONT_SMALL,
                        WatchUi.loadResource(Rez.Strings.Searching),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        } else { // STATE_TIMEOUT
            dc.drawText(cx, cy - 25, Graphics.FONT_SMALL,
                        WatchUi.loadResource(Rez.Strings.NotFound),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 15, Graphics.FONT_TINY,
                        WatchUi.loadResource(Rez.Strings.RetryHint1),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, cy + 35, Graphics.FONT_TINY,
                        WatchUi.loadResource(Rez.Strings.RetryHint2),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
```

- [ ] **Step 2: Compile to verify**

```bash
cd /home/piko/garmin_app
./compile.sh
```

Expected: only error about missing `StarkVargDelegate`.

---

## Task 5: StarkVargDelegate.mc (input handling)

BACK exits the app in all states. ENTER/SELECT retries scan only in `STATE_TIMEOUT`.

**Files:**
- Create: `source/StarkVargDelegate.mc`

- [ ] **Step 1: Create source/StarkVargDelegate.mc**

```monkey-c
import Toybox.Lang;
import Toybox.WatchUi;

class StarkVargDelegate extends WatchUi.BehaviorDelegate {

    private var _bleManager as BleManager;

    function initialize(bleManager as BleManager) {
        BehaviorDelegate.initialize();
        _bleManager = bleManager;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onSelect() as Boolean {
        if (_bleManager.getState() == STATE_TIMEOUT) {
            _bleManager.startScan();
        }
        return true;
    }
}
```

- [ ] **Step 2: Compile — should now succeed**

```bash
cd /home/piko/garmin_app
./compile.sh
```

Expected: `Gotowe! Plik: output/HelloWorld.prg` — clean compile, no errors.

---

## Task 6: Remove Hello World files + final clean compile

**Files:**
- Delete: `source/HelloWorldApp.mc`
- Delete: `source/HelloWorldView.mc`
- Delete: `source/HelloWorldDelegate.mc`

- [ ] **Step 1: Delete Hello World source files**

```bash
rm /home/piko/garmin_app/source/HelloWorldApp.mc
rm /home/piko/garmin_app/source/HelloWorldView.mc
rm /home/piko/garmin_app/source/HelloWorldDelegate.mc
```

- [ ] **Step 2: Final compile**

```bash
cd /home/piko/garmin_app
./compile.sh
```

Expected: `Gotowe! Plik: output/HelloWorld.prg`

- [ ] **Step 3: Verify output exists**

```bash
ls -lh /home/piko/garmin_app/output/HelloWorld.prg
```

Expected: file exists and is non-zero size.

---

## After completion

Before flashing to the watch, edit `source/BleManager.mc` and replace `"YOUR_VIN_HERE"` with the actual motorcycle VIN (e.g. `"UDUEX1AE3SA000588"`), then recompile.
