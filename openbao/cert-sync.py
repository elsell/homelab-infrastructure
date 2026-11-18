"""Copy secrets.jsksell.com's certificate from the cluster (namespace openbao) into OpenBao's TLS
volume and reload OpenBao (SIGHUP to PID 1 in its PID namespace). --once: fetch and exit.
Keeps the current certificate if the cluster can't be reached."""
import base64, json, os, signal, ssl, sys, time, urllib.request

API = "https://192.168.2.92:16443/api/v1/namespaces/openbao/secrets/secrets-jsksell-com-tls"
CRED = "/cred"
TLS = "/tls"


def fetch():
    ctx = ssl.create_default_context(cafile=f"{CRED}/ca.crt")
    # MicroK8s's CA has no key-usage extension, which Python 3.13's strict X.509 mode rejects;
    # the chain and the server's IP SAN are still verified.
    ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
    req = urllib.request.Request(API, headers={"Authorization": "Bearer " + open(f"{CRED}/token").read().strip()})
    with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
        data = json.load(r)["data"]
    return base64.b64decode(data["tls.crt"]), base64.b64decode(data["tls.key"])


def install(crt, key):
    if os.path.exists(f"{TLS}/tls.crt") and open(f"{TLS}/tls.crt", "rb").read() == crt:
        return False
    for name, content in (("tls.key", key), ("tls.crt", crt)):
        tmp = f"{TLS}/.{name}"
        with open(tmp, "wb") as f:
            os.fchmod(f.fileno(), 0o600)
            f.write(content)
        os.replace(tmp, f"{TLS}/{name}")
    return True


def main():
    once = "--once" in sys.argv
    while True:
        try:
            if install(*fetch()):
                print("installed a new certificate", flush=True)
                if not once:
                    os.kill(1, signal.SIGHUP)
        except Exception as e:  # noqa: BLE001 - keep serving the last certificate
            print(f"cert fetch failed: {e}", flush=True)
            if once and not os.path.exists(f"{TLS}/tls.crt"):
                sys.exit(1)
        if once:
            return
        time.sleep(12 * 3600)


main()
