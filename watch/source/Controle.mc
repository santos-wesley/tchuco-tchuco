import Toybox.Attention;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Estado da apresentação e envio dos comandos ("next"/"prev") para o ntfy.
class Controle {
    var status as String = "PRONTO";            // resultado do último envio
    var detalhe as String = "";                 // código do erro, quando falha
    var cor as Graphics.ColorType = Graphics.COLOR_BLACK;   // faixa de status
    var slide as Number = 1;                    // contador de slides
    var inicio as Number? = null;               // System.getTimer() do 1º clique

    private var _pendente as String? = null;    // comando aguardando resposta
    private var _fila as String? = null;        // no máximo UM comando na fila

    // Chamado pelos botões com "next" ou "prev".
    function comando(cmd as String) as Void {
        if (inicio == null) {
            inicio = System.getTimer();         // o cronômetro parte no 1º clique
        }
        if (_pendente == null) {
            enviar(cmd);
        } else {
            _fila = cmd;                        // fila de 1: vale o último clique
            status = "ENVIANDO +1";
        }
        WatchUi.requestUpdate();
    }

    // Publica o comando no ntfy pelo celular (Garmin Connect, via Bluetooth).
    private function enviar(cmd as String) as Void {
        _pendente = cmd;
        status = "ENVIANDO";
        detalhe = "";
        cor = Graphics.COLOR_YELLOW;
        // "Publish as JSON" do ntfy: POST na URL base com o tópico no corpo.
        // No fr955 o makeWebRequest só envia dicionários (não há corpo de texto
        // puro), e com :responseType JSON a resposta precisa ser application/json,
        // que é exatamente o que o ntfy devolve.
        Communications.makeWebRequest(
            Config.URL_BASE + "/",
            { "topic" => Config.TOPICO, "message" => cmd },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:aoResponder)
        );
    }

    // Resposta do envio: 200 = publicado; outro valor positivo = erro HTTP;
    // zero ou negativo = erro do Connect IQ (Bluetooth, celular ou rede).
    function aoResponder(codigo as Number,
            dados as Dictionary or String or Null) as Void {
        var cmd = _pendente;
        _pendente = null;
        // Aparece no console do simulador e no log do relógio.
        System.println("envio de " + cmd + ": " + codigo);
        if (codigo == 200) {
            if ("next".equals(cmd)) {
                slide += 1;
                status = "OK >>";
            } else {
                if (slide > 1) {
                    slide -= 1;
                }
                status = "<< OK";
            }
            cor = Graphics.COLOR_GREEN;
            vibrar(150);                        // vibração curta: enviado
            var proximo = _fila;
            _fila = null;
            if (proximo != null) {
                enviar(proximo);                // agora é a vez do comando da fila
            }
        } else {
            _fila = null;                       // não insiste em cima de um erro
            if (codigo == Communications.BLE_CONNECTION_UNAVAILABLE) {
                status = "SEM CELULAR";
            } else if (codigo > 0) {
                status = "ERRO HTTP";           // ex.: 429 = limite do ntfy
            } else {
                status = "SEM INTERNET";
            }
            detalhe = "código " + codigo;
            cor = Graphics.COLOR_RED;
            vibrar(1000);                       // vibração longa: falhou
        }
        WatchUi.requestUpdate();
    }

    // No Forerunner só a duração muda (a intensidade é sempre a mesma).
    private function vibrar(ms as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, ms)]);
        }
    }
}
