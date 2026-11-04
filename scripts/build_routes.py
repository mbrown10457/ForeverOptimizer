#!/usr/bin/env python3
"""Build ForeverOptimizer/Data/Routes.lua from the route specs in scripts/routes/.

Usage: python3 scripts/build_routes.py <QuestieDB_Forever.toc> [out.lua]

A spec is a text file, one step per line:
  ROUTE key | name | faction | races(csv) | minLevel | maxLevel
  INCLUDE <file>                         splice another spec file (shared sections) in place
  [@CLASS[,CLASS] | @-CLASS] A|C|T <questID> [| note]            accept / complete / turn in
  [@CLASS,Race] ...                      a race token (Orc, Troll, Tauren) limits a step to that race
  ... A|C|T <questID> | <who> | <map x y> | note                    coordinate override
  GOTO <label> | <map x y> [| note]      HEARTH <label> | <map x y> [| note]
  [@CLASS] TRAIN <level> | <who> | <map x y> | note
  LEVEL <n> [| note]                     NOTE <text>
Quest titles, giver names and coordinates come from QuestieDB so the guide works
without QuestieDB installed; at run time the addon prefers live data when present.
"""
import os, re, sys, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import questiedb_toc as Q

def norm(o):
    if isinstance(o, bytes): return o.decode('utf-8', 'replace')
    if isinstance(o, dict): return {norm(k): norm(v) for k, v in o.items()}
    if isinstance(o, list): return [norm(v) for v in o]
    return o

def g(d, k):
    if not isinstance(d, dict): return None
    return d.get(k, d.get(str(k)))

def lua_str(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'

class DB:
    def __init__(self, toc):
        Q.load(toc)
        self.area = {}
        zfile = os.path.join(os.path.dirname(toc), 'support', 'Forever', 'Zones', 'areaIdToUiMapId.lua')
        for m in re.finditer(r'\[(\d+)\]\s*=\s*(\d+)', open(zfile, encoding='utf-8').read()):
            self.area[int(m.group(1))] = int(m.group(2))
        self.cache = {}

    def first_spawn(self, spawns):
        if not isinstance(spawns, dict): return None
        for area, pts in spawns.items():
            try: area = int(area)
            except (TypeError, ValueError): continue
            m = self.area.get(area)
            if not m: continue
            for p in pts or []:
                if isinstance(p, (list, tuple)) and len(p) >= 2 and p[0] is not None and p[0] >= 0:
                    return m, round(float(p[0]), 1), round(float(p[1]), 1)
        return None

    def npc(self, i):
        k = ('n', i)
        if k not in self.cache:
            n = norm(Q.entity('Npc-', i, [7]))
            self.cache[k] = (g(n, 1) or ('npc %d' % i), self.first_spawn(g(n, 7)))
        return self.cache[k]

    def obj(self, i):
        k = ('o', i)
        if k not in self.cache:
            o = norm(Q.entity('Object-', i, [4]))
            self.cache[k] = (g(o, 1) or ('object %d' % i), self.first_spawn(g(o, 4)))
        return self.cache[k]

    def quest(self, qid):
        k = ('q', qid)
        if k not in self.cache:
            q = norm(Q.entity('Quest-', qid, [2, 3, 9, 10]))
            self.cache[k] = q if g(q, 1) else None
        return self.cache[k]

    @staticmethod
    def slot(t, i):
        if isinstance(t, dict): return g(t, i)
        if isinstance(t, list) and len(t) >= i: return t[i - 1]
        return None

    def giver(self, q, field):
        by = g(q, field)
        for i in self.slot(by, 1) or []:
            name, at = self.npc(int(i))
            if at: return name, at
        for i in self.slot(by, 2) or []:
            name, at = self.obj(int(i))
            if at: return name, at
        for i in self.slot(by, 1) or []:
            return self.npc(int(i))
        return None, None

    def item_sources(self, i):
        k = ('i', i)
        if k not in self.cache:
            it = norm(Q.entity('Item-', i, [2, 3]))
            self.cache[k] = (g(it, 1) or ('item %d' % i), g(it, 2) or [], g(it, 3) or [])
        return self.cache[k]

    def objective(self, q):
        objs = g(q, 10)
        for row in self.slot(objs, 1) or []:          # creatures
            if isinstance(row, list) and row:
                name, at = self.npc(int(row[0]))
                if at: return (row[1] if len(row) > 1 and row[1] else name), at
        for row in self.slot(objs, 2) or []:          # objects
            if isinstance(row, list) and row:
                name, at = self.obj(int(row[0]))
                if at: return (row[1] if len(row) > 1 and row[1] else name), at
        for row in self.slot(objs, 3) or []:          # items: who drops them
            if isinstance(row, list) and row:
                iname, npcs, objects = self.item_sources(int(row[0]))
                for n in npcs[:6]:
                    name, at = self.npc(int(n))
                    if at: return '%s (%s)' % (iname, name), at
                for o in objects[:4]:
                    name, at = self.obj(int(o))
                    if at: return iname, at
        trig = g(q, 9)
        if isinstance(trig, list) and len(trig) >= 2:
            at = self.first_spawn(trig[1])
            if at: return trig[0] or 'event', at
        return None, None

COORD = re.compile(r'^\s*(\d+)[\s,]+([\d.]+)[\s,]+([\d.]+)\s*$')

def parse_parts(rest):
    return [p.strip() for p in rest.split('|')]

def lines(path):
    """(path, line number, text) for every line, with INCLUDE <file> spliced in place."""
    for ln, raw in enumerate(open(path, encoding='utf-8'), 1):
        s = raw.strip()
        if s.startswith('INCLUDE '):
            for item in lines(os.path.join(os.path.dirname(path), s[8:].strip())): yield item
        else:
            yield path, ln, raw

def split_tags(tag):
    """'@HUNTER,Troll' -> ('HUNTER', 'Troll'); '-WARLOCK' -> ('-WARLOCK', None). Upper-case tokens are classes."""
    neg = tag.startswith('-')
    toks = [t for t in tag.lstrip('-').split(',') if t]
    classes = [t for t in toks if t.isupper()]
    races = [t for t in toks if not t.isupper()]
    cls = (('-' if neg else '') + ','.join(classes)) if classes else None
    return cls, (','.join(races) or None)

def build(db, path):
    route = None
    steps = []
    warnings = []
    for path, ln, raw in lines(path):
        line = raw.split('#', 1)[0].strip() if not raw.lstrip().startswith('#') else ''
        if not line: continue
        if line.startswith('ROUTE '):
            f = parse_parts(line[6:])
            route = dict(key=f[0], name=f[1], faction=f[2], races=[r.strip() for r in f[3].split(',')], lo=int(f[4]), hi=int(f[5]))
            continue
        cls, race = None, None
        if line.startswith('@'):
            tag, line = line[1:].split(None, 1)
            cls, race = split_tags(tag)
        parts = parse_parts(line)
        head = parts[0].split(None, 1)
        kind = head[0].upper()
        arg = head[1].strip() if len(head) > 1 else ''
        extra = parts[1:]
        step = dict(kind=kind, cls=cls, race=race, note=None, who='', title='', at=None, num=0, req=None)
        def take_coords():
            for i, e in enumerate(extra):
                m = COORD.match(e)
                if m:
                    step['at'] = (int(m.group(1)), float(m.group(2)), float(m.group(3)))
                    del extra[i]
                    return
        if kind in ('A', 'C', 'T'):
            qid = int(arg)
            step['num'] = qid
            q = db.quest(qid)
            if not q:
                warnings.append('%s:%d quest %d not in QuestieDB' % (path, ln, qid)); continue
            step['title'] = g(q, 1)
            if kind == 'A': step['req'] = g(q, 4) or 0
            if kind in ('C', 'T'):
                by = g(q, 2)
                if not db.slot(by, 1): step['auto'] = True   # no NPC giver: an item, an object, a trigger or the chain grants it
            take_coords()
            if kind == 'A': who, at = db.giver(q, 2)
            elif kind == 'T': who, at = db.giver(q, 3)
            else: who, at = db.objective(q)
            if extra and not step['at'] and len(extra) >= 2: step['who'] = extra.pop(0)
            elif extra and step['at']: step['who'] = extra.pop(0)
            step['who'] = step['who'] or who or ''
            step['at'] = step['at'] or at
            step['note'] = extra[0] if extra else None
            if not step['at'] and kind != 'C':
                warnings.append('%s:%d %s %d (%s) has no coordinates' % (path, ln, kind, qid, step['title']))
        elif kind in ('GOTO', 'HEARTH'):
            step['title'] = arg
            take_coords()
            step['note'] = extra[0] if extra else None
            if not step['at']: warnings.append('%s:%d %s needs "map x y"' % (path, ln, kind))
        elif kind == 'TRAIN':
            step['num'] = int(arg)
            step['title'] = 'Train at level %d' % step['num']
            take_coords()
            if extra: step['who'] = extra.pop(0)
            step['note'] = extra[0] if extra else None
        elif kind == 'LEVEL':
            step['num'] = int(arg)
            step['title'] = 'Reach level %d' % step['num']
            step['note'] = extra[0] if extra else None
        elif kind == 'NOTE':
            step['title'] = arg
            step['note'] = extra[0] if extra else None
        else:
            warnings.append('%s:%d unknown step %s' % (path, ln, kind)); continue
        steps.append(step)
    if not route: raise SystemExit('no ROUTE line in ' + path)
    route['steps'] = steps
    return route, warnings

def emit(route):
    out = ['R[#R + 1] = { key = %s, name = %s, faction = %s, races = { %s }, levels = { %d, %d }, steps = {' % (
        lua_str(route['key']), lua_str(route['name']), lua_str(route['faction']),
        ', '.join('%s = true' % r for r in route['races']), route['lo'], route['hi'])]
    for s in route['steps']:
        at = s['at']
        fields = [lua_str(s['kind']), str(s['num']), lua_str(s['title']), lua_str(s['who'])]
        if at: fields += [str(at[0]), '%.1f' % at[1], '%.1f' % at[2]]
        keyed = []
        if s['cls']: keyed.append('class = %s' % lua_str(s['cls']))
        if s['race']: keyed.append('race = %s' % lua_str(s['race']))
        if s['req'] and s['req'] > 1: keyed.append('req = %d' % s['req'])
        if s.get('auto'): keyed.append('auto = true')
        if s['note']: keyed.append('note = %s' % lua_str(s['note']))
        out.append('  { ' + ', '.join(fields + keyed) + ' },')
    out.append('} }')
    return '\n'.join(out)

def main():
    toc = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'ForeverOptimizer', 'Data', 'Routes.lua')
    db = DB(toc)
    specs = sorted(glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'routes', '*.txt')))
    version = 'unknown'
    for line in open(toc, encoding='utf-8', errors='replace'):
        if line.startswith('## Version:'): version = line.split(':', 1)[1].strip(); break
    blocks, total = [], 0
    for spec in specs:
        route, warnings = build(db, spec)
        for w in warnings: print('warn', w)
        blocks.append(emit(route))
        total += len(route['steps'])
        print('%s: %d steps' % (route['name'], len(route['steps'])))
    with open(out, 'w', encoding='utf-8') as f:
        f.write('-- GENERATED by scripts/build_routes.py from scripts/routes/*.txt and QuestieDB %s. Do not edit.\n' % version)
        f.write('-- Step: { kind, id, title, who, mapID, x, y, class=, race=, req=, note= }. Kinds: A accept, C complete, T turn in,\n')
        f.write('-- GOTO, HEARTH, TRAIN, LEVEL, NOTE. Coordinates are 0-100 on the uiMap.\n')
        f.write('local ADDON, FO = ...\nFO.Routes = FO.Routes or {}\nlocal R = FO.Routes\nR.source = %s\n' % lua_str('QuestieDB ' + version))
        f.write('\n'.join(blocks) + '\n')
    print('wrote %s: %d routes, %d steps' % (out, len(blocks), total))

if __name__ == '__main__':
    main()
