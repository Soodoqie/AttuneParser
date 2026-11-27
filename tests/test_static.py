# -*- coding: utf-8 -*-
"""Static and Lua 5.1 safety checks for AttuneParser (and optional sibling TalorianTP)."""

import argparse
import os
import re
import sys

AP_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
    "until", "while",
}


def find_talorian_dir(cli_dir):
    if cli_dir:
        return cli_dir if os.path.isdir(cli_dir) else None
    env_dir = os.environ.get("TALORIAN_TP_DIR")
    if env_dir and os.path.isdir(env_dir):
        return env_dir
    sibling = os.path.join(os.path.dirname(AP_ROOT), "TalorianTP")
    if os.path.isfile(os.path.join(sibling, "TalorianTP.lua")):
        return sibling
    return None


def check_delimiters(txt, label):
    stack = []
    pairs = {"(": ")", "[": "]", "{": "}"}
    close_map = {v: k for k, v in pairs.items()}
    i, n = 0, len(txt)
    line_no = 1
    while i < n:
        ch = txt[i]
        if ch == "\n":
            line_no += 1
            i += 1
            continue
        if txt.startswith("--", i):
            m = re.match(r"--\[(=*)\[", txt[i : i + 24])
            if m:
                end_tag = "]" + m.group(1) + "]"
                idx = txt.find(end_tag, i + len(m.group(0)))
                if idx == -1:
                    raise AssertionError(f"Unclosed long comment in {label}:{line_no}")
                line_no += txt[i : idx + len(end_tag)].count("\n")
                i = idx + len(end_tag)
                continue
            idx = txt.find("\n", i)
            i = n if idx == -1 else idx
            continue
        if ch in ('"', "'"):
            q = ch
            i += 1
            while i < n:
                c2 = txt[i]
                if c2 == "\\":
                    i += 2
                    continue
                if c2 == "\n":
                    line_no += 1
                if c2 == q:
                    i += 1
                    break
                i += 1
            continue
        if ch == "[":
            m = re.match(r"\[(=*)\[", txt[i : i + 24])
            if m:
                end_tag = "]" + m.group(1) + "]"
                idx = txt.find(end_tag, i + len(m.group(0)))
                if idx == -1:
                    raise AssertionError(f"Unclosed long string in {label}:{line_no}")
                line_no += txt[i : idx + len(end_tag)].count("\n")
                i = idx + len(end_tag)
                continue
        if ch in pairs:
            stack.append((ch, line_no))
        elif ch in close_map:
            if not stack or stack[-1][0] != close_map[ch]:
                raise AssertionError(f"Delimiter mismatch {ch} at {label}:{line_no} (stack={stack[-3:]})")
            stack.pop()
        i += 1
    if stack:
        raise AssertionError(f"Unclosed delimiters in {label}: {stack[:5]}")


def check_string_format(txt, label):
    fmt_cnt = 0
    for m in re.finditer(r'string\.format\("([^"\n]+)"', txt):
        fmt_cnt += 1
        fmt = m.group(1)
        cleaned = re.sub(r"%(?:%|[-+ #0]*\d*(?:\.\d+)?[cdiouxXeEfgGsq])", "", fmt)
        if "%" in cleaned:
            ln = txt.count("\n", 0, m.start()) + 1
            raise AssertionError(f"Stray % in string.format at {label}:{ln}: {fmt}")
    return fmt_cnt


def lua51_top_locals(path):
    text = open(path, encoding="utf-8").read()
    i, n = 0, len(text)
    line = 1
    tokens = []
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c in " \t\r\f\v":
            i += 1
        elif c == "-" and text[i : i + 2] == "--":
            m = re.match(r"--\[(=*)\[", text[i : i + 24])
            if m:
                close = "]" + m.group(1) + "]"
                j = text.find(close, i + len(m.group(0)))
                if j == -1:
                    line += text[i:].count("\n")
                    break
                line += text[i : j + len(close)].count("\n")
                i = j + len(close)
            else:
                j = text.find("\n", i)
                i = j if j != -1 else n
        elif c == "[" and re.match(r"\[(=*)\[", text[i : i + 24]):
            m = re.match(r"\[(=*)\[", text[i : i + 24])
            close = "]" + m.group(1) + "]"
            j = text.find(close, i + len(m.group(0)))
            if j == -1:
                tokens.append(("STR", "", line))
                break
            line += text[i : j + len(close)].count("\n")
            tokens.append(("STR", "", line))
            i = j + len(close)
        elif c in ('"', "'"):
            q = c
            i += 1
            while i < n:
                if text[i] == "\\":
                    if text[i : i + 2] == "\\\n":
                        line += 1
                    i += 2
                elif text[i] == q:
                    i += 1
                    break
                else:
                    if text[i] == "\n":
                        line += 1
                    i += 1
            tokens.append(("STR", "", line))
        elif c.isalpha() or c == "_":
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            w = text[i:j]
            tokens.append(("KW" if w in KEYWORDS else "ID", w, line))
            i = j
        elif c.isdigit() or (c == "." and i + 1 < n and text[i + 1].isdigit()):
            m = re.match(r"0[xX][0-9a-fA-F]+|\d*\.?\d+(?:[eE][+-]?\d+)?", text[i:])
            tokens.append(("NUM", m.group(0), line))
            i += len(m.group(0))
        elif text[i : i + 3] == "...":
            tokens.append(("SYM", "...", line))
            i += 3
        elif text[i : i + 2] in ("==", "~=", "<=", ">=", ".."):
            tokens.append(("SYM", text[i : i + 2], line))
            i += 2
        else:
            tokens.append(("SYM", c, line))
            i += 1

    frames = [{"name": "<file>", "line": 1, "blocks": [0], "peak": 0, "peak_line": 1, "struct": []}]
    all_peaks = []
    idx = 0
    nt = len(tokens)
    while idx < nt:
        typ, val, ln = tokens[idx]
        cf = frames[-1]
        if typ == "KW" and val == "function":
            j = idx + 1
            while j < nt and tokens[j][1] != "(":
                j += 1
            nm = "".join(tokens[k][1] for k in range(idx + 1, j)) or f"<anon@{ln}>"
            k = j + 1
            pc = 0
            while k < nt and tokens[k][1] != ")":
                if tokens[k][0] == "ID":
                    pc += 1
                k += 1
            if ":" in nm:
                pc += 1
            frames.append({"name": nm, "line": ln, "blocks": [pc], "peak": pc, "peak_line": ln, "struct": []})
            idx = k + 1
            continue
        if typ == "KW" and val == "local":
            if idx + 1 < nt and tokens[idx + 1][0] == "KW" and tokens[idx + 1][1] == "function":
                cf["blocks"][-1] += 1
                if cf["blocks"][-1] > cf["peak"]:
                    cf["peak"] = cf["blocks"][-1]
                    cf["peak_line"] = ln
                idx += 1
                continue
            count = 0
            j = idx + 1
            while j < nt:
                if tokens[j][0] == "ID":
                    count += 1
                    j += 1
                    if j < nt and tokens[j][1] == ",":
                        j += 1
                    else:
                        break
                else:
                    break
            cf["blocks"][-1] += count
            if cf["blocks"][-1] > cf["peak"]:
                cf["peak"] = cf["blocks"][-1]
                cf["peak_line"] = ln
            idx = j
            continue
        if typ == "KW" and val == "for":
            j = idx + 1
            lvc = 0
            while j < nt and not (tokens[j][0] == "KW" and tokens[j][1] in ("in", "do")) and tokens[j][1] != "=":
                if tokens[j][0] == "ID":
                    lvc += 1
                j += 1
            cf["struct"].append(("for", lvc, ln))
        elif typ == "KW" and val in ("while", "if"):
            cf["struct"].append((val, 0, ln))
        elif typ == "KW" and val == "then":
            cf["blocks"].append(cf["blocks"][-1])
        elif typ == "KW" and val in ("elseif", "else"):
            if len(cf["blocks"]) > 1:
                cf["blocks"].pop()
            if val == "else":
                cf["blocks"].append(cf["blocks"][-1])
        elif typ == "KW" and val == "do":
            if cf["struct"] and cf["struct"][-1][0] in ("for", "while"):
                kind, lvc, sln = cf["struct"].pop()
                cf["struct"].append(("loop", 0, sln))
                extra = 3 if kind == "for" else 0
                cf["blocks"].append(cf["blocks"][-1] + lvc + extra)
            else:
                cf["struct"].append(("do", 0, ln))
                cf["blocks"].append(cf["blocks"][-1])
            if cf["blocks"][-1] > cf["peak"]:
                cf["peak"] = cf["blocks"][-1]
                cf["peak_line"] = ln
        elif typ == "KW" and val == "repeat":
            cf["struct"].append(("repeat", 0, ln))
            cf["blocks"].append(cf["blocks"][-1])
        elif typ == "KW" and val == "until":
            if cf["struct"] and cf["struct"][-1][0] == "repeat":
                cf["struct"].pop()
            if len(cf["blocks"]) > 1:
                cf["blocks"].pop()
        elif typ == "KW" and val == "end":
            if cf["struct"] and cf["struct"][-1][0] in ("if", "do", "loop"):
                cf["struct"].pop()
                if len(cf["blocks"]) > 1:
                    cf["blocks"].pop()
            elif len(frames) > 1:
                f = frames.pop()
                all_peaks.append((f["peak"], f["line"], f["peak_line"], f["name"]))
            else:
                raise AssertionError(f"UNMATCHED end in {path} at L{ln}")
        idx += 1

    f0 = frames[0]
    all_peaks.append((f0["peak"], 1, f0["peak_line"], "<file>"))
    if f0["struct"]:
        raise AssertionError(f"UNCLOSED struct at EOF in {path}: {f0['struct']}")
    all_peaks.sort(reverse=True)
    return all_peaks


def audit_addon(root, name, check_lua_files):
    for fn in sorted(os.listdir(root)):
        fp = os.path.join(root, fn)
        if not os.path.isfile(fp):
            continue
        raw = open(fp, "rb").read()
        if raw.startswith(b"\xef\xbb\xbf"):
            raise AssertionError(f"UTF-8 BOM found: {name}/{fn}")
        if fn.endswith((".lua", ".xml", ".toc")):
            txt = raw.decode("utf-8")
            bad = [(i + 1, c, hex(ord(c))) for i, l in enumerate(txt.splitlines()) for c in l if ord(c) > 0x04FF]
            if bad:
                raise AssertionError(f"Chars > 0x04FF in {name}/{fn}: {bad[:5]}")
            if fn.endswith(".toc") and "Bindings.xml" in txt:
                raise AssertionError(f"Bindings.xml listed in toc: {name}/{fn}")
            if fn.endswith(".lua"):
                if "C_Timer" in txt:
                    raise AssertionError(f"C_Timer found in {name}/{fn}")
                if ":SetShown(" in txt:
                    raise AssertionError(f":SetShown( found in {name}/{fn}")
                check_delimiters(txt, f"{name}/{fn}")
                check_string_format(txt, f"{name}/{fn}")
    for fn in check_lua_files:
        fp = os.path.join(root, fn)
        peaks = lua51_top_locals(fp)
        max_loc = peaks[0][0]
        assert max_loc < 195, f"Lua 5.1 local register overflow risk in {name}/{fn}: {peaks[0]}"
        print(f"LOCALS OK {name}/{fn}: peak={max_loc} ({peaks[0][3]})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--talorian-dir", default=None)
    args = parser.parse_args()

    audit_addon(
        AP_ROOT,
        "AttuneParser",
        ["AttuneParser.lua", "AttuneParser_UI.lua", "AttuneParser_Integrations.lua"],
    )
    tdir = find_talorian_dir(args.talorian_dir)
    if tdir:
        audit_addon(tdir, "TalorianTP", ["TalorianTP.lua"])
    else:
        print("TalorianTP sibling directory not found; skipped cross-addon static check.")
    print("STATIC CHECKS PASSED")


if __name__ == "__main__":
    main()
