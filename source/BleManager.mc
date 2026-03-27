import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// STARK_VARG_VIN is defined per-variant in source-vin-default/ or source-vin-km/

const SCAN_TIMEOUT_MS = 30000;

// UUID strings — hyphenated format required by stringToUuid()
const BATT_SERVICE_UUID_STR  = "00006000-5374-6172-4b20-467574757265";
const BATT_SOC_CHAR_UUID_STR = "00006004-5374-6172-4b20-467574757265";
const LIVE_SERVICE_UUID_STR  = "00002000-5374-6172-4b20-467574757265";
const LIVE_MAP_CHAR_UUID_STR = "00002004-5374-6172-4b20-467574757265";

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
    private var _serviceUuid as BluetoothLowEnergy.Uuid;
    private var _charUuid as BluetoothLowEnergy.Uuid;

    function initialize() {
        BleDelegate.initialize();
        _state = STATE_SPLASH;
        _soc = 0;
        _timer = null;
        _splashTimer = null;
        _pendingError = 0;
        _powerMode = null;
        _serviceUuid = BluetoothLowEnergy.stringToUuid(BATT_SERVICE_UUID_STR);
        _charUuid    = BluetoothLowEnergy.stringToUuid(BATT_SOC_CHAR_UUID_STR);
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
                    _stopTimer();
                    BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
                    BluetoothLowEnergy.pairDevice(result);
                    return;
                }
                result = scanResults.next() as BluetoothLowEnergy.ScanResult?;
            }
        } catch (e instanceof Lang.Exception) {
            _state = STATE_BLE_UNAVAILABLE;
            _soc = 11; // ERR:11 = crash in onScanResults
            WatchUi.requestUpdate();
        }
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device,
                                     state as BluetoothLowEnergy.ConnectionState) as Void {
        try {
            if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
                _state = STATE_CONNECTED;
                _enableNotifications(device);
            } else {
                _state = STATE_RECONNECTING;
                _powerMode = null;
                WatchUi.requestUpdate();
                _doScan();
                return;
            }
        } catch (e instanceof Lang.Exception) {
            _state = STATE_BLE_UNAVAILABLE;
            _soc = 22; // ERR:22 = crash in onConnectedStateChanged
        }
        WatchUi.requestUpdate();
    }

    function onCharacteristicChanged(char as BluetoothLowEnergy.Characteristic,
                                     value as Lang.ByteArray) as Void {
        try {
            // UUID dispatch: compare toString() outputs to avoid case/format mismatches.
            // Uuid.equals() is reference equality in Monkey C — not suitable for value comparison.
            var uuidStr = char.getUuid().toString();
            var socUuidStr = BluetoothLowEnergy.stringToUuid(BATT_SOC_CHAR_UUID_STR).toString();
            if (uuidStr.equals(socUuidStr)) {
                if (value.size() >= 1) {
                    var soc = value[0] & 0xFF;
                    if (value.size() >= 2) {
                        soc = soc | ((value[1] & 0xFF) << 8);
                    }
                    _soc = soc > 100 ? 100 : soc;
                }
            } else {
                // LiveMap characteristic — single byte, power mode 1-5
                if (value.size() >= 1) {
                    var pm = value[0] & 0xFF;
                    _powerMode = (pm >= 1 && pm <= 5) ? pm : null;
                }
            }
            WatchUi.requestUpdate();
        } catch (e instanceof Lang.Exception) {
            _state = STATE_BLE_UNAVAILABLE;
            _soc = 33; // ERR:33 = crash in onCharacteristicChanged
            WatchUi.requestUpdate();
        }
    }

    // ── private ────────────────────────────────────────────────────────────

    // Enable notifications by writing 0x0001 to the CCCD descriptor.
    private function _enableNotifications(device as BluetoothLowEnergy.Device) as Void {
        // ── Battery Service — SOC ────────────────────────────────────────────────
        var service;
        try {
            service = device.getService(_serviceUuid);
        } catch (e instanceof Lang.Exception) {
            WatchUi.requestUpdate(); return;
        }
        if (service == null) { WatchUi.requestUpdate(); return; }

        var characteristic;
        try {
            characteristic = service.getCharacteristic(_charUuid);
        } catch (e instanceof Lang.Exception) {
            WatchUi.requestUpdate(); return;
        }
        if (characteristic == null) { WatchUi.requestUpdate(); return; }

        var cccd;
        try {
            cccd = characteristic.getDescriptor(BluetoothLowEnergy.cccdUuid());
        } catch (e instanceof Lang.Exception) {
            WatchUi.requestUpdate(); return;
        }
        if (cccd == null) { WatchUi.requestUpdate(); return; }

        try {
            cccd.requestWrite([0x01, 0x00]b);
        } catch (e instanceof Lang.Exception) {
            WatchUi.requestUpdate();
        }

        // ── Live Service — LiveMap (power mode 1-5) ──────────────────────────────
        var liveService;
        try {
            liveService = device.getService(
                BluetoothLowEnergy.stringToUuid(LIVE_SERVICE_UUID_STR));
        } catch (e instanceof Lang.Exception) {
            WatchUi.requestUpdate(); return;
        }
        if (liveService == null) { WatchUi.requestUpdate(); return; }

        var liveMapChar;
        try {
            liveMapChar = liveService.getCharacteristic(
                BluetoothLowEnergy.stringToUuid(LIVE_MAP_CHAR_UUID_STR));
        } catch (e instanceof Lang.Exception) {
            WatchUi.requestUpdate(); return;
        }
        if (liveMapChar == null) { WatchUi.requestUpdate(); return; }

        var liveMapCccd;
        try {
            liveMapCccd = liveMapChar.getDescriptor(BluetoothLowEnergy.cccdUuid());
        } catch (e instanceof Lang.Exception) {
            WatchUi.requestUpdate(); return;
        }
        if (liveMapCccd == null) { WatchUi.requestUpdate(); return; }

        try {
            liveMapCccd.requestWrite([0x01, 0x00]b);
        } catch (e instanceof Lang.Exception) {
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
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        } catch (e instanceof Lang.Exception) {
            // BLE unavailable — nothing to stop
        }
        _state = STATE_TIMEOUT;
        WatchUi.requestUpdate();
    }

    private function _doScan() as Void {
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        } catch (e instanceof Lang.Exception) {
            _state = STATE_BLE_UNAVAILABLE;
            WatchUi.requestUpdate();
            return;
        }
        _startTimer();
        WatchUi.requestUpdate();
    }
}
