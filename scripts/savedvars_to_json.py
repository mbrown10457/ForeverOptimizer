#!/usr/bin/env python3 -I
"""Convert a WoW SavedVariables .lua file to JSON.

Usage:
  scripts/savedvars_to_json.py <file.lua> [--var NAME] [-o out.json]

Default SavedVariables location on Mac (Forever):
  /Applications/World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/AHLedger.lua

Handles the subset of Lua Blizzard emits: nested tables, string/number/bool/nil,
["key"] = and [123] = keys, positional array entries, comments.
No eval, no Lua runtime needed.
"""
import argparse, json, re, sys

class P:
    def __init__(self, s):
        self.s, self.i, self.n = s, 0, len(s)

    def ws(self):
        while self.i < self.n:
            c = self.s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif self.s.startswith("--", self.i):
                j = self.s.find("\n", self.i)
                self.i = self.n if j < 0 else j + 1
            else:
                break

    def peek(self, lit):
        self.ws()
        return self.s.startswith(lit, self.i)

    def eat(self, lit):
        self.ws()
        if not self.s.startswith(lit, self.i):
            raise SyntaxError(f"expected {lit!r} at {self.i}: {self.s[self.i:self.i+30]!r}")
        self.i += len(lit)

    def string(self):
        q = self.s[self.i]; self.i += 1
        out = []
        while True:
            c = self.s[self.i]
            if c == "\\":
                nxt = self.s[self.i + 1]
                m = re.match(r"\d{1,3}", self.s[self.i + 1:self.i + 4])
                if m:
                    out.append(chr(int(m.group()))); self.i += 1 + len(m.group()); continue
                out.append({"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'"}.get(nxt, nxt))
                self.i += 2
            elif c == q:
                self.i += 1; return "".join(out)
            else:
                out.append(c); self.i += 1

    NUM = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)")

    def value(self):
        self.ws()
        c = self.s[self.i]
        if c in "\"'":
            return self.string()
        if c == "{":
            return self.table()
        for lit, v in (("true", True), ("false", False), ("nil", None)):
            if self.s.startswith(lit, self.i) and not (self.s[self.i + len(lit):self.i + len(lit) + 1] or " ").isalnum():
                self.i += len(lit); return v
        m = self.NUM.match(self.s, self.i)
        if m:
            self.i = m.end()
            t = m.group()
            if t.lower().startswith(("0x", "-0x")):
                return int(t, 16)
            f = float(t)
            return int(f) if f.is_integer() and "." not in t and "e" not in t.lower() else f
        if self.s.startswith("math.huge", self.i):
            self.i += 9; return float("inf")
        if self.s.startswith("-math.huge", self.i):
            self.i += 10; return float("-inf")
        raise SyntaxError(f"bad value at {self.i}: {self.s[self.i:self.i+30]!r}")

    def table(self):
        self.eat("{")
        d, arr, idx = {}, [], 1
        while True:
            self.ws()
            if self.peek("}"):
                self.eat("}"); break
            if self.peek("["):
                self.eat("["); k = self.value(); self.eat("]"); self.eat("="); v = self.value()
                d[k] = v
            else:
                m = re.match(r"[A-Za-z_]\w*\s*=", self.s[self.i:])
                if m and not self.s.startswith(("true", "false", "nil"), self.i):
                    k = m.group().rstrip("= \t")
                    self.i += m.end(); v = self.value(); d[k] = v
                else:
                    arr.append(self.value()); idx += 1
            self.ws()
            if self.peek(","): self.eat(",")
            elif self.peek(";"): self.eat(";")
        if arr and not d:
            return arr
        for j, v in enumerate(arr, 1):
            d[j] = v
        # pure int-keyed 1..n tables become lists
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[k] for k in sorted(d)]
        return {str(k): v for k, v in d.items()}

def parse_file(text):
    p = P(text); out = {}
    while True:
        p.ws()
        if p.i >= p.n: break
        m = re.match(r"([A-Za-z_][\w]*)\s*=", text[p.i:])
        if not m:
            raise SyntaxError(f"expected assignment at {p.i}: {text[p.i:p.i+30]!r}")
        name = m.group(1); p.i += m.end()
        out[name] = p.value()
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--var", help="only emit this top-level variable")
    ap.add_argument("-o", "--out")
    a = ap.parse_args()
    with open(a.file, encoding="utf-8", errors="replace") as f:
        data = parse_file(f.read())
    if a.var:
        data = data[a.var]
    js = json.dumps(data, indent=2, ensure_ascii=False)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f: f.write(js)
        print(f"wrote {a.out}", file=sys.stderr)
    else:
        print(js)

if __name__ == "__main__":
    main()
