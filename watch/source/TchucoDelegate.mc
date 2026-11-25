import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Botões físicos: START e DOWN = próximo, UP = anterior, BACK = sair.
//
// Usa InputDelegate (e não BehaviorDelegate) de propósito: no BehaviorDelegate
// um toque na tela vira onSelect e um deslizar vira onNextPage/onPreviousPage,
// e aqui os toques precisam ser ignorados.
class TchucoDelegate extends WatchUi.InputDelegate {
    private var _controle as Controle;
    private var _backEm as Number = 0;    // quando o BACK físico foi apertado
    private var _toqueEm as Number = 0;   // quando a tela foi tocada pela última vez

    function initialize(controle as Controle) {
        InputDelegate.initialize();
        _controle = controle;
    }

    // Só botão físico gera onKeyPressed; guarda o momento em que foi o BACK.
    function onKeyPressed(evento as WatchUi.KeyEvent) as Boolean {
        if (evento.getKey() == WatchUi.KEY_ESC) {
            _backEm = System.getTimer();
        }
        return false;
    }

    function onKey(evento as WatchUi.KeyEvent) as Boolean {
        var tecla = evento.getKey();
        if (tecla == WatchUi.KEY_ENTER || tecla == WatchUi.KEY_DOWN) {
            _controle.comando("next");
        } else if (tecla == WatchUi.KEY_UP) {
            _controle.comando("prev");
        } else if (tecla == WatchUi.KEY_ESC) {
            // No 955, deslizar o dedo para a direita também chega aqui como BACK.
            // Vale como BACK de verdade se o botão foi apertado agora há pouco
            // ou, na dúvida, se a tela não acabou de ser tocada.
            var agora = System.getTimer();
            if (agora - _backEm < 2000 || agora - _toqueEm > 800) {
                // Pede confirmação antes de sair.
                WatchUi.pushView(new WatchUi.Confirmation("Sair?"),
                        new SairDelegate(), WatchUi.SLIDE_IMMEDIATE);
            }
        } else {
            return false;   // outras teclas: comportamento padrão do sistema
        }
        return true;
    }

    // Toques na tela: só anota o momento e devolve true, que avisa o sistema
    // de que o evento já foi tratado. Nada mais acontece.
    private function toque() as Boolean {
        _toqueEm = System.getTimer();
        return true;
    }

    function onTap(evento as WatchUi.ClickEvent) as Boolean {
        return toque();
    }

    function onHold(evento as WatchUi.ClickEvent) as Boolean {
        return toque();
    }

    function onRelease(evento as WatchUi.ClickEvent) as Boolean {
        return toque();
    }

    function onSwipe(evento as WatchUi.SwipeEvent) as Boolean {
        return toque();
    }

    function onDrag(evento as WatchUi.DragEvent) as Boolean {
        return toque();
    }

    function onFlick(evento as WatchUi.FlickEvent) as Boolean {
        return toque();
    }
}

// Resposta da pergunta "Sair?": só fecha o app se a pessoa confirmar.
class SairDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(resposta as WatchUi.Confirm) as Boolean {
        if (resposta == WatchUi.CONFIRM_YES) {
            System.exit();
        }
        return true;
    }
}
