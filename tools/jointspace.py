#!/usr/bin/env python3
"""Philips JointSpace v6 protocol probe (Mac side) for the iPhone remote app."""
import base64, hmac, hashlib, json, os, random, ssl, string, sys, urllib.request

TV = os.environ.get("TV", "192.168.1.109")
BASE = f"https://{TV}:1926/6/"
HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(HERE, "jointspace_mac_pairing.json")
SHARED_KEY = base64.b64decode(
    "ZmVay1EQVFOaZhwQ4Kv81ypLAZNczV9sG4KkseXWn1NEk6cXmPKO/MCa9sryslvLCFMnNe4Z4CPXzToowvhHvA==")
CTX = ssl._create_unverified_context()


def opener(user=None, password=None):
    handlers = [urllib.request.HTTPSHandler(context=CTX)]
    if user:
        mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
        mgr.add_password(None, BASE, user, password)
        handlers.append(urllib.request.HTTPDigestAuthHandler(mgr))
    return urllib.request.build_opener(*handlers)


def call(path, body=None, auth=True):
    st = json.load(open(STATE)) if os.path.exists(STATE) else {}
    op = opener(st["device"]["id"], st["auth_key"]) if auth and "auth_key" in st else opener()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method="POST" if data else "GET",
                                 headers={"Content-Type": "application/json"})
    try:
        with op.open(req, timeout=8) as r:
            txt = r.read().decode("utf-8", "replace")
            return r.status, txt
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def main():
    cmd = sys.argv[1]
    if cmd == "request":
        dev = {"device_name": "Mac", "device_os": "macOS", "type": "native",
               "id": "".join(random.choice(string.ascii_letters + string.digits) for _ in range(16)),
               "app_id": "com.sametdemirel.tvkumanda", "app_name": "TV Kumanda (test)"}
        if os.path.exists(STATE):
            os.remove(STATE)
        code, txt = call("pair/request", {"access": {"scope": ["read", "write", "control"]}, "device": dev}, auth=False)
        print(code, txt)
        resp = json.loads(txt)
        json.dump({"device": dev, "auth_key": resp["auth_key"], "timestamp": resp["timestamp"], "paired": False},
                  open(STATE, "w"))
    elif cmd == "grant":
        pin = sys.argv[2]
        st = json.load(open(STATE))
        sig = base64.b64encode(hmac.new(SHARED_KEY, str(st["timestamp"]).encode() + pin.encode(),
                                        hashlib.sha1).digest()).decode()
        body = {"auth": {"auth_appId": "1", "auth_timestamp": st["timestamp"], "auth_signature": sig, "pin": pin},
                "device": st["device"]}
        code, txt = call("pair/grant", body)
        print(code, txt)
        if code == 200:
            st["paired"] = True
            json.dump(st, open(STATE, "w"))
    elif cmd == "get":
        print(*call(sys.argv[2]))
    elif cmd == "post":
        print(*call(sys.argv[2], json.loads(sys.argv[3])))


if __name__ == "__main__":
    main()
