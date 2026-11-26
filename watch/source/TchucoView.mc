import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// A single View draws all the app's screens (menu, settings and
// presentation), designed for the MIP display: black background, big letters.
class TchucoView extends WatchUi.View {
    // From green to red using only colors the 64-color display has.
    private const COLORS as Array<Number> = [0x00FF00, 0x55FF00, 0xAAFF00,
            0xFFFF00, 0xFFAA00, 0xFF5500, 0xFF0000];

    private var _controller as Controller;
    private var _clock as Timer.Timer?;

    function initialize(controller as Controller) {
        View.initialize();
        _controller = controller;
    }

    // While the screen is visible, one "tick" per second: keeps the light on,
    // moves the clock and fires the alerts.
    function onShow() as Void {
        var clock = new Timer.Timer();
        clock.start(method(:onSecond), 1000, true);
        _clock = clock;
    }

    function onHide() as Void {
        var clock = _clock;
        if (clock != null) {
            clock.stop();
            _clock = null;
        }
    }

    function onSecond() as Void {
        _controller.tick();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (_controller.screen == Screen.MENU) {
            drawMenu(dc);
        } else if (_controller.screen == Screen.SLIDES) {
            drawSlides(dc);
        } else {
            drawSetting(dc);
        }
    }

    // One list option: the highlighted one goes in a white box, black text.
    private function drawOption(dc as Graphics.Dc, y as Number,
            text as String, highlighted as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var boxH = dc.getHeight() * 15 / 100;
        if (highlighted) {
            var boxW = dc.getTextWidthInPixels(text, Graphics.FONT_SMALL) + 28;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
            dc.fillRoundedRectangle(cx - boxW / 2, y - boxH / 2, boxW, boxH, 10);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(cx, y, Graphics.FONT_SMALL, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    // Start menu: four options and, at the bottom, a line explaining the
    // highlighted one. UP/DOWN choose, START confirms.
    private function drawMenu(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var alert = _controller.alertOn;
        var labels = ["FREE", "TIMER",
                alert ? "ALERT: " + _controller.alertMin + " MIN" : "ALERT: OFF",
                _controller.light ? "LIGHT: ON" : "LIGHT: AUTO"];
        var timerHint = _controller.totalMin + " min" + (alert
                ? ", alert " + _controller.alertMin : ", no alert");
        if (_controller.alertDoesNotFit(_controller.totalMin)) {
            timerHint = doesNotFit();
        }
        var hints = [
                alert ? "alert every " + _controller.alertMin + " min"
                        : "no time alerts",
                timerHint,
                "for both modes",
                "START toggles"];
        for (var i = 0; i < labels.size(); i++) {
            drawOption(dc, h * (20 + 17 * i) / 100, labels[i],
                    i == _controller.item);
        }
        dc.drawText(dc.getWidth() / 2, h * 87 / 100, Graphics.FONT_XTINY,
                hints[_controller.item],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // In timer mode, the text saying the alert interval is equal to or longer
    // than the total time (e.g. 2 minutes of time, an alert every 5).
    private function doesNotFit() as String {
        return "alert " + _controller.alertMin + " won't fit";
    }

    // Settings. Minutes: the big value in the middle, "+" next to the UP
    // button and "-" next to DOWN. Alerts: a choice between NO and YES. START
    // moves on, BACK goes back.
    private function drawSetting(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var title = "TOTAL TIME";
        var hint = "START to begin";
        if (_controller.screen == Screen.ALERTS) {
            title = "ALERTS";
            hint = "START to confirm";
        } else if (_controller.screen == Screen.ALERT_EVERY) {
            title = "ALERT EVERY";
            hint = "START to save";
        }
        dc.drawText(cx, h * 21 / 100, Graphics.FONT_SMALL, title, center);
        if (_controller.screen == Screen.ALERTS) {
            drawOption(dc, h * 42 / 100, "NO", _controller.value == 0);
            drawOption(dc, h * 62 / 100, "YES", _controller.value == 1);
        } else {
            dc.drawText(cx, h * 48 / 100, Graphics.FONT_NUMBER_HOT,
                    _controller.value.format("%d"), center);
            dc.drawText(cx, h * 71 / 100, Graphics.FONT_SMALL, "MIN", center);
            dc.drawText(w * 11 / 100, h * 48 / 100, Graphics.FONT_MEDIUM, "+", center);
            dc.drawText(w * 17 / 100, h * 71 / 100, Graphics.FONT_MEDIUM, "-", center);
        }
        // A total time the alert does not fit in: says so right away, in a
        // white band with black text, and START stays blocked. After a refused
        // START, the band says what to do.
        if (_controller.screen == Screen.TOTAL
                && _controller.alertDoesNotFit(_controller.value)) {
            hint = _controller.blocked ? "increase the time" : doesNotFit();
            dc.fillRectangle(0, h * 80 / 100, w, h * 20 / 100);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(cx, h * 88 / 100, Graphics.FONT_XTINY, hint, center);
    }

    // Presentation: the time in the middle and the slide counter below. The
    // top banner (sending, OK, failures) is always white with black text, so
    // it is not mistaken for the time colors, and it goes away by itself.
    private function drawSlides(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        var status = _controller.status;
        var detail = _controller.detail;
        var visible = _controller.statusVisible();
        if (_controller.exiting) {
            detail = "to exit";
            status = "BACK AGAIN";
            visible = true;
        }
        if (visible) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
            dc.fillRectangle(0, 0, w, h * 30 / 100);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 9 / 100, Graphics.FONT_XTINY, detail, center);
            dc.drawText(cx, h * 20 / 100, Graphics.FONT_SMALL, status, center);
        }

        // Free mode: white stopwatch, counting up from the first slide change.
        // Timer mode: a countdown that starts as soon as this screen opens and
        // goes from green to red; after the end, it shows in red how far over
        // the limit it is ("+MM:SS").
        var sec = _controller.elapsed();
        var timeColor = Graphics.COLOR_WHITE as Graphics.ColorType;
        var sign = "";
        if (_controller.timed) {
            var total = _controller.totalMin * 60;
            var stage = COLORS.size() - 1;          // time is up: red
            sec = total - sec;
            if (sec >= 0) {
                stage = (total - sec) * COLORS.size() / total;
                if (stage >= COLORS.size()) {
                    stage = COLORS.size() - 1;
                }
            } else {
                sec = -sec;
                sign = "+";
            }
            timeColor = COLORS[stage];
        }
        var clockText = ((sec % 3600) / 60).format("%02d") + ":"
                + (sec % 60).format("%02d");
        if (sec >= 3600) {
            clockText = (sec / 3600).format("%d") + ":" + clockText;
        }
        clockText = sign + clockText;
        // In the largest number font that fits.
        var font = Graphics.FONT_NUMBER_THAI_HOT;
        if (dc.getTextWidthInPixels(clockText, font) > w - 20) {
            font = Graphics.FONT_NUMBER_HOT;
        }
        if (dc.getTextWidthInPixels(clockText, font) > w - 20) {
            font = Graphics.FONT_NUMBER_MEDIUM;
        }
        if (_controller.alerting) {
            // Time alert: the middle of the screen lights up in the current
            // time color.
            dc.setColor(timeColor, timeColor);
            dc.fillRectangle(0, h * 33 / 100, w, h * 35 / 100);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(timeColor, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(cx, h * 50 / 100, font, clockText, center);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 80 / 100, Graphics.FONT_MEDIUM,
                "SLIDE " + _controller.slide, center);
    }
}
