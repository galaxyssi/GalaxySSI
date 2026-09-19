#!/usr/bin/env python3
"""Wi-Fi setup interoperability client. Never sends configuration before explicit code comparison.

The phone app must implement this protocol; this CLI is a developer test tool, not a replacement UI.
"""
import argparse
import hashlib
import json
import secrets
import socket
import ssl
import struct
from pathlib import Path


def send(sock, value):
    data = json.dumps(value, separators=(',', ':')).encode()
    if len(data) > 32768:
        raise ValueError('Configuration exceeds the protocol limit')
    sock.sendall(struct.pack('!I', len(data)) + data)


def receive(sock):
    def exact(size):
        data = bytearray()
        while len(data) < size:
            block = sock.recv(size - len(data))
            if not block:
                raise ConnectionError('Watch closed the connection')
            data.extend(block)
        return bytes(data)
    size, = struct.unpack('!I', exact(4))
    if not 2 <= size <= 32768:
        raise ValueError('Invalid frame size')
    return json.loads(exact(size))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('host', help='Watch IPv4 address displayed in Connection help')
    parser.add_argument('port', type=int)
    parser.add_argument('--config', type=Path, help='Private JSON file; never put API keys in shell arguments')
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding='utf-8-sig')) if args.config else None
    if config is not None:
        if config.get('type') != 'configure' or config.get('kind') not in ('cloud', 'desktop'):
            parser.error('Expected type=configure, kind=cloud or desktop')
    # Bootstrap trust is established by the commit/reveal SAS and explicit comparison on BOTH devices.
    # CERT_NONE is restricted to this setup connection; never use it for cloud/model/desktop traffic.
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    tls.minimum_version = ssl.TLSVersion.TLSv1_2
    tls.check_hostname = False
    tls.verify_mode = ssl.CERT_NONE
    with socket.create_connection((args.host, args.port), timeout=10) as tcp:
        with tls.wrap_socket(tcp, server_hostname=None) as sock:
            sock.settimeout(65)
            client_nonce = secrets.token_bytes(32)
            send(sock, dict(type='hello', version=1, commitment=hashlib.sha256(client_nonce).hexdigest()))
            challenge = receive(sock)
            if challenge.get('type') != 'challenge' or challenge.get('version') != 1:
                raise ValueError('Unsupported setup protocol')
            send(sock, dict(type='reveal', nonce=client_nonce.hex()))
            reveal = receive(sock)
            nonce = bytes.fromhex(reveal['nonce'])
            if len(nonce) != 32 or not secrets.compare_digest(hashlib.sha256(nonce).hexdigest(), challenge['commitment']):
                raise ValueError('Invalid commitment')
            cert_hash = hashlib.sha256(sock.getpeercert(binary_form=True)).digest()
            digest = hashlib.sha256(b'GalaxySSI-Watch-Setup-v1' + cert_hash + client_nonce + nonce).digest()
            code = f'{int.from_bytes(digest, "big") % 1000000:06d}'
            print(f'Compare with the WATCH: {code[:3]} {code[3:]}')
            print('Approve on the watch only if the codes match.')
            if input('Codes match on both devices? Type YES: ').strip() != 'YES':
                return
            send(sock, dict(type='confirm', accept=True))
            if receive(sock).get('type') != 'ready':
                raise ValueError('Watch did not approve')
            if config is None:
                print('Handshake verified. No configuration sent.')
                return
            send(sock, config)
            result = receive(sock)
            if result.get('status') == 'saved':
                print('Watch confirmed configuration storage.')
            elif result.get('status') == 'pairing_started':
                print('Pairing request submitted; desktop authorization is still pending.')
            else:
                raise ValueError('Configuration was not acknowledged')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, EOFError):
        raise SystemExit('Setup failed or expired. No success acknowledgment received; retry from the watch.')
