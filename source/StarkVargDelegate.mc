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
