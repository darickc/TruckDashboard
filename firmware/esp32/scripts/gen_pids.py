#!/usr/bin/env python3
"""
gen_pids.py — one-shot generator: exportedPIDs.csv (Torque Pro export) -> C++
PID table rows for lib/ObdCore/src/PidDefs.cpp.

Usage (from firmware/esp32/):
    python3 scripts/gen_pids.py            # reads the repo's Torque export
    python3 scripts/gen_pids.py <file.csv>

The output is REVIEWED BY A HUMAN and pasted into PidDefs.cpp — this script
is not part of the build. Rationale: mechanically transcribing 50+ scale
factors avoids typo bugs (0.03625 vs 0.3625 silently corrupts boost), while a
checked-in table keeps the firmware reviewable and free of runtime expression
parsing.

What it does:
  * ModeAndPID "0x221310" -> service 0x22, DID 0x1310 (UDS read-by-identifier).
    "0x0105" -> service 0x01, PID 0x05.
  * Folds each Torque equation into LinearDecode {byteOffset, width, isSigned,
    scale, bias} by evaluating it at raw=0/1/large and checking linearity.
    'signed(A)' maps to isSigned. Anything non-linear (e.g. BARO()) is flagged
    '// MANUAL:' and NEVER guessed.
  * Header mapping: 'Auto' -> ObdModule::Auto (ELM default functional 7DF);
    symbolic names ('TCM', 'ABS') -> module enums whose ATSH header is nullptr
    (UNVERIFIED — must be confirmed on the truck); literal hex ('726',
    'C410F1') passes through verbatim.
  * Rows in the curated ALLOWLIST get PidKey/ChannelId/poll metadata and are
    emitted as active table rows; everything else is emitted as a reference
    comment block for future use.
"""

import csv
from pathlib import Path
import re
import sys

# (ModeAndPID lower-case, Header) -> (PidKey, ChannelId, pollMs, priority, timeoutMs, retries)
ALLOWLIST = {
    ("0x221310", "Auto"): ("Eot", "EotF", 500, 3, 500, 2),
    ("0x2209d0", "Auto"): ("FicmMainPower", "FicmMainV", 400, 3, 500, 2),
    ("0x221446", "Auto"): ("Icp", "IcpPsi", 100, 1, 500, 2),
    ("0x221434", "Auto"): ("IprDuty", "IprPct", 150, 2, 500, 2),
    ("0x22096d", "Auto"): ("VgtDuty", "VgtPct", 150, 2, 500, 2),
    ("0x221440", "Auto"): ("Map", "MapPsi", 100, 0, 500, 2),  # plain-MAP row only
    ("0x221445", "Auto"): ("Ebp", "EbpPsi", 200, 2, 500, 2),
    ("0x221674", "Auto"): ("TransTemp1", "TransTempF", 500, 3, 500, 2),
    ("0x221674", "TCM"): ("TransTemp2", "TransTempF", 500, 3, 500, 2),
    ("0x2211bd", "C410F1"): ("TransTemp3", "TransTempF", 500, 3, 500, 2),
    ("0x2211b3", "Auto"): ("Gear1", "GearNum", 500, 4, 500, 2),
    ("0x2211b3", "TCM"): ("Gear2", "GearNum", 500, 4, 500, 2),
    ("0x221172", "Auto"): ("BatteryVoltage", "BatteryV", 1000, 4, 500, 2),
}

UNIT_MAP = {
    "°c": "Celsius", "°f": "Fahrenheit", "psi": "Psi", "v": "Volts",
    "volts": "Volts", "%": "Percent", "km/h": "Kmh", "rpm": "Rpm",
    "gear": "Gear", "count": "Count", "µs": "Microseconds",
    "mg/stroke": "MgPerStroke", "gph": "Gph", "deg.": "Degrees",
    "°": "Degrees", "g": "Gforce",
}

HEADER_MAP = {
    "Auto": "Auto", "TCM": "Tcm", "ABS": "Abs",
    "726": "Hdr726", "C410F1": "HdrC410F1",
}


def fold_linear(equation):
    """Fold a Torque equation into (byteOffset, width, isSigned, scale, bias).

    Returns None when the equation is not a linear function of a single 1- or
    2-byte big-endian field (those rows are flagged MANUAL, never guessed).
    """
    eq = equation.strip()
    is_signed = "signed(" in eq
    eq = eq.replace("signed(A)", "A")  # sign handled by the decoder
    if re.search(r"[a-zA-Z_]{2,}\(", eq):  # any remaining function call: BARO() etc.
        return None

    letters = sorted(set(re.findall(r"\b([ABCD])\b", eq)))
    if not letters:
        return None

    two_byte = re.search(r"\(\s*(?:A\s*\*\s*256|256\s*\*\s*A)\s*\)\s*\+\s*B", eq)
    if two_byte:
        if letters != ["A", "B"]:
            return None
        offset, width = 0, 2

        def f(raw):
            return eval(eq, {"__builtins__": {}}, {"A": (raw >> 8) & 0xFF, "B": raw & 0xFF})
    elif len(letters) == 1:
        offset, width = "ABCD".index(letters[0]), 1

        def f(raw):
            return eval(eq, {"__builtins__": {}}, {letters[0]: raw})
    else:
        return None

    try:
        bias = float(f(0))
        scale = float(f(1)) - bias
        # Linearity check at two more points.
        for probe in (7, 200 if width == 1 else 20000):
            if abs(f(probe) - (bias + scale * probe)) > 1e-6 * max(1.0, abs(f(probe))):
                return None
    except Exception:
        return None
    return offset, width, is_signed, scale, bias


def fmt_float(x):
    if x == int(x) and abs(x) < 1e7:
        return f"{x:.1f}f"
    return f"{x:.9g}f"


# The export lives with the signal registry, not with the firmware.
DEFAULT_CSV = (Path(__file__).resolve().parents[3]
               / "shared/signals/imports/torque/exportedPIDs.csv")


def main(path):
    active, comments, manual = [], [], []
    with open(path, newline="") as fh:
        reader = csv.reader(fh, skipinitialspace=True)
        header = next(reader)
        assert header[0].strip('" ') == "Name", f"unexpected CSV header: {header}"
        for row in reader:
            if len(row) < 12:
                continue
            name, short, mode_pid, equation = (c.strip() for c in row[0:4])
            units, hdr = row[6].strip(), row[7].strip()
            mp = mode_pid.lower()
            value = int(mp, 16)
            if value > 0xFFFF:  # e.g. 0x221310
                service, pid = (value >> 16) & 0xFF, value & 0xFFFF
            else:  # e.g. 0x0105
                service, pid = (value >> 8) & 0xFF, value & 0xFF

            lin = fold_linear(equation)
            unit = UNIT_MAP.get(units.lower(), "None")
            module = HEADER_MAP.get(hdr)
            if module is None:
                manual.append(f"// MANUAL: {name}: unmapped header '{hdr}'")
                continue

            meta = ALLOWLIST.get((mp, hdr))
            if lin is None:
                manual.append(
                    f"// MANUAL: {name} ({mode_pid}, hdr {hdr}): non-linear equation"
                    f" '{equation}' — implement by hand if needed"
                    + (" (boost = MAP - baro lives in Derived.cpp)" if "BARO" in equation else "")
                )
                continue

            off, width, signed, scale, bias = lin
            if meta is not None:
                key, channel, poll, prio, timeout, retries = meta
                active.append(
                    f"    // {name} — Torque: {mode_pid} \"{equation}\" [{units}] hdr={hdr}\n"
                    f"    {{PidKey::{key}, ChannelId::{channel}, \"{name.replace('[FORD]', '')}\", \"{short}\",\n"
                    f"     0x{service:02X}, 0x{pid:04X}, ObdModule::{module},\n"
                    f"     {{{off}, {width}, {'true' if signed else 'false'}, {fmt_float(scale)}, {fmt_float(bias)}}},\n"
                    f"     nullptr, Unit::{unit}, {poll}, {prio}, {timeout}, {retries}, false}},"
                )
            else:
                comments.append(
                    f"//   {name}: svc 0x{service:02X} pid 0x{pid:04X} hdr={hdr}"
                    f" decode{{{off},{width},{'S' if signed else 'U'},{scale:.9g},{bias:.9g}}} [{units}]"
                )

    print("// ---- generated by scripts/gen_pids.py from exportedPIDs.csv ----")
    print("// ---- ACTIVE ROWS (curated allowlist) ----")
    for a in active:
        print(a)
    print()
    print("// ---- MANUAL-ATTENTION ROWS ----")
    for m in manual:
        print(m)
    print()
    print("// ---- REMAINING TORQUE EXPORT ROWS (reference, not in table) ----")
    for c in comments:
        print(c)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else str(DEFAULT_CSV))
