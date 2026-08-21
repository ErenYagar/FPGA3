#!/usr/bin/env python3
"""Stream NIST GCM .rsp vectors to the FPGA3 Arty UART image."""

import argparse
import hashlib
import json
import sys
import time
from datetime import datetime
from pathlib import Path

import serial


CMD_MODE = 0x01
CMD_KEY = 0x02
CMD_IV = 0x03
CMD_AAD = 0x04
CMD_PT = 0x05
CMD_CT = 0x06
CMD_TAG = 0x07
CMD_RUN = 0x08

RSP_STATUS = 0x80
RSP_DATA = 0x81
RSP_TAG = 0x82

STAT_ENC_OK = 0x00
STAT_DEC_OK = 0x01
STAT_AUTH_FAIL = 0xFF


def parse_rsp(path: Path, mode: str):
    section = {}
    current = None
    with path.open("r", encoding="ascii") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("[") and line.endswith("]"):
                name, value = (part.strip() for part in line[1:-1].split("=", 1))
                section[name] = int(value)
            elif line.startswith("Count ="):
                if current is not None:
                    yield current
                current = dict(section)
                current.update(
                    Count=int(line.split("=", 1)[1]),
                    FAIL=False,
                    mode=mode,
                    source=path.name,
                )
            elif current is not None and line == "FAIL":
                current["FAIL"] = True
            elif current is not None:
                name, value = (part.strip() for part in line.split("=", 1))
                current[name] = value.lower()
    if current is not None:
        yield current


def to_bytes(value: str) -> bytes:
    return bytes.fromhex(value) if value else b""


def send_frame(port, command: int, bit_length: int, payload: bytes):
    expected_bytes = (bit_length + 7) // 8
    if len(payload) != expected_bytes:
        raise ValueError(
            f"command 0x{command:02x}: payload={len(payload)} expected={expected_bytes}"
        )
    port.write(bytes((command, (bit_length >> 8) & 0xFF, bit_length & 0xFF)))
    if payload:
        port.write(payload)


def recv_exact(port, count: int) -> bytes:
    result = bytearray()
    deadline = time.monotonic() + port.timeout
    while len(result) < count:
        chunk = port.read(count - len(result))
        if chunk:
            result.extend(chunk)
        elif time.monotonic() >= deadline:
            raise TimeoutError(f"UART timeout: received {len(result)}/{count} bytes")
    return bytes(result)


def recv_frame(port):
    header = recv_exact(port, 3)
    frame_type = header[0]
    bit_length = (header[1] << 8) | header[2]
    payload = recv_exact(port, (bit_length + 7) // 8)
    return frame_type, bit_length, payload


def execute_case(port, case):
    mode = case["mode"]
    key = to_bytes(case["Key"])
    iv = to_bytes(case["IV"])
    aad = to_bytes(case.get("AAD", ""))
    data = to_bytes(case.get("PT", "") if mode == "enc" else case.get("CT", ""))
    tag = (bytes((case["Taglen"] + 7) // 8) if mode == "enc"
           else to_bytes(case["Tag"]))

    send_frame(port, CMD_MODE, 8, bytes((0 if mode == "enc" else 1,)))
    send_frame(port, CMD_KEY, case["Keylen"], key)
    send_frame(port, CMD_IV, case["IVlen"], iv)
    send_frame(port, CMD_AAD, case["AADlen"], aad)
    send_frame(port, CMD_PT if mode == "enc" else CMD_CT, case["PTlen"], data)
    send_frame(port, CMD_TAG, case["Taglen"], tag)
    send_frame(port, CMD_RUN, 0, b"")
    port.flush()

    frame_type, status_bits, status_payload = recv_frame(port)
    if frame_type != RSP_STATUS or status_bits != 8 or len(status_payload) != 1:
        raise RuntimeError(
            f"bad status frame type=0x{frame_type:02x} bits={status_bits}"
        )
    status = status_payload[0]
    observed_data = b""
    observed_tag = b""

    if mode == "enc":
        if case["PTlen"]:
            frame_type, data_bits, observed_data = recv_frame(port)
            if frame_type != RSP_DATA or data_bits != case["PTlen"]:
                raise RuntimeError(
                    f"bad ciphertext frame type=0x{frame_type:02x} bits={data_bits}"
                )
        frame_type, tag_bits, observed_tag = recv_frame(port)
        if frame_type != RSP_TAG or tag_bits != case["Taglen"]:
            raise RuntimeError(
                f"bad tag frame type=0x{frame_type:02x} bits={tag_bits}"
            )
        expected_status = STAT_ENC_OK
        expected_data = to_bytes(case.get("CT", ""))
        expected_tag = to_bytes(case["Tag"])
    elif case["FAIL"]:
        expected_status = STAT_AUTH_FAIL
        expected_data = b""
        expected_tag = b""
    else:
        if case["PTlen"]:
            frame_type, data_bits, observed_data = recv_frame(port)
            if frame_type != RSP_DATA or data_bits != case["PTlen"]:
                raise RuntimeError(
                    f"bad plaintext frame type=0x{frame_type:02x} bits={data_bits}"
                )
        expected_status = STAT_DEC_OK
        expected_data = to_bytes(case.get("PT", ""))
        expected_tag = b""

    passed = (
        status == expected_status
        and observed_data == expected_data
        and observed_tag == expected_tag
    )
    return {
        "passed": passed,
        "status": status,
        "expected_status": expected_status,
        "data": observed_data.hex(),
        "expected_data": expected_data.hex(),
        "tag": observed_tag.hex(),
        "expected_tag": expected_tag.hex(),
    }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="COM4")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--progress", type=int, default=100)
    parser.add_argument("--stop-on-fail", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--bitstream", type=Path)
    parser.add_argument("files", nargs="*", type=Path)
    args = parser.parse_args()

    board_dir = Path(__file__).resolve().parent
    rsp_dir = board_dir.parents[1] / "rtl" / "functional test" / "rsp"
    files = args.files or [
        rsp_dir / "gcmEncryptExtIV128.rsp",
        rsp_dir / "gcmEncryptExtIV192.rsp",
        rsp_dir / "gcmEncryptExtIV256.rsp",
        rsp_dir / "gcmDecrypt128.rsp",
        rsp_dir / "gcmDecrypt192.rsp",
        rsp_dir / "gcmDecrypt256.rsp",
    ]
    cases = []
    for path in files:
        mode = "enc" if "encrypt" in path.name.lower() else "dec"
        cases.extend(parse_rsp(path, mode))
    if args.limit is not None:
        cases = cases[: args.limit]

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output = args.output or board_dir / "results" / f"nist_uart_{timestamp}.jsonl"
    output.parent.mkdir(parents=True, exist_ok=True)
    summary_path = output.with_suffix(".summary.json")
    passed = 0
    failed = 0
    first_failure = None
    started = time.monotonic()

    with serial.Serial(args.port, args.baud, timeout=args.timeout) as port:
        time.sleep(0.1)
        port.reset_input_buffer()
        port.reset_output_buffer()
        with output.open("w", encoding="utf-8") as evidence:
            for index, case in enumerate(cases):
                case_started = time.monotonic()
                try:
                    result = execute_case(port, case)
                except Exception as exc:
                    result = {"passed": False, "exception": str(exc)}
                record = {
                    "global_index": index,
                    "source": case["source"],
                    "Count": case["Count"],
                    "mode": case["mode"],
                    "Keylen": case["Keylen"],
                    "IVlen": case["IVlen"],
                    "AADlen": case["AADlen"],
                    "PTlen": case["PTlen"],
                    "Taglen": case["Taglen"],
                    "expected_fail": case["FAIL"],
                    "elapsed_ms": round((time.monotonic() - case_started) * 1000, 3),
                    **result,
                }
                evidence.write(json.dumps(record, sort_keys=True) + "\n")
                evidence.flush()
                if result["passed"]:
                    passed += 1
                else:
                    failed += 1
                    if first_failure is None:
                        first_failure = record
                    print("FAIL", json.dumps(record, sort_keys=True), flush=True)
                    if args.stop_on_fail:
                        break
                if args.progress and (index + 1) % args.progress == 0:
                    elapsed = time.monotonic() - started
                    print(
                        f"NIST_UART_PROGRESS done={index + 1} pass={passed} "
                        f"fail={failed} elapsed_s={elapsed:.1f}",
                        flush=True,
                    )

    summary = {
        "port": args.port,
        "baud": args.baud,
        "requested": len(cases),
        "executed": passed + failed,
        "pass": passed,
        "fail": failed,
        "elapsed_s": round(time.monotonic() - started, 3),
        "files": [{"path": str(path), "sha256": sha256(path)} for path in files],
        "bitstream": str(args.bitstream) if args.bitstream else None,
        "bitstream_sha256": sha256(args.bitstream) if args.bitstream else None,
        "first_failure": first_failure,
        "evidence": str(output),
    }
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")
    print("NIST_UART_SUMMARY", json.dumps(summary, sort_keys=True), flush=True)
    if failed or passed != len(cases):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
