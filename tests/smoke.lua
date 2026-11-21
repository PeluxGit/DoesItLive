-- generic WoW mocks
T = 100
function GetTime() return T end
function issecretvalue(v) return false end
local units = { player = {"Daft","Druid"}, party1 = {"Tank","Smith"}, party2 = {"Mage","Jones"} }
function UnitExists(u) return units[u] ~= nil end
function UnitName(u) local n = units[u] if n then return n[1], n[2] end end
function GetUnitName(u) local n = units[u] if n then return n[1].." "..n[2] end end
function IsInRaid() return false end
function GetNumSubgroupMembers() return 2 end
function GetNumGroupMembers() return 3 end
function UnitIsFriend() return true end
function UnitIsUnit(a,b) return a==b end
function UnitIsDeadOrGhost() return false end
function UnitInRange() return true, true end
function UnitHealthMax() return 5000 end
function UnitGetIncomingHeals() return 0 end
COMBAT = false
function InCombatLockdown() return COMBAT end
function UnitAffectingCombat() return COMBAT end
function UnitGUID() return "Player-1" end
function GetSpellBonusHealing() return 0 end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
function CreateColor(r,g,b,a) return {r,g,b,a} end
local descs = {
  [2090]={"Rejuvenation","Heals the target for 131 over 12 sec."},
  [8938]={"Regrowth","Heals a friendly target for 84 to 98 and another 155 over 21 sec."},
  [48438]={"Wild Growth","Heals the target and their party for 679 over 7 sec. Party members must be within 43.5 yards of target. The amount healed is applied quickly at first, and slows down as Wild Growth reaches its full duration."},
}
C_Spell = { GetSpellName=function(id) return descs[id] and descs[id][1] end, GetSpellDescription=function(id) return descs[id] and descs[id][2] end }
C_UnitAuras = { GetAuraDataByIndex=function() return nil end }
local timers = {}
C_Timer = { After=function(s,f) timers[#timers+1]=f end, NewTicker=function(s,f) return {Cancel=function() end} end }
function runTimers() local n=0 while #timers>0 and n<100 do local f=table.remove(timers,1) f() n=n+1 end end
hooksecurefunc=function() end
SlashCmdList = {}
UISpecialFrames = {}
Settings = { RegisterCanvasLayoutCategory=function() return {} end, RegisterAddOnCategory=function() end }
Enum = { DamageMeterType = { HealingDone = 2 }, DamageMeterSessionType = { Current = 1 } }
METER = {}
C_DamageMeter = { GetCombatSessionSourceFromType=function(s,t,g) assert(t==2) return { combatSpells = METER } end }

local handlers = {}
local Mock = {}
local function new(kind, name)
  local o = { _kind = kind or "Frame", _children = {} }
  setmetatable(o, Mock)
  if name then _G[name] = o end
  return o
end
Mock.__index = function(t, k)
  if type(k) == "string" and k:sub(1,1) == "_" then return nil end
  local special = {
    GetWidth = function() return 100 end, GetHeight = function(self) return self._h or 20 end,
    GetFrameLevel = function() return 1 end, IsShown = function(self) return self._shown ~= false end,
    IsVisible = function() return true end, Show=function(self) self._shown=true end, Hide=function(self) self._shown=false end,
    SetShown=function(self,v) self._shown = v and true or false end,
    GetChildren = function(self) return table.unpack(self._children) end,
    IsObjectType = function(self, k) return self._kind == k end,
    GetFont = function() return "font" end, GetStringWidth = function() return 40 end,
    GetAttribute = function(self) return self._unit end,
    SetScript = function(self, ev, fn) if ev=="OnEvent" then handlers[#handlers+1]=fn end self["_"..ev]=fn end,
    GetStatusBarTexture = function(self) self._tex = self._tex or new("Texture") return self._tex end,
    GetThumbTexture = function(self) return new("Texture") end,
    GetValue = function() return 0 end, GetChecked = function() return true end,
    GetOrientation = function() return "HORIZONTAL" end, GetReverseFill = function() return false end,
    IsMouseOver = function() return false end,
  }
  if special[k] then return special[k] end
  return function(self, ...) return new("Texture") end
end
function CreateFrame(kind, name, parent)
  local f = new(kind, name)
  if parent and parent._children then table.insert(parent._children, f) end
  return f
end
GameFontNormalSmall = new("Font")
GameTooltip = new("Frame")
function fire(ev, ...) for _,h in ipairs(handlers) do h(nil, ev, ...) end end

-- EUI header with one button (player)
local header = CreateFrame("Frame", "ERFPartyHeader")
local btn = CreateFrame("Button", nil, header); btn._unit = "player"
local hb = CreateFrame("StatusBar", nil, btn); hb._h = 30
local pb = CreateFrame("StatusBar", nil, btn); pb._h = 4
units.target = {"Rando","Healer"}
function UnitInParty(u) return u=="party1" or u=="party2" end
function UnitInRaid(u) return nil end
local pf = CreateFrame("Frame", "EllesmereUIUnitFrames_Target"); pf.Health = CreateFrame("StatusBar", nil, pf)
local tf = CreateFrame("Frame", "TargetFrame"); tf.healthbar = CreateFrame("StatusBar", nil, tf)
units.nameplate1 = {"Rando","Healer"}
local plate = CreateFrame("Frame", "NamePlate1")
plate.UnitFrame = CreateFrame("Frame", nil, plate); plate.UnitFrame.healthBar = CreateFrame("StatusBar", nil, plate.UnitFrame)
C_NamePlate = { GetNamePlateForUnit = function(u) if u == "nameplate1" then return plate end end }
PartyFrame = { MemberFrame1 = { unit = "party1", healthbar = CreateFrame("StatusBar") } }
CompactPartyFrameMember1 = CreateFrame("Button"); CompactPartyFrameMember1.unit = "party1"; CompactPartyFrameMember1.healthBar = CreateFrame("StatusBar")
BBF = { HealthBar = function(f) return f.bbfBar end }
local pf2 = CreateFrame("Frame", "PlayerFrame"); pf2.healthbar = CreateFrame("StatusBar", nil, pf2); pf2.bbfBar = CreateFrame("StatusBar", nil, pf2)
