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
        var ageStr;
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
