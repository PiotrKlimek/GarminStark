import Toybox.Application;
import Toybox.Background;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// UUID string constants are defined in StarkBatteryDFService.mc
// (module scope — visible here too)

class StarkBatteryDFApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    (:typecheck(disableBackgroundCheck))
    function onStart(state as Lang.Dictionary?) as Void {
        System.println("[DF] onStart");

        // Register BLE profile — throws if already registered; safe to ignore
        try {
            System.println("[DF] registerProfile");
            BluetoothLowEnergy.registerProfile({
                :uuid => BluetoothLowEnergy.stringToUuid(DF_BATT_SERVICE_UUID_STR),
                :characteristics => [{
                    :uuid => BluetoothLowEnergy.stringToUuid(DF_BATT_SOC_CHAR_UUID_STR),
                    :descriptors => [BluetoothLowEnergy.cccdUuid()]
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

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new StarkBatteryDFService()];
    }
}
