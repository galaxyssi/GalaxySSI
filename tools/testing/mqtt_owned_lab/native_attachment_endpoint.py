"""Test-only phone-protocol sender; the Desktop attachment consumer stays real."""
import base64
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import threading
import uuid


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


class AttachmentEndpoint:
    def __init__(self, endpoint):
        self.endpoint = endpoint
        self.root = endpoint.root / "attachment-fixtures"
        self.root.mkdir(exist_ok=True)
        self.lock = threading.RLock()
        self.receipt_path = self.root / "receipts.json"
        self.receipts = json.loads(self.receipt_path.read_text()) if self.receipt_path.exists() else {}

    def case_path(self, case):
        if not isinstance(case, str) or not re.fullmatch(r"[a-f0-9]{32}", case):
            raise ValueError("Invalid owned attachment case")
        return self.root / case

    def load(self, case):
        directory = self.case_path(case)
        return directory, json.loads((directory / "case.json").read_text())

    def prepare(self, value):
        from input_attachment_transfer import ATTACHMENT_CHUNK_BYTES, transfer_id_for
        from link_protocol import valid_route_id
        route = value["receiver_route"]
        if not valid_route_id(route) or len(list(self.root.glob("*/case.json"))) >= 16:
            raise ValueError("Invalid or excessive owned attachment case")
        kind = value["kind"]
        if kind not in {"png", "video", "file"}:
            raise ValueError("Unsupported owned attachment kind")
        if kind == "file" and (type(value.get("size")) is not int or not 1 <= value["size"] <= 32 * 1024 * 1024):
            raise ValueError("Owned fixture byte limit exceeded")
        case = uuid.uuid4().hex
        directory = self.case_path(case)
        directory.mkdir()
        if kind == "png":
            from PIL import Image
            source, mime = directory / "owned-image.png", "image/png"
            Image.frombytes("RGB", (200, 170), random.Random(1234).randbytes(102000)).save(source)
        elif kind == "video":
            source, mime = directory / "owned-video.mp4", "video/mp4"
            ffmpeg = shutil.which("ffmpeg")
            if not ffmpeg:
                raise ValueError("FFmpeg required for actual video fixture")
            subprocess.run([ffmpeg, "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=426x240:rate=12",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=16000", "-t", "2", "-c:v", "libx264",
                "-threads", "2", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "32k", "-movflags", "+faststart", str(source)],
                check=True, capture_output=True, timeout=30, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        elif kind == "file":
            size = value["size"]
            source, mime = directory / "owned-file.bin", "application/octet-stream"
            generator = random.Random(1234)
            with source.open("xb") as stream:
                remaining = size
                while remaining:
                    chunk = generator.randbytes(min(remaining, 1024 * 1024))
                    stream.write(chunk)
                    remaining -= len(chunk)
        size, sha = source.stat().st_size, digest(source)
        manifest = {"client_route_id": route, "conversation_id": "owned-attachment-" + case,
            "task_id": case, "turn_id": "turn-" + case, "contact_id": self.endpoint.remote,
            "attachment_id": "attachment-" + case, "attachment_ordinal": 0, "client_message_id": "1",
            "name": source.name, "mime_type": mime, "size_bytes": size, "original_size_bytes": size,
            "sha256": sha, "chunk_size_bytes": ATTACHMENT_CHUNK_BYTES,
            "chunk_count": (size + ATTACHMENT_CHUNK_BYTES - 1) // ATTACHMENT_CHUNK_BYTES}
        manifest["transfer_id"] = transfer_id_for(*(manifest[key] for key in
            ("client_route_id", "conversation_id", "task_id", "turn_id", "attachment_id", "sha256")))
        record = {"case": case, "kind": kind, "source": source.name, "manifest": manifest,
                  "message_id": str(uuid.uuid4())}
        (directory / "case.json").write_text(json.dumps(record), encoding="utf-8")
        return record

    def capture_receipt(self, payload):
        # Only the phone-side business receipt consumer is a fixture. Crypto,
        # inbox persistence and every Desktop input consumer remain production.
        transfer = payload.get("transfer_id")
        records = [json.loads(path.read_text()) for path in self.root.glob("*/case.json")]
        record = next((item for item in records if item["manifest"]["transfer_id"] == transfer), None)
        if record is None or any(payload.get(key) != record["manifest"][key] for key in
                                 ("sha256", "client_route_id", "conversation_id", "contact_id", "task_id", "turn_id", "attachment_id")):
            raise ValueError("Unexpected authenticated attachment receipt")
        with self.lock:
            self.receipts[transfer] = dict(payload)
            temporary = self.receipt_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(self.receipts), encoding="utf-8")
            os.replace(temporary, self.receipt_path)

    def send(self, case, operation, index=None):
        directory, record = self.load(case)
        manifest = record["manifest"]
        if operation == "peer":
            payload = {**manifest, "type": "peer_message", "message_id": record["message_id"],
                "source_message_id": record["message_id"], "content": "owned-attachment-" + case,
                "attachments": [{"id": manifest["attachment_id"], "transfer_id": manifest["transfer_id"],
                    "name": manifest["name"], "mime_type": manifest["mime_type"], "size": manifest["size_bytes"],
                    "transport_status": "chunked", "sha256": manifest["sha256"]}], "peer_chat": True}
        else:
            payload = {**manifest, "type": "input_attachment_" + operation, "message_id": str(uuid.uuid4())}
            if operation == "manifest":
                payload.update(resume=True, eager_chunks=False)
            elif operation == "chunk":
                if type(index) is not int or not 0 <= index < manifest["chunk_count"]:
                    raise ValueError("Invalid owned chunk index")
                with (directory / record["source"]).open("rb") as source:
                    source.seek(index * manifest["chunk_size_bytes"])
                    data = source.read(manifest["chunk_size_bytes"])
                payload.update(chunk_index=index, chunk_size=len(data), chunk_sha256=hashlib.sha256(data).hexdigest(),
                               data_b64=base64.b64encode(data).decode())
            else:
                raise ValueError("Unsupported owned attachment operation")
        if getattr(self.endpoint, "measurements", None):
            self.endpoint.measurements.begin(payload["message_id"])
        ok = self.endpoint.bridge._publish_phone_payload(self.endpoint.client,
                {"_client_route_id": self.endpoint.route}, payload)
        return {"queued": bool(ok), "message_id": payload["message_id"]}

    def inspect(self, manifest, message_id):
        from peer_chat_store import peer_chat_store, _REMOTE_PURPOSE
        from secure_state import unseal_identifier
        from input_attachment_transfer import resolved_attachment_path
        source = resolved_attachment_path(manifest, client_route_id=self.endpoint.route,
            conversation_id=manifest["conversation_id"], task_id=manifest["task_id"], turn_id=manifest["turn_id"])
        if source is None:
            return {"complete": False}
        if not source.resolve().is_relative_to((self.endpoint.root / "workspace").resolve()):
            raise ValueError("Transfer escaped isolated workspace")
        store = peer_chat_store()
        with closing(store._connect()) as db:
            ids = [row[0] for row in db.execute("SELECT message_id,remote_message_id FROM peer_messages WHERE direction='inbound'")
                   if unseal_identifier(store.database_path, row[1], purpose=_REMOTE_PURPOSE) == message_id]
        result = {"complete": True, "sha256": digest(source), "size": source.stat().st_size, "business_rows": len(ids)}
        if len(ids) == 1:
            message = store.get_message(ids[0])
            contents = hashlib.sha256()
            size = 0
            for block in store.stream_attachment(ids[0], 0):
                contents.update(block)
                size += len(block)
            result.update(stream_sha256=contents.hexdigest(), stream_size=size,
                          attachments=message["attachments"], route_ok=message["client_route_id"] == self.endpoint.route)
            if manifest["mime_type"] == "image/png":
                from PIL import Image
                with Image.open(source) as image:
                    result["image_size"] = list(image.size)
                    image.verify()
                result["media_valid"] = True
            elif manifest["mime_type"] == "video/mp4":
                ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
                if not ffmpeg or not ffprobe:
                    raise ValueError("FFmpeg and ffprobe required to verify received video")
                probe = subprocess.run([ffprobe, "-v", "error", "-show_entries", "stream=codec_type,codec_name,width,height:format=duration",
                    "-of", "json", str(source)], check=True, capture_output=True, timeout=20,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                result["video"] = json.loads(probe.stdout)
                subprocess.run([ffmpeg, "-v", "error", "-i", str(source), "-f", "null", "-"], check=True,
                    capture_output=True, timeout=30, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                result["media_valid"] = True
        return result

    def command(self, value):
        op = value["operation"]
        if op == "prepare":
            return self.prepare(value)
        if op in {"manifest", "chunk", "peer"}:
            return self.send(value["case"], op, value.get("index"))
        if op == "receipt":
            with self.lock:
                return self.receipts.get(value["transfer_id"])
        if op == "inspect":
            return self.inspect(value["manifest"], value["message_id"])
        raise ValueError("Unsupported attachment fixture command")
