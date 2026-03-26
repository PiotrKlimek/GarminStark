import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// STARK_VARG_VIN is defined per-variant in source-vin-default/ or source-vin-km/

const SCAN_TIMEOUT_MS = 30000;

// UUID strings — hyphenated format required by stringToUuid()
const BATT_SERVICE_UUID_STR  = "00006000-5374-6172-4b20-467574757265";
const BATT_SOC_CHAR_UUID_STR = "00006004-5374-6172-4b20-467574757265";
const STATUS_SERVICE_UUID_STR   = "00001000-5374-6172-4b20-467574757265";
const STATUS_BIKE_CHAR_UUID_STR = "00001002-5374-6172-4b20-467574757265";

const SPLASH_DURATION_MS = 2000;

enum {
    STATE_SPLASH,
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
    private var _splashTimer as Timer.Timer?;
    private var _pendingError as Number;
    private var _powerMode as Number?;
    private var _bleDebug as String;
    private var _serviceUuid as BluetoothLowEnergy.Uuid;
    private var _charUuid as BluetoothLowEnergy.Uuid;
    // Pre-computed toString() results — used for UUID dispatch in onCharacteristicChanged.
    // Comparing toString() to toString() avoids format mismatches (case, hyphens) that
    // occur when comparing toString() output directly to our string constants.
    private var _socCharUuidStr as String;
    private var _bikeStatusCharUuidStr as String;

    function initialize() {
        BleDelegate.initialize();
        _state = STATE_SPLASH;
        _soc = 0;
        _timer = null;
        _splashTimer = null;
        _pendingError = 0;
        _powerMode = null;
        _bleDebug = "init";
        _serviceUuid = BluetoothLowEnergy.stringToUuid(BATT_SERVICE_UUID_STR);
        _charUuid    = BluetoothLowEnergy.stringToUuid(BATT_SOC_CHAR_UUID_STR);
        _socCharUuidStr        = BluetoothLowEnergy.stringToUuid(BATT_SOC_CHAR_UUID_STR).toString();
        _bikeStatusCharUuidStr = BluetoothLowEnergy.stringToUuid(STATUS_BIKE_CHAR_UUID_STR).toString();
        System.println("[BLE] socCharUuidStr=" + _socCharUuidStr);
        System.println("[BLE] bikeStatusCharUuidStr=" + _bikeStatusCharUuidStr);
    }

    // ── public API ─────────────────────────────────────────────────────────

    function getState() as Number {
        return _state;
    }

    function getSoc() as Number {
        return _soc;
    }

    function getPowerMode() as Number? {
        return _powerMode;
    }

    function getBleDebug() as String {
        return _bleDebug;
    }

    function startSplash() as Void {
        _splashTimer = new Timer.Timer();
        _splashTimer.start(method(:_onSplashDone), SPLASH_DURATION_MS, false);
        WatchUi.requestUpdate();
    }

    function startScan() as Void {
        _state = STATE_SCANNING;
        _doScan();
    }

    function _onSplashDone() as Void {
        _splashTimer = null;
        if (_pendingError != 0) {
            _state = STATE_BLE_UNAVAILABLE;
            _soc = _pendingError;
        } else {
            startScan();
        }
        WatchUi.requestUpdate();
    }

    function setBleUnavailable() as Void {
        _state = STATE_BLE_UNAVAILABLE;
        _soc = 0;
        WatchUi.requestUpdate();
    }

    function setDebugState(code as Number) as Void {
        _pendingError = code;
    }

    function stop() as Void {
        _stopTimer();
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        } catch (e instanceof Lang.Exception) {
            // BLE unavailable — nothing to stop
        }
    }

    // ── test mode (no motorcycle needed) ───────────────────────────────────

    // Call from delegate onMenu() to simulate a connected motorcycle.
    // Each call cycles: CONNECTED(75%) → CONNECTED(20%) → RECONNECTING → TIMEOUT → back to scan.
    function simulateNextState() as Void {
        _stopTimer();
        try { BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF); } catch (e instanceof Lang.Exception) {}
        if (_state != STATE_CONNECTED) {
            _state = STATE_CONNECTED;
            _soc = 75;
            _powerMode = 3;
        } else if (_soc == 75) {
            _soc = 20; // test red bar
        } else if (_soc == 20) {
            _state = STATE_RECONNECTING;
            _powerMode = null;
        } else {
            _state = STATE_TIMEOUT;
        }
        WatchUi.requestUpdate();
    }

    // ── BleDelegate callbacks ───────────────────────────────────────────────

    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        try {
            var result = scanResults.next() as BluetoothLowEnergy.ScanResult?;
            while (result != null) {
                var name = result.getDeviceName();
                if (name != null && name.equals(STARK_VARG_VIN)) {
                    System.println("[BLE] VIN match — pairing: " + name);
                    _stopTimer();
                    BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
                    BluetoothLowEnergy.pairDevice(result);
                    return;
                }
                result = scanResults.next() as BluetoothLowEnergy.ScanResult?;
            }
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] ERR:11 exception in onScanResults: " + e.getErrorMessage());
            _state = STATE_BLE_UNAVAILABLE;
            _soc = 11; // ERR:11 = crash in onScanResults
            WatchUi.requestUpdate();
        }
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device,
                                     state as BluetoothLowEnergy.ConnectionState) as Void {
        try {
            if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
                System.println("[BLE] connected — enabling notifications");
                _state = STATE_CONNECTED;
                _bleDebug = "connecting...";
                _enableNotifications(device);
            } else {
                System.println("[BLE] disconnected — reconnecting");
                _state = STATE_RECONNECTING;
                _powerMode = null;
                _bleDebug = "disconnected";
                WatchUi.requestUpdate();
                _doScan();
                return;
            }
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] ERR:22 exception in onConnectedStateChanged: " + e.getErrorMessage());
            _state = STATE_BLE_UNAVAILABLE;
            _soc = 22; // ERR:22 = crash in onConnectedStateChanged
        }
        WatchUi.requestUpdate();
    }

    function onCharacteristicChanged(char as BluetoothLowEnergy.Characteristic,
                                     value as Lang.ByteArray) as Void {
        try {
            var uuidStr = char.getUuid().toString();
            if (uuidStr.equals(_socCharUuidStr)) {
                if (value.size() >= 1) {
                    var soc = value[0] & 0xFF;
                    if (value.size() >= 2) {
                        soc = soc | ((value[1] & 0xFF) << 8);
                    }
                    _soc = soc > 100 ? 100 : soc;
                    System.println("[BLE] SOC=" + _soc + "%");
                }
            } else if (uuidStr.equals(_bikeStatusCharUuidStr)) {
                if (value.size() >= 1) {
                    var pm = value[0] & 0x0F;
                    System.println("[BLE] BikeStatus byte0=0x" + value[0].format("%02X") + " nibble=" + pm);
                    _powerMode = (pm >= 1 && pm <= 5) ? pm : null;
                    if (_powerMode != null) {
                        _bleDebug = "S:ok P:ok M" + _powerMode.toString();
                        System.println("[BLE] powerMode=" + _powerMode.toString());
                    } else {
                        _bleDebug = "S:ok P:OOR:" + pm.toString();
                        System.println("[BLE] powerMode=null (out of range 1-5, raw=" + pm.toString() + ")");
                    }
                } else {
                    _bleDebug = "S:ok P:empty";
                    System.println("[BLE] BikeStatus notification empty — ignored");
                }
            } else {
                System.println("[BLE] unknown char UUID: " + uuidStr);
            }
            WatchUi.requestUpdate();
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] ERR:33 exception in onCharacteristicChanged: " + e.getErrorMessage());
            _state = STATE_BLE_UNAVAILABLE;
            _soc = 33; // ERR:33 = crash in onCharacteristicChanged
            WatchUi.requestUpdate();
        }
    }

    // ── private ────────────────────────────────────────────────────────────

    // Enable notifications by writing 0x0001 to the CCCD descriptor.
    // UUIDs are passed as hyphenated strings — Connect IQ requires String format
    // for 128-bit UUIDs; ByteArray casts are rejected at runtime.
    private function _enableNotifications(device as BluetoothLowEnergy.Device) as Void {
        // ── Battery Service — SOC ────────────────────────────────────────────────
        var service;
        try {
            service = device.getService(_serviceUuid);
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] exception getting BattService: " + e.getErrorMessage());
            _bleDebug = "S:ex-svc";
            WatchUi.requestUpdate(); return;
        }
        if (service == null) {
            System.println("[BLE] BattService not found");
            _bleDebug = "S:no-svc";
            WatchUi.requestUpdate(); return;
        }
        System.println("[BLE] BattService found");

        var characteristic;
        try {
            characteristic = service.getCharacteristic(_charUuid);
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] exception getting SOC char: " + e.getErrorMessage());
            _bleDebug = "S:ex-chr";
            WatchUi.requestUpdate(); return;
        }
        if (characteristic == null) {
            System.println("[BLE] SOC char not found");
            _bleDebug = "S:no-chr";
            WatchUi.requestUpdate(); return;
        }
        System.println("[BLE] SOC char found");

        var cccd;
        try {
            cccd = characteristic.getDescriptor(BluetoothLowEnergy.cccdUuid());
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] exception getting SOC CCCD: " + e.getErrorMessage());
            _bleDebug = "S:ex-ccd";
            WatchUi.requestUpdate(); return;
        }
        if (cccd == null) {
            System.println("[BLE] SOC CCCD not found");
            _bleDebug = "S:no-ccd";
            WatchUi.requestUpdate(); return;
        }
        System.println("[BLE] SOC CCCD found — writing");

        try {
            cccd.requestWrite([0x01, 0x00]b);
            System.println("[BLE] SOC CCCD write sent");
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] exception writing SOC CCCD: " + e.getErrorMessage());
            _bleDebug = "S:ex-sub";
            WatchUi.requestUpdate();
        }

        // ── Status Service — Bike Status (power mode) ────────────────────────────
        var statusService;
        try {
            statusService = device.getService(
                BluetoothLowEnergy.stringToUuid(STATUS_SERVICE_UUID_STR));
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] exception getting StatusService: " + e.getErrorMessage());
            _bleDebug = "S:ok P:ex-svc";
            WatchUi.requestUpdate(); return;
        }
        if (statusService == null) {
            System.println("[BLE] StatusService not found — power mode unavailable");
            _bleDebug = "S:ok P:no-svc";
            WatchUi.requestUpdate(); return;
        }
        System.println("[BLE] StatusService found");

        var bikeStatusChar;
        try {
            bikeStatusChar = statusService.getCharacteristic(
                BluetoothLowEnergy.stringToUuid(STATUS_BIKE_CHAR_UUID_STR));
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] exception getting BikeStatus char: " + e.getErrorMessage());
            _bleDebug = "S:ok P:ex-chr";
            WatchUi.requestUpdate(); return;
        }
        if (bikeStatusChar == null) {
            System.println("[BLE] BikeStatus char not found — power mode unavailable");
            _bleDebug = "S:ok P:no-chr";
            WatchUi.requestUpdate(); return;
        }
        System.println("[BLE] BikeStatus char found");

        var statusCccd;
        try {
            statusCccd = bikeStatusChar.getDescriptor(BluetoothLowEnergy.cccdUuid());
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] exception getting BikeStatus CCCD: " + e.getErrorMessage());
            _bleDebug = "S:ok P:ex-ccd";
            WatchUi.requestUpdate(); return;
        }
        if (statusCccd == null) {
            System.println("[BLE] BikeStatus CCCD not found — power mode unavailable");
            _bleDebug = "S:ok P:no-ccd";
            WatchUi.requestUpdate(); return;
        }
        System.println("[BLE] BikeStatus CCCD found — writing");

        try {
            statusCccd.requestWrite([0x01, 0x00]b);
            _bleDebug = "S:ok P:sub...";
            System.println("[BLE] BikeStatus CCCD write sent — power mode notifications enabled");
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] exception writing BikeStatus CCCD: " + e.getErrorMessage());
            _bleDebug = "S:ok P:ex-sub";
            WatchUi.requestUpdate();
        }
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
        System.println("[BLE] scan timeout after 30s");
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        } catch (e instanceof Lang.Exception) {
            // BLE unavailable — nothing to stop
        }
        _state = STATE_TIMEOUT;
        WatchUi.requestUpdate();
    }

    private function _doScan() as Void {
        System.println("[BLE] starting scan for VIN: " + STARK_VARG_VIN);
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        } catch (e instanceof Lang.Exception) {
            System.println("[BLE] scan failed — BLE unavailable: " + e.getErrorMessage());
            _state = STATE_BLE_UNAVAILABLE;
            WatchUi.requestUpdate();
            return;
        }
        _startTimer();
        WatchUi.requestUpdate();
    }
}
