#!/usr/bin/env python3
"""Drive a QEMU guest's graphical console through the QEMU monitor.

The installer test needs the real Calamares GUI: the pages a person clicks. With
`-display none` + `-device virtio-vga` the guest still renders to a framebuffer,
so the monitor's `screendump` captures the screen and `sendkey` / `mouse_move` +
`mouse_button` operate the keyboard and mouse. Screens are read back with
tesseract, so every action can be confirmed instead of assumed.

Usage:
  qemu-gui.py MONITOR_SOCK status
  qemu-gui.py MONITOR_SOCK dump  OUT.png
  qemu-gui.py MONITOR_SOCK text  OUT.png          # OCR of the screen (stdout)
  qemu-gui.py MONITOR_SOCK click X Y
  qemu-gui.py MONITOR_SOCK key   ret|tab|spc|...
  qemu-gui.py MONITOR_SOCK type  TEXT
  qemu-gui.py MONITOR_SOCK wait  OUT.png TEXT [TIMEOUT_S]

Exit status: 0 on success, 1 when `wait` timed out, 2 on a monitor error.
"""
import os
import re
import socket
import subprocess
import sys
import tempfile
import time

try:
    from PIL import Image
except ImportError:  # pragma: no cover - host tooling
    Image = None


def monitor(path, command, settle=0.35):
    """Send one monitor command and return its reply text."""
    last = None
    for _ in range(40):
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(path)
            break
        except OSError as exc:  # socket not created yet
            last = exc
            time.sleep(0.25)
    else:
        raise SystemExit(f"monitor socket {path} unavailable: {last}")
    # Short reads: the monitor keeps the connection open, so waiting for EOF
    # would cost a full socket timeout per keystroke.
    sock.settimeout(0.5)
    time.sleep(0.1)
    sock.sendall((command + "\n").encode())
    time.sleep(settle)
    data = b""
    while True:
        try:
            chunk = sock.recv(65536)
        except (TimeoutError, socket.timeout):
            break
        if not chunk:
            break
        data += chunk
        if data.endswith(b"(qemu) "):
            break
    sock.close()
    return data.decode(errors="replace")


def dump(mon, out_png):
    """Capture the screen to out_png; returns the OCR text of the capture."""
    out_png = os.path.abspath(out_png)
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    ppm = tempfile.NamedTemporaryFile(suffix=".ppm", delete=False)
    ppm.close()
    try:
        monitor(mon, f"screendump {ppm.name}", settle=0.6)
        if os.path.getsize(ppm.name) == 0:
            raise SystemExit("screendump produced no file")
        if Image is not None:
            with Image.open(ppm.name) as img:
                img.save(out_png)
        else:  # fall back to ImageMagick
            subprocess.run(["magick", ppm.name, out_png], check=True)
    finally:
        os.unlink(ppm.name)
    return ocr(out_png)


def ocr(png):
    if not os.path.exists(png):
        return ""
    # psm 6 = one uniform block of text: handles Calamares' mixed layout well and
    # keeps small button labels ("Next", "Install", "Done") that plain psm 3 drops.
    result = subprocess.run(
        ["tesseract", png, "stdout", "--psm", "6"],
        capture_output=True,
        text=True,
        errors="replace",
    )
    text = result.stdout
    # Word boxes as well: the driver clicks labels it has just read.
    return text


def ocr_words(png):
    """Return [(word, x_center, y_center)] for the current screen."""
    result = subprocess.run(
        ["tesseract", png, "stdout", "--psm", "11", "tsv"],
        capture_output=True,
        text=True,
        errors="replace",
    )
    words = []
    for line in result.stdout.splitlines()[1:]:
        cols = line.split("\t")
        if len(cols) < 12:
            continue
        text = cols[11].strip()
        if not text:
            continue
        try:
            left, top, width, height = (int(cols[i]) for i in (6, 7, 8, 9))
        except ValueError:
            continue
        words.append((text, left + width // 2, top + height // 2))
    return words


KEY_NAMES = {
    " ": "spc",
    "-": "minus",
    ".": "dot",
    "/": "slash",
    "_": "shift-minus",
    "@": "shift-2",
    ":": "shift-semicolon",
    ",": "comma",
    "=": "equal",
    "+": "shift-equal",
}


def key_name(char):
    if char in KEY_NAMES:
        return KEY_NAMES[char]
    if char.isdigit():
        return char
    if char.isalpha():
        return char if char.islower() else f"shift-{char.lower()}"
    raise SystemExit(f"no key mapping for {char!r}")


def type_text(mon, text, delay=0.06):
    for char in text:
        monitor(mon, f"sendkey {key_name(char)}", settle=delay)


def click(mon, x, y):
    monitor(mon, f"mouse_move {int(x)} {int(y)}", settle=0.25)
    monitor(mon, "mouse_button 1", settle=0.25)
    monitor(mon, "mouse_button 0", settle=0.25)


def matches(text, needle):
    """Does the screen text satisfy needle?

    OCR merges and drops spaces ("Whatis your name?"), so a plain-text needle is
    also matched against the whitespace-free screen text. Regex needles are
    matched normally.
    """
    if re.search(needle, text, re.IGNORECASE):
        return True
    if re.search(r"[\\^$.|?*+()\[\]{}]", needle):
        return False
    return re.sub(r"\s+", "", needle).lower() in re.sub(r"\s+", "", text).lower()


def wait_text(mon, out_png, needle, timeout=180):
    """Poll the screen until needle appears; returns the last OCR text."""
    deadline = time.time() + timeout
    text = ""
    while time.time() < deadline:
        text = dump(mon, out_png)
        if matches(text, needle):
            return text
        time.sleep(2)
    return text


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    mon, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if cmd == "status":
        print(monitor(mon, "info status"))
    elif cmd == "dump":
        text = dump(mon, args[0])
        print(f"--- {args[0]}")
        print(text)
    elif cmd == "text":
        print(ocr(args[0]))
    elif cmd == "words":
        for word, x, y in ocr_words(args[0]):
            print(f"{word}\t{x}\t{y}")
    elif cmd == "click":
        click(mon, int(args[0]), int(args[1]))
    elif cmd == "key":
        monitor(mon, f"sendkey {args[0]}", settle=0.25)
    elif cmd == "type":
        type_text(mon, args[0])
    elif cmd == "wait":
        out_png, needle = args[0], args[1]
        timeout = float(args[2]) if len(args) > 2 else 180.0
        text = wait_text(mon, out_png, needle, timeout)
        if not matches(text, needle):
            print(f"TIMEOUT waiting for {needle!r}; last screen text:", file=sys.stderr)
            print(text, file=sys.stderr)
            raise SystemExit(1)
        print(f"ok: saw {needle!r}")
    else:
        raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    main()
