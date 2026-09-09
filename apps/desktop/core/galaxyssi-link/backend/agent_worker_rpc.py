"""Bounded synchronous worker RPCs over the existing authenticated peer transport."""
from dataclasses import dataclass, field
from copy import deepcopy
import hashlib
import json
import math
import threading
import time
import uuid

from agent_worker_registry import WorkerAccessError, _binding, _identifier

PROTOCOL = "galaxyssi.worker-control.v1"
OPERATIONS = frozenset({"status", "connect", "heartbeat", "poll", "renew", "report", "receipt"})
TRANSPORT_FIELDS = frozenset({"message_id", "conversation_id", "source_message_id", "_client_route_id"})
MAX_RESPONSE_BYTES = 512 * 1024 + 2048
MAX_REQUEST_BYTES = 16 * 1024 - 1024


def request_digest(payload):
    # These fields are added by the authenticated application envelope ingress.
    value = {key: item for key, item in payload.items() if key not in TRANSPORT_FIELDS}
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


class WorkerRpcError(RuntimeError):
    pass


def _copy(value, limit):
    try:
        encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        size = len(encoded.encode("utf-8"))
        if size > limit:
            raise WorkerRpcError("worker_rpc_payload_too_large")
        return json.loads(encoded), size
    except (TypeError, ValueError, RecursionError) as error:
        raise WorkerRpcError("worker_rpc_payload_invalid") from error


@dataclass(frozen=True)
class WorkerRpcResult:
    payload: dict = field(repr=False)
    sent_at: float
    received_at: float


@dataclass
class _Pending:
    binding: str = field(repr=False)
    digest: str = field(repr=False)
    sent_at: float
    deadline: float
    size: int
    ready: threading.Event = field(default_factory=threading.Event, repr=False)
    result: WorkerRpcResult | None = field(default=None, repr=False)
    error: str = ""


class AgentWorkerRpcClient:
    """Called by a local worker controller, never from an MQTT ingress callback.

    No request threads, timers, automatic enrollment or automatic model execution.
    Transport failure/timeout is ambiguous: callers retry the same logical RPC ID
    and sequence, not a new execution. Sender IO uses the existing transport bounds.
    """

    def __init__(self, get_peer, send, *, max_pending=128, per_route=16,
                 max_bytes=8 * 1024 * 1024, clock=time.monotonic):
        if any(type(n) is not int or n < 1 for n in (max_pending, per_route, max_bytes)):
            raise ValueError("Positive integer worker RPC limits are required")
        if max_pending > 128 or per_route > 128 or max_bytes > 64 * 1024 * 1024:
            raise ValueError("Worker RPC limits exceed the local safety ceiling")
        self._get_peer, self._send, self._clock = get_peer, send, clock
        self._max_pending, self._per_route, self._max_bytes = max_pending, per_route, max_bytes
        self._lock = threading.Lock()
        self._pending, self._routes, self._route_bytes = {}, {}, {}
        self._max_route_bytes = min(max_bytes, 1024 * 1024)
        self._bytes = 0
        self._closed = False

    def _peer(self, route):
        peer = self._get_peer(route)
        if not peer or peer.get("client_route_id") != route:
            raise WorkerRpcError("worker_rpc_pairing_unavailable")
        try:
            peer = deepcopy(peer)
            return peer, _binding(peer)
        except WorkerAccessError as error:
            raise WorkerRpcError("worker_rpc_pairing_unavailable") from error

    def request(self, route, operation, fields=None, *, request_id=None, timeout=10.0):
        if (not isinstance(route, str) or not isinstance(operation, str) or operation not in OPERATIONS
                or type(timeout) not in (float, int) or not math.isfinite(timeout) or not 0 < timeout <= 30):
            raise WorkerRpcError("worker_rpc_request_invalid")
        fields = {} if fields is None else fields
        reserved = TRANSPORT_FIELDS | {"type", "protocol", "request_id", "attempt_id"}
        if not isinstance(fields, dict) or reserved.intersection(fields):
            raise WorkerRpcError("worker_rpc_fields_invalid")
        try:
            request_id = _identifier(request_id if request_id is not None else uuid.uuid4().hex)
        except WorkerAccessError as error:
            raise WorkerRpcError("worker_rpc_request_id_invalid") from error
        payload, size = _copy(dict(fields, type=f"agent_worker_{operation}",
                                   protocol=PROTOCOL, request_id=request_id, attempt_id=uuid.uuid4().hex), MAX_REQUEST_BYTES)
        peer, binding = self._peer(route)
        started = self._clock()
        entry = _Pending(binding, request_digest(payload), started, started + timeout, size)
        key = (route, request_id)
        with self._lock:
            if self._closed:
                raise WorkerRpcError("worker_rpc_closed")
            if key in self._pending:
                raise WorkerRpcError("worker_rpc_already_pending")
            if (len(self._pending) >= self._max_pending or self._routes.get(route, 0) >= self._per_route
                    or self._bytes + size > self._max_bytes
                    or self._route_bytes.get(route, 0) + size > self._max_route_bytes):
                raise WorkerRpcError("worker_rpc_busy")
            self._pending[key] = entry
            self._routes[route] = self._routes.get(route, 0) + 1
            self._route_bytes[route] = self._route_bytes.get(route, 0) + size
            self._bytes += size
        try:
            # Never hold the correlation lock while publishing or waiting.
            if self._peer(route)[1] != binding:
                raise WorkerRpcError("worker_rpc_pairing_changed")
            with self._lock:
                if entry.error:
                    raise WorkerRpcError(entry.error)
            if self._clock() >= entry.deadline:
                raise WorkerRpcError("worker_rpc_timeout")
            try:
                sent = self._send(peer, payload)
            except Exception as error:
                raise WorkerRpcError("worker_rpc_publish_failed") from error
            if not sent and not entry.ready.is_set():
                raise WorkerRpcError("worker_rpc_publish_failed")
            if not entry.ready.wait(max(0, entry.deadline - self._clock())):
                raise WorkerRpcError("worker_rpc_timeout")
            if entry.error:
                raise WorkerRpcError(entry.error)
            if self._peer(route)[1] != binding:
                raise WorkerRpcError("worker_rpc_pairing_changed")
            return entry.result
        finally:
            with self._lock:
                self._pending.pop(key)
                self._bytes -= entry.size
                self._routes[route] -= 1
                self._route_bytes[route] -= entry.size
                if not self._routes[route]:
                    del self._routes[route]
                    del self._route_bytes[route]

    def receive(self, peer, source, payload):
        """Only after Signal decryption and application source validation."""
        if (not isinstance(peer, dict) or source != peer.get("signal_name")
                or not isinstance(payload, dict) or payload.get("type") != "agent_worker_response"
                or payload.get("protocol") != PROTOCOL or type(payload.get("ok")) is not bool
                or not isinstance(payload.get("request_id"), str)):
            return False
        route = peer.get("client_route_id")
        if not isinstance(route, str):
            return False
        try:
            binding = _binding(peer)
            if binding != self._peer(route)[1]:
                return False
        except (WorkerAccessError, WorkerRpcError):
            return False
        key = (route, payload["request_id"])
        with self._lock:
            entry = self._pending.get(key)
            if (entry is None or entry.ready.is_set() or entry.binding != binding
                    or payload.get("request_digest") != entry.digest or self._clock() >= entry.deadline):
                return False
        try:
            value, size = _copy(payload, MAX_RESPONSE_BYTES)
        except WorkerRpcError:
            return False
        with self._lock:
            received = self._clock()
            if (self._pending.get(key) is not entry or entry.ready.is_set()
                    or received >= entry.deadline or self._bytes + size > self._max_bytes
                    or self._route_bytes[route] + size > self._max_route_bytes):
                return False
            entry.result = WorkerRpcResult(value, entry.sent_at, received)
            entry.size += size
            self._bytes += size
            self._route_bytes[route] += size
            entry.ready.set()
            return True

    def close(self):
        with self._lock:
            self._closed = True
            for entry in self._pending.values():
                entry.error = "worker_rpc_closed"
                entry.ready.set()

    def snapshot(self):
        with self._lock:
            return {"pending": len(self._pending), "routes": len(self._routes), "bytes": self._bytes,
                    "max_pending": self._max_pending, "per_route": self._per_route,
                    "max_bytes": self._max_bytes, "max_route_bytes": self._max_route_bytes, "closed": self._closed}
