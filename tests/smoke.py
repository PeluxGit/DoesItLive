import lupa
import os
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
L = lupa.LuaRuntime()
L.execute(open(os.path.join(HERE, 'smoke.lua')).read())
ns = L.table()
toc = [l.strip() for l in open(os.path.join(ROOT, 'DoesItLive.toc')) if l.strip().endswith('.lua')]
for f in toc:
    src = open(os.path.join(ROOT, f)).read()
    L.execute("local a={...}; local fn=assert(load(a[1], '@'..a[2])); fn('DoesItLive', a[3])", src, f, ns)
g = L.globals()
g.fire("ADDON_LOADED","DoesItLive"); g.fire("PLAYER_LOGIN"); g.runTimers()
ns.db.debug = True
g.print = L.eval("function(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring(select(i,...)) end io.write(table.concat(t,' '),'\\n') end")
ns.rescan()
n = sum(1 for _ in ns.overlays.items()) if False else len(list(ns.overlays.items()))
print("overlays:", n)
# fight
g.T = 100; g.COMBAT = True; g.fire("PLAYER_REGEN_DISABLED")
g.fire("UNIT_SPELLCAST_SENT","player","Daft Druid","c1",2090); g.fire("UNIT_SPELLCAST_SUCCEEDED","player","c1",2090)
g.fire("UNIT_SPELLCAST_SENT","player","Daft Druid","c2",8938); g.fire("UNIT_SPELLCAST_SUCCEEDED","player","c2",8938)
g.fire("UNIT_SPELLCAST_SENT","player","Tank Smith","c3",48438); g.fire("UNIT_SPELLCAST_SUCCEEDED","player","c3",48438)
tot, parts, serial = ns.remainingFor("player")
print("player at cast:", tot, [(p.name, round(p.amount,1)) for p in parts.values()])
print("party2 WG at cast:", ns.remainingFor("party2"))
g.T = 101.05; print("party2 WG after 1 tick:", ns.remainingFor("party2"))
g.T = 104; tot, parts, serial = ns.remainingFor("player"); print("player t=4:", tot, "serial", serial)
ns.db.drain = "smooth"; print("player t=4 smooth:", ns.remainingFor("player")); ns.db.drain="ticks"
ns.redraw()
g.T = 125; g.COMBAT = False
# meter: rejuv 4 ticks => desc 32.75*4=131 ; real 1.3x -> 170.3 ; regrowth direct 91 + 7 ticks*22.14=155 -> 1.2x
g.METER = L.eval("{ {spellID=2090, totalAmount=170.3}, {spellID=8938, totalAmount=(91+155)*1.2}, {spellID=48438, totalAmount=679*3*1.1} }")
g.fire("PLAYER_REGEN_ENABLED"); g.runTimers()
for k, v in ns.db.learned.items(): print("learned", k, v.name, v.tick, v.desc)
# new cast uses learned
g.fire("UNIT_SPELLCAST_SENT","player","Daft Druid","c4",2090); g.fire("UNIT_SPELLCAST_SUCCEEDED","player","c4",2090)
print("rejuv after learning:", ns.remainingFor("player")[0] if False else ns.remainingFor("player"))
# options window + presets
g.SlashCmdList.DOESITLIVE("")
for p in ns.PRESETS.values():
    for k, v in p['values'].items(): ns.db[k] = v
    ns.refreshLook()
g.SlashCmdList.DOESITLIVE("test"); ns.redraw()
g.SlashCmdList.DOESITLIVE("probe"); g.SlashCmdList.DOESITLIVE("learned")
print("OK")
ns.testMode = False
ns.rescan()
srcs = {}
for k, o in ns.overlays.items(): srcs[o.source] = srcs.get(o.source, 0) + 1
print("sources:", srcs)
g.T = 200
g.fire("UNIT_SPELLCAST_SENT","player","Rando Healer","c9",2090); g.fire("UNIT_SPELLCAST_SUCCEEDED","player","c9",2090)
g.fire("UNIT_SPELLCAST_SENT","player","Rando Healer","c10",48438); g.fire("UNIT_SPELLCAST_SUCCEEDED","player","c10",48438)
print("target (non-group):", ns.remainingFor("target"))
print("party1 untouched by WG on outsider:", ns.remainingFor("party1"))
g.fire("UNIT_SPELLCAST_SENT","player","","c11",2090); g.fire("UNIT_SPELLCAST_SUCCEEDED","player","c11",2090)
ns.redraw(); print("OK2")
g.fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); g.runTimers()
ns.rescan()
srcs = {}
for k, o in ns.overlays.items(): srcs[o.source] = srcs.get(o.source, 0) + 1
print("sources:", srcs)
print("nameplate1 (Rando):", ns.remainingFor("nameplate1")[0] if False else ns.remainingFor("nameplate1"))
ns.redraw()
g.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); ns.redraw()
g.SlashCmdList.DOESITLIVE("probe")
print("OK3")
