import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Estado da apresentação: envio dos comandos ("next"/"prev") para o ntfy,
// tempo (modo livre ou cronometrado) e ajustes.
//
// Cada comando passa por duas etapas, sempre uma requisição por vez:
//   1) publicar ("ENVIANDO"): POST do comando no ntfy;
//   2) conferir ("CONFIRMANDO"): o script do computador publica o id do
//      comando no tópico "<tópico>-ack" e o relógio consulta esse tópico.
// O "OK" só aparece depois da confirmação do computador. Um clique novo tem
// prioridade sobre a conferência do comando anterior.
class Controle {
    private const TENTATIVAS as Number = 3;     // consultas antes de desistir
    private const ESPERA_MS as Number = 700;    // pausa antes de cada consulta
    // Vibração: intensidade de 0 a 100 e duração em ms (veja vibrar).
    private const SUAVE as Number = 25;
    private const FORTE as Number = 100;
    private const CURTA_MS as Number = 50;      // confirmado e aviso de tempo
    private const LONGA_MS as Number = 300;     // falha
    private const FIM_MS as Number = 500;       // cada vibração do fim do tempo
    private const AVISO_TOQUES as Number = 3;   // vibrações suaves por aviso
    private const FIM_TOQUES as Number = 5;     // vibrações fortes no fim
    private const MAX_MIN as Number = 180;      // maior valor dos ajustes

    var status as String = "PRONTO";            // situação do último envio
    var detalhe as String = "";                 // tempo da confirmação ou erro
    var cor as Graphics.ColorType = Graphics.COLOR_BLACK;   // faixa de status
    var slide as Number = 1;                    // contador de slides
    var inicio as Number? = null;               // System.getTimer() do 1º clique
    var duracaoMin as Number = 0;               // 0 = modo livre; senão, minutos
    var avisoMin as Number = 5;                 // aviso a cada N minutos (0 = não)
    var avisando as Boolean = false;            // aviso de tempo em andamento
    var saindo as Boolean = false;              // esperando o 2º BACK para sair
    var ajuste as Number = 0;                   // 0 = fora, 1 = tempo, 2 = aviso
    var opcao as Number = 0;                    // minutos mostrados no ajuste

    private var _noAr as Boolean = false;       // há uma requisição em andamento
    private var _fila as String? = null;        // no máximo UM comando na fila
    private var _ultimo as String = "";         // último comando publicado
    private var _id as String = "";             // id desse comando no ntfy
    private var _delta as Number = 0;           // slides ainda não confirmados
    private var _tentativa as Number = 0;       // consultas já feitas
    private var _clique as Number = 0;          // System.getTimer() do envio
    private var _pausa as Timer.Timer = new Timer.Timer();
    private var _proxAviso as Number = 0;       // próximo aviso: segundos que faltam
    private var _fimAvisado as Boolean = false; // o fim do tempo já foi avisado
    private var _suaves as Number = 0;          // vibrações suaves ainda a dar
    private var _fortes as Number = 0;          // vibrações fortes ainda a dar
    private var _modoEm as Number = 0;          // último botão em saindo/ajuste

    function initialize() {
        // Os ajustes ficam guardados no relógio.
        duracaoMin = lerAjuste("duracaoMin", 0);
        avisoMin = lerAjuste("avisoMin", 5);
    }

    private function lerAjuste(chave as String, padrao as Number) as Number {
        var valor = Application.Storage.getValue(chave);
        if (valor instanceof Number) {
            return valor;
        }
        return padrao;
    }

    // ---------------------------------------------------------------- tempo

    // Segundos de apresentação já decorridos (0 antes do primeiro clique).
    function decorrido() as Number {
        var ini = inicio;
        if (ini == null) {
            return 0;
        }
        return (System.getTimer() - ini) / 1000;
    }

    // Recalcula o próximo aviso a partir do tempo que falta agora. No modo
    // cronometrado os avisos caem quando faltam múltiplos de avisoMin
    // (por exemplo: faltam 10, faltam 5).
    private function programarAvisos() as Void {
        var falta = duracaoMin * 60 - decorrido();
        var passo = avisoMin * 60;
        _proxAviso = 0;
        if (passo > 0 && falta > 0) {
            _proxAviso = ((falta - 1) / passo) * passo;
        }
        _fimAvisado = (falta <= 0);
        _suaves = 0;
        _fortes = 0;
    }

    // Chamado pela tela uma vez por segundo.
    function tique() as Void {
        // A pergunta de saída e o ajuste se desfazem sozinhos se ninguém mexer.
        var parado = System.getTimer() - _modoEm;
        if (parado > 3000) {
            saindo = false;
        }
        if (parado > 8000) {
            ajuste = 0;
        }
        // Modo cronometrado: avisos durante a contagem e alarme no fim.
        if (inicio != null && duracaoMin > 0) {
            var falta = duracaoMin * 60 - decorrido();
            if (!_fimAvisado && falta <= 0) {
                _fimAvisado = true;
                _fortes = FIM_TOQUES;           // o tempo acabou
            } else if (_proxAviso > 0 && falta <= _proxAviso) {
                _proxAviso -= avisoMin * 60;
                _suaves = AVISO_TOQUES;
            }
        }
        // Uma vibração por segundo até completar o aviso.
        avisando = (_fortes > 0 || _suaves > 0);
        if (_fortes > 0) {
            _fortes -= 1;
            vibrar(FORTE, FIM_MS);
        } else if (_suaves > 0) {
            _suaves -= 1;
            vibrar(SUAVE, CURTA_MS);
        }
    }

    // -------------------------------------------------------- sair e ajustes

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

    // Segurar UP: abre os ajustes, começando pelo tempo total.
    function abrirAjuste() as Void {
        saindo = false;
        ajuste = 1;
        opcao = duracaoMin;
        _modoEm = System.getTimer();
        WatchUi.requestUpdate();
    }

    // UP (+1) e DOWN (-1) no ajuste: de 1 em 1 minuto até 30, de 5 em 5 até
    // 60 e de 15 em 15 até 180. Zero vale "LIVRE" (tempo) ou "DESLIGADO" (aviso).
    function mudarOpcao(sentido as Number) as Void {
        var passo = 15;
        if (opcao < 30 || (opcao == 30 && sentido < 0)) {
            passo = 1;
        } else if (opcao < 60 || (opcao == 60 && sentido < 0)) {
            passo = 5;
        }
        opcao += sentido * passo;
        if (opcao < 0) {
            opcao = 0;
        } else if (opcao > MAX_MIN) {
            opcao = MAX_MIN;
        }
        _modoEm = System.getTimer();
        WatchUi.requestUpdate();
    }

    // START no ajuste: grava no relógio e passa para o ajuste seguinte.
    function gravarAjuste() as Void {
        if (ajuste == 1) {
            duracaoMin = opcao;
            Application.Storage.setValue("duracaoMin", opcao);
            ajuste = (opcao > 0) ? 2 : 0;       // no modo livre não há aviso
            opcao = avisoMin;
        } else {
            avisoMin = opcao;
            Application.Storage.setValue("avisoMin", opcao);
            ajuste = 0;
        }
        programarAvisos();
        _modoEm = System.getTimer();
        WatchUi.requestUpdate();
    }

    // BACK no ajuste: sai sem gravar o que está na tela.
    function sairDoAjuste() as Void {
        ajuste = 0;
        WatchUi.requestUpdate();
    }

    // -------------------------------------------------------------- comandos

    // Chamado pelos botões com "next" ou "prev".
    function comando(cmd as String) as Void {
        saindo = false;                         // desiste de sair
        if (inicio == null) {
            inicio = System.getTimer();         // o tempo parte no 1º clique
            programarAvisos();
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
                vibrar(SUAVE, LONGA_MS);
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
        vibrar(SUAVE, CURTA_MS);
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
        vibrar(SUAVE, LONGA_MS);
    }

    private function mostrar(texto as String, det as String,
            c as Graphics.ColorType) as Void {
        status = texto;
        detalhe = det;
        cor = c;
    }

    // No Forerunner o relógio pode ignorar a intensidade pedida, então a
    // diferença entre suave e forte vem principalmente da duração.
    private function vibrar(forca as Number, ms as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(forca, ms)]);
        }
    }
}
