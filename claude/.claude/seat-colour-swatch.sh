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

# Rows come from the status line's own state table, badge and all, so a state
# added there shows up here without this script being touched.
print("\n  The seat states, as this terminal renders them:\n")
for state, row in sl.SEAT_STATES.items():
    code = row["colour"]
    label = "someone@example.invalid · max"
    if row["badge"]:
        label += f" · {row['badge']}"
    print(f"    \x1b[{code}m{sl.SEAT_GLYPH} {label}\x1b[0m"
          f"   {state:<13} {names.get(code, '?')}({code})")

# Which pairs share a colour is derived from what they assert, not hardcoded,
# so the instruction below stays true as states come and go.
shared = {}
for state, row in sl.SEAT_STATES.items():
    shared.setdefault(row["asserts"], []).append(state)
pairs = [" and ".join(sts) for sts in shared.values() if len(sts) > 1]
if pairs:
    print(f"\n  {'; '.join(pairs)} share a colour by design — each asserts the same")
    print("  thing, and the badge is what tells them apart. Ignoring those pairs,")
    print("  are the rest obviously different colours?")
else:
    print("\n  Are these all obviously different colours?")
print("  Any pair that looks alike is a silent failure — one of them is a verdict")
print("  nobody can read.\n")
PY
