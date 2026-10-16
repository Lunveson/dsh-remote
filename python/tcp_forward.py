"""TCP 端口转发：让手机能访问只监听 127.0.0.1 的服务（如 dsh GUI）。

用法：
    python tcp_forward.py <监听IP> <监听端口> <目标IP> <目标端口>
例：
    python tcp_forward.py 192.168.156.61 19387 127.0.0.1 19387

手机浏览器访问 http://192.168.156.61:19387 即可。
用户态实现，不需要管理员权限。
"""
import socket
import sys
import threading

BUF = 65536


def pipe(src, dst):
    """单向搬运：src -> dst。"""
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


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    lip, lport, tip, tport = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4])

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((lip, lport))
    srv.listen(32)
    print(f"[forward] {lip}:{lport}  ->  {tip}:{tport}", flush=True)

    while True:
        try:
            conn, addr = srv.accept()
        except Exception:
            continue
        try:
            back = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            back.connect((tip, tport))
        except Exception as e:
            print(f"[forward] 目标连不上: {e}", flush=True)
            conn.close()
            continue
        print(f"[forward] {addr[0]}:{addr[1]} 已连接", flush=True)
        threading.Thread(target=pipe, args=(conn, back), daemon=True).start()
        threading.Thread(target=pipe, args=(back, conn), daemon=True).start()


if __name__ == "__main__":
    main()
