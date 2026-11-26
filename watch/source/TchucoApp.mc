import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// App entry point: creates the controller (state + sending), the view and the
// button handling.
class TchucoApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var controller = new Controller();
        return [new TchucoView(controller), new TchucoDelegate(controller)];
    }
}
