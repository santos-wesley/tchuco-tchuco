import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Tela única, pensada para o visor MIP: fundo preto, letras grandes e uma
// faixa colorida no topo com o resultado do último envio.
class TchucoView extends WatchUi.View {
    private var _controle as Controle;
    private var _relogio as Timer.Timer?;

    function initialize(controle as Controle) {
        View.initialize();
        _controle = controle;
    }

    // Enquanto a tela está visível, redesenha 1x por segundo (cronômetro).
    function onShow() as Void {
        var relogio = new Timer.Timer();
        relogio.start(method(:aoTique), 1000, true);
        _relogio = relogio;
    }

    function onHide() as Void {
        var relogio = _relogio;
        if (relogio != null) {
            relogio.stop();
            _relogio = null;
        }
    }

    function aoTique() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var largura = dc.getWidth();
        var altura = dc.getHeight();
        var cx = largura / 2;
        var centro = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Faixa de status: amarelo = enviando, verde = enviado, vermelho = falhou.
        var cor = _controle.cor;
        dc.setColor(cor, cor);
        dc.fillRectangle(0, 0, largura, altura * 33 / 100);
        var fundoEscuro = (cor == Graphics.COLOR_BLACK || cor == Graphics.COLOR_RED);
        dc.setColor(fundoEscuro ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK,
                Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, altura * 9 / 100, Graphics.FONT_XTINY,
                _controle.detalhe, centro);
        dc.drawText(cx, altura * 21 / 100, Graphics.FONT_SMALL,
                _controle.status, centro);

        // Cronômetro no centro, na maior fonte de números que couber.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var tempo = tempoDecorrido();
        var fonte = Graphics.FONT_NUMBER_THAI_HOT;
        if (dc.getTextWidthInPixels(tempo, fonte) > largura - 20) {
            fonte = Graphics.FONT_NUMBER_MEDIUM;    // a partir de 1 hora
        }
        dc.drawText(cx, altura * 53 / 100, fonte, tempo, centro);

        // Contador de slides embaixo.
        dc.drawText(cx, altura * 83 / 100, Graphics.FONT_MEDIUM,
                "SLIDE " + _controle.slide, centro);
    }

    // Tempo desde o primeiro clique: "MM:SS" ou "H:MM:SS".
    private function tempoDecorrido() as String {
        var inicio = _controle.inicio;
        var seg = 0;
        if (inicio != null) {
            seg = (System.getTimer() - inicio) / 1000;
        }
        var texto = ((seg % 3600) / 60).format("%02d") + ":"
                + (seg % 60).format("%02d");
        if (seg >= 3600) {
            texto = (seg / 3600).format("%d") + ":" + texto;
        }
        return texto;
    }
}
