import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Tela única, pensada para o visor MIP: fundo preto, letras grandes, uma
// faixa colorida no topo com o resultado do último envio e o tempo no centro.
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

    // Enquanto a tela está visível, redesenha 1x por segundo (tempo e avisos).
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
        _controle.tique();      // avisos de tempo, quando for a hora
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var largura = dc.getWidth();
        var altura = dc.getHeight();
        var cx = largura / 2;
        var centro = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Faixa do topo. Normalmente mostra o último envio: amarelo = enviando
        // ou confirmando, verde = confirmado pelo computador, vermelho = falhou.
        // Fica branca na pergunta de saída e nos ajustes.
        var cor = _controle.cor;
        var status = _controle.status;
        var detalhe = _controle.detalhe;
        var rodape = "SLIDE " + _controle.slide;
        var fonteRodape = Graphics.FONT_MEDIUM;
        if (_controle.ajuste != 0) {
            var tempoTotal = (_controle.ajuste == 1);
            cor = Graphics.COLOR_WHITE;
            detalhe = tempoTotal ? "tempo total" : "aviso a cada";
            if (_controle.opcao > 0) {
                status = _controle.opcao + " MIN";
            } else {
                status = tempoTotal ? "LIVRE" : "DESLIGADO";
            }
            rodape = "START GRAVA";
            fonteRodape = Graphics.FONT_SMALL;
        } else if (_controle.saindo) {
            cor = Graphics.COLOR_WHITE;
            detalhe = "para sair";
            status = "BACK DE NOVO";
        } else if (_controle.inicio == null && _controle.duracaoMin > 0) {
            // Antes de começar, lembra o aviso que está configurado.
            detalhe = (_controle.avisoMin > 0)
                    ? "aviso: " + _controle.avisoMin + " min" : "sem aviso";
        }
        dc.setColor(cor, cor);
        dc.fillRectangle(0, 0, largura, altura * 33 / 100);
        var fundoEscuro = (cor == Graphics.COLOR_BLACK || cor == Graphics.COLOR_RED);
        dc.setColor(fundoEscuro ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK,
                Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, altura * 9 / 100, Graphics.FONT_XTINY, detalhe, centro);
        dc.drawText(cx, altura * 21 / 100, Graphics.FONT_SMALL, status, centro);

        // Tempo no centro. Modo livre: cronômetro branco, contando para cima.
        // Modo cronometrado: contagem regressiva que vai do verde ao vermelho;
        // depois do fim, mostra em vermelho quanto passou ("+MM:SS").
        var seg = _controle.decorrido();
        var corTempo = Graphics.COLOR_WHITE as Graphics.ColorType;
        var sinal = "";
        if (_controle.duracaoMin > 0) {
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
        var tempo = sinal + ((seg % 3600) / 60).format("%02d") + ":"
                + (seg % 60).format("%02d");
        if (seg >= 3600) {
            tempo = sinal + (seg / 3600).format("%d") + ":" + tempo.substring(
                    sinal.length(), tempo.length());
        }
        // Na maior fonte de números que couber.
        var fonte = Graphics.FONT_NUMBER_THAI_HOT;
        if (dc.getTextWidthInPixels(tempo, fonte) > largura - 20) {
            fonte = Graphics.FONT_NUMBER_HOT;
        }
        if (dc.getTextWidthInPixels(tempo, fonte) > largura - 20) {
            fonte = Graphics.FONT_NUMBER_MEDIUM;
        }
        if (_controle.avisando) {
            // Aviso de tempo: o meio da tela acende na cor do momento.
            dc.setColor(corTempo, corTempo);
            dc.fillRectangle(0, altura * 36 / 100, largura, altura * 35 / 100);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(corTempo, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(cx, altura * 53 / 100, fonte, tempo, centro);

        // Embaixo: contador de slides (ou a dica dos ajustes).
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, altura * 83 / 100, fonteRodape, rodape, centro);
    }
}
