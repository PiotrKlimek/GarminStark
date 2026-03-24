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

        // Splash screen
        if (state == STATE_SPLASH) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 20, Graphics.FONT_LARGE,
                        "STARK VARG", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 20, Graphics.FONT_SMALL,
                        "v" + APP_VERSION, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // BLE unavailable — show error + debug code
        if (state == STATE_BLE_UNAVAILABLE) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 15, Graphics.FONT_MEDIUM,
                        WatchUi.loadResource(Rez.Strings.BleUnavailable),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 20, Graphics.FONT_SMALL,
                        "ERR:" + _bleManager.getSoc().toString(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Title (all other states)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 30, Graphics.FONT_SMALL,
                    "STARK VARG", Graphics.TEXT_JUSTIFY_CENTER);

        if (state == STATE_SCANNING) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_MEDIUM,
                        WatchUi.loadResource(Rez.Strings.Scanning),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        } else if (state == STATE_CONNECTED) {
            var soc = _bleManager.getSoc();

            dc.drawText(cx, cy - 20, Graphics.FONT_NUMBER_HOT,
                        soc.toString() + "%",
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
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 15, Graphics.FONT_MEDIUM,
                        WatchUi.loadResource(Rez.Strings.Disconnected),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, cy + 15, Graphics.FONT_SMALL,
                        WatchUi.loadResource(Rez.Strings.Searching),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        } else { // STATE_TIMEOUT
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
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
