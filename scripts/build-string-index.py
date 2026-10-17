#!/usr/bin/env python3
# build-string-index.py - Stage B: build the string index that anchors everything.
#
# Usage:
#   python3 -I build-string-index.py <apktool-decoded-dir> [out.tsv]
#
# The -I flag runs Python in isolated mode (ignores the current dir and user site-packages),
# which is the right habit when pointing a script at an untrusted, decoded artifact tree.
#
# Why this exists:
#   Obfuscated class and method names change on every app build. String literals do not. The
#   backbone of "resolve by shape, not by name" is a flat index of every string literal, the
#   smali file it lives in, and the method that holds it. You grep THIS to find the code that
#   builds a given endpoint, reads a given JSON key, or logs a given marker, then you anchor your
#   analysis on that stable string instead of the obfuscated name.
#
# Output: tab-separated, three columns, one row per const-string:
#   <smali_path>\t<method_signature>\t<string_literal>
#
# Manual equivalent (rougher, no method column):
#   grep -rn 'const-string' <decoded>/smali* | sed -E 's/.*const-string[^"]*"(.*)"/\1/'
#
# Example use after it runs:
#   grep -P '\treel_mentions$' strings.tsv          # who references this JSON key
#   grep -i 'https://' strings.tsv | grep -i api    # candidate endpoints
#
# Fail-soft: unreadable files are counted and skipped, never fatal.

import os
import re
import sys

# const-string vN, "literal"      and      const-string/jumbo vN, "literal"
# smali escapes: \" \\ \n \t \uXXXX. We capture the raw escaped literal and unescape the common ones.
CONST_RE = re.compile(r'const-string(?:/jumbo)?\s+[vp]\d+\s*,\s*"((?:\\.|[^"\\])*)"')
METHOD_RE = re.compile(r'^\s*\.method\b(.*)$')
ENDMETHOD_RE = re.compile(r'^\s*\.end method\b')

UNESCAPE = {'\\n': '\n', '\\t': '\t', '\\r': '\r', '\\"': '"', '\\\\': '\\', "\\'": "'"}


def unescape(s):
    # handle \uXXXX then the simple pairs; keep it best-effort, never throw
    def u(m):
        try:
            return chr(int(m.group(1), 16))
        except Exception:
            return m.group(0)
    s = re.sub(r'\\u([0-9a-fA-F]{4})', u, s)
    for k, v in UNESCAPE.items():
        s = s.replace(k, v)
    return s


def clean_field(s):
    # keep the TSV flat: collapse tabs/newlines in a literal so columns stay aligned
    return s.replace('\t', '\\t').replace('\r', '\\r').replace('\n', '\\n')


def main():
    if len(sys.argv) < 2:
        print("usage: build-string-index.py <apktool-decoded-dir> [out.tsv]", file=sys.stderr)
        return 2
    root = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, 'strings.tsv')
    if not os.path.isdir(root):
        print("ERROR: not a directory: %s" % root, file=sys.stderr)
        return 2

    files = 0
    skipped = 0
    rows = 0
    try:
        out = open(out_path, 'w', encoding='utf-8', newline='\n')
    except Exception as e:
        print("ERROR: cannot write %s: %s" % (out_path, e), file=sys.stderr)
        return 2

    with out:
        for dirpath, _dirs, names in os.walk(root):
            for name in names:
                if not name.endswith('.smali'):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, root)
                files += 1
                try:
                    with open(path, encoding='utf-8', errors='replace') as fh:
                        method = '<class>'
                        for line in fh:
                            m = METHOD_RE.match(line)
                            if m:
                                # ".method public final A0M(...)Z" -> keep the signature tail
                                method = m.group(1).strip().split()[-1] if m.group(1).strip() else '<method>'
                                continue
                            if ENDMETHOD_RE.match(line):
                                method = '<class>'
                                continue
                            for cm in CONST_RE.finditer(line):
                                lit = unescape(cm.group(1))
                                out.write('%s\t%s\t%s\n' % (rel, clean_field(method), clean_field(lit)))
                                rows += 1
                except Exception as e:
                    skipped += 1
                    print("WARN: skipped %s (%s)" % (rel, e), file=sys.stderr)

    print("indexed %d string(s) from %d smali file(s)%s -> %s"
          % (rows, files, (" (%d skipped)" % skipped) if skipped else "", out_path))
    if files == 0:
        print("note: found no .smali files. Did you decode with apktool first? "
              "(apktool d base.apk -o <decoded>)", file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
