#!/usr/bin/env bash
# The half of the seat-colour guarantee that cannot be automated.
#
# `test-statusline-seat.py` asserts that the four seat states use four different
# escape codes. That is not the property that matters. The property that matters
# is that they render as four different COLOURS in this terminal's theme — and
# this script exists because they once did not: bright blue and dim were
# distinct codes and the same colour to the eye, so a correctly verified seat
# was unreadable for five days. See docs/adr/0014.
#
# Run it after any theme change. If two rows look alike, the palette is wrong no
# matter what the suite says.

set -u
here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The codes are imported from the status line itself, never restated here: a
# swatch that can disagree with what renders is worse than no swatch.
python3 - "$here/statusline-pace.py" <<'PY'
import importlib.util, sys

spec = importlib.util.spec_from_file_location("sl", sys.argv[1])
sl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sl)

names = {v: k for k, v in vars(sl).items()
         if isinstance(v, str) and k.isupper() and v.isdigit()}

print("\n  The seat states, as this terminal renders them:\n")
for state, code in sl.SEAT_COLORS.items():
    print(f"    \x1b[{code}m{sl.SEAT_GLYPH} someone@example.invalid · max\x1b[0m"
          f"   {state:<13} {names.get(code, '?')}({code})")
print("\n  Are they all obviously different colours? If any two look alike, that")
print("  pair is a silent failure: one of them is a verdict nobody can read.\n")
PY
