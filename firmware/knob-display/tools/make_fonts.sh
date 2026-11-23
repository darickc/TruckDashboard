#!/bin/sh
# The dial's fonts (ADR-0044): LVGL's built-in fonts have no "°" or "—",
# which the dial's text uses, and stop at 48 px. Generates src/fonts/*.c with
# lv_font_conv 1.5.3 from Montserrat (SIL Open Font License 1.1):
#   - Medium: the copy inside the LVGL package;
#   - SemiBold: from the Montserrat project's release v7.222, checked against
#     its SHA-256 and kept in .pio/fonts/.
#
#   make knob-fonts        (or: sh tools/make_fonts.sh, from firmware/knob-display)
#
# Needs Node (npx), curl and the LVGL package (pio pkg install -e knob).
set -eu
cd "$(dirname "$0")/.."

MEDIUM=.pio/libdeps/knob/lvgl/scripts/built_in_font/Montserrat-Medium.ttf
if [ ! -f "$MEDIUM" ]; then
    echo "missing $MEDIUM: run 'pio pkg install -e knob' first" >&2
    exit 1
fi

SEMIBOLD=.pio/fonts/Montserrat-SemiBold-v7.222.ttf
SEMIBOLD_URL=https://raw.githubusercontent.com/JulietaUla/Montserrat/v7.222/fonts/ttf/Montserrat-SemiBold.ttf
SEMIBOLD_SHA256=49fbfce003ad1692d7c9a6502791577088c12c50088d4caa27dbbfe540ad9d13
if [ ! -f "$SEMIBOLD" ]; then
    mkdir -p .pio/fonts
    curl -sSLf -o "$SEMIBOLD.part" "$SEMIBOLD_URL"
    mv "$SEMIBOLD.part" "$SEMIBOLD"
fi
echo "$SEMIBOLD_SHA256  $SEMIBOLD" | shasum -a 256 -c - >/dev/null || {
    echo "$SEMIBOLD: checksum doesn't match $SEMIBOLD_SHA256" >&2
    rm -f "$SEMIBOLD"
    exit 1
}

CONV="npx --yes lv_font_conv@1.5.3"
OUT=src/fonts
mkdir -p "$OUT"
rm -f "$OUT"/dial_*.c

# Text: ASCII, Latin-1, ° − – — ‘ ’ “ ” …
TEXT=0x20-0x7E,0xA0-0xFF,0x2212,0x2013-0x2014,0x2018-0x2019,0x201C-0x201D,0x2026
# Numbers with their signs and units.
NUM=0x20-0x7E,0xB0,0x2212,0x2014
# Small capitals for names and labels: as TEXT (a phone's name can have
# accented letters).
CAPS=$TEXT

gen() { # name font size range
    $CONV --no-compress --no-prefilter --bpp 4 --format lvgl --size "$3" \
        --font "$2" --range "$4" --lv-font-name "$1" -o "$OUT/$1.c"
    echo "  $OUT/$1.c"
}

echo "fonts:"
gen dial_speed "$SEMIBOLD" 120 0x30-0x39,0x2014
gen dial_big "$SEMIBOLD" 56 "$NUM"
gen dial_caller "$SEMIBOLD" 30 "$TEXT"
gen dial_title "$SEMIBOLD" 22 "$TEXT"
gen dial_value "$MEDIUM" 30 "$NUM"
gen dial_text "$MEDIUM" 22 "$TEXT"
gen dial_small "$MEDIUM" 16 "$TEXT"
gen dial_caps "$MEDIUM" 13 "$CAPS"
