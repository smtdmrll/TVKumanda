#!/usr/bin/env python3
"""Android TV Remote v2 probe (Mac side): pairing on 6467, remote commands on 6466."""
import hashlib, os, socket, ssl, subprocess, sys, time

TV = os.environ.get("TV", "192.168.1.109")
HERE = os.path.dirname(os.path.abspath(__file__))
CERT, KEY = os.path.join(HERE, "..", "certs", "cert.pem"), os.path.join(HERE, "..", "certs", "key.pem")
CODE_FILE = os.path.join(HERE, "code.txt")
SERIAL = os.environ.get("ANDROID_SERIAL", "192.168.1.109:37703")


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def read_varint(buf, i):
    shift = result = 0
    while True:
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, i
        shift += 7


def fv(num, val):
    return varint(num << 3) + varint(val)


def fb(num, data):
    if isinstance(data, str):
        data = data.encode()
    return varint(num << 3 | 2) + varint(len(data)) + data


def parse(data):
    i, out = 0, []
    while i < len(data):
        key, i = read_varint(data, i)
        num, wt = key >> 3, key & 7
        if wt == 0:
            v, i = read_varint(data, i)
        elif wt == 2:
            ln, i = read_varint(data, i)
            v = data[i:i + ln]
            i += ln
        elif wt == 5:
            v, i = data[i:i + 4], i + 4
        elif wt == 1:
            v, i = data[i:i + 8], i + 8
        else:
            raise ValueError(f"wire type {wt}")
        out.append((num, v))
    return out


def connect(port):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    ctx.load_cert_chain(CERT, KEY)
    raw = socket.create_connection((TV, port), timeout=10)
    return ctx.wrap_socket(raw)


class Framed:
    def __init__(self, sock):
        self.sock, self.buf = sock, b""

    def send(self, msg):
        self.sock.sendall(varint(len(msg)) + msg)

    def recv(self, timeout=10):
        self.sock.settimeout(timeout)
        while True:
            if self.buf:
                try:
                    ln, pos = read_varint(self.buf, 0)
                    if len(self.buf) >= pos + ln:
                        msg, self.buf = self.buf[pos:pos + ln], self.buf[pos + ln:]
                        return msg
                except IndexError:
                    pass
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("closed")
            self.buf += chunk


def modulus_exponent(der):
    out = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-modulus", "-text"],
                         input=der, capture_output=True).stdout.decode()
    n = int(out.split("Modulus=")[1].split()[0], 16)
    e = int(out.split("Exponent: ")[1].split()[0])
    return n, e


def outer(field, payload):
    return fv(1, 2) + fv(2, 200) + fb(field, payload)


def pair():
    s = connect(6467)
    f = Framed(s)
    f.send(outer(10, fb(1, "atvremote") + fb(2, "TV Kumanda")))
    print("ack:", parse(f.recv()))
    enc = fv(1, 3) + fv(2, 6)
    f.send(outer(20, fb(1, enc) + fv(3, 1)))
    print("options:", parse(f.recv()))
    f.send(outer(30, fb(1, enc) + fv(2, 1)))
    print("config ack:", parse(f.recv()), flush=True)
    time.sleep(1.5)
    subprocess.run(f"adb -s {SERIAL} exec-out screencap -p > {HERE}/code.png", shell=True)
    print("SCREEN", flush=True)
    if os.path.exists(CODE_FILE):
        os.remove(CODE_FILE)
    for _ in range(240):
        if os.path.exists(CODE_FILE):
            break
        time.sleep(0.5)
    code = open(CODE_FILE).read().strip().upper()
    server = modulus_exponent(s.getpeercert(binary_form=True))
    client = modulus_exponent(subprocess.run(["openssl", "x509", "-in", CERT, "-outform", "DER"],
                                             capture_output=True).stdout)
    h = hashlib.sha256()
    for n, e in (client, server):
        h.update(bytes.fromhex(f"{n:X}"))
        h.update(bytes.fromhex(f"0{e:X}"))
    h.update(bytes.fromhex(code[2:]))
    digest = h.digest()
    print("check byte ok:", digest[0] == int(code[:2], 16))
    f.send(outer(40, fb(1, digest)))
    print("secret ack:", parse(f.recv()))


FEATURES = 1 | 2 | 4 | 32 | 64 | 512  # ping, key, ime, power, volume, app link


def session(actions):
    s = connect(6466)
    f = Framed(s)
    ime = {"counter": 0, "field": 0}
    deadline = time.time() + 6
    ready = False
    while time.time() < deadline or not ready:
        try:
            msg = parse(f.recv(timeout=2))
        except socket.timeout:
            if ready:
                break
            continue
        for num, v in msg:
            if num == 1:
                tv = dict(parse(v))
                code1 = tv.get(1, 0)
                print("TV configure code1:", code1, "device:", parse(tv.get(2, b"")))
                info = fv(3, 1) + fb(4, "1") + fb(5, "atvremote") + fb(6, "1.0.0")
                f.send(fb(1, fv(1, FEATURES & code1) + fb(2, info)))
            elif num == 2:
                f.send(fb(2, fv(1, FEATURES)))
                ready = True
                print("set_active -> ready")
            elif num == 8:
                f.send(fb(9, fv(1, dict(parse(v)).get(1, 0))))
            elif num == 21:
                d = dict(parse(v))
                ime["counter"], ime["field"] = d.get(1, 0), d.get(2, 0)
                print("TV ime batch edit:", ime)
            else:
                print("TV msg", num, parse(v) if isinstance(v, bytes) else v)
    for act in actions:
        kind, _, arg = act.partition(":")
        if kind == "key":
            f.send(fb(10, fv(1, int(arg)) + fv(2, 3)))
        elif kind == "app":
            f.send(fb(90, fb(1, arg)))
        elif kind == "text":
            obj = fv(1, len(arg) - 1) + fv(2, len(arg) - 1) + fb(3, arg)
            f.send(fb(21, fv(1, ime["counter"]) + fv(2, ime["field"]) + fb(3, fv(1, 1) + fb(2, obj))))
        elif kind == "wait":
            end = time.time() + float(arg)
            while time.time() < end:
                try:
                    for num, v in parse(f.recv(timeout=max(0.1, end - time.time()))):
                        if num == 8:
                            f.send(fb(9, fv(1, dict(parse(v)).get(1, 0))))
                        elif num == 21:
                            d = dict(parse(v))
                            ime["counter"], ime["field"] = d.get(1, 0), d.get(2, 0)
                            print("TV ime batch edit:", ime, parse(v))
                        elif num == 22:
                            print("TV ime show:", parse(v))
                        else:
                            print("TV msg", num, v[:80])
                except socket.timeout:
                    pass
        print("sent", act, flush=True)
    s.close()


if __name__ == "__main__":
    if sys.argv[1] == "pair":
        pair()
    else:
        session(sys.argv[2:])
