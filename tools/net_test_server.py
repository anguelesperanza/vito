#!/usr/bin/env python3
"""The PC side of Examples/Net-Example.

    python tools/net_test_server.py                  echo server, TCP and UDP port 9999
    python tools/net_test_server.py --connect IP     connect to the Vita's server on port 9998

Run it with no arguments, type the address it prints into the example on the
Vita (Up opens the keyboard), then press Square (TCP) or Triangle (UDP): the
PC sends back whatever it receives, and prints it.

For the other direction, press R on the Vita and, within 20 seconds, run this
with --connect and the Vita's IP address (shown on its screen).

The PC and the Vita must be on the same network. If nothing arrives, the PC's
firewall is the usual reason: allow Python on private networks, or allow
port 9999.

Only the Python standard library is used. Ctrl+C stops it.
"""
import argparse
import socket
import threading

ECHO_PORT = 9999
VITA_PORT = 9998


def local_addresses():
    found = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            found.add(info[4][0])
    except OSError:
        pass
    # The address used to reach the outside is the one on the LAN. Connecting a
    # UDP socket sends nothing; it only picks the route.
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))
            found.add(s.getsockname()[0])
    except OSError:
        pass
    return sorted(a for a in found if not a.startswith("127."))


def tcp_echo():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("0.0.0.0", ECHO_PORT))
        server.listen()
        while True:
            connection, peer = server.accept()
            with connection:
                data = connection.recv(4096)
                print(f"TCP from {peer[0]}: {data!r}")
                connection.sendall(data)


def udp_echo():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
        server.bind(("0.0.0.0", ECHO_PORT))
        while True:
            data, peer = server.recvfrom(4096)
            print(f"UDP from {peer[0]}: {data!r}")
            server.sendto(data, peer)


def connect(ip):
    with socket.create_connection((ip, VITA_PORT), timeout=10) as connection:
        connection.sendall(b"hello from the PC\n")
        print(f"sent a greeting to {ip}:{VITA_PORT}")
        print(f"the Vita answered: {connection.recv(4096)!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--connect", metavar="IP", help="connect to the Vita's server instead of serving")
    args = parser.parse_args()
    if args.connect:
        connect(args.connect)
        return

    print(f"Echo server on TCP and UDP port {ECHO_PORT}. This PC's address:")
    for address in local_addresses() or ["(none found; look it up with ipconfig)"]:
        print(f"    {address}")
    print("Type that address into Net-Example on the Vita. Ctrl+C stops this.")
    threading.Thread(target=udp_echo, daemon=True).start()
    try:
        tcp_echo()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
