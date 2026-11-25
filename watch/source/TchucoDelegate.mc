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

    function initialize(controle as Controle) {
        InputDelegate.initialize();
        _controle = controle;
    }

    function onKey(evento as WatchUi.KeyEvent) as Boolean {
        var tecla = evento.getKey();
        if (tecla == WatchUi.KEY_ENTER || tecla == WatchUi.KEY_DOWN) {
            _controle.comando("next");
        } else if (tecla == WatchUi.KEY_UP) {
            _controle.comando("prev");
        } else if (tecla == WatchUi.KEY_ESC) {
            // BACK: pede confirmação antes de sair.
            WatchUi.pushView(new WatchUi.Confirmation("Sair?"),
                    new SairDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else {
            return false;   // outras teclas: comportamento padrão do sistema
        }
        return true;
    }

    // Toques na tela: devolver true avisa o sistema que o evento já foi
    // tratado, então nada acontece.
    function onTap(evento as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onHold(evento as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onRelease(evento as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSwipe(evento as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    function onDrag(evento as WatchUi.DragEvent) as Boolean {
        return true;
    }

    function onFlick(evento as WatchUi.FlickEvent) as Boolean {
        return true;
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
