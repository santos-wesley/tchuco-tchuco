import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Tudo é feito só pelos botões físicos; a tela sensível ao toque é ignorada.
//
//   Menu inicial   UP/DOWN escolhem, START confirma, BACK fecha o app
//   Ajustes        UP aumenta, DOWN diminui, START segue, BACK volta
//   Apresentação   START = próximo slide, DOWN = slide anterior,
//                  BACK duas vezes = volta para o menu
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
        var start = (tecla == WatchUi.KEY_ENTER);
        var up = (tecla == WatchUi.KEY_UP);
        var down = (tecla == WatchUi.KEY_DOWN);
        // No 955, deslizar o dedo para a direita também chega como BACK.
        // Vale como BACK de verdade se o botão foi apertado agora há pouco
        // ou, na dúvida, se a tela não acabou de ser tocada.
        var agora = System.getTimer();
        var back = (tecla == WatchUi.KEY_ESC)
                && (agora - _backEm < 2000 || agora - _toqueEm > 800);

        if (_controle.tela == Tela.SLIDES) {
            if (start) {
                _controle.comando("next");
            } else if (down) {
                _controle.comando("prev");
            } else if (back && _controle.pedirSaida()) {
                _controle.irParaMenu();             // segundo BACK
            }
        } else if (_controle.tela == Tela.MENU) {
            if (up) {
                _controle.moverMenu(-1);
            } else if (down) {
                _controle.moverMenu(1);
            } else if (start) {
                _controle.escolherMenu();
            } else if (back) {
                System.exit();
            }
        } else {
            if (up) {
                _controle.mudarOpcao(1);            // mais minutos
            } else if (down) {
                _controle.mudarOpcao(-1);           // menos minutos
            } else if (start) {
                _controle.avancarAjuste();
            } else if (back) {
                _controle.voltarAjuste();
            }
        }
        // As quatro teclas do app nunca passam para o sistema; as outras
        // (por exemplo, segurar UP) seguem o comportamento padrão.
        return start || up || down || (tecla == WatchUi.KEY_ESC);
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
