import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.WatchUi;

class StarkVargApp extends Application.AppBase {

    private var bleManager as BleManager;

    function initialize() {
        AppBase.initialize();
        bleManager = new BleManager();
    }

    function onStart(state as Lang.Dictionary?) as Void {
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => BluetoothLowEnergy.stringToUuid(BATT_SERVICE_UUID_STR),
                :characteristics => [{
                    :uuid => BluetoothLowEnergy.stringToUuid(BATT_SOC_CHAR_UUID_STR),
                    :descriptors => [BluetoothLowEnergy.cccdUuid()]
                }]
            });
        } catch (e instanceof Lang.Exception) {
            // Profile may already be registered from a previous run — continue
        }
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => BluetoothLowEnergy.stringToUuid(LIVE_SERVICE_UUID_STR),
                :characteristics => [{
                    :uuid => BluetoothLowEnergy.stringToUuid(LIVE_MAP_CHAR_UUID_STR),
                    :descriptors => [BluetoothLowEnergy.cccdUuid()]
                }]
            });
        } catch (e instanceof Lang.Exception) {
            // Profile may already be registered from a previous run — continue
        }
        try {
            BluetoothLowEnergy.setDelegate(bleManager);
        } catch (e instanceof Lang.Exception) {
            bleManager.setBleUnavailable();
            return;
        }
        bleManager.startSplash();
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
