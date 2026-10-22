"""Run the production WebSocket manager against local rejected/delayed handshakes."""
from pathlib import Path
import base64
import hashlib
import json
import re
import socket
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WebSocketLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="jifen-ws-lifecycle-")
        source = (ROOT / "jifen/Core/CloudSync/MatchWebSocketManager.swift").read_text()
        source = source.split("/// 显示端设备信息")[0].replace("import UIKit\n", "")
        source = source.replace("DisplayStateWireCodec.currentWallClockMs()", "Int64(Date().timeIntervalSince1970 * 1000)")
        source += '''
private func currentDisplayDeviceInfo() -> [String: Any] { [:] }
extension MatchWebSocketManager { var auditAttempts: Int { reconnectAttempts } }
@main struct LifecycleTest {
 @MainActor static func main() async {
  let manager = MatchWebSocketManager.shared
  manager.connect(matchId: "local-fixture", token: "local-fixture", wsUrl: CommandLine.arguments[1])
  precondition(!manager.isConnected, "resume is not a completed handshake")
  if CommandLine.arguments[2] == "reject" {
   let end = Date().addingTimeInterval(50)
   while Date() < end {
    precondition(!manager.isConnected, "rejected handshakes must never publish connected")
    if manager.auditAttempts == 5 && manager.connectionState == .disconnected { break }
    try? await Task.sleep(nanoseconds: 50_000_000)
   }
   precondition(manager.auditAttempts == 5 && manager.connectionState == .disconnected)
   try? await Task.sleep(nanoseconds: 1_000_000_000)
  } else {
   let end = Date().addingTimeInterval(8)
   while !manager.isConnected && Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
   precondition(manager.isConnected, "a successful handshake must publish connected")
   precondition(manager.auditAttempts == 0)
  }
  manager.disconnect()
 }
}
'''
        source_file = Path(cls.directory.name) / "main.swift"
        cls.binary = Path(cls.directory.name) / "lifecycle"
        source_file.write_text(source)
        subprocess.run(["swiftc", "-parse-as-library", "-swift-version", "5", str(source_file), "-o", str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def run_server(self, mode):
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen()
        server.settimeout(0.1)
        stop = threading.Event()
        attempts = []

        def serve():
            while not stop.is_set():
                try:
                    connection, _ = server.accept()
                except socket.timeout:
                    continue
                with connection:
                    connection.settimeout(2)
                    try:
                        request = connection.recv(65536)
                        attempts.append(time.monotonic())
                        if mode == "reject":
                            connection.sendall(b"HTTP/1.1 401 Unauthorized\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
                        else:
                            time.sleep(0.3)
                            key = re.search(br"Sec-WebSocket-Key:\s*([^\r\n]+)", request, re.I).group(1)
                            accept = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
                            connection.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
                            while not stop.wait(0.1):
                                pass
                    except OSError:
                        pass

        worker = threading.Thread(target=serve)
        worker.start()
        try:
            result = subprocess.run([str(self.binary), f"ws://127.0.0.1:{server.getsockname()[1]}", mode], capture_output=True, text=True, timeout=55)
            self.assertEqual(result.returncode, 0, result.stderr[-3000:])
        finally:
            stop.set()
            worker.join(timeout=3)
            server.close()
        return attempts

    def test_rejected_handshakes_back_off_and_stop_after_five_retries(self):
        attempts = self.run_server("reject")
        self.assertEqual(len(attempts), 6, "one initial handshake plus at most five retries")
        gaps = [b - a for a, b in zip(attempts, attempts[1:])]
        for actual, minimum in zip(gaps, [0.8, 1.8, 3.8, 7.8, 15.8]):
            self.assertGreaterEqual(actual, minimum)
        print(json.dumps({"rejected_handshakes": len(attempts), "gaps_seconds": [round(gap, 2) for gap in gaps]}))

    def test_delayed_success_connects_only_after_handshake(self):
        self.assertEqual(len(self.run_server("success")), 1)


if __name__ == "__main__":
    unittest.main()
