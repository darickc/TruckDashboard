"""Synthetic NMEA over UDP, for capturing gpsd's JSON output on the Mac.
Phases: no fix (5 s), 3D fix moving north-east (8 s), 2D fix (3 s), no fix (3 s)."""
import socket, sys, time, datetime

def cs(body):
    c = 0
    for ch in body:
        c ^= ord(ch)
    return f"${body}*{c:02X}\r\n"

def dm(v, lat):
    a = abs(v); d = int(a); m = (a - d) * 60
    if lat:
        return f"{d:02d}{m:07.4f}", "N" if v >= 0 else "S"
    return f"{d:03d}{m:07.4f}", "E" if v >= 0 else "W"

port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
lat, lon = 39.8283, -98.5795
t0 = datetime.datetime(2026, 11, 11, 18, 0, 0)
for i in range(19):
    t = t0 + datetime.timedelta(seconds=i)
    hms = t.strftime("%H%M%S") + ".00"
    dmy = t.strftime("%d%m%y")
    if i < 5 or i >= 16:
        q, sats, mode, valid = 0, 2, 1, "V"
    elif i < 13:
        q, sats, mode, valid = 1, 8, 3, "A"
        lat += 0.0002; lon += 0.0002
    else:
        q, sats, mode, valid = 1, 3, 2, "A"
    la, ns = dm(lat, True); lo, ew = dm(lon, False)
    speed_kn = 30.0 if valid == "A" else 0.0
    msgs = []
    if q:
        msgs.append(cs(f"GPGGA,{hms},{la},{ns},{lo},{ew},{q},{sats:02d},1.2,{560.0 if mode == 3 else ''},M,-24.0,M,,"))
        msgs.append(cs(f"GPRMC,{hms},{valid},{la},{ns},{lo},{ew},{speed_kn:.1f},45.0,{dmy},,,A"))
    else:
        msgs.append(cs(f"GPGGA,{hms},,,,,0,{sats:02d},,,M,,M,,"))
        msgs.append(cs(f"GPRMC,{hms},V,,,,,,,{dmy},,,N"))
    used = [str(n) for n in range(1, sats + 1)] if q else []
    used += [""] * (12 - len(used))
    msgs.append(cs(f"GPGSA,A,{mode},{','.join(used)},2.1,1.2,1.7"))
    svs = [f"{n:02d},{30 + n},{n * 30 % 360:03d},{35 + n}" for n in range(1, 9)]
    msgs.append(cs(f"GPGSV,2,1,08,{','.join(svs[:4])}"))
    msgs.append(cs(f"GPGSV,2,2,08,{','.join(svs[4:])}"))
    s.sendto("".join(msgs).encode(), ("127.0.0.1", port))
    time.sleep(1)
