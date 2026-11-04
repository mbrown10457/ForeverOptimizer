"""Offline reader for the QuestieDB TOC metadata store (baked mode).

QuestieDB_<Flavor>.toc carries every entity as `## X-<Kind>-<id>-<field>: <base64 CBOR>`
lines. load(toc) reads them; entity(prefix, id, fields) decodes one row.
"""
import sys, base64, zlib, struct, re, json
toc = None
store = {}

def load(path):
    global toc
    toc = path
    store.clear()
    for line in open(path, encoding='utf-8', errors='replace'):
        if line.startswith('## X-'):
            k, _, v = line[5:].partition(':')
            store[k.strip()] = v.strip()

def cbor(b, i=0):
    ib = b[i]; mt = ib >> 5; ai = ib & 31; i += 1
    if mt == 7:
        if ai == 20: return False, i
        if ai == 21: return True, i
        if ai == 22: return None, i
        if ai == 23: return None, i
        if ai == 24: return b[i], i + 1
        if ai == 25: return struct.unpack('>e', b[i:i+2])[0], i + 2
        if ai == 26: return struct.unpack('>f', b[i:i+4])[0], i + 4
        if ai == 27: return struct.unpack('>d', b[i:i+8])[0], i + 8
        raise ValueError('mt 7 ai %d' % ai)
    if ai < 24: n = ai
    elif ai == 24: n = b[i]; i += 1
    elif ai == 25: n = struct.unpack('>H', b[i:i+2])[0]; i += 2
    elif ai == 26: n = struct.unpack('>I', b[i:i+4])[0]; i += 4
    elif ai == 27: n = struct.unpack('>Q', b[i:i+8])[0]; i += 8
    elif ai == 31: n = None
    else: raise ValueError('ai %d' % ai)
    if mt == 0: return n, i
    if mt == 1: return -1 - n, i
    if mt == 2: return b[i:i+n], i + n
    if mt == 3: return b[i:i+n].decode('utf-8', 'replace'), i + n
    if mt == 4:
        out = []
        if n is None:
            while b[i] != 0xff:
                v, i = cbor(b, i); out.append(v)
            return out, i + 1
        for _ in range(n):
            v, i = cbor(b, i); out.append(v)
        return out, i
    if mt == 5:
        out = {}
        if n is None:
            while b[i] != 0xff:
                k, i = cbor(b, i); v, i = cbor(b, i); out[k] = v
            return out, i + 1
        for _ in range(n):
            k, i = cbor(b, i); v, i = cbor(b, i); out[k] = v
        return out, i
    if mt == 6:
        return cbor(b, i)
    if mt == 7:
        if ai == 20: return False, i
        if ai == 21: return True, i
        if ai == 22: return None, i
        if ai == 25: return struct.unpack('>e', b[i:i+2])[0], i + 2
        if ai == 26: return struct.unpack('>f', b[i:i+4])[0], i + 4
        if ai == 27: return struct.unpack('>d', b[i:i+8])[0], i + 8
    raise ValueError('mt %d ai %d' % (mt, ai))

def stored(key):
    v = store.get(key)
    if v is None: return None
    m = re.match(r'^~(\d+)~$', v)
    if m:
        v = ''.join(store[key + '-' + str(n)] for n in range(1, int(m.group(1)) + 1))
    return v

def val(key):
    v = stored(key)
    if v is None: return None
    return cbor(base64.b64decode(v))[0]

def ids(prefix):
    raw = base64.b64decode(stored(prefix + 'IDS'))
    try: raw = zlib.decompress(raw)
    except Exception: raw = zlib.decompress(raw, -15)
    return cbor(raw)[0]

def entity(prefix, id, fields):
    row = val('%s%d-S' % (prefix, id)) or {}
    out = {}
    if isinstance(row, list):
        for i, v in enumerate(row, 1): out[i] = v
    else: out.update(row)
    for f in fields:
        v = val('%s%d-%d' % (prefix, id, f))
        if v is not None: out[f] = v
    return out

if __name__ == '__main__':
    load(sys.argv[1])
    print('quest ids', len(ids('Quest-')))
    def norm(o):
        if isinstance(o, bytes): return o.decode('utf-8', 'replace')
        if isinstance(o, dict): return {str(norm(k)): norm(v) for k, v in o.items()}
        if isinstance(o, list): return [norm(v) for v in o]
        return o
    q = entity('Quest-', int(sys.argv[2]), [2,3,8,10,12,13,14])
    print(json.dumps(norm(q), default=str)[:1500])
    if len(sys.argv) > 3:
        n = entity('Npc-', int(sys.argv[3]), [7,10,11])
        print(json.dumps(norm(n), default=str)[:800])
