#!/usr/bin/env python3
"""
set_day1.py <params file> <day1 InProcess path | ''>

Set (or clear, with an empty second argument) `day1_path` in a UNP params
file so that P2 -reg treats the session as a later day of a multi-session
subject and cross-day aligns it to the given first session.

Runs inside Slurm jobs too, so it must work with any python3 (>= 3.6) and
depends on nothing.  A backup <params>.day1.bak is written.
"""
import os
import re
import shutil
import sys

LINE_RE = re.compile(r'^\s*#?\s*set\s+day1_path\s*=.*$')
COMMENT = "\t#full path to the first session. If you cd to this path, you should see the Anatomical folder of the first session."


def set_day1(params_path, day1_path):
    with open(params_path, errors="replace") as fh:
        lines = fh.read().splitlines()
    new_line = ("set day1_path = %s %s" % (day1_path, COMMENT)) if day1_path else \
               ("#set day1_path = $cwd:h/$patid %s" % COMMENT)
    done = False
    out = []
    for line in lines:
        if LINE_RE.match(line):
            if not done:
                out.append(new_line)
                done = True
            # drop duplicate day1_path lines
            continue
        out.append(line)
    if not done:
        # insert after patid if present, else append
        for i, line in enumerate(out):
            if re.match(r'^\s*set\s+patid\s*=', line):
                out.insert(i + 1, new_line)
                done = True
                break
        if not done:
            out.append(new_line)
    shutil.copy2(params_path, params_path + ".day1.bak")
    with open(params_path, "w") as fh:
        fh.write("\n".join(out) + "\n")
    return new_line


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    params, day1 = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
    if not os.path.isfile(params):
        print("set_day1: params file not found: %s" % params)
        sys.exit(1)
    if day1:
        if os.path.basename(day1.rstrip("/")) == os.path.basename(os.path.dirname(os.path.abspath(params))):
            print("set_day1: day1 is the session itself; refusing")
            sys.exit(1)
        if not os.path.isdir(day1):
            print("set_day1: WARNING day1 path does not exist (yet?): %s" % day1)
    print("set_day1: " + set_day1(params, day1))


if __name__ == "__main__":
    main()
