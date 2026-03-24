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

    // Long press UP/MENU: cycle through states for UI testing without a motorcycle.
    // CONNECTED(75%) → CONNECTED(20%) → RECONNECTING → TIMEOUT → (repeat)
    function onMenu() as Boolean {
        _bleManager.simulateNextState();
        return true;
    }
}
