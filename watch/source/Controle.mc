import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Estado da apresentação e envio dos comandos ("next"/"prev") para o ntfy.
//
// Cada comando passa por duas etapas, sempre uma requisição por vez:
//   1) publicar ("ENVIANDO"): POST do comando no ntfy;
//   2) conferir ("CONFIRMANDO"): o script do computador publica o id do
//      comando no tópico "<tópico>-ack" e o relógio consulta esse tópico.
// O "OK" só aparece depois da confirmação do computador. Um clique novo tem
// prioridade sobre a conferência do comando anterior.
class Controle {
    private const TENTATIVAS as Number = 3;        // consultas antes de desistir
    private const ESPERA_MS as Number = 700;       // pausa antes de cada consulta
    private const VIBRA_FORCA as Number = 25;      // 0 a 100 (veja vibrar)
    private const VIBRA_CURTA as Number = 50;      // ms: confirmado, aviso de tempo
    private const VIBRA_LONGA as Number = 300;     // ms: falha
    private const AVISO_TOQUES as Number = 3;      // vibrações por aviso, 1 por s
    // Opções do aviso de tempo, em minutos (0 = desligado).
    private const OPCOES as Array<Number> = [0, 1, 2, 3, 5, 10, 15, 20, 30];

    var saindo as Boolean = false;              // esperando o 2º BACK para sair
    var ajustando as Boolean = false;           // escolhendo o aviso de tempo
    var opcao as Number = 0;                    // minutos mostrados no ajuste
    var status as String = "PRONTO";            // situação do último envio
    var detalhe as String = "";                 // tempo da confirmação ou erro
    var cor as Graphics.ColorType = Graphics.COLOR_BLACK;   // faixa de status
    var slide as Number = 1;                    // contador de slides
    var inicio as Number? = null;               // System.getTimer() do 1º clique
    var avisoMin as Number = 5;                 // aviso de tempo: minutos (0 = não)
    var avisando as Boolean = false;            // aviso de tempo em andamento

    private var _noAr as Boolean = false;       // há uma requisição em andamento
    private var _fila as String? = null;        // no máximo UM comando na fila
    private var _ultimo as String = "";         // último comando publicado
    private var _id as String = "";             // id desse comando no ntfy
    private var _delta as Number = 0;           // slides ainda não confirmados
    private var _tentativa as Number = 0;       // consultas já feitas
    private var _clique as Number = 0;          // System.getTimer() do envio
    private var _pausa as Timer.Timer = new Timer.Timer();
    private var _avisos as Number = 0;          // avisos de tempo já dados
    private var _toques as Number = 0;          // vibrações que faltam no aviso
    private var _modoEm as Number = 0;          // último botão em saindo/ajustando

    function initialize() {
        // O intervalo do aviso de tempo fica guardado no relógio.
        var salvo = Application.Storage.getValue("avisoMin");
        if (salvo instanceof Number) {
            avisoMin = salvo;
        }
    }

    // BACK: o primeiro só pergunta; um segundo BACK em 3 s devolve true.
    function pedirSaida() as Boolean {
        if (saindo) {
            return true;
        }
        saindo = true;
        _modoEm = System.getTimer();
        WatchUi.requestUpdate();
        return false;
    }

    // Segurar UP: entra no ajuste do aviso de tempo.
    function abrirAjuste() as Void {
        saindo = false;
        ajustando = true;
        opcao = avisoMin;
        _modoEm = System.getTimer();
        WatchUi.requestUpdate();
    }

    // UP e DOWN no ajuste: opção anterior (-1) ou seguinte (+1).
    function mudarOpcao(passo as Number) as Void {
        var total = OPCOES.size();
        opcao = OPCOES[(OPCOES.indexOf(opcao) + passo + total) % total];
        _modoEm = System.getTimer();
        WatchUi.requestUpdate();
    }

    // START grava a opção no relógio; BACK sai sem gravar.
    function fecharAjuste(gravar as Boolean) as Void {
        if (gravar) {
            avisoMin = opcao;
            Application.Storage.setValue("avisoMin", opcao);
            _avisos = marcos();                 // conta os próximos a partir daqui
            _toques = 0;
        }
        ajustando = false;
        WatchUi.requestUpdate();
    }

    // Quantos intervalos de aviso já se passaram desde o início.
    private function marcos() as Number {
        var ini = inicio;
        if (ini == null || avisoMin <= 0) {
            return 0;
        }
        return (System.getTimer() - ini) / 60000 / avisoMin;
    }

    // Chamado pelos botões com "next" ou "prev".
    function comando(cmd as String) as Void {
        saindo = false;                         // desiste de sair
        if (inicio == null) {
            inicio = System.getTimer();         // o cronômetro parte no 1º clique
        }
        if (_noAr) {
            _fila = cmd;                        // fila de 1: vale o último clique
            status = "ENVIANDO +1";
        } else {
            _pausa.stop();                      // não espera a conferência anterior
            publicar(cmd);
        }
        WatchUi.requestUpdate();
    }

    // Etapa 1: publica o comando pelo celular (Garmin Connect, via Bluetooth).
    private function publicar(cmd as String) as Void {
        _noAr = true;
        _ultimo = cmd;
        _clique = System.getTimer();
        mostrar("ENVIANDO", "", Graphics.COLOR_YELLOW);
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
            method(:aoPublicar)
        );
    }

    // Resposta do ntfy: 200 = publicado; outro valor positivo = erro HTTP;
    // zero ou negativo = erro do Connect IQ (Bluetooth, celular ou rede).
    function aoPublicar(codigo as Number,
            dados as Dictionary or String or Null) as Void {
        _noAr = false;
        // Aparece no console do simulador e no log do relógio.
        System.println("envio de " + _ultimo + ": " + codigo);
        var proximo = _fila;
        if (codigo != 200) {
            falhar(codigo);
        } else {
            _delta += _ultimo.equals("next") ? 1 : -1;
            var id = (dados instanceof Dictionary) ? dados["id"] : null;
            if (proximo != null) {
                _fila = null;
                publicar(proximo);              // outro clique: ele vai antes
            } else if (id instanceof String) {
                _id = id;
                _tentativa = 0;
                status = "CONFIRMANDO";
                _pausa.start(method(:conferir), ESPERA_MS, false);
            } else {
                confirmado();                   // sem id não há o que conferir
            }
        }
        WatchUi.requestUpdate();
    }

    // Etapa 2: lê as confirmações recentes. O formato "raw" do ntfy devolve
    // texto puro (um id por linha), que o Connect IQ aceita como TEXT_PLAIN.
    function conferir() as Void {
        _noAr = true;
        _tentativa += 1;
        Communications.makeWebRequest(
            Config.URL_BASE + "/" + Config.TOPICO + "-ack/raw",
            // "n" só muda a URL a cada consulta, para o celular não usar cache
            { "poll" => "1", "since" => "30s", "n" => System.getTimer() },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType =>
                    Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            },
            method(:aoConferir)
        );
    }

    function aoConferir(codigo as Number,
            dados as Dictionary or String or Null) as Void {
        _noAr = false;
        System.println("consulta " + _tentativa + ": " + codigo);
        var achou = false;
        if (codigo == 200 && dados instanceof String) {
            achou = (dados.find(_id) != null);
        }
        var proximo = _fila;
        if (achou) {
            confirmado();
        }
        if (proximo != null) {
            _fila = null;
            publicar(proximo);                  // um clique novo tem prioridade
        } else if (!achou) {
            if (codigo == Communications.BLE_CONNECTION_UNAVAILABLE) {
                falhar(codigo);
            } else if (_tentativa < TENTATIVAS) {
                _pausa.start(method(:conferir), ESPERA_MS, false);
            } else {
                // O ntfy recebeu o comando, mas nenhum computador confirmou.
                System.println("sem confirmacao");
                _delta = 0;
                mostrar("SEM PC", (codigo == 200) ? "sem resposta"
                        : "código " + codigo, Graphics.COLOR_RED);
                vibrar(VIBRA_LONGA);
            }
        }
        WatchUi.requestUpdate();
    }

    // O computador executou o comando: atualiza o contador e avisa.
    private function confirmado() as Void {
        slide += _delta;
        if (slide < 1) {
            slide = 1;
        }
        _delta = 0;
        var ms = System.getTimer() - _clique;
        System.println("confirmado em " + ms + " ms");
        mostrar(_ultimo.equals("next") ? "OK >>" : "<< OK",
                (ms / 1000.0).format("%.1f") + " s", Graphics.COLOR_GREEN);
        vibrar(VIBRA_CURTA);
    }

    // O comando nem chegou ao ntfy.
    private function falhar(codigo as Number) as Void {
        _fila = null;                           // não insiste em cima de um erro
        _delta = 0;
        var texto = "SEM INTERNET";
        if (codigo == Communications.BLE_CONNECTION_UNAVAILABLE) {
            texto = "SEM CELULAR";
        } else if (codigo > 0) {
            texto = "ERRO HTTP";                // ex.: 429 = limite do ntfy
        }
        mostrar(texto, "código " + codigo, Graphics.COLOR_RED);
        vibrar(VIBRA_LONGA);
    }

    private function mostrar(texto as String, det as String,
            c as Graphics.ColorType) as Void {
        status = texto;
        detalhe = det;
        cor = c;
    }

    // Chamado pela tela uma vez por segundo: a cada avisoMin minutos de
    // apresentação dá AVISO_TOQUES vibrações curtas, uma por segundo.
    function tique() as Void {
        // A pergunta de saída e o ajuste se desfazem sozinhos se ninguém mexer.
        var parado = System.getTimer() - _modoEm;
        if (parado > 3000) {
            saindo = false;
        }
        if (parado > 8000) {
            ajustando = false;
        }
        var agora = marcos();
        if (agora > _avisos) {
            _avisos = agora;
            _toques = AVISO_TOQUES;
        }
        avisando = (_toques > 0);
        if (avisando) {
            _toques -= 1;
            vibrar(VIBRA_CURTA);
        }
    }

    // Vibração suave. No Forerunner o relógio pode ignorar a intensidade
    // pedida, então a suavidade vem principalmente da duração curta.
    private function vibrar(ms as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(VIBRA_FORCA, ms)]);
        }
    }
}
