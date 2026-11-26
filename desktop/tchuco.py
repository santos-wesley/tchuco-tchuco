#!/usr/bin/env python3
"""Tchuco Tchuco - computer side.

Listens to an ntfy.sh topic and turns each message into a key press:
    "next" -> right arrow        "prev" -> left arrow

After each command it publishes a confirmation to the "<topic>-ack" topic;
that is how the watch knows a computer is listening.

Usage:
    python tchuco.py YOUR_TOPIC            (or the TCHUCO_TOPIC variable)
    python tchuco.py YOUR_TOPIC --dry-run  (only prints, presses no keys)
"""
import argparse
import http.client
import json
import os
import signal
import threading
import time
import urllib.request

SERVER = "https://ntfy.sh"
# received command -> (pynput key, text for the log)
COMMANDS = {
    "next": ("right", "right arrow"),
    "prev": ("left", "left arrow"),
}
# Seconds without receiving anything = dead connection. ntfy.sh sends a
# "keepalive" every 45 s, so a longer silence means the connection dropped.
TIMEOUT = 60
# Ceiling, in seconds, for the wait between reconnection attempts.
MAX_WAIT = 15


def log(text):
    print(time.strftime("%H:%M:%S"), text, flush=True)


def make_presser(dry_run):
    """Return the key-pressing function; with --dry-run it does nothing."""
    if dry_run:
        return lambda key: None
    # Imported only here: --dry-run works even without pynput installed.
    from pynput.keyboard import Controller, Key

    keyboard = Controller()

    def press(key):
        keyboard.press(getattr(Key, key))
        keyboard.release(getattr(Key, key))

    return press


def read_arguments():
    parser = argparse.ArgumentParser(
        description="Changes slides with commands coming from ntfy.")
    parser.add_argument(
        "topic", nargs="?", default=os.environ.get("TCHUCO_TOPIC"),
        help="ntfy topic (or the TCHUCO_TOPIC environment variable)")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="only print the commands, without pressing keys")
    args = parser.parse_args()
    if not args.topic:
        parser.error("give the topic as an argument or in the TCHUCO_TOPIC "
                     "environment variable")
    return args


def confirm(topic, command_id):
    """Publish the id of the command just executed to the ack topic."""
    try:
        request = urllib.request.Request(
            f"{SERVER}/{topic}-ack", data=command_id.encode())
        urllib.request.urlopen(request, timeout=10).close()
    except (OSError, http.client.HTTPException) as error:
        log(f"confirmation not sent: {error}")


def handle(event, press, topic):
    """Handle one line of the stream: only "next" and "prev" become keys."""
    if event.get("event") != "message":
        return  # "open" and "keepalive" are not commands
    command = event.get("message", "").strip().lower()
    if command in COMMANDS:
        key, name = COMMANDS[command]
        press(key)
        log(f"{command} -> {name}")
        # The confirmation goes in another thread so it does not delay the
        # next command; the watch looks for this id in "<topic>-ack".
        threading.Thread(target=confirm, daemon=True,
                         args=(topic, event.get("id", ""))).start()
    else:
        log(f"ignored message: {command[:40]!r}")


def main():
    args = read_arguments()
    # Ctrl+C quits right away, even in the middle of a network read.
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    press = make_presser(args.dry_run)

    # ntfy's JSON stream: one message per line. Without the "since" parameter
    # the server only delivers what is published AFTER the connection, so old
    # messages in the topic are never processed.
    url = f"{SERVER}/{args.topic}/json"
    mode = " (dry-run: no keys are pressed)" if args.dry_run else ""
    # The topic works as a password: the log shows only its beginning.
    log(f"topic {args.topic[:4]}... on {SERVER}{mode}")

    wait = 1
    while True:
        try:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
                for line in response:
                    event = json.loads(line)
                    if event.get("event") == "open":
                        log("connected; waiting for commands (Ctrl+C quits)")
                        wait = 1
                    handle(event, press, args.topic)
            log("the server closed the connection")
        except (OSError, ValueError, http.client.HTTPException) as error:
            # OSError: network, timeout and HTTP errors.
            # ValueError: a line that is not JSON.
            log(f"connection lost: {error}")
        log(f"reconnecting in {wait} s")
        time.sleep(wait)
        wait = min(wait * 2, MAX_WAIT)


if __name__ == "__main__":
    main()
