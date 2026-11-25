# Tchuco Tchuco

Passador de slides usando um Garmin Forerunner 955 / 955 Solar.

```
relógio (app Connect IQ)
   │  Bluetooth
   ▼
celular pareado (Garmin Connect)
   │  HTTPS POST
   ▼
ntfy.sh  ◄──── stream ────  computador (desktop/tchuco.py)
                             "next" → seta direita
                             "prev" → seta esquerda
```

O relógio e o computador podem estar em redes diferentes: o único ponto de
encontro é um tópico do [ntfy.sh](https://ntfy.sh). Não há servidor próprio,
app de celular, banco de dados nem login.

| Pasta | O que é |
|---|---|
| `watch/` | App do relógio (Connect IQ, Monkey C, alvo `fr955`) |
| `desktop/` | Script do computador (Python 3, um arquivo, Windows e macOS) |

## Botões do relógio

| Botão | Ação |
|---|---|
| START (superior direito) | próximo slide (`next`) |
| DOWN (inferior esquerdo) | próximo slide (`next`) |
| UP (meio esquerdo) | slide anterior (`prev`) |
| BACK (inferior direito) | pergunta "Sair?" antes de fechar o app |
| Toques e deslizes na tela | ignorados |

A tela mostra, de cima para baixo: o status do último envio (faixa amarela =
enviando, verde = enviado, vermelha = falhou, com o código do erro), o
cronômetro da apresentação (começa no primeiro clique) e o contador de
slides. Vibração curta = enviado; vibração longa = falhou.

![Telas do app no simulador](docs/telas.png)

## 1. O tópico (é a sua senha)

Quem souber o nome do tópico consegue passar os seus slides, então use um nome
longo e aleatório e não o coloque no git. Para gerar um:

```
python -c "import secrets; print('tchuco-' + secrets.token_hex(16))"
```

O mesmo tópico vai em dois lugares:

1. **Relógio:** copie `watch/Config.mc.exemplo` para `watch/source/Config.mc`
   (arquivo ignorado pelo git) e troque o valor de `TOPICO`. Esse é o único
   arquivo com a URL base e o tópico. Não crie outra cópia com extensão `.mc`
   dentro de `watch/`: o compilador junta todos os `.mc` da pasta.
2. **Computador:** variável de ambiente `TCHUCO_TOPICO` ou argumento do script.

## 2. Computador

Requisitos: Python 3 (testado com o 3.13) e o pacote `pynput`.

```
python -m venv .venv
.venv\Scripts\activate          (macOS: source .venv/bin/activate)
pip install pynput
```

Para rodar (deixe a apresentação em primeiro plano, em modo de exibição):

```
# Windows (PowerShell)
$env:TCHUCO_TOPICO = "seu-topico"
python desktop\tchuco.py

# macOS
export TCHUCO_TOPICO="seu-topico"
python desktop/tchuco.py
```

Também funciona `python desktop/tchuco.py seu-topico`, mas assim o tópico fica
visível no terminal; prefira a variável de ambiente se a tela estiver sendo
projetada. `--dry-run` só imprime os comandos, sem apertar teclas (nesse modo
o `pynput` nem precisa estar instalado). `Ctrl+C` encerra.

O script só processa mensagens publicadas depois que ele conectou, e
reconecta sozinho se a conexão cair.

**macOS:** na primeira execução, autorize o terminal em *Ajustes do Sistema →
Privacidade e Segurança → Acessibilidade*; sem isso o sistema descarta as
teclas em silêncio. Se aparecer `CERTIFICATE_VERIFY_FAILED` (Python instalado
pelo python.org), rode uma vez o `Install Certificates.command` que fica na
pasta do Python em *Aplicativos*.

## 3. Relógio

### 3.1 Instalar o SDK (uma vez)

1. Instale o Java 11 ou mais novo.
2. Em <https://developer.garmin.com/connect-iq/sdk/>, baixe o **SDK Manager**,
   extraia em uma pasta e abra.
3. Aceite o contrato e faça login com a sua conta Garmin.
4. Na aba **SDK**, baixe a versão mais recente e marque-a como SDK ativo.
5. Na aba **Devices**, baixe só o **Forerunner® 955 / Solar**. Todos os
   dispositivos juntos, com as fontes, ocupam cerca de 1,5 GB.
6. (Opcional) No VS Code, instale a extensão **Monkey C** e rode
   *Monkey C: Verify Installation*.

### 3.2 Chave de desenvolvedor (uma vez)

O compilador assina o app com uma chave RSA de 4096 bits. Guarde-a: ela não
vai para o git.

```
openssl genrsa -out watch/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in watch/developer_key.pem -out watch/developer_key.der -nocrypt
```

No Windows o `openssl` vem junto com o Git
(`C:\Program Files\Git\usr\bin\openssl.exe`). Outra opção é o comando
*Monkey C: Generate a Developer Key* do VS Code.

### 3.3 Compilar

```
# Windows (PowerShell)
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
& "$sdk\bin\monkeyc.bat" -d fr955 -f watch\monkey.jungle -o watch\bin\TchucoTchuco.prg -y watch\developer_key.der -w -r

# macOS
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
"$SDK/bin/monkeyc" -d fr955 -f watch/monkey.jungle -o watch/bin/TchucoTchuco.prg -y watch/developer_key.der -w -r
```

- `fr955` vale para o Forerunner 955 e para o 955 Solar.
- `-w` mostra os avisos do compilador; a checagem de tipos estrita já está
  ligada no `watch/monkey.jungle`.
- `-r` gera a versão enxuta, que é a que vai para o relógio. Sem o `-r` sai a
  versão de depuração, que também roda no simulador.

Com o SDK 9.3.0 o resultado esperado é `BUILD SUCCESSFUL`, sem avisos.

### 3.4 Rodar no simulador

```
# Windows (PowerShell)
& "$sdk\bin\connectiq.bat"
& "$sdk\bin\monkeydo.bat" watch\bin\TchucoTchuco.prg fr955

# macOS
"$SDK/bin/connectiq"
"$SDK/bin/monkeydo" watch/bin/TchucoTchuco.prg fr955
```

O primeiro comando abre o simulador; o segundo carrega o app e fica mostrando
o que ele imprime (por exemplo `envio de next: 200`). Clique com o mouse nos
botões do relógio desenhado na tela. O simulador faz a requisição HTTPS de
verdade a partir do computador, então o caminho inteiro é testado, menos o
Bluetooth e o celular.

Menus úteis do simulador:

- *Settings → Connection Type → BLE → Not Connected*: simula o celular
  desconectado (o app mostra "SEM CELULAR", código -104).
- *File → View HTTP Traffic*: mostra as requisições feitas pelo app.

### 3.5 Copiar para o relógio

1. Conecte o relógio no USB.
2. Copie `watch/bin/TchucoTchuco.prg` para a pasta `GARMIN/APPS` do relógio.
   O 955 aparece como dispositivo de mídia (MTP): no Windows ele surge no
   Explorador de Arquivos; no macOS é preciso um programa de MTP, como o
   OpenMTP, e o Garmin Express precisa estar fechado.
3. Desconecte o cabo. O app aparece na lista de atividades e apps.

Para ver os `System.println` do app no relógio, crie antes um arquivo vazio
com o mesmo nome do `.prg` na pasta de logs: `GARMIN/APPS/LOGS/TchucoTchuco.TXT`.

## Por que o POST é em JSON

O plano inicial era um `POST` com o texto `next` para `https://ntfy.sh/<tópico>`.
No fr955 isso não é possível, e o formato escolhido foi o seguinte:

- **Requisição:** `POST https://ntfy.sh/` com `Content-Type: application/json`
  e o corpo `{"topic": "<tópico>", "message": "next"}` (o "Publish as JSON" do
  ntfy, que exige a URL raiz, e não a URL do tópico).
- **Resposta:** o ntfy devolve a mensagem publicada como objeto JSON, com
  `Content-Type: application/json`.

Motivos:

- O `Communications.makeWebRequest` recebe os dados como um dicionário e os
  serializa como JSON ou como formulário. Corpo de texto puro só existe com a
  opção `:body`, disponível a partir do Connect IQ 6.0.3; o 955 está na API 5.2.
- Sem informar o `Content-Type`, um `POST` sai como
  `application/x-www-form-urlencoded`, e o ntfy usa o corpo inteiro como texto
  da mensagem: chegaria `message=next` em vez de `next`.
- Com `:responseType => HTTP_RESPONSE_CONTENT_TYPE_JSON`, o Connect IQ exige
  que a resposta venha como `application/json` com um JSON válido; senão o
  callback recebe o erro -400 ou -1002 mesmo com a mensagem publicada.

Conferido com `curl` no ntfy.sh:

| Requisição | Mensagem publicada |
|---|---|
| JSON na URL raiz (formato usado) | `next` |
| Formulário `message=next` na URL do tópico | `message=next` |
| JSON `{"message":"next"}` na URL do tópico | `{"message":"next"}` |

No simulador, esse formato recebe a resposta 200 do ntfy.sh em menos de 1
segundo e o script do computador recebe o comando.

## Roteiro de teste

**1. Só o computador, com curl**

```
python desktop/tchuco.py --dry-run
```

Em outro terminal (no PowerShell use `curl.exe`, porque `curl` é um apelido de
outro comando):

```
curl.exe -d "next" "https://ntfy.sh/$env:TCHUCO_TOPICO"      (PowerShell)
curl -d "prev" "https://ntfy.sh/$TCHUCO_TOPICO"              (macOS)
```

O script deve imprimir `next -> seta direita` e `prev -> seta esquerda`. Uma
mensagem publicada antes de o script conectar não pode aparecer.

**2. Computador apertando teclas**

Abra a apresentação em modo de exibição, rode o script sem `--dry-run` e
repita os comandos `curl`: o slide deve avançar e voltar.

**3. Simulador**

Com o script rodando em `--dry-run`, abra o app no simulador (seção 3.4):

- START e DOWN: o terminal do `monkeydo` mostra `envio de next: 200`, o script
  imprime `next -> seta direita`, a faixa fica verde e o contador sobe;
- UP: `prev`, e o contador desce;
- o cronômetro começa no primeiro clique;
- clicar ou arrastar o mouse sobre a tela do relógio não faz nada;
- BACK pergunta "Sair?"; *Cancel* volta ao app e *Confirm* fecha;
- com *BLE → Not Connected*: faixa vermelha, "SEM CELULAR" e nada chega ao
  script.

**4. Relógio de verdade**

Com o celular por perto, Bluetooth ligado e o Garmin Connect aberto:

- START, DOWN e UP passam os slides, com vibração curta;
- com o Bluetooth do celular desligado: vibração longa e "SEM CELULAR";
- com o celular em modo avião e Bluetooth ligado: vibração longa e uma
  mensagem de falha com o código do erro;
- toques e deslizes na tela não fazem nada; BACK pergunta antes de sair;
- deixe o app aberto pelo tempo de uma apresentação e confira se ele
  continua na tela.

## Limitações conhecidas

- **Latência.** Cada clique passa por Bluetooth, celular, internet e ntfy.
  Não é instantâneo e varia com o celular e a rede; se o Garmin Connect
  estiver "dormindo" no celular, o primeiro clique pode demorar mais.
- **Depende de internet nos dois lados** e do ntfy.sh estar no ar. Não há
  modo offline.
- **Envio pendurado.** Quem decide quando desistir de uma requisição é o
  sistema, não o app. No simulador, um servidor que não responde levou 21
  segundos para virar erro; nesse intervalo a faixa fica amarela.
- **Fila de um comando.** Enquanto um envio está pendente, só o último clique
  fica guardado; três cliques muito rápidos viram dois comandos.
- **O contador de slides é local.** Ele conta os envios confirmados pelo ntfy,
  não o que o computador fez. Começa em 1 e não sabe quantos slides existem.
- **Limites do ntfy.sh gratuito** (por endereço IP): 250 mensagens por dia,
  rajada de 60 requisições e depois uma a cada 5 segundos, mensagens de até
  4.096 bytes, 30 conexões simultâneas. Ao estourar o limite o relógio mostra
  "ERRO HTTP" com o código 429. Numa rede compartilhada o limite é dividido
  com as outras pessoas.
- **O tópico é público.** Quem souber o nome pode publicar (e apertar as setas
  no seu computador) ou escutar. Troque o tópico se ele vazar. O script só
  aceita `next` e `prev`.
- **Cliques feitos durante uma queda do computador são descartados**, de
  propósito, para os slides não pularem sozinhos na reconexão. As mensagens
  ficam 12 horas no cache do ntfy, mas o script nunca lê o cache.
- **Queda silenciosa.** Se a conexão do computador morrer sem aviso, o script
  pode levar até 60 segundos para perceber e reconectar.
- **As teclas vão para a janela em primeiro plano.** A apresentação precisa
  estar em foco. No Windows, se o programa da apresentação estiver rodando
  como administrador, o script também precisa estar.
- **macOS:** exige a permissão de Acessibilidade para o terminal.
- **O computador não pode entrar em suspensão**; o script não impede isso.
- **Vibração.** No Forerunner a intensidade é fixa; só a duração muda.
- **Toque.** No 955, deslizar o dedo para a direita chega ao app como o botão
  BACK. O app separa os dois casos (só o botão físico gera o evento de "tecla
  apertada"); isso funcionou no simulador e ainda precisa ser conferido no
  relógio. A pergunta "Sair?" é uma tela do sistema e aceita toque. Segurar os
  botões aciona os atalhos do próprio relógio.
- **O simulador não reproduz tudo.** Ele não tem Bluetooth, celular nem motor
  de vibração, e devolve 404 quando o servidor é inalcançável, em vez do
  código de erro que o relógio daria.
