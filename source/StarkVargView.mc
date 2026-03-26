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

        // Debug bar — bottom of screen, all states except splash
        // Format: "S:ok P:sub..." / "S:ok P:ok M3" / "S:ok P:no-svc" etc.
        if (state != STATE_SPLASH) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h - 12, Graphics.FONT_SYSTEM_XTINY,
                        _bleManager.getBleDebug(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

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
            var powerMode = _bleManager.getPowerMode();

            // SOC value — shifted up slightly to make room for mode line
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 30, Graphics.FONT_NUMBER_HOT,
                        soc.toString() + "%",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // Battery bar
            var barX = 20;
            var barY = cy + 35;
            var barMaxW = w - 40;
            var barH = 14;

            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, barY, barMaxW, barH);

            var barColor = soc > 20 ? Graphics.COLOR_GREEN : Graphics.COLOR_RED;
            var fillW = barMaxW * soc / 100;
            if (fillW < 1) { fillW = 1; }
            dc.setColor(barColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, barY, fillW, barH);

            // Power mode
            var modeStr = (powerMode != null) ? "M" + powerMode.toString() : "M?";
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 63, Graphics.FONT_MEDIUM,
                        modeStr,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

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
