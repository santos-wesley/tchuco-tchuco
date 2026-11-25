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

    // Uma opção de lista: a destacada vai em tarja branca com letra preta.
    private function desenharOpcao(dc as Graphics.Dc, y as Number,
            texto as String, destacada as Boolean) as Void {
        var cx = dc.getWidth() / 2;
        var alt = dc.getHeight() * 15 / 100;
        if (destacada) {
            var larg = dc.getTextWidthInPixels(texto, Graphics.FONT_SMALL) + 28;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
            dc.fillRoundedRectangle(cx - larg / 2, y - alt / 2, larg, alt, 10);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(cx, y, Graphics.FONT_SMALL, texto,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    // Menu inicial: quatro opções e, embaixo, uma linha explicando a que está
    // destacada. UP/DOWN escolhem, START confirma.
    private function desenharMenu(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var aviso = _controle.avisoLigado;
        var rotulos = ["LIVRE", "CRONÔMETRO",
                aviso ? "AVISO: " + _controle.avisoMin + " MIN" : "AVISO: NÃO",
                _controle.luz ? "LUZ: LIGADA" : "LUZ: AUTO"];
        var ajudas = [
                aviso ? "aviso a cada " + _controle.avisoMin + " min"
                        : "sem aviso de tempo",
                _controle.duracaoMin + " min" + (aviso
                        ? ", aviso " + _controle.avisoMin : ", sem aviso"),
                "vale nos dois modos",
                "START troca"];
        for (var i = 0; i < rotulos.size(); i++) {
            desenharOpcao(dc, h * (20 + 17 * i) / 100, rotulos[i],
                    i == _controle.item);
        }
        dc.drawText(dc.getWidth() / 2, h * 87 / 100, Graphics.FONT_XTINY,
                ajudas[_controle.item],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Ajustes. Minutos: o valor grande no centro, "+" ao lado do botão UP e
    // "-" ao lado do DOWN. Avisos: escolha entre NÃO e SIM. START segue,
    // BACK volta.
    private function desenharAjuste(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centro = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var titulo = "TEMPO TOTAL";
        var ajuda = "START começa";
        if (_controle.tela == Tela.AVISOS) {
            titulo = "AVISOS";
            ajuda = "START confirma";
        } else if (_controle.tela == Tela.AVISO) {
            titulo = "AVISO A CADA";
            ajuda = "START grava";
        }
        dc.drawText(cx, h * 21 / 100, Graphics.FONT_SMALL, titulo, centro);
        if (_controle.tela == Tela.AVISOS) {
            desenharOpcao(dc, h * 42 / 100, "NÃO", _controle.opcao == 0);
            desenharOpcao(dc, h * 62 / 100, "SIM", _controle.opcao == 1);
        } else {
            dc.drawText(cx, h * 48 / 100, Graphics.FONT_NUMBER_HOT,
                    _controle.opcao.format("%d"), centro);
            dc.drawText(cx, h * 71 / 100, Graphics.FONT_SMALL, "MIN", centro);
            dc.drawText(w * 11 / 100, h * 48 / 100, Graphics.FONT_MEDIUM, "+", centro);
            dc.drawText(w * 17 / 100, h * 71 / 100, Graphics.FONT_MEDIUM, "-", centro);
        }
        dc.drawText(cx, h * 88 / 100, Graphics.FONT_XTINY, ajuda, centro);
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

        // Modo livre: cronômetro branco, contando para cima a partir do
        // primeiro slide passado.
        // Cronometrado: contagem regressiva, que já começa ao abrir esta tela
        // e vai do verde ao vermelho; depois do fim, mostra em vermelho
        // quanto passou ("+MM:SS").
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
