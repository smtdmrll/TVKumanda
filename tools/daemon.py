#!/usr/bin/env python3
"""Keeps one remote session open, logs every TV message (decoded) and runs commands from cmd.txt."""
import os, socket, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atv

HERE = os.path.dirname(os.path.abspath(__file__))
CMD = os.path.join(HERE, "cmd.txt")
LOG = os.path.join(HERE, "daemon.log")
open(CMD, "w").close()
log = open(LOG, "w", buffering=1)


def dump(data, depth=0):
    out = []
    for num, v in atv.parse(data):
        if isinstance(v, bytes):
            try:
                inner = atv.parse(v) if v else []
                ok = inner and all(n > 0 for n, _ in inner)
            except Exception:
                ok = False
            if ok and depth < 4:
                out.append(f"{num}:{{{dump(v, depth + 1)}}}")
            else:
                out.append(f"{num}:{v!r}")
        else:
            out.append(f"{num}={v}")
    return " ".join(out)


s = atv.connect(6466)
f = atv.Framed(s)
ime = {"counter": 0, "field": 0}
done = 0
while True:
    try:
        frame = f.recv(timeout=0.2)
        fields = atv.parse(frame)
        for num, v in fields:
            if num == 1:
                tv = dict(atv.parse(v))
                info = atv.fv(3, 1) + atv.fb(4, "1") + atv.fb(5, "atvremote") + atv.fb(6, "1.0.0")
                f.send(atv.fb(1, atv.fv(1, atv.FEATURES & tv.get(1, 0)) + atv.fb(2, info)))
            elif num == 2:
                f.send(atv.fb(2, atv.fv(1, atv.FEATURES)))
            elif num == 8:
                f.send(atv.fb(9, atv.fv(1, dict(atv.parse(v)).get(1, 0))))
                continue
            elif num == 21:
                d = dict(atv.parse(v))
                ime["counter"], ime["field"] = d.get(1, 0), d.get(2, 0)
            elif num == 20:
                app = dict(atv.parse(v)).get(1)
                if app:
                    ime["field"] = dict(atv.parse(app)).get(1, ime["field"])
        log.write(f"{time.strftime('%H:%M:%S')} TV  {dump(frame)}\n")
    except socket.timeout:
        pass
    except Exception as e:
        log.write(f"closed: {e}\n")
        break
    lines = open(CMD).read().splitlines()
    for line in lines[done:]:
        kind, _, arg = line.partition(" ")
        if kind == "key":
            f.send(atv.fb(10, atv.fv(1, int(arg)) + atv.fv(2, 3)))
        elif kind == "down":
            f.send(atv.fb(10, atv.fv(1, int(arg)) + atv.fv(2, 1)))
        elif kind == "up":
            f.send(atv.fb(10, atv.fv(1, int(arg)) + atv.fv(2, 2)))
        elif kind == "app":
            f.send(atv.fb(90, atv.fb(1, arg)))
        elif kind == "text":
            n = len(arg) - 1
            obj = atv.fv(1, n) + atv.fv(2, n) + atv.fb(3, arg)
            f.send(atv.fb(21, atv.fv(1, ime["counter"]) + atv.fv(2, ime["field"]) + atv.fb(3, atv.fv(1, 1) + atv.fb(2, obj))))
        elif kind == "ctr":
            a, b = arg.split()
            ime["counter"], ime["field"] = int(a), int(b)
        elif kind == "quit":
            sys.exit(0)
        log.write(f"{time.strftime('%H:%M:%S')} ME  {line}  (ime={ime})\n")
    done = len(lines)
