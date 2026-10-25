"""Explicit multimodal CLI contracts; never pretend that plain path text is an image."""
from __future__ import annotations

import json
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory

from agent_vision import VISION_POLICY, VisionInputError, load_images


def _options(command, replacements, *, drop_prompt=False):
    result = []
    index = 0
    while index < len(command):
        value = command[index]
        option = value.split("=", 1)[0]
        if option in replacements:
            index += 1 if "=" in value else 2
        elif drop_prompt and value == "{prompt}":
            index += 1
        else:
            result.append(value)
            index += 1
    for option, value in replacements.items():
        result.extend([option, value])
    return result


@contextmanager
def cli_input(agent_id, command, text, paths, cwd, apply_prompt):
    if not paths:
        yield apply_prompt(command, text)
        return
    if agent_id not in {"codex", "claude", "hermes", "gemini"}:
        raise VisionInputError("vision_transport_unsupported: configure an image-capable ACP adapter for this agent")
    images = load_images(paths)
    prompt = text + "\n\n" + VISION_POLICY
    if agent_id == "claude":
        blocks = [{"type": "text", "text": prompt}]
        for image in images:
            blocks.extend([
                {"type": "text", "text": image.label},
                {"type": "image", "source": {"type": "base64", "media_type": image.mime_type,
                                                "data": image.encoded()}},
            ])
        args = _options(command, {"--input-format": "stream-json", "--output-format": "stream-json"}, drop_prompt=True)
        if "--verbose" not in args:
            args.append("--verbose")
        yield args, json.dumps({"type": "user", "message": {"role": "user", "content": blocks}},
                              ensure_ascii=False) + "\n"
        return
    if agent_id == "hermes" and len(images) > 2:
        raise VisionInputError("vision_transport_unsupported: this Hermes CLI accepts at most two image inputs; use ACP for more")
    temp_root = Path(cwd) / "temp"
    temp_root.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="vision-", dir=temp_root) as temporary:
        local_paths = []
        for index, image in enumerate(images):
            suffix = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "image/gif": ".gif"}[image.mime_type]
            path = Path(temporary) / f"input-{index + 1}{suffix}"
            path.write_bytes(image.data)
            local_paths.append(path)
            prompt += f"\nInput {index + 1}: {image.label}"
        if agent_id == "hermes":
            # Hermes' documented single-query parser accepts a leading image and --image.
            prompt = f'"{local_paths[0]}" {prompt}'
            args = list(command)
            if len(local_paths) == 2:
                args = _options(args, {"--image": str(local_paths[1])})
            yield apply_prompt(args, prompt)
        elif agent_id == "gemini":
            references = " ".join("@" + path.relative_to(cwd).as_posix() for path in local_paths)
            yield apply_prompt(command, prompt + "\n" + references)
        else:
            args = list(command)
            position = len(args) - 1 if args[-1:] == ["-"] else len(args)
            args[position:position] = [part for path in local_paths for part in ("--image", str(path))]
            yield apply_prompt(args, prompt)


def final_cli_output(agent_id: str, raw: str) -> str:
    if agent_id != "claude":
        return raw
    for line in reversed(raw.splitlines()):
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if isinstance(event, dict) and event.get("type") == "result":
            if event.get("is_error"):
                raise VisionInputError("vision_provider_failed: " + str(event.get("result") or event.get("subtype") or "unknown"))
            return str(event.get("result") or "")
    raise VisionInputError("vision_provider_failed: Claude returned no final result event")
