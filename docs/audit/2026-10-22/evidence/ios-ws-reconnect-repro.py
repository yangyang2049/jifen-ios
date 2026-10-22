"""Reproduce IOS-02 on loopback using the current production WS manager.
No production network traffic or repository source edits. Run from iOS repo.
"""
from pathlib import Path
import json
import socket
import subprocess
import tempfile
import threading
import time

root = Path(__file__).resolve().parents[4]
source = (root / 'jifen/Core/CloudSync/MatchWebSocketManager.swift').read_text()
source = source.split('/// 显示端设备信息')[0].replace('import UIKit\n', '')
source = source.replace('DisplayStateWireCodec.currentWallClockMs()', 'Int64(Date().timeIntervalSince1970 * 1000)')
server = socket.socket()
server.bind(('127.0.0.1', 0))
server.listen()
server.settimeout(0.1)
port = server.getsockname()[1]
source += '''
private func currentDisplayDeviceInfo() -> [String: Any] { [:] }
@main struct ReconnectAudit {
 @MainActor static func main() async {
  let manager = MatchWebSocketManager.shared
  manager.connect(matchId: "audit-only", token: "audit-only", wsUrl: "ws://127.0.0.1:PORT")
  try? await Task.sleep(nanoseconds: 7_300_000_000)
  manager.disconnect()
 }
}
'''.replace('PORT', str(port))
with tempfile.TemporaryDirectory(prefix='ios-ws-audit-') as directory:
    swift = Path(directory) / 'main.swift'
    executable = Path(directory) / 'audit'
    swift.write_text(source)
    subprocess.run(['swiftc', '-parse-as-library', '-swift-version', '5', str(swift), '-o', str(executable)], check=True)
    stop = threading.Event()
    offsets = []
    start = time.monotonic()
    def serve():
        while not stop.is_set():
            try:
                connection, _ = server.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(2)
                try:
                    connection.recv(65536)
                    offsets.append(round(time.monotonic() - start, 3))
                    connection.sendall(b'HTTP/1.1 401 Unauthorized\r\nConnection: close\r\nContent-Length: 0\r\n\r\n')
                except OSError:
                    pass
    worker = threading.Thread(target=serve)
    worker.start()
    try:
        result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=15)
    finally:
        stop.set()
        worker.join()
        server.close()
    print(json.dumps({'handshake_attempts': len(offsets), 'offsets_seconds': offsets, 'exit': result.returncode,
                      'bug_observed': len(offsets) > 6}, ensure_ascii=False, indent=2))
