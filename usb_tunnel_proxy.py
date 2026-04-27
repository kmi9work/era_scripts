#!/usr/bin/env python3
"""
Brother QL-810W USB HTTP Tunnel Proxy

Creates a TCP proxy that forwards HTTP requests through the printer's
USB management tunnel (Interface 1, AltSetting 1), allowing you to
access the printer's web interface directly from your browser.

Usage:
    sudo python3 usb_tunnel_proxy.py [--port PORT] [--password PASSWORD]

Then open: http://localhost:8080

The web interface will appear in your browser exactly as if you were
connected to the printer over the network.

If --password is provided, the script will automatically log in
and maintain the session. Otherwise, the login page will appear.

Supported features:
  - Automatic cookie/session management
  - Persistent auth across requests
  - All web interface pages (General, Printer Settings, Admin, Network)
"""

import sys
import time
import socket
import threading
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler

# USB imports (loaded after sudo check)
usb_core = None
usb_util = None

VID = 0x04f9   # Brother Industries, Ltd
PID = 0x209c   # QL-810W Label Printer


class USBHTTPTunnel:
    """HTTP tunnel over USB management interface."""

    def __init__(self):
        self.dev = None
        self.cfg = None
        self.ep_in = None
        self.ep_out = None
        self.cookie = ""
        self.password = None
        self._lock = threading.Lock()

    def connect(self):
        """Open USB connection and set up management tunnel."""
        global usb_core, usb_util
        import usb.core as usb_core
        import usb.util as usb_util

        dev = usb_core.find(idVendor=VID, idProduct=PID)
        if dev is None:
            return False

        for intf_num in [0, 1]:
            try:
                if dev.is_kernel_driver_active(intf_num):
                    dev.detach_kernel_driver(intf_num)
            except Exception:
                pass

        dev.set_configuration()
        self.cfg = dev.get_active_configuration()
        self.dev = dev
        return True

    def _setup_tunnel(self):
        """Set Interface 1 to AltSetting 1 (Bulk endpoints)."""
        try:
            usb_util.release_interface(self.dev, 1)
        except Exception:
            pass
        try:
            if self.dev.is_kernel_driver_active(1):
                self.dev.detach_kernel_driver(1)
        except Exception:
            pass

        self.dev.set_interface_altsetting(interface=1, alternate_setting=1)
        time.sleep(0.1)

        try:
            usb_util.claim_interface(self.dev, 1)
        except Exception:
            pass

        intf1 = self.cfg[(1, 1)]
        for ep in intf1:
            if ep.bEndpointAddress & 0x80:
                self.ep_in = ep
            else:
                self.ep_out = ep

    def _release_tunnel(self):
        """Release Interface 1."""
        try:
            usb_util.release_interface(self.dev, 1)
        except Exception:
            pass

    def request(self, method: str, path: str, headers: dict = None,
                body: bytes = b"") -> tuple:
        """
        Send HTTP request through USB tunnel.

        Returns: (status_code: int, response_headers: dict, body: bytes)
        """
        if headers is None:
            headers = {}

        with self._lock:
            self._setup_tunnel()

            # Build HTTP request
            req_line = f"{method} {path} HTTP/1.1\r\n"
            req = req_line.encode()

            # Default headers
            default_headers = {
                "Host": "localhost",
            }
            if self.cookie:
                default_headers["Cookie"] = self.cookie

            # Merge headers (user headers override defaults)
            all_headers = {**default_headers, **headers}
            if body:
                all_headers["Content-Length"] = str(len(body))

            for k, v in all_headers.items():
                req += f"{k}: {v}\r\n".encode()
            req += b"\r\n"
            if body:
                req += body

            # Send
            try:
                self.ep_out.write(req, timeout=10000)
            except Exception as e:
                self._release_tunnel()
                return (0, {}, b"")

            # Read response
            all_data = bytearray()
            for _ in range(50):
                time.sleep(0.1)
                try:
                    chunk = bytes(self.dev.read(self.ep_in, 2048, timeout=500))
                    all_data.extend(chunk)
                except Exception:
                    if len(all_data) > 0:
                        break

            self._release_tunnel()

            # Parse response
            resp = bytes(all_data)
            if not resp:
                return (0, {}, b"")

            header_end = resp.find(b"\r\n\r\n")
            if header_end < 0:
                return (0, {}, resp)

            # Parse status line
            status_line = resp[:resp.find(b"\r\n")].decode("utf-8", errors="replace")
            status_code = 0
            if " " in status_line:
                try:
                    status_code = int(status_line.split(" ")[1])
                except (IndexError, ValueError):
                    pass

            # Parse headers
            resp_headers = {}
            header_section = resp[:header_end].decode("utf-8", errors="replace")
            for line in header_section.split("\r\n")[1:]:
                if ":" in line:
                    k, v = line.split(":", 1)
                    resp_headers[k.strip().lower()] = v.strip()

            # Capture session cookie
            if "set-cookie" in resp_headers:
                cookie_val = resp_headers["set-cookie"].split(";")[0].strip()
                if cookie_val:
                    self.cookie = cookie_val
                    print(f"[USB Tunnel] Session cookie captured")

            body_data = resp[header_end + 4:]

            return (status_code, resp_headers, body_data)

    def login(self, password: str) -> bool:
        """Log in to printer web interface."""
        self.password = password
        body = f"B126={password}&loginurl=/general/status.html"
        status, headers, resp_body = self.request(
            "POST", "/general/status.html",
            {"Content-Type": "application/x-www-form-urlencoded"},
            body.encode()
        )
        # Follow the redirect to establish session
        self.request("GET", "/general/status.html")
        return bool(self.cookie)

    def close(self):
        """Close USB connection."""
        if self.dev:
            try:
                usb_util.release_interface(self.dev, 1)
            except Exception:
                pass
            try:
                usb_util.release_interface(self.dev, 0)
            except Exception:
                pass
            try:
                self.dev.attach_kernel_driver(1)
            except Exception:
                pass
            try:
                self.dev.attach_kernel_driver(0)
            except Exception:
                pass
            try:
                usb_util.dispose_resources(self.dev)
            except Exception:
                pass
            self.dev = None


# Global tunnel instance
tunnel = USBHTTPTunnel()


class ProxyHTTPRequestHandler(BaseHTTPRequestHandler):
    """Handle HTTP requests from browser, forward through USB tunnel."""

    def do_GET(self):
        self._handle_request("GET")

    def do_POST(self):
        self._handle_request("POST")

    def do_HEAD(self):
        self._handle_request("HEAD")

    def _handle_request(self, method):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b""

        # Build forwarding headers
        fwd_headers = {}
        for k, v in self.headers.items():
            kl = k.lower()
            if kl not in ("host", "connection", "content-length",
                          "accept-encoding"):
                fwd_headers[k] = v

        # Forward through USB tunnel
        status, resp_headers, resp_body = tunnel.request(
            method, self.path, fwd_headers, body
        )

        if status == 0:
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"USB Tunnel Error: No response from printer")
            return

        # Forward response back to browser
        self.send_response(status)
        for k, v in resp_headers.items():
            if k.lower() not in ("transfer-encoding", "content-encoding"):
                self.send_header(k, v)
        self.end_headers()

        if resp_body:
            try:
                self.wfile.write(resp_body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def log_message(self, format, *args):
        """Log to stdout."""
        sys.stderr.write(f"[USB Tunnel] {self.client_address[0]} - "
                         f"{args[0]} {args[1]} {args[2]}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Brother QL-810W USB HTTP Tunnel Proxy"
    )
    parser.add_argument("--port", type=int, default=8080,
                        help="Local port to listen on (default: 8080)")
    parser.add_argument("--password", help="Admin password for auto-login")
    parser.add_argument("--bind", default="127.0.0.1",
                        help="Bind address (default: 127.0.0.1)")

    args = parser.parse_args()

    # Check for root
    if os.geteuid() != 0:
        print("This script requires root for USB access.")
        print("Run with: sudo python3 usb_tunnel_proxy.py")
        sys.exit(1)

    # Connect to printer
    print("Connecting to Brother QL-810W via USB...")
    if not tunnel.connect():
        print("ERROR: Printer not found. Make sure it's powered on and connected.")
        sys.exit(1)

    print(f"  ✅ USB connected: {tunnel.dev.product} "
          f"(S/N: {tunnel.dev.serial_number})")

    # Auto-login if password provided
    if args.password:
        print(f"  🔑 Logging in with provided password...")
        if tunnel.login(args.password):
            print(f"  ✅ Login successful! Session cookie captured.")
        else:
            print(f"  ⚠️  Login failed - account may be locked.")
            print(f"  Wait 2-3 minutes or power cycle the printer, then retry.")

    print(f"\n  🌐 HTTP Tunnel Proxy running on "
          f"http://{args.bind}:{args.port}")
    print(f"  🔌 Open in your browser to access the printer's web interface.")
    print(f"  Press Ctrl+C to stop.\n")

    # Start HTTP server
    server = HTTPServer((args.bind, args.port), ProxyHTTPRequestHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()
        tunnel.close()
        print("Done.")


if __name__ == "__main__":
    import os  # noqa: needed for euid check
    main()
