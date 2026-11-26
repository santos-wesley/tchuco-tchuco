import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The app's screens.
module Screen {
    const MENU as Number = 0;           // start menu
    const TOTAL as Number = 1;          // timer: total time
    const ALERTS as Number = 2;         // time alerts: yes or no
    const ALERT_EVERY as Number = 3;    // time alerts: every how many minutes
    const SLIDES as Number = 4;         // presentation (the slide clicker)
}

// App state: current screen, settings, presentation time and the sending of
// the commands ("next"/"prev") to ntfy.
//
// Each command goes through two steps, always one request at a time:
//   1) publish ("SENDING"): POST the command to ntfy;
//   2) poll ("CONFIRMING"): the computer script publishes the command id to
//      the "<topic>-ack" topic and the watch polls that topic.
// "OK" only shows up after the computer confirms. A new press takes priority
// over the confirmation of the previous command.
class Controller {
    private const MAX_POLLS as Number = 3;      // polls before giving up
    private const POLL_WAIT_MS as Number = 700; // pause before each poll
    // Vibration: strength from 0 to 100 and duration in ms (see buzz).
    private const SOFT as Number = 25;
    private const STRONG as Number = 100;
    private const SHORT_MS as Number = 50;      // confirmed and time alert
    private const LONG_MS as Number = 300;      // failure
    private const END_MS as Number = 500;       // each end-of-time vibration
    private const ALERT_PULSES as Number = 3;   // soft vibrations per alert
    private const END_PULSES as Number = 5;     // strong vibrations at the end
    private const MAX_MIN as Number = 180;      // largest value in the settings
    // How long the top banner stays on screen after the result.
    private const OK_MS as Number = 3000;
    private const ERROR_MS as Number = 10000;

    var screen as Number = Screen.MENU;
    var item as Number = 0;                     // menu: 0 free, 1 timer,
                                                // 2 alert, 3 light
    var value as Number = 0;                    // value shown in the settings
    var blocked as Boolean = false;             // START refused: alert won't fit
    var timed as Boolean = false;               // mode of this presentation
    var totalMin as Number = 20;                // timer: total time
    var alertOn as Boolean = false;             // time alerts (both modes)
    var alertMin as Number = 5;                 // alert every N minutes
    var light as Boolean = true;                // keep the backlight on
    var status as String = "";                  // top banner: last command
    var detail as String = "";                  // confirmation time or error
    var slide as Number = 1;                    // slide counter
    var startedAt as Number? = null;            // System.getTimer() at the start
    var alerting as Boolean = false;            // a time alert is going on
    var exiting as Boolean = false;             // waiting for the 2nd BACK

    private var _busy as Boolean = false;       // command without a result yet
    private var _inFlight as Boolean = false;   // a request is in progress
    private var _queued as String? = null;      // at most ONE queued command
    private var _last as String = "";           // last published command
    private var _id as String = "";             // that command's id on ntfy
    private var _delta as Number = 0;           // slides not confirmed yet
    private var _batch as Number = 0;           // commands not confirmed yet
    private var _polls as Number = 0;           // polls made so far
    private var _sentAt as Number = 0;          // System.getTimer() of the send
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _pulses as Number = 0;          // "OK" vibrations still to give
    private var _statusUntil as Number = 0;     // until when the banner stays
    private var _exitAskedAt as Number = 0;     // when the 1st BACK was pressed
    private var _nextAlert as Number = 0;       // next alert: elapsed seconds
    private var _endSignaled as Boolean = false; // end of time already signaled
    private var _softLeft as Number = 0;        // soft vibrations still to give
    private var _strongLeft as Number = 0;      // strong vibrations still to give

    function initialize() {
        // The settings are stored on the watch.
        totalMin = readNumber("totalMin", 20);
        if (totalMin < 1) {
            totalMin = 20;
        }
        alertMin = readNumber("alertMin", 5);
        if (alertMin < 1) {
            alertMin = 5;
        }
        item = readNumber("mode", 0);           // the menu opens on the last mode
        alertOn = readBoolean("alertOn", false);
        light = readBoolean("light", true);
    }

    private function readBoolean(key as String, fallback as Boolean) as Boolean {
        var stored = Application.Storage.getValue(key);
        if (stored instanceof Boolean) {
            return stored;
        }
        return fallback;
    }

    private function readNumber(key as String, fallback as Number) as Number {
        var stored = Application.Storage.getValue(key);
        if (stored instanceof Number) {
            return stored;
        }
        return fallback;
    }

    // ----------------------------------------------------------------- menu

    // UP and DOWN on the menu: previous (-1) or next (+1) option.
    function moveMenu(step as Number) as Void {
        item = (item + step + 4) % 4;
        WatchUi.requestUpdate();
    }

    // START on the menu.
    function selectMenu() as Void {
        if (item == 0) {
            begin(false);                       // straight to the free clicker
        } else if (item == 1) {
            value = totalMin;                   // timer: asks for the total time
            blocked = false;
            screen = Screen.TOTAL;
        } else if (item == 2) {
            value = alertOn ? 1 : 0;            // alerts: yes or no
            screen = Screen.ALERTS;
        } else {
            light = !light;
            Application.Storage.setValue("light", light);
        }
        WatchUi.requestUpdate();
    }

    // UP (+1) and DOWN (-1) in the settings. On the alerts question they
    // toggle between NO and YES; minutes go by 1 up to 30, by 5 up to 60 and
    // by 15 up to 180.
    function changeValue(direction as Number) as Void {
        blocked = false;
        if (screen == Screen.ALERTS) {
            value = 1 - value;
        } else {
            var step = 15;
            if (value < 30 || (value == 30 && direction < 0)) {
                step = 1;
            } else if (value < 60 || (value == 60 && direction < 0)) {
                step = 5;
            }
            value += direction * step;
            if (value < 1) {
                value = 1;
            } else if (value > MAX_MIN) {
                value = MAX_MIN;
            }
        }
        WatchUi.requestUpdate();
    }

    // START in the settings: saves what is on screen and moves on. On the
    // total time, START stays blocked while the alert does not fit: it only
    // vibrates and explains.
    function confirmSetting() as Void {
        if (screen == Screen.TOTAL && alertDoesNotFit(value)) {
            blocked = true;
            buzz(SOFT, LONG_MS);
        } else if (screen == Screen.TOTAL) {
            totalMin = value;                   // timer: starts counting now
            Application.Storage.setValue("totalMin", value);
            begin(true);
        } else if (screen == Screen.ALERTS && value == 1) {
            value = alertMin;                   // YES: asks how often
            screen = Screen.ALERT_EVERY;
        } else {
            alertOn = (screen == Screen.ALERT_EVERY);
            if (alertOn) {
                alertMin = value;
                Application.Storage.setValue("alertMin", value);
            }
            Application.Storage.setValue("alertOn", alertOn);
            screen = Screen.MENU;
        }
        WatchUi.requestUpdate();
    }

    // BACK in the settings: goes back one screen without saving.
    function backFromSetting() as Void {
        if (screen == Screen.ALERT_EVERY) {
            value = 1;
            screen = Screen.ALERTS;
        } else {
            screen = Screen.MENU;
        }
        WatchUi.requestUpdate();
    }

    // Opens the presentation screen, reset, in the chosen mode.
    private function begin(withTimer as Boolean) as Void {
        timed = withTimer;
        item = withTimer ? 1 : 0;
        Application.Storage.setValue("mode", item);
        slide = 1;
        status = "";
        detail = "";
        exiting = false;
        alerting = false;
        _statusUntil = 0;
        _busy = false;                          // nothing pending from last time
        _delta = 0;
        _batch = 0;
        _queued = null;
        _softLeft = 0;
        _strongLeft = 0;
        // In timer mode the clock runs right away; in free mode, from the
        // first slide change.
        startedAt = null;
        if (withTimer) {
            startClock();
        }
        screen = Screen.SLIDES;
    }

    // Marks the start of the clock and schedules the first alert. In free
    // mode alerts come every alertMin minutes; in timer mode, when multiples
    // of alertMin remain (for example: 10 left, 5 left).
    private function startClock() as Void {
        startedAt = System.getTimer();
        _endSignaled = false;
        _nextAlert = 0;
        if (alertOn) {
            var step = alertMin * 60;
            _nextAlert = step;
            if (timed) {
                var total = totalMin * 60;
                _nextAlert = total - ((total - 1) / step) * step;
                if (_nextAlert >= total) {
                    _nextAlert = 0;             // time shorter than the interval
                }
            }
        }
    }

    // In timer mode the alert only happens if the interval is shorter than
    // the total time: with 2 minutes of time, an alert every 5 would never
    // come. So the total time screen says so and refuses to start like that.
    function alertDoesNotFit(minutes as Number) as Boolean {
        return alertOn && alertMin >= minutes;
    }

    // BACK in the presentation: the first one only asks; a second BACK within
    // 3 s returns true (and the caller goes back to the menu).
    function requestExit() as Boolean {
        if (exiting) {
            return true;
        }
        exiting = true;
        _exitAskedAt = System.getTimer();
        WatchUi.requestUpdate();
        return false;
    }

    function goToMenu() as Void {
        _timer.stop();
        _pulses = 0;
        exiting = false;
        alerting = false;
        screen = Screen.MENU;
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------------- time

    // Seconds of presentation elapsed so far (0 before the clock starts).
    function elapsed() as Number {
        var start = startedAt;
        if (start == null) {
            return 0;
        }
        return (System.getTimer() - start) / 1000;
    }

    // Called by the view once per second.
    function tick() as Void {
        // Screen always lit: each call renews the backlight timeout.
        if (light && (Attention has :backlight)) {
            Attention.backlight(true);
        }
        // The exit question goes away by itself.
        if (exiting && System.getTimer() - _exitAskedAt > 3000) {
            exiting = false;
        }
        // Time alerts (both modes) and, in timer mode, the end alarm.
        if (screen == Screen.SLIDES && startedAt != null) {
            var sec = elapsed();
            var total = totalMin * 60;
            if (timed && !_endSignaled && sec >= total) {
                _endSignaled = true;
                _strongLeft = END_PULSES;       // time is up
            } else if (_nextAlert > 0 && sec >= _nextAlert) {
                _nextAlert += alertMin * 60;
                if (timed && _nextAlert >= total) {
                    _nextAlert = 0;             // the next one would be the end
                }
                _softLeft = ALERT_PULSES;
            }
        }
        // One vibration per second until the alert is complete.
        alerting = (_strongLeft > 0 || _softLeft > 0);
        if (_strongLeft > 0) {
            _strongLeft -= 1;
            buzz(STRONG, END_MS);
        } else if (_softLeft > 0) {
            _softLeft -= 1;
            buzz(SOFT, SHORT_MS);
        }
    }

    // The top banner only shows while a command is in progress and for a few
    // seconds after the result.
    function statusVisible() as Boolean {
        return _busy || System.getTimer() < _statusUntil;
    }

    // ------------------------------------------------------------- commands

    // Called by the buttons with "next" or "prev".
    function command(cmd as String) as Void {
        exiting = false;                        // gives up exiting
        if (startedAt == null) {
            startClock();                       // free mode: starts on 1st press
        }
        if (_inFlight) {
            _queued = cmd;                      // queue of 1: last press wins
            status = "SENDING +1";
        } else {
            _timer.stop();                      // don't wait for the last poll
            _pulses = 0;
            publish(cmd);
        }
        WatchUi.requestUpdate();
    }

    // Step 1: publishes the command through the phone (Garmin Connect, over
    // Bluetooth).
    private function publish(cmd as String) as Void {
        _busy = true;
        _inFlight = true;
        _last = cmd;
        _sentAt = System.getTimer();
        status = "SENDING";
        detail = "";
        // ntfy's "Publish as JSON": POST to the base URL with the topic in the
        // body. On the fr955, makeWebRequest only sends dictionaries (there is
        // no plain-text body), and with a JSON :responseType the reply must be
        // application/json, which is exactly what ntfy returns.
        Communications.makeWebRequest(
            Config.BASE_URL + "/",
            { "topic" => Config.TOPIC, "message" => cmd },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onPublished)
        );
    }

    // ntfy's reply: 200 = published; another positive value = HTTP error;
    // zero or negative = Connect IQ error (Bluetooth, phone or network).
    function onPublished(code as Number,
            data as Dictionary or String or Null) as Void {
        _inFlight = false;
        // Shows up in the simulator console and in the watch log.
        System.println("sent " + _last + ": " + code);
        var pending = _queued;
        if (code != 200) {
            fail(code);
        } else {
            _delta += _last.equals("next") ? 1 : -1;
            _batch += 1;
            var id = (data instanceof Dictionary) ? data["id"] : null;
            if (pending != null) {
                _queued = null;
                publish(pending);               // another press: it goes first
            } else if (id instanceof String) {
                _id = id;
                _polls = 0;
                status = "CONFIRMING";
                _timer.stop();
                _timer.start(method(:poll), POLL_WAIT_MS, false);
            } else {
                confirmed();                    // no id, nothing to check
            }
        }
        WatchUi.requestUpdate();
    }

    // Step 2: reads the recent confirmations. ntfy's "raw" format returns
    // plain text (one id per line), which Connect IQ accepts as TEXT_PLAIN.
    function poll() as Void {
        _inFlight = true;
        _polls += 1;
        Communications.makeWebRequest(
            Config.BASE_URL + "/" + Config.TOPIC + "-ack/raw",
            // "n" only changes the URL on each poll, so the phone won't cache it
            { "poll" => "1", "since" => "30s", "n" => System.getTimer() },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType =>
                    Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            },
            method(:onPolled)
        );
    }

    function onPolled(code as Number,
            data as Dictionary or String or Null) as Void {
        _inFlight = false;
        System.println("poll " + _polls + ": " + code);
        var found = false;
        if (code == 200 && data instanceof String) {
            found = (data.find(_id) != null);
        }
        var pending = _queued;
        if (found) {
            confirmed();
        }
        if (pending != null) {
            _queued = null;
            publish(pending);                   // a new press takes priority
        } else if (!found) {
            if (code == Communications.BLE_CONNECTION_UNAVAILABLE) {
                fail(code);
            } else if (_polls < MAX_POLLS) {
                _timer.stop();
                _timer.start(method(:poll), POLL_WAIT_MS, false);
            } else {
                // ntfy got the command, but no computer confirmed it.
                System.println("no confirmation");
                finishWithError("NO PC", (code == 200) ? "no reply"
                        : "code " + code);
            }
        }
        WatchUi.requestUpdate();
    }

    // The computer ran it: updates the counter and answers once for each
    // confirmed command (two quick presses = "OK x2" and two vibrations).
    private function confirmed() as Void {
        var count = _batch;
        slide += _delta;
        if (slide < 1) {
            slide = 1;
        }
        _delta = 0;
        _batch = 0;
        _busy = false;
        var ms = System.getTimer() - _sentAt;
        System.println("confirmed in " + ms + " ms (" + count + ")");
        status = _last.equals("next") ? "OK >>" : "<< OK";
        if (count > 1) {
            status = "OK x" + count;
        }
        detail = (ms / 1000.0).format("%.1f") + " s";
        _statusUntil = System.getTimer() + OK_MS;
        buzz(SOFT, SHORT_MS);
        _pulses = ((count > 4) ? 4 : count) - 1;
        if (_pulses > 0) {
            _timer.stop();
            _timer.start(method(:pulse), 300, true);
        }
    }

    // The remaining vibrations of an "OK" for several commands.
    function pulse() as Void {
        buzz(SOFT, SHORT_MS);
        _pulses -= 1;
        if (_pulses <= 0) {
            _timer.stop();
        }
    }

    // The command never reached ntfy.
    private function fail(code as Number) as Void {
        var text = "NO INTERNET";
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) {
            text = "NO PHONE";
        } else if (code > 0) {
            text = "HTTP ERROR";                // e.g. 429 = ntfy rate limit
        }
        finishWithError(text, "code " + code);
    }

    // Ends with a failure: shows the banner for longer and gives the long
    // vibration.
    private function finishWithError(text as String, info as String) as Void {
        _queued = null;                         // don't insist after an error
        _delta = 0;
        _batch = 0;
        _busy = false;
        status = text;
        detail = info;
        _statusUntil = System.getTimer() + ERROR_MS;
        buzz(SOFT, LONG_MS);
    }

    // On the Forerunner the watch may ignore the requested strength, so the
    // difference between soft and strong comes mostly from the duration.
    private function buzz(strength as Number, ms as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(strength, ms)]);
        }
    }
}
