import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Telas do app.
module Tela {
    const MENU as Number = 0;       // menu inicial
    const TEMPO as Number = 1;      // cronômetro: tempo total
    const AVISOS as Number = 2;     // avisos de tempo: sim ou não
    const AVISO as Number = 3;      // avisos de tempo: a cada quantos minutos
    const SLIDES as Number = 4;     // apresentação (passador de slides)
}

// Estado do app: em que tela está, ajustes, tempo da apresentação e envio
// dos comandos ("next"/"prev") para o ntfy.
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
    // Quanto tempo o aviso do topo fica na tela depois do resultado.
    private const OK_MS as Number = 3000;
    private const ERRO_MS as Number = 10000;

    var tela as Number = Tela.MENU;
    var item as Number = 0;                     // menu: 0 livre, 1 cronômetro,
                                                // 2 aviso, 3 luz
    var opcao as Number = 0;                    // valor mostrado nos ajustes
    var cronometrado as Boolean = false;        // modo da apresentação atual
    var duracaoMin as Number = 20;              // cronômetro: tempo total
    var avisoLigado as Boolean = false;         // avisos de tempo (nos dois modos)
    var avisoMin as Number = 5;                 // aviso a cada N minutos
    var luz as Boolean = true;                  // manter a luz do visor acesa
    var status as String = "";                  // aviso do topo: último envio
    var detalhe as String = "";                 // tempo da confirmação ou erro
    var slide as Number = 1;                    // contador de slides
    var inicio as Number? = null;               // System.getTimer() do 1º clique
    var avisando as Boolean = false;            // aviso de tempo em andamento
    var saindo as Boolean = false;              // esperando o 2º BACK para sair

    private var _ocupado as Boolean = false;    // comando ainda sem resultado
    private var _noAr as Boolean = false;       // há uma requisição em andamento
    private var _fila as String? = null;        // no máximo UM comando na fila
    private var _ultimo as String = "";         // último comando publicado
    private var _id as String = "";             // id desse comando no ntfy
    private var _delta as Number = 0;           // slides ainda não confirmados
    private var _lote as Number = 0;            // comandos ainda não confirmados
    private var _tentativa as Number = 0;       // consultas já feitas
    private var _clique as Number = 0;          // System.getTimer() do envio
    private var _pausa as Timer.Timer = new Timer.Timer();
    private var _pulsos as Number = 0;          // vibrações de "OK" que faltam
    private var _statusAte as Number = 0;       // até quando o aviso do topo fica
    private var _saidaEm as Number = 0;         // quando o 1º BACK foi apertado
    private var _proxAviso as Number = 0;       // próximo aviso: segundos decorridos
    private var _fimAvisado as Boolean = false; // o fim do tempo já foi avisado
    private var _suaves as Number = 0;          // vibrações suaves ainda a dar
    private var _fortes as Number = 0;          // vibrações fortes ainda a dar

    function initialize() {
        // Os ajustes ficam guardados no relógio.
        duracaoMin = lerNumero("duracaoMin", 20);
        if (duracaoMin < 1) {
            duracaoMin = 20;
        }
        avisoMin = lerNumero("avisoMin", 5);
        if (avisoMin < 1) {
            avisoMin = 5;
        }
        item = lerNumero("modo", 0);            // o menu abre no último modo usado
        avisoLigado = lerLogico("avisoLigado", false);
        luz = lerLogico("luz", true);
    }

    private function lerLogico(chave as String, padrao as Boolean) as Boolean {
        var valor = Application.Storage.getValue(chave);
        if (valor instanceof Boolean) {
            return valor;
        }
        return padrao;
    }

    private function lerNumero(chave as String, padrao as Number) as Number {
        var valor = Application.Storage.getValue(chave);
        if (valor instanceof Number) {
            return valor;
        }
        return padrao;
    }

    // ----------------------------------------------------------------- menu

    // UP e DOWN no menu: opção anterior (-1) ou seguinte (+1).
    function moverMenu(passo as Number) as Void {
        item = (item + passo + 4) % 4;
        WatchUi.requestUpdate();
    }

    // START no menu.
    function escolherMenu() as Void {
        if (item == 0) {
            comecar(false);                     // direto para o passador livre
        } else if (item == 1) {
            opcao = duracaoMin;                 // cronômetro: pede o tempo total
            tela = Tela.TEMPO;
        } else if (item == 2) {
            opcao = avisoLigado ? 1 : 0;        // avisos: sim ou não
            tela = Tela.AVISOS;
        } else {
            luz = !luz;
            Application.Storage.setValue("luz", luz);
        }
        WatchUi.requestUpdate();
    }

    // UP (+1) e DOWN (-1) nos ajustes. Na pergunta dos avisos alternam entre
    // NÃO e SIM; nos minutos vão de 1 em 1 até 30, de 5 em 5 até 60 e de 15
    // em 15 até 180.
    function mudarOpcao(sentido as Number) as Void {
        if (tela == Tela.AVISOS) {
            opcao = 1 - opcao;
        } else {
            var passo = 15;
            if (opcao < 30 || (opcao == 30 && sentido < 0)) {
                passo = 1;
            } else if (opcao < 60 || (opcao == 60 && sentido < 0)) {
                passo = 5;
            }
            opcao += sentido * passo;
            if (opcao < 1) {
                opcao = 1;
            } else if (opcao > MAX_MIN) {
                opcao = MAX_MIN;
            }
        }
        WatchUi.requestUpdate();
    }

    // START nos ajustes: grava o que está na tela e segue.
    function avancarAjuste() as Void {
        if (tela == Tela.TEMPO) {
            duracaoMin = opcao;                 // cronômetro: já começa a contar
            Application.Storage.setValue("duracaoMin", opcao);
            comecar(true);
        } else if (tela == Tela.AVISOS && opcao == 1) {
            opcao = avisoMin;                   // SIM: pergunta de quanto em quanto
            tela = Tela.AVISO;
        } else {
            avisoLigado = (tela == Tela.AVISO);
            if (avisoLigado) {
                avisoMin = opcao;
                Application.Storage.setValue("avisoMin", opcao);
            }
            Application.Storage.setValue("avisoLigado", avisoLigado);
            tela = Tela.MENU;
        }
        WatchUi.requestUpdate();
    }

    // BACK nos ajustes: volta uma tela, sem gravar o que está na tela.
    function voltarAjuste() as Void {
        if (tela == Tela.AVISO) {
            opcao = 1;
            tela = Tela.AVISOS;
        } else {
            tela = Tela.MENU;
        }
        WatchUi.requestUpdate();
    }

    // Abre a tela de apresentação, zerada, no modo escolhido.
    private function comecar(comTempo as Boolean) as Void {
        cronometrado = comTempo;
        item = comTempo ? 1 : 0;
        Application.Storage.setValue("modo", item);
        slide = 1;
        status = "";
        detalhe = "";
        saindo = false;
        avisando = false;
        _statusAte = 0;
        _ocupado = false;                       // nada pendente da vez anterior
        _delta = 0;
        _lote = 0;
        _fila = null;
        _suaves = 0;
        _fortes = 0;
        // No cronômetro o tempo corre desde já; no modo livre, a partir do
        // primeiro slide passado.
        inicio = null;
        if (comTempo) {
            iniciarTempo();
        }
        tela = Tela.SLIDES;
    }

    // Marca o início do tempo e programa o primeiro aviso. No modo livre os
    // avisos saem a cada avisoMin minutos; no cronômetro, quando faltam
    // múltiplos de avisoMin (por exemplo: faltam 10, faltam 5).
    private function iniciarTempo() as Void {
        inicio = System.getTimer();
        _fimAvisado = false;
        _proxAviso = 0;
        if (avisoLigado) {
            var passo = avisoMin * 60;
            _proxAviso = passo;
            if (cronometrado) {
                var total = duracaoMin * 60;
                _proxAviso = total - ((total - 1) / passo) * passo;
                if (_proxAviso >= total) {
                    _proxAviso = 0;             // o tempo é menor que o intervalo
                }
            }
        }
    }

    // No cronômetro o aviso só acontece se o intervalo for menor que o tempo
    // total: com 2 minutos de tempo, um aviso a cada 5 nunca chegaria. As
    // telas usam isto para dizer, antes de começar, que o aviso não cabe.
    function avisoNaoCabe(totalMin as Number) as Boolean {
        return avisoLigado && avisoMin >= totalMin;
    }

    // BACK na apresentação: o primeiro só pergunta; um segundo BACK em 3 s
    // devolve true (e quem chamou volta para o menu).
    function pedirSaida() as Boolean {
        if (saindo) {
            return true;
        }
        saindo = true;
        _saidaEm = System.getTimer();
        WatchUi.requestUpdate();
        return false;
    }

    function irParaMenu() as Void {
        _pausa.stop();
        _pulsos = 0;
        saindo = false;
        avisando = false;
        tela = Tela.MENU;
        WatchUi.requestUpdate();
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

    // Chamado pela tela uma vez por segundo.
    function tique() as Void {
        // Tela sempre ligada: cada chamada renova o tempo da luz do visor.
        if (luz && (Attention has :backlight)) {
            Attention.backlight(true);
        }
        // A pergunta de saída se desfaz sozinha.
        if (saindo && System.getTimer() - _saidaEm > 3000) {
            saindo = false;
        }
        // Avisos de tempo (nos dois modos) e, no cronômetro, o alarme do fim.
        if (tela == Tela.SLIDES && inicio != null) {
            var seg = decorrido();
            var total = duracaoMin * 60;
            if (cronometrado && !_fimAvisado && seg >= total) {
                _fimAvisado = true;
                _fortes = FIM_TOQUES;           // o tempo acabou
            } else if (_proxAviso > 0 && seg >= _proxAviso) {
                _proxAviso += avisoMin * 60;
                if (cronometrado && _proxAviso >= total) {
                    _proxAviso = 0;             // o próximo já seria o fim
                }
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

    // O aviso do topo só aparece enquanto há um comando em andamento e por
    // alguns segundos depois do resultado.
    function statusVisivel() as Boolean {
        return _ocupado || System.getTimer() < _statusAte;
    }

    // -------------------------------------------------------------- comandos

    // Chamado pelos botões com "next" ou "prev".
    function comando(cmd as String) as Void {
        saindo = false;                         // desiste de sair
        if (inicio == null) {
            iniciarTempo();                     // modo livre: parte no 1º clique
        }
        if (_noAr) {
            _fila = cmd;                        // fila de 1: vale o último clique
            status = "ENVIANDO +1";
        } else {
            _pausa.stop();                      // não espera a conferência anterior
            _pulsos = 0;
            publicar(cmd);
        }
        WatchUi.requestUpdate();
    }

    // Etapa 1: publica o comando pelo celular (Garmin Connect, via Bluetooth).
    private function publicar(cmd as String) as Void {
        _ocupado = true;
        _noAr = true;
        _ultimo = cmd;
        _clique = System.getTimer();
        status = "ENVIANDO";
        detalhe = "";
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
            _lote += 1;
            var id = (dados instanceof Dictionary) ? dados["id"] : null;
            if (proximo != null) {
                _fila = null;
                publicar(proximo);              // outro clique: ele vai antes
            } else if (id instanceof String) {
                _id = id;
                _tentativa = 0;
                status = "CONFIRMANDO";
                _pausa.stop();
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
                _pausa.stop();
                _pausa.start(method(:conferir), ESPERA_MS, false);
            } else {
                // O ntfy recebeu o comando, mas nenhum computador confirmou.
                System.println("sem confirmacao");
                encerrar("SEM PC", (codigo == 200) ? "sem resposta"
                        : "código " + codigo);
            }
        }
        WatchUi.requestUpdate();
    }

    // O computador executou: atualiza o contador e responde uma vez para
    // cada comando confirmado (dois toques seguidos = "OK x2" e duas vibrações).
    private function confirmado() as Void {
        var quantos = _lote;
        slide += _delta;
        if (slide < 1) {
            slide = 1;
        }
        _delta = 0;
        _lote = 0;
        _ocupado = false;
        var ms = System.getTimer() - _clique;
        System.println("confirmado em " + ms + " ms (" + quantos + ")");
        status = _ultimo.equals("next") ? "OK >>" : "<< OK";
        if (quantos > 1) {
            status = "OK x" + quantos;
        }
        detalhe = (ms / 1000.0).format("%.1f") + " s";
        _statusAte = System.getTimer() + OK_MS;
        vibrar(SUAVE, CURTA_MS);
        _pulsos = ((quantos > 4) ? 4 : quantos) - 1;
        if (_pulsos > 0) {
            _pausa.stop();
            _pausa.start(method(:pulsar), 300, true);
        }
    }

    // Vibrações seguintes de um "OK" de vários comandos.
    function pulsar() as Void {
        vibrar(SUAVE, CURTA_MS);
        _pulsos -= 1;
        if (_pulsos <= 0) {
            _pausa.stop();
        }
    }

    // O comando nem chegou ao ntfy.
    private function falhar(codigo as Number) as Void {
        var texto = "SEM INTERNET";
        if (codigo == Communications.BLE_CONNECTION_UNAVAILABLE) {
            texto = "SEM CELULAR";
        } else if (codigo > 0) {
            texto = "ERRO HTTP";                // ex.: 429 = limite do ntfy
        }
        encerrar(texto, "código " + codigo);
    }

    // Fim com falha: mostra o aviso por mais tempo e dá a vibração longa.
    private function encerrar(texto as String, det as String) as Void {
        _fila = null;                           // não insiste em cima de um erro
        _delta = 0;
        _lote = 0;
        _ocupado = false;
        status = texto;
        detalhe = det;
        _statusAte = System.getTimer() + ERRO_MS;
        vibrar(SUAVE, LONGA_MS);
    }

    // No Forerunner o relógio pode ignorar a intensidade pedida, então a
    // diferença entre suave e forte vem principalmente da duração.
    private function vibrar(forca as Number, ms as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(forca, ms)]);
        }
    }
}
