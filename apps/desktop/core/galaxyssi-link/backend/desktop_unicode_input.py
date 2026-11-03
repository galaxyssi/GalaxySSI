"""Correctly sized Win32 INPUT union for Unicode SendInput on x86 and x64."""
import ctypes


class KeyboardInput(ctypes.Structure):
    _fields_ = [("vk", ctypes.c_uint16), ("scan", ctypes.c_uint16),
                ("flags", ctypes.c_uint32), ("time", ctypes.c_uint32), ("extra", ctypes.c_size_t)]


class MouseInput(ctypes.Structure):
    _fields_ = [("dx", ctypes.c_int32), ("dy", ctypes.c_int32), ("data", ctypes.c_uint32),
                ("flags", ctypes.c_uint32), ("time", ctypes.c_uint32), ("extra", ctypes.c_size_t)]


class HardwareInput(ctypes.Structure):
    _fields_ = [("message", ctypes.c_uint32), ("low", ctypes.c_uint16), ("high", ctypes.c_uint16)]


class InputUnion(ctypes.Union):
    _fields_ = [("ki", KeyboardInput), ("mi", MouseInput), ("hi", HardwareInput)]


class Input(ctypes.Structure):
    _anonymous_ = ("value",)
    _fields_ = [("type", ctypes.c_uint32), ("value", InputUnion)]


def unicode_events(text: str):
    encoded = bytearray(text.encode("utf-16-le"))
    events = []
    try:
        for offset in range(0, len(encoded), 2):
            unit = int.from_bytes(encoded[offset:offset + 2], "little")
            events.extend((Input(type=1, ki=KeyboardInput(0, unit, 4, 0, 0)),
                           Input(type=1, ki=KeyboardInput(0, unit, 6, 0, 0))))
        return (Input * len(events))(*events)
    finally:
        encoded[:] = b"\0" * len(encoded)


def send_unicode(text: str) -> bool:
    events = unicode_events(text)
    try:
        send = ctypes.windll.user32.SendInput
        send.argtypes = [ctypes.c_uint32, ctypes.POINTER(Input), ctypes.c_int]
        send.restype = ctypes.c_uint32
        return send(len(events), events, ctypes.sizeof(Input)) == len(events)
    finally:
        ctypes.memset(ctypes.addressof(events), 0, ctypes.sizeof(events))
