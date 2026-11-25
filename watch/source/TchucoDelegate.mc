import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Tudo é feito só pelos botões físicos; a tela sensível ao toque é ignorada.
//
//   START         próximo slide
//   DOWN          slide anterior
//   BACK          pede confirmação; um segundo BACK em seguida fecha o app
//   segurar UP    ajuste do aviso de tempo (UP/DOWN escolhem, START grava)
//
// Usa InputDelegate (e não BehaviorDelegate) de propósito: no BehaviorDelegate
// um toque na tela vira onSelect e um deslizar vira onNextPage/onPreviousPage.
// O app também não abre telas do sistema (menu, confirmação), porque elas
// aceitam toque.
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
        // No 955, deslizar o dedo para a direita também chega como BACK.
        // Vale como BACK de verdade se o botão foi apertado agora há pouco
        // ou, na dúvida, se a tela não acabou de ser tocada.
        var agora = System.getTimer();
        var back = (tecla == WatchUi.KEY_ESC)
                && (agora - _backEm < 2000 || agora - _toqueEm > 800);

        if (_controle.ajustando) {
            // Ajuste do aviso de tempo.
            if (tecla == WatchUi.KEY_UP) {
                _controle.mudarOpcao(-1);
            } else if (tecla == WatchUi.KEY_DOWN) {
                _controle.mudarOpcao(1);
            } else if (tecla == WatchUi.KEY_ENTER) {
                _controle.fecharAjuste(true);       // START grava
            } else if (back) {
                _controle.fecharAjuste(false);      // BACK sai sem gravar
            }
        } else if (tecla == WatchUi.KEY_ENTER) {
            _controle.comando("next");              // START: avança
        } else if (tecla == WatchUi.KEY_DOWN) {
            _controle.comando("prev");              // DOWN: volta
        } else if (tecla == WatchUi.KEY_MENU) {
            _controle.abrirAjuste();                // segurar UP
        } else if (back) {
            if (_controle.pedirSaida()) {           // true no segundo BACK
                System.exit();
            }
        } else if (tecla != WatchUi.KEY_ESC) {
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
