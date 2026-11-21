#!/usr/bin/env python3
"""Log into a QEMU serial console and run a shell script from the host.

Usage: qemu-serial-run.py SOCKET LOG PAYLOAD [SUMMARY]

The payload is base64-encoded and written to /tmp/remote-payload.sh in the guest,
then executed with sudo (the live user has passwordless sudo). Every guest byte
is mirrored into LOG; SUMMARY gets the payload output between its BEGIN/END
markers only.
"""
import base64
import os
import re
import socket
import sys
import time

SOCK, LOG, PAYLOAD = sys.argv[1], sys.argv[2], sys.argv[3]
SUMMARY = sys.argv[4] if len(sys.argv) > 4 else ""
USER = os.environ.get("LIVE_USER", "liveuser")
PASSWORD = os.environ.get("LIVE_PASS", "live")
LOGIN_TIMEOUT = float(os.environ.get("LOGIN_TIMEOUT", "420"))
# The live session needs sudo (passwordless there); an installed system must not,
# so its checks run unprivileged.
USE_SUDO = os.environ.get("USE_SUDO", "1") != "0"
RUN_TIMEOUT = float(os.environ.get("RUN_TIMEOUT", "3600"))
ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b[()][B0]")

log = open(LOG, "ab", buffering=0)
seen = b""


def connect(path, tries=240):
    for _ in range(tries):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path)
            s.settimeout(0.5)
            return s
        except OSError:
            time.sleep(0.25)
    print("serial socket unavailable", file=sys.stderr)
    raise SystemExit(3)


def pump():
    global seen
    try:
        data = sock.recv(65536)
    except (socket.timeout, OSError):
        return b""
    if data:
        log.write(data)
        seen += data
    return data


def wait_for(patterns, timeout, label):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pump()
        for pat in patterns:
            if pat in seen:
                return pat
    print(f"timeout waiting for {label}", file=sys.stderr)
    return None


def send(text):
    sock.sendall(text.encode())


def wait_prompt(timeout, tail=4096):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pump()
        if b"]$ " in seen[-tail:]:
            return True
    return False


def plain(data):
    return ANSI.sub(b"", data).decode("utf-8", "replace").replace("\r", "")


sock = connect(SOCK)

if not wait_for([b"login:"], LOGIN_TIMEOUT, "login prompt"):
    with open(SUMMARY or LOG + ".summary", "w", encoding="utf-8") as fh:
        fh.write("NO LOGIN PROMPT\n\n" + plain(seen)[-4000:])
    raise SystemExit(2)

time.sleep(0.5)
send(f"{USER}\n")
if not wait_for([b"Password:"], 60, "password prompt"):
    raise SystemExit(2)
time.sleep(0.3)
send(f"{PASSWORD}\n")
time.sleep(2)
pump()
send("stty -echo\n")
wait_prompt(20)

# Ship the payload in base64 chunks: one long line would overflow the tty line
# discipline, and a heredoc over a serial link is slow and error prone.
data = base64.b64encode(open(PAYLOAD, "rb").read()).decode()
send(": > /tmp/remote-payload.b64\n")
wait_prompt(20)
for i in range(0, len(data), 700):
    chunk = data[i : i + 700]
    send(f"printf '%s' '{chunk}' >> /tmp/remote-payload.b64\n")
    if not wait_prompt(30):
        print("prompt missing while shipping payload", file=sys.stderr)
pump()

send("base64 -d /tmp/remote-payload.b64 > /tmp/remote-payload.sh && chmod +x /tmp/remote-payload.sh\n")
wait_prompt(60)

send("printf '\\n===BEGIN payload===\\n'\n")
wait_prompt(20)
runner = "sudo bash" if USE_SUDO else "bash"
send(f"{runner} /tmp/remote-payload.sh; echo PAYLOAD-EXIT:$?\n")

deadline = time.time() + RUN_TIMEOUT
while time.time() < deadline:
    pump()
    if b"PAYLOAD-EXIT:" in seen:
        break
else:
    print("payload did not finish in time", file=sys.stderr)

pump()
text = plain(seen)
m = re.search(r"===BEGIN payload===\n(.*?)PAYLOAD-EXIT:(\d+)", text, re.S)
body = m.group(1) if m else text[-20000:]
status = int(m.group(2)) if m else -1

if SUMMARY:
    with open(SUMMARY, "w", encoding="utf-8") as fh:
        fh.write(f"# Serial payload run (exit {status})\n\n```\n{body.strip()}\n```\n")

print(f"payload exit status: {status}", file=sys.stderr)
raise SystemExit(0 if status == 0 else 1)
