import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Uma única View desenha as telas do app (menu, ajustes do cronômetro e
// apresentação), todas pensadas para o visor MIP: fundo preto e letras grandes.
class TchucoView extends WatchUi.View {
    // Do verde ao vermelho usando só cores que o visor de 64 cores tem.
    private const CORES as Array<Number> = [0x00FF00, 0x55FF00, 0xAAFF00,
            0xFFFF00, 0xFFAA00, 0xFF5500, 0xFF0000];

    private var _controle as Controle;
    private var _relogio as Timer.Timer?;

    function initialize(controle as Controle) {
        View.initialize();
        _controle = controle;
    }

    // Enquanto a tela está visível, um "tique" por segundo: mantém a luz
    // acesa, anda o tempo e dispara os avisos.
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
        _controle.tique();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (_controle.tela == Tela.MENU) {
            desenharMenu(dc);
        } else if (_controle.tela == Tela.SLIDES) {
            desenharSlides(dc);
        } else {
            desenharAjuste(dc);
        }
    }

    // Menu inicial: três opções, a destacada em tarja branca, e embaixo uma
    // linha explicando a opção destacada. UP/DOWN escolhem, START confirma.
    private function desenharMenu(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centro = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var rotulos = ["LIVRE", "CRONÔMETRO",
                _controle.luz ? "LUZ: LIGADA" : "LUZ: AUTO"];
        var ajudas = ["só passar os slides",
                _controle.duracaoMin + " min" + ((_controle.avisoMin > 0)
                        ? ", aviso " + _controle.avisoMin : ", sem aviso"),
                "START troca"];

        dc.drawText(cx, h * 11 / 100, Graphics.FONT_XTINY, "TCHUCO TCHUCO", centro);
        for (var i = 0; i < rotulos.size(); i++) {
            var y = h * (31 + 19 * i) / 100;
            if (i == _controle.item) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
                dc.fillRoundedRectangle(w * 10 / 100, y - h * 8 / 100,
                        w * 80 / 100, h * 16 / 100, h * 4 / 100);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(cx, y, Graphics.FONT_SMALL, rotulos[i], centro);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 87 / 100, Graphics.FONT_XTINY,
                ajudas[_controle.item], centro);
    }

    // Ajustes do cronômetro: o valor grande no centro, "+" ao lado do botão
    // UP e "-" ao lado do DOWN. START segue, BACK volta.
    private function desenharAjuste(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centro = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var tempoTotal = (_controle.tela == Tela.TEMPO);

        dc.drawText(cx, h * 21 / 100, Graphics.FONT_SMALL,
                tempoTotal ? "TEMPO TOTAL" : "AVISO A CADA", centro);
        if (_controle.opcao > 0) {
            dc.drawText(cx, h * 48 / 100, Graphics.FONT_NUMBER_HOT,
                    _controle.opcao.format("%d"), centro);
            dc.drawText(cx, h * 71 / 100, Graphics.FONT_SMALL, "MIN", centro);
        } else {
            dc.drawText(cx, h * 52 / 100, Graphics.FONT_MEDIUM, "SEM AVISO", centro);
        }
        dc.drawText(w * 11 / 100, h * 48 / 100, Graphics.FONT_MEDIUM, "+", centro);
        dc.drawText(w * 17 / 100, h * 71 / 100, Graphics.FONT_MEDIUM, "-", centro);
        dc.drawText(cx, h * 88 / 100, Graphics.FONT_XTINY,
                tempoTotal ? "START continua" : "START começa", centro);
    }

    // Apresentação: o tempo no centro e o contador de slides embaixo. O aviso
    // do topo (envio, OK, falhas) é sempre branco com letra preta, para não
    // se confundir com as cores do tempo, e some sozinho.
    private function desenharSlides(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centro = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        var status = _controle.status;
        var detalhe = _controle.detalhe;
        var visivel = _controle.statusVisivel();
        if (_controle.saindo) {
            detalhe = "para sair";
            status = "BACK DE NOVO";
            visivel = true;
        }
        if (visivel) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
            dc.fillRectangle(0, 0, w, h * 30 / 100);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 9 / 100, Graphics.FONT_XTINY, detalhe, centro);
            dc.drawText(cx, h * 20 / 100, Graphics.FONT_SMALL, status, centro);
        }

        // Modo livre: cronômetro branco, contando para cima.
        // Cronometrado: contagem regressiva que vai do verde ao vermelho;
        // depois do fim, mostra em vermelho quanto passou ("+MM:SS").
        var seg = _controle.decorrido();
        var corTempo = Graphics.COLOR_WHITE as Graphics.ColorType;
        var sinal = "";
        if (_controle.cronometrado) {
            var total = _controle.duracaoMin * 60;
            var etapa = CORES.size() - 1;           // tempo esgotado: vermelho
            seg = total - seg;
            if (seg >= 0) {
                etapa = (total - seg) * CORES.size() / total;
                if (etapa >= CORES.size()) {
                    etapa = CORES.size() - 1;
                }
            } else {
                seg = -seg;
                sinal = "+";
            }
            corTempo = CORES[etapa];
        }
        var tempo = ((seg % 3600) / 60).format("%02d") + ":"
                + (seg % 60).format("%02d");
        if (seg >= 3600) {
            tempo = (seg / 3600).format("%d") + ":" + tempo;
        }
        tempo = sinal + tempo;
        // Na maior fonte de números que couber.
        var fonte = Graphics.FONT_NUMBER_THAI_HOT;
        if (dc.getTextWidthInPixels(tempo, fonte) > w - 20) {
            fonte = Graphics.FONT_NUMBER_HOT;
        }
        if (dc.getTextWidthInPixels(tempo, fonte) > w - 20) {
            fonte = Graphics.FONT_NUMBER_MEDIUM;
        }
        if (_controle.avisando) {
            // Aviso de tempo: o meio da tela acende na cor do momento.
            dc.setColor(corTempo, corTempo);
            dc.fillRectangle(0, h * 33 / 100, w, h * 35 / 100);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(corTempo, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(cx, h * 50 / 100, fonte, tempo, centro);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 80 / 100, Graphics.FONT_MEDIUM,
                "SLIDE " + _controle.slide, centro);
    }
}
