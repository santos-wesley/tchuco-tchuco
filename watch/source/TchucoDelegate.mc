import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Everything is done with the physical buttons only; the touchscreen is
// ignored.
//
//   Start menu     UP/DOWN choose, START confirms, BACK closes the app
//   Settings       UP and DOWN change the value, START moves on, BACK goes back
//   Presentation   START = next slide, DOWN = previous slide,
//                  BACK twice = back to the menu
//
// It uses InputDelegate (not BehaviorDelegate) on purpose: with
// BehaviorDelegate a tap becomes onSelect and a swipe becomes
// onNextPage/onPreviousPage. The app also never opens system screens (menu,
// confirmation), because those accept touch.
class TchucoDelegate extends WatchUi.InputDelegate {
    private var _controller as Controller;
    private var _backPressedAt as Number = 0;   // when physical BACK was pressed
    private var _touchedAt as Number = 0;       // when the screen was last touched

    function initialize(controller as Controller) {
        InputDelegate.initialize();
        _controller = controller;
    }

    // Only a physical button generates onKeyPressed; stores when it was BACK.
    function onKeyPressed(event as WatchUi.KeyEvent) as Boolean {
        if (event.getKey() == WatchUi.KEY_ESC) {
            _backPressedAt = System.getTimer();
        }
        return false;
    }

    function onKey(event as WatchUi.KeyEvent) as Boolean {
        var key = event.getKey();
        var start = (key == WatchUi.KEY_ENTER);
        var up = (key == WatchUi.KEY_UP);
        var down = (key == WatchUi.KEY_DOWN);
        // On the 955, swiping right also arrives as BACK. It counts as a real
        // BACK if the button was pressed just now or, when in doubt, if the
        // screen was not touched a moment ago.
        var now = System.getTimer();
        var back = (key == WatchUi.KEY_ESC)
                && (now - _backPressedAt < 2000 || now - _touchedAt > 800);

        if (_controller.screen == Screen.SLIDES) {
            if (start) {
                _controller.command("next");
            } else if (down) {
                _controller.command("prev");
            } else if (back && _controller.requestExit()) {
                _controller.goToMenu();             // second BACK
            }
        } else if (_controller.screen == Screen.MENU) {
            if (up) {
                _controller.moveMenu(-1);
            } else if (down) {
                _controller.moveMenu(1);
            } else if (start) {
                _controller.selectMenu();
            } else if (back) {
                System.exit();
            }
        } else {
            if (up) {
                _controller.changeValue(1);         // more minutes
            } else if (down) {
                _controller.changeValue(-1);        // fewer minutes
            } else if (start) {
                _controller.confirmSetting();
            } else if (back) {
                _controller.backFromSetting();
            }
        }
        // The app's four keys never reach the system; the others (for example,
        // holding UP) keep their default behavior.
        return start || up || down || (key == WatchUi.KEY_ESC);
    }

    // Touches: only records the moment and returns true, which tells the
    // system the event was handled. Nothing else happens.
    private function touch() as Boolean {
        _touchedAt = System.getTimer();
        return true;
    }

    function onTap(event as WatchUi.ClickEvent) as Boolean {
        return touch();
    }

    function onHold(event as WatchUi.ClickEvent) as Boolean {
        return touch();
    }

    function onRelease(event as WatchUi.ClickEvent) as Boolean {
        return touch();
    }

    function onSwipe(event as WatchUi.SwipeEvent) as Boolean {
        return touch();
    }

    function onDrag(event as WatchUi.DragEvent) as Boolean {
        return touch();
    }

    function onFlick(event as WatchUi.FlickEvent) as Boolean {
        return touch();
    }
}
