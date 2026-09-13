"""Disposable loopback-only TLS brokers. Never changes the production catalog."""
import ipaddress
import ssl
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

from amqtt.broker import Broker
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


@dataclass(frozen=True)
class Endpoint:
    port: int
    host: str = "127.0.0.1"


def create_certificates(directory: Path):
    now = datetime.now(timezone.utc)
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "GalaxySSI disposable MQTT lab CA")])
    ca = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name)
          .public_key(ca_key.public_key()).serial_number(x509.random_serial_number())
          .not_valid_before(now - timedelta(minutes=1)).not_valid_after(now + timedelta(days=1))
          .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
          .add_extension(x509.KeyUsage(False, False, False, False, False, True, True, None, None), critical=True)
          .sign(ca_key, hashes.SHA256()))
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")])
    certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(ca_name)
                   .public_key(key.public_key()).serial_number(x509.random_serial_number())
                   .not_valid_before(now - timedelta(minutes=1)).not_valid_after(now + timedelta(days=1))
                   .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
                   .add_extension(x509.SubjectAlternativeName([
                       x509.DNSName("localhost"), x509.IPAddress(ipaddress.ip_address("127.0.0.1"))]), critical=False)
                   .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
                   .sign(ca_key, hashes.SHA256()))
    (directory / "ca.pem").write_bytes(ca.public_bytes(serialization.Encoding.PEM))
    (directory / "server.pem").write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    (directory / "server-key.pem").write_bytes(key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))


class OwnedBrokers:
    """Three independent stores/listeners; broker IDs are test labels, not public hosts."""
    def __init__(self):
        self.brokers = {}
        self.endpoints = {}
        self._temporary = None

    async def __aenter__(self):
        self._temporary = TemporaryDirectory(prefix="galaxyssi-owned-mqtt-")
        self.directory = Path(self._temporary.name)
        create_certificates(self.directory)
        try:
            for label in ("emqx", "hivemq", "mosquitto"):
                await self.start(label)
        except BaseException:
            await self.__aexit__(None, None, None)
            raise
        return self

    def client_tls(self):
        context = ssl.create_default_context(cafile=str(self.directory / "ca.pem"))
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
        return context

    async def start(self, label):
        if label not in ("emqx", "hivemq", "mosquitto") or label in self.brokers:
            raise ValueError("Unknown or already running lab broker")
        port = self.endpoints[label].port if label in self.endpoints else 0
        broker = Broker({
            "listeners": {"default": {
                "type": "tcp", "bind": f"127.0.0.1:{port}", "max_connections": 24,
                "ssl": True, "cafile": str(self.directory / "ca.pem"),
                "certfile": str(self.directory / "server.pem"), "keyfile": str(self.directory / "server-key.pem"),
            }},
            "plugins": {"amqtt.plugins.authentication.AnonymousAuthPlugin": {"allow_anonymous": True}},
        })
        await broker.start()
        self.brokers[label] = broker
        # Pin amqtt: this private access only discovers the OS-assigned test port.
        address = broker._servers["default"].instance.sockets[0].getsockname()
        assert address[0] == "127.0.0.1"
        self.endpoints[label] = Endpoint(address[1])

    async def stop(self, label):
        broker = self.brokers.pop(label, None)
        if broker:
            await broker.shutdown()

    async def __aexit__(self, *_):
        try:
            for label in list(self.brokers):
                await self.stop(label)
        finally:
            if self._temporary:
                self._temporary.cleanup()
