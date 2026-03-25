import Toybox.Application;
import Toybox.Background;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// BLE UUID constants — defined here, used by both Service and App
const DF_BATT_SERVICE_UUID_STR  = "00006000-5374-6172-4b20-467574757265";
const DF_BATT_SOC_CHAR_UUID_STR = "00006004-5374-6172-4b20-467574757265";

// ── BLE delegate: handles scan/connect/characteristic callbacks ──────────────
// Lives in the background task; created by StarkBatteryDFService and passed
// to BluetoothLowEnergy.setDelegate().
class DFBleDelegate extends BluetoothLowEnergy.BleDelegate {

    private var _svc        as StarkBatteryDFService;
    private var _startTime  as Lang.Number;

    function initialize(svc as StarkBatteryDFService, startTime as Lang.Number) {
        BleDelegate.initialize();
        _svc       = svc;
        _startTime = startTime;
    }

    // ── BLE callbacks ─────────────────────────────────────────────────────────

    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        var elapsed = Time.now().value() - _startTime;

        // Wall-clock scan timeout (Timer.Timer unavailable in background)
        if (elapsed >= 10) {
            System.println("[DF] scan timeout after " + elapsed + "s — stopping");
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            _svc.writeState("TO", null);
            return;
        }

        var result = scanResults.next() as BluetoothLowEnergy.ScanResult?;
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
            result = scanResults.next() as BluetoothLowEnergy.ScanResult?;
        }
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device,
                                     state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            System.println("[DF] connected");
            _svc.writeState("CON", null);
            _enableNotifications(device);
        } else {
            System.println("[DF] disconnected before notification — exit");
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            _svc.writeState("DIS", "dis");
        }
    }

    function onCharacteristicChanged(char as BluetoothLowEnergy.Characteristic,
                                     value as Lang.ByteArray) as Void {
        if (value.size() < 2) {
            System.println("[DF] notification too short (" + value.size() + " bytes) — skip");
            return;
        }
        System.println("[DF] notification raw=[" + value[0] + "," + value[1] + "]");

        var soc = (value[0] & 0xFF) | ((value[1] & 0xFF) << 8);
        if (soc > 100) { soc = 100; }

        var now = Time.now().value();
        Application.Storage.setValue("df_soc", soc);
        Application.Storage.setValue("df_soc_ts", now);
        System.println("[DF] soc=" + soc + " ts=" + now);

        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        // "CON" here means "last known state was connected + SOC read succeeded".
        _svc.writeState("CON", "ok");
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private function _enableNotifications(device as BluetoothLowEnergy.Device) as Void {
        var serviceUuid = BluetoothLowEnergy.stringToUuid(DF_BATT_SERVICE_UUID_STR);
        var charUuid    = BluetoothLowEnergy.stringToUuid(DF_BATT_SOC_CHAR_UUID_STR);

        var service = device.getService(serviceUuid);
        System.println("[DF] service=" + (service != null ? "found" : "NULL"));
        if (service == null) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            _svc.writeState("ERR", "no-svc");
            return;
        }

        var characteristic = service.getCharacteristic(charUuid);
        System.println("[DF] char=" + (characteristic != null ? "found" : "NULL"));
        if (characteristic == null) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            _svc.writeState("ERR", "no-chr");
            return;
        }

        var cccd = characteristic.getDescriptor(BluetoothLowEnergy.cccdUuid());
        System.println("[DF] cccd=" + (cccd != null ? "found" : "NULL"));
        if (cccd == null) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            _svc.writeState("ERR", "no-ccd");
            return;
        }

        cccd.requestWrite([0x01, 0x00]b);
        System.println("[DF] CCCD write sent");
    }
}

// ── Background service delegate ───────────────────────────────────────────────
// Called by OS every 5 minutes via the TemporalEvent.
class StarkBatteryDFService extends System.ServiceDelegate {

    private var _bleDelegate as DFBleDelegate?;

    function initialize() {
        ServiceDelegate.initialize();
        _bleDelegate = null;
    }

    // ── Entry point — called by OS every 5 minutes ────────────────────────────

    function onTemporalEvent() as Void {
        var startTime = Time.now().value();
        System.println("[DF] onTemporalEvent start ts=" + startTime);

        try {
            // Defensive teardown of any lingering prior session
            System.println("[DF] teardown: setScanState OFF");
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);

            _bleDelegate = new DFBleDelegate(self, startTime);
            BluetoothLowEnergy.setDelegate(_bleDelegate);
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
            System.println("[DF] scan started");

            writeState("SCN", null);
        } catch (e instanceof Lang.Exception) {
            System.println("[DF] exception: " + e.getErrorMessage());
            writeState("ERR", "ex");
        }
    }

    // ── Called by DFBleDelegate to persist state ───────────────────────────────
    // (package-internal: public so DFBleDelegate can call it)

    function writeState(state as Lang.String, event as Lang.String?) as Void {
        Application.Storage.setValue("df_state", state);
        if (event != null) {
            Application.Storage.setValue("df_last_event", event);
        }
    }
}
