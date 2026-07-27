#!/usr/bin/env python3
"""Screen candidate app names for collisions. NOT legal clearance — see caveat in output.

Sources actually queried live:
  * iTunes Search API  — existing iOS apps with the same/similar name (public, no key)
  * Verisign RDAP      — .com registration status (public, no key)
USPTO has no key-free public search API, so exact verification URLs are emitted instead.
"""
import json, sys, time, urllib.parse, urllib.request

UA = {"User-Agent": "name-screen/1.0"}

def get(url, timeout=25):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception:
        return None, b""

def norm(s):
    return "".join(ch for ch in s.lower() if ch.isalnum())

def appstore(name):
    q = urllib.parse.quote(name)
    st, body = get(f"https://itunes.apple.com/search?term={q}&entity=software&country=us&limit=25")
    if st != 200 or not body:
        return None, []
    try:
        results = json.loads(body).get("results", [])
    except Exception:
        return None, []
    tgt = norm(name)
    hits = []
    for r in results:
        tn = r.get("trackName", "")
        n = norm(tn)
        if n == tgt:
            kind = "EXACT"
        elif tgt and (tgt in n or n in tgt):
            kind = "CONTAINS"
        else:
            continue
        hits.append((kind, tn, r.get("sellerName", ""), r.get("primaryGenreName", "")))
    return len(results), hits

def domain(name):
    d = norm(name) + ".com"
    st, _ = get(f"https://rdap.verisign.com/com/v1/domain/{d}")
    return d, ("AVAILABLE" if st == 404 else "registered" if st == 200 else f"HTTP {st}")

def uspto_links(name):
    q = urllib.parse.quote(name)
    return [
        f"https://tmsearch.uspto.gov/search/search-information?q={q}",
        f"https://www.trademarkia.com/search?q={q}",
    ]

def screen(names):
    print("=" * 78)
    print("NAME SCREEN — collision indicators only. NOT a legal clearance opinion.")
    print("=" * 78)
    for n in names:
        total, hits = appstore(n)
        d, dstat = domain(n)
        exact = [h for h in hits if h[0] == "EXACT"]
        near  = [h for h in hits if h[0] == "CONTAINS"]
        risk = "HIGH" if exact else ("MEDIUM" if near else "clear-so-far")
        print(f"\n### {n}   [App Store: {risk}]")
        print(f"  .com          {d}  {dstat}")
        if total is None:
            print("  App Store     query failed")
        else:
            print(f"  App Store     {total} results scanned; {len(exact)} exact, {len(near)} near")
            for k, tn, sn, g in (exact + near)[:6]:
                print(f"      {k:<9} {tn}  —  {sn}  [{g}]")
        for u in uspto_links(n):
            print(f"  verify        {u}")
        time.sleep(0.4)

if __name__ == "__main__":
    screen(sys.argv[1:] or ["Underhood", "Motorkeep", "Roadfolio", "AutoChronicle"])
