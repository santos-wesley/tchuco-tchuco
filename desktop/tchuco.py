#!/usr/bin/env python3
"""Tchuco Tchuco - lado do computador.

Escuta um tópico do ntfy.sh e transforma cada mensagem em uma tecla:
    "next" -> seta direita        "prev" -> seta esquerda

Depois de cada comando, publica uma confirmação no tópico "<tópico>-ack";
é assim que o relógio sabe que existe um computador ouvindo.

Uso:
    python tchuco.py SEU_TOPICO            (ou a variável TCHUCO_TOPICO)
    python tchuco.py SEU_TOPICO --dry-run  (só imprime, não aperta teclas)
"""
import argparse
import http.client
import json
import os
import signal
import threading
import time
import urllib.request

SERVIDOR = "https://ntfy.sh"
# comando recebido -> (tecla no pynput, texto do log)
COMANDOS = {
    "next": ("right", "seta direita"),
    "prev": ("left", "seta esquerda"),
}
# Segundos sem receber nada = conexão morta. O ntfy.sh manda um "keepalive"
# a cada 45 s, então um silêncio maior que isso significa que a conexão caiu.
TIMEOUT = 60
# Teto, em segundos, da espera entre tentativas de reconexão.
ESPERA_MAX = 15


def log(texto):
    print(time.strftime("%H:%M:%S"), texto, flush=True)


def criar_apertador(dry_run):
    """Devolve a função que aperta uma tecla; no --dry-run não faz nada."""
    if dry_run:
        return lambda tecla: None
    # Importado só aqui: o --dry-run funciona mesmo sem o pynput instalado.
    from pynput.keyboard import Controller, Key

    teclado = Controller()

    def apertar(tecla):
        teclado.press(getattr(Key, tecla))
        teclado.release(getattr(Key, tecla))

    return apertar


def ler_argumentos():
    parser = argparse.ArgumentParser(
        description="Passa slides com comandos vindos do ntfy.")
    parser.add_argument(
        "topico", nargs="?", default=os.environ.get("TCHUCO_TOPICO"),
        help="tópico do ntfy (ou variável de ambiente TCHUCO_TOPICO)")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="só imprime os comandos, sem apertar teclas")
    args = parser.parse_args()
    if not args.topico:
        parser.error("informe o tópico como argumento ou na variável "
                     "de ambiente TCHUCO_TOPICO")
    return args


def confirmar(topico, id_comando):
    """Publica no tópico de confirmação o id do comando já executado."""
    try:
        pedido = urllib.request.Request(
            f"{SERVIDOR}/{topico}-ack", data=id_comando.encode())
        urllib.request.urlopen(pedido, timeout=10).close()
    except (OSError, http.client.HTTPException) as erro:
        log(f"confirmação não enviada: {erro}")


def tratar(evento, apertar, topico):
    """Trata uma linha do stream: só "next" e "prev" viram tecla."""
    if evento.get("event") != "message":
        return  # "open" e "keepalive" não são comandos
    comando = evento.get("message", "").strip().lower()
    if comando in COMANDOS:
        tecla, nome = COMANDOS[comando]
        apertar(tecla)
        log(f"{comando} -> {nome}")
        # A confirmação vai em outra thread para não atrasar o próximo
        # comando; o relógio procura por este id no tópico "<tópico>-ack".
        threading.Thread(target=confirmar, daemon=True,
                         args=(topico, evento.get("id", ""))).start()
    else:
        log(f"mensagem ignorada: {comando[:40]!r}")


def main():
    args = ler_argumentos()
    # Ctrl+C encerra na hora, mesmo no meio de uma leitura de rede.
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    apertar = criar_apertador(args.dry_run)

    # Stream JSON do ntfy: uma mensagem por linha. Sem o parâmetro "since"
    # o servidor só entrega o que for publicado DEPOIS da conexão, então
    # mensagens antigas do tópico nunca são processadas.
    url = f"{SERVIDOR}/{args.topico}/json"
    modo = " (dry-run: nenhuma tecla é apertada)" if args.dry_run else ""
    # O tópico funciona como senha: o log mostra só o começo dele.
    log(f"tópico {args.topico[:4]}... em {SERVIDOR}{modo}")

    espera = 1
    while True:
        try:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as resposta:
                for linha in resposta:
                    evento = json.loads(linha)
                    if evento.get("event") == "open":
                        log("conectado; aguardando comandos (Ctrl+C sai)")
                        espera = 1
                    tratar(evento, apertar, args.topico)
            log("o servidor encerrou a conexão")
        except (OSError, ValueError, http.client.HTTPException) as erro:
            # OSError: rede, timeout e erros HTTP.
            # ValueError: linha que não é JSON.
            log(f"conexão caiu: {erro}")
        log(f"reconectando em {espera} s")
        time.sleep(espera)
        espera = min(espera * 2, ESPERA_MAX)


if __name__ == "__main__":
    main()
