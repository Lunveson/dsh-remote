"""dsh web 反向代理：自动注入认证 cookie，让手机能直接访问 dsh GUI。

原理：
  dsh web 用"签名 cookie"认证，cookie 名 = dsh-auth-<b64url(sha256(Host))>
  值 = v1.<b64url(payload)>.<b64url(HMAC-SHA256(secret, body))>
  secret 持久存在 ~/.dsh/.credentials.yaml 的 client-connection/browser-session

本代理监听局域网 IP:端口，对每个请求自动加上这个 cookie，转发到 127.0.0.1。
手机浏览器打开 http://<电脑IP>:19387 即可，不需要任何认证操作。

用法：
  python dsh_proxy.py <监听IP> <监听端口> <目标IP> <目标端口>
例：
  python dsh_proxy.py 192.168.156.61 19387 127.0.0.1 19387

只在本机运行、只连本机服务，不额外暴露任何东西。
"""
import base64
import hashlib
import hmac
import json
import os
import socket
import sys
import threading
import time

BUF = 65536
SECRET_FILE = os.path.expanduser(r"~\.dsh\.credentials.yaml")


def b64url_decode(s: str) -> bytes:
    pad = "=" * ((4 - len(s) % 4) % 4)
    return base64.urlsafe_b64decode(s + pad)


def load_secret(path=SECRET_FILE):
    """从 credentials yaml 取 secret，并解码成 32 字节（dsh 的 canonicalSecret 行为）。"""
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    in_record = False
    raw = None
    for line in lines:
        s = line.strip()
        if s.startswith("client-connection/browser-session:"):
            in_record = True
            continue
        if in_record:
            if s.startswith("secret:"):
                raw = s.split(":", 1)[1].strip()
                break
            if line and not line.startswith(" ") and not line.startswith("\t") and not s.startswith("kind:"):
                in_record = False
    if raw is None:
        raise SystemExit("没找到 secret，检查 " + path)
    # ★关键：dsh 用的是 base64url 解码后的 32 字节作为 HMAC key★
    return b64url_decode(raw)


def b64url(data: bytes) -> str:
    return base64.b64encode(data).decode().replace("+", "-").replace("/", "_").rstrip("=")


def make_cookie(authority: str, secret: bytes) -> str:
    """按 dsh 的算法签一个 cookie。secret 必须是解码后的字节。"""
    name = "dsh-auth-" + b64url(hashlib.sha256(authority.encode("utf-8")).digest())
    now = int(time.time() * 1000)
    payload = {
        "version": 1,
        "authority": authority,
        "issuedAt": now,
        "expiresAt": now + 30 * 24 * 3600 * 1000,
    }
    # ★键顺序必须和 JS 的 JSON.stringify 一致★
    body = b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    sig = b64url(hmac.new(secret, body.encode("utf-8"), hashlib.sha256).digest())
    return f"{name}=v1.{body}.{sig}"


def inject_cookie(header_bytes: bytes, secret: str) -> bytes:
    """把 Cookie 头塞进请求头（已有就覆盖）。"""
    text = header_bytes.decode("latin-1")
    lines = text.split("\r\n")
    # 找 Host 头算 authority
    authority = None
    cookie_idx = None
    for i, ln in enumerate(lines):
        low = ln.lower()
        if low.startswith("host:"):
            authority = ln.split(":", 1)[1].strip()
        elif low.startswith("cookie:"):
            cookie_idx = i
    if authority is None:
        return header_bytes
    cookie = make_cookie(authority, secret)
    if cookie_idx is not None:
        lines[cookie_idx] = "Cookie: " + cookie
    else:
        # ★必须插在【第一个空行之前】（请求头结束位置），否则会跑到请求体里★
        blank = len(lines) - 1
        for i, ln in enumerate(lines):
            if ln == "":
                blank = i
                break
        lines.insert(blank, "Cookie: " + cookie)
    return "\r\n".join(lines).encode("latin-1")


def pipe(src, dst):
    try:
        while True:
            data = src.recv(BUF)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            try:
                s.close()
            except Exception:
                pass


def handle(client, tip, tport, secret):
    try:
        client.settimeout(15)
        # 读请求头（直到 \r\n\r\n）
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = client.recv(BUF)
            if not chunk:
                client.close()
                return
            buf += chunk
            if len(buf) > 262144:
                break

        # 记日志（看手机请求了什么，含 Host / Origin / Upgrade）
        try:
            txt = buf.decode("latin-1", "ignore")
            first_line = txt.split("\r\n", 1)[0]
            host = origin = upgrade = ""
            for ln in txt.split("\r\n"):
                low = ln.lower()
                if low.startswith("host:"):
                    host = ln.split(":", 1)[1].strip()
                elif low.startswith("origin:"):
                    origin = ln.split(":", 1)[1].strip()
                elif low.startswith("upgrade:"):
                    upgrade = ln.split(":", 1)[1].strip()
            with open(r"D:\DSH工作区\大肥鱼游戏\tools\proxy.log", "a", encoding="utf-8") as lf:
                lf.write(f"{time.strftime('%H:%M:%S')} {first_line} | Host={host} Origin={origin} Upgrade={upgrade}\n")
        except Exception:
            pass

        head, _, rest = buf.partition(b"\r\n\r\n")
        new_head = inject_cookie(head + b"\r\n\r\n", secret)

        back = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        back.connect((tip, tport))
        back.sendall(new_head)
        if rest:
            back.sendall(rest)

        client.settimeout(None)
        # WebSocket 或普通 HTTP：头处理完就双向透传
        threading.Thread(target=pipe, args=(client, back), daemon=True).start()
        pipe(back, client)
    except Exception:
        try:
            client.close()
        except Exception:
            pass


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    lip, lport, tip, tport = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
    secret = load_secret()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((lip, lport))
    srv.listen(32)
    print(f"[dsh-proxy] {lip}:{lport} -> {tip}:{tport}  (自动注入 cookie)", flush=True)

    while True:
        try:
            conn, addr = srv.accept()
        except Exception:
            continue
        print(f"[dsh-proxy] {addr[0]}:{addr[1]} 已连接", flush=True)
        threading.Thread(target=handle, args=(conn, tip, tport, secret), daemon=True).start()


if __name__ == "__main__":
    main()
