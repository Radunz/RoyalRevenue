-- Harness: carrega o Royal Revenue com API do WoW simulada e os SavedVariables reais
ADDON_DIR = ADDON_DIR or "../"
NOW = NOW or os.time()
local realtime = os.time
time = function(t) if t then return realtime(t) end return NOW end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out+1] = p end return unpack(out) end
tinsert, tremove = table.insert, table.remove
format = string.format
hooksecurefunc = function(t, k, fn) if type(t) == "string" then return end local o = t[k]; t[k] = function(...) local r = { o(...) }; fn(...); return unpack(r) end end
GetLocale = function() return LOCALE or "ptBR" end
GetRealmName = function() return "Goldrinn" end
UnitName = function() return "Radunz" end
UnitFullName = function() return "Radunz", "Goldrinn" end
UnitClass = function() return "Druid", "DRUID" end
UnitGUID = function() return "Player-1" end
GetServerTime = function() return NOW end
HTIME = 1000; GetTime = function() return HTIME end   -- cada FIRE = um quadro novo (+0,0001 s)
IsShiftKeyDown = function() return false end
InCombatLockdown = function() return false end
GetProfessions = function() return nil end
GetMoney = function() return 0 end
PlaySound = function() end
GetMoneyString = function(c) return tostring(c) .. "c" end
BreakUpLargeNumbers = function(n) return tostring(n) end
SOUNDKIT = {}
local enumN = 0
Enum = setmetatable({}, { __index = function(t, k) local v = setmetatable({}, { __index = function(t2, k2) enumN = enumN + 1; rawset(t2, k2, enumN); return enumN end }); rawset(t, k, v); return v end })
print = print
EVENTS = {}

local function noop() end
local Widget = {}
frames = {}; ALLF = frames
local function NewWidget(kind)
	local w = { _kind = kind, _shown = false, _w = 960, _h = 600, _scripts = {}, _text = "" }
	return setmetatable(w, Widget)
end
Widget.__index = function(t, k)
	local v = rawget(Widget, k)
	if v then return v end
	if type(k) == "string" and k:match("^%u") then return noop end
	return nil
end
function Widget:RegisterEvent(e) EVENTS[e] = EVENTS[e] or {}; table.insert(EVENTS[e], self) end
function Widget:UnregisterEvent() end
function Widget:SetScript(k, fn) self._scripts[k] = fn end
function Widget:GetScript(k) return self._scripts[k] end
function Widget:HookScript(k, fn) self._scripts[k] = fn end
function Widget:Enable() rawset(self, "_enabled", true) end
function Widget:Disable() rawset(self, "_enabled", false) end
function Widget:IsEnabled() return rawget(self, "_enabled") ~= false end
function Widget:Show() self._shown = true end
function Widget:Hide() self._shown = false end
function Widget:SetShown(v) self._shown = v and true or false end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:GetWidth() return self._w end
function Widget:GetHeight() return self._h end
function Widget:SetWidth(w) self._w = w end
function Widget:SetHeight(h) self._h = h end
function Widget:SetSize(w, h) self._w, self._h = w, h end
function Widget:SetText(t) self._text = t end
function Widget:GetText() return self._text end
function Widget:GetStringHeight() return 14 end
function Widget:GetStringWidth() return #(self._text or "") * 6 end
function Widget:GetVerticalScroll() return 0 end
function Widget:GetFontString() return NewWidget("fs") end
function Widget:GetID() return self._id or 1 end
function Widget:SetID(i) self._id = i end
function Widget:GetChecked() return false end
function Widget:GetName() return self._name end
function Widget:GetParent() return self._parent end
function Widget:GetLeft() return 0 end
function Widget:GetTop() return 0 end
function Widget:GetRight() return 960 end
function Widget:GetBottom() return 0 end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetFrameLevel() return 1 end
function Widget:GetNumPoints() return 0 end
function Widget:GetCenter() return 0, 0 end
function Widget:GetScale() return 1 end
function Widget:GetValue() return 0 end
function Widget:GetThumbTexture() local t = rawget(self, "_thumb") or NewWidget("thumb"); rawset(self, "_thumb", t); return t end
function Widget:GetMinMaxValues() return 0, 1 end
function Widget:IsMouseOver() return false end
function Widget:Cancel() end
for _, m in ipairs({ "CreateLine", "CreateFontString", "CreateTexture", "CreateMaskTexture", "CreateAnimationGroup", "CreateAnimation" }) do
	Widget[m] = function(self) return NewWidget("child") end
end
CreateFrame = function(kind, name, parent)
	local w = NewWidget(kind)
	w._name, w._parent = name, parent
	if name then _G[name] = w end
	table.insert(frames, w)
	return w
end
UIParent = NewWidget("UIParent")
GameTooltip = NewWidget("tt")
Minimap = NewWidget("mm")
GameFontNormal, GameFontHighlight, GameFontHighlightSmall, GameFontDisableSmall, GameFontNormalLarge, GameFontNormalSmall = {}, {}, {}, {}, {}, {}
UISpecialFrames = {}
C_Timer = { After = function(s, fn) table.insert(TIMERS, fn) end, NewTicker = function(s, fn) return { Cancel = noop } end, NewTimer = function(s, fn) return { Cancel = noop } end }
TIMERS = {}
C_Item = {
	GetItemCount = function(id) return (STOCK and STOCK[id]) or 0 end,
	GetItemNameByID = function(id) return "Item" .. id end,
	GetItemInfo = function(id) return "Item" .. id, "|Hitem:" .. id .. "|h" end,
	GetItemIconByID = function() return 134400 end,
	GetItemQualityByID = function() return 1 end,
	GetItemQualityColor = function() return 1, 1, 1 end,
}
C_TradeSkillUI = {}
C_AddOns = { IsAddOnLoaded = function() return false end, GetAddOnMetadata = function() return "1.1.0" end }
C_ClassColor = { GetClassColor = function() return { WrapTextInColorCode = function(_, s) return s end } end }
C_AuctionHouse = { GetCommoditySearchResultInfo = function(id, i) return AH_SEARCH and AH_SEARCH[id] and { unitPrice = AH_SEARCH[id] } or nil end }
Settings = nil
MenuUtil = nil
SlashCmdList = {}
LibStub = nil

-- SavedVariables reais
dofile("fixtures/sv11.lua")

-- carrega na ordem do .toc
local toc = io.open(ADDON_DIR .. "RoyalRevenue.toc"):read("*a")
local root = {}
for line in toc:gmatch("[^\r\n]+") do
	if not line:match("^#") and line:match("%.lua$") then
		local path = ADDON_DIR .. line:gsub("\\", "/")
		local chunk = assert(loadfile(path))
		chunk("RoyalRevenue", root)
	end
end
RR = root

function FIRE(e, ...)
	HTIME = (HTIME or 1000) + 0.0001
	for _, f in ipairs(EVENTS[e] or {}) do
		local fn = f._scripts.OnEvent
		if fn then fn(f, e, ...) end
	end
end
function RUNTIMERS()
	local n = 0
	while #TIMERS > 0 and n < 200 do
		local list = TIMERS; TIMERS = {}
		for _, fn in ipairs(list) do pcall(fn) end
		n = n + 1
	end
end
FIRE("ADDON_LOADED", "RoyalRevenue")
FIRE("PLAYER_LOGIN")
FIRE("PLAYER_ENTERING_WORLD", true, false)
