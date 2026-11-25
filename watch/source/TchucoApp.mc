import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Ponto de entrada do app: cria o controle (estado + envio), a tela e os botões.
class TchucoApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var controle = new Controle();
        return [new TchucoView(controle), new TchucoDelegate(controle)];
    }
}
