import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Ponto de entrada do app: cria o controle (estado + envio), a tela e os botões.
class TchucoApp extends Application.AppBase {
    private var _sessao as ActivityRecording.Session?;

    function initialize() {
        AppBase.initialize();
    }

    // Um app não consegue bloquear as notificações do relógio. O que dá para
    // fazer é gravar uma "atividade" enquanto ele está aberto: assim o relógio
    // passa a seguir a regra de notificações "durante a atividade", que pode
    // ser deixada como "desligado" nas configurações do relógio.
    function onStart(state as Dictionary?) as Void {
        if (Toybox has :ActivityRecording) {
            var sessao = ActivityRecording.createSession({
                :name => "Apresentacao",
                :sport => Activity.SPORT_GENERIC
            });
            sessao.start();
            _sessao = sessao;
        }
    }

    // Ao fechar, a atividade é descartada: nada vai para o Garmin Connect.
    function onStop(state as Dictionary?) as Void {
        var sessao = _sessao;
        if (sessao != null) {
            sessao.stop();
            sessao.discard();
            _sessao = null;
            System.println("atividade descartada");
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var controle = new Controle();
        return [new TchucoView(controle), new TchucoDelegate(controle)];
    }
}
