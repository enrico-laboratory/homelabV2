# Minimal TrueNAS JSON-RPC 2.0 client over websocket (RFC 6455), standard library only.
#
# Used by library/truenas_api.py. Kept free of Ansible imports so it can be tested on its own:
#   python3 -I -c 'import sys; sys.path.insert(0, "ansible/playbooks/module_utils"); import truenas_ws; ...'
#
# Scope: what the TrueNAS middleware needs and nothing more: one wss:// connection, text frames
# (with fragmentation), ping/pong, close, JSON-RPC calls, API-key login (PLAIN, TrueNAS 25.x) and
# waiting for middleware jobs by polling core.get_jobs.

import base64
import hashlib
import json
import os
import socket
import ssl
import struct
import time
from urllib.parse import urlparse

_WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

OP_CONT, OP_TEXT, OP_BIN, OP_CLOSE, OP_PING, OP_PONG = 0x0, 0x1, 0x2, 0x8, 0x9, 0xA


class TrueNASError(Exception):
    """A JSON-RPC error returned by the middleware, or a failed job."""

    def __init__(self, message, data=None):
        super().__init__(message)
        self.data = data


class WebSocket:
    def __init__(self, url, verify_ssl=True, timeout=60):
        u = urlparse(url)
        if u.scheme not in ("ws", "wss"):
            raise ValueError("url must be ws:// or wss://")
        port = u.port or (443 if u.scheme == "wss" else 80)
        sock = socket.create_connection((u.hostname, port), timeout=timeout)
        if u.scheme == "wss":
            ctx = ssl.create_default_context()
            if not verify_ssl:
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE
            sock = ctx.wrap_socket(sock, server_hostname=u.hostname)
        self.sock = sock
        self._buf = b""
        self._handshake(u.hostname, port, u.path or "/")

    # -- low level -------------------------------------------------------------------------------

    def _read(self, n):
        while len(self._buf) < n:
            chunk = self.sock.recv(max(65536, n - len(self._buf)))
            if not chunk:
                raise ConnectionError("connection closed by server")
            self._buf += chunk
        data, self._buf = self._buf[:n], self._buf[n:]
        return data

    def _handshake(self, host, port, path):
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(req.encode())
        while b"\r\n\r\n" not in self._buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("connection closed during websocket handshake")
            self._buf += chunk
        head, self._buf = self._buf.split(b"\r\n\r\n", 1)
        lines = head.decode("latin-1").split("\r\n")
        if " 101 " not in lines[0] + " ":
            raise ConnectionError(f"websocket handshake failed: {lines[0]}")
        headers = {k.strip().lower(): v.strip() for k, v in (l.split(":", 1) for l in lines[1:] if ":" in l)}
        expect = base64.b64encode(hashlib.sha1((key + _WS_GUID).encode()).digest()).decode()
        if headers.get("sec-websocket-accept") != expect:
            raise ConnectionError("websocket handshake failed: bad Sec-WebSocket-Accept")

    def _send_frame(self, opcode, payload=b""):
        header = bytes([0x80 | opcode])
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack("!H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack("!Q", n)
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + mask + masked)

    def _recv_frame(self):
        b1, b2 = self._read(2)
        fin, opcode = b1 & 0x80, b1 & 0x0F
        n = b2 & 0x7F
        if n == 126:
            (n,) = struct.unpack("!H", self._read(2))
        elif n == 127:
            (n,) = struct.unpack("!Q", self._read(8))
        mask = self._read(4) if b2 & 0x80 else None
        payload = self._read(n)
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        return bool(fin), opcode, payload

    # -- messages --------------------------------------------------------------------------------

    def send_text(self, text):
        self._send_frame(OP_TEXT, text.encode("utf-8"))

    def recv_text(self):
        parts = []
        while True:
            fin, opcode, payload = self._recv_frame()
            if opcode == OP_PING:
                self._send_frame(OP_PONG, payload)
                continue
            if opcode == OP_PONG:
                continue
            if opcode == OP_CLOSE:
                raise ConnectionError("websocket closed by server")
            parts.append(payload)
            if fin:
                return b"".join(parts).decode("utf-8")

    def close(self):
        try:
            self._send_frame(OP_CLOSE, struct.pack("!H", 1000))
        except OSError:
            pass
        self.sock.close()


class Client:
    """JSON-RPC 2.0 client for the TrueNAS middleware (/api/current)."""

    def __init__(self, url, verify_ssl=True, timeout=60):
        self.ws = WebSocket(url, verify_ssl=verify_ssl, timeout=timeout)
        self._id = 0

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.ws.close()

    def call(self, method, *params, job=False, job_timeout=3600):
        self._id += 1
        my_id = self._id
        self.ws.send_text(json.dumps({"jsonrpc": "2.0", "id": my_id, "method": method, "params": list(params)}))
        while True:
            msg = json.loads(self.ws.recv_text())
            if msg.get("id") != my_id:
                continue  # notifications (collection_update, ...) or stale replies
            if "error" in msg:
                err = msg["error"]
                data = err.get("data") or {}
                reason = data.get("reason") or err.get("message") or str(err)
                extra = data.get("extra")
                raise TrueNASError(f"{method}: {reason}" + (f" {extra}" if extra else ""), data)
            result = msg.get("result")
            break
        if job:
            return self.wait_job(result, job_timeout)
        return result

    def wait_job(self, job_id, timeout=3600):
        deadline = time.time() + timeout
        while time.time() < deadline:
            jobs = self.call("core.get_jobs", [["id", "=", job_id]])
            if jobs:
                j = jobs[0]
                if j["state"] == "SUCCESS":
                    return j.get("result")
                if j["state"] in ("FAILED", "ABORTED"):
                    raise TrueNASError(f"job {job_id} ({j.get('method')}) {j['state']}: {j.get('error')}", j)
            time.sleep(1)
        raise TrueNASError(f"job {job_id} did not finish within {timeout}s")

    def login_api_key(self, username, key):
        """PLAIN API-key login (TrueNAS 25.x). Falls back to the legacy call when login_ex is absent."""
        try:
            resp = self.call("auth.login_ex", {"mechanism": "API_KEY_PLAIN", "username": username, "api_key": key})
            if resp.get("response_type") != "SUCCESS":
                raise TrueNASError(f"auth.login_ex: {resp.get('response_type')}")
            return True
        except TrueNASError as e:
            if "auth.login_ex" in str(e) and "does not exist" not in str(e).lower():
                raise
        if not self.call("auth.login_with_api_key", key):
            raise TrueNASError("auth.login_with_api_key: rejected")
        return True
