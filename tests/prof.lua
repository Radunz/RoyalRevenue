local t0 = os.clock()
dofile(HARNESS or "harness12.lua")
C_Item.GetItemInfoInstant = C_Item.GetItemInfoInstant or function(id) return tonumber(id) or 1, "", "", "", 134400, 7, 5 end
C_CurrencyInfo = C_CurrencyInfo or { GetCurrencyInfo = function(id) return { name = "Moeda" .. id } end }
print(string.format("LOAD+LOGIN %.0f ms", (os.clock() - t0) * 1000))
RUNT0 = os.clock(); RUNTIMERS(); print(string.format("timers pós-login %.0f ms", (os.clock() - RUNT0) * 1000))
local C, L = RR.Craft, RR.Livro
C_WowTokenPublic = C_WowTokenPublic or { UpdateMarketPrice = function() end, GetCurrentMarketPrice = function() return 2930400000 end }
-- amostragem
samples = {}
local function hook()
  local info = debug.getinfo(2, "Sl")
  if info then local k = (info.short_src:match("[^/]+/[^/]+$") or info.short_src) .. ":" .. (info.currentline or 0); samples[k] = (samples[k] or 0) + 1 end
end
local function T(name, fn, n)
  n = n or 1
  local t = os.clock()
  debug.sethook(hook, "", 1000)
  for i = 1, n do local ok, e = pcall(fn); if not ok then print("ERR", name, e) break end end
  debug.sethook()
  print(string.format("%-28s %8.1f ms", name, (os.clock() - t) * 1000 / n))
  if PER then
    local arr = {}
    for k, v in pairs(samples) do table.insert(arr, { k, v }) end
    table.sort(arr, function(a, b) return a[2] > b[2] end)
    local o = {}
    for i = 1, math.min(6, #arr) do table.insert(o, arr[i][2] .. " " .. arr[i][1]) end
    print("      " .. table.concat(o, "  "))
    samples = {}
  end
end
PROF_T = T
RR.Open("craft")
for id = 1, 9 do T("craft tab " .. id, function() C.UI.ShowTab(id) end) end
for id = 1, 9 do T("craft redraw " .. id, function() C.UI.ShowTab(id); C.UI.RefreshTab(id) end) end
if C.Plan and C.Plan.Build then T("Plan.Build", function() C.Plan.Build() end, 3) end
T("Buy.Build", function() C.Buy.Build() end, 3)
if C.Queue.Shopping then T("Queue.Shopping", function() C.Queue.Shopping() end, 3) end
if L and L.Ledger and L.Ledger.DRE then T("Ledger.DRE 30d", function() L.Ledger.DRE() end, 3) end
RR.Open("livro")
local f = LucroLivroFrame
for i, tb in ipairs(f.Tabs or {}) do T("livro tab " .. i .. " " .. tostring(tb._text or tb.text or ""), function() tb._scripts.OnClick(tb) end) end
T("FIRE BAG_UPDATE_DELAYED", function() FIRE("BAG_UPDATE_DELAYED") end, 20)
T("FIRE PLAYER_MONEY", function() FIRE("PLAYER_MONEY") end, 20)
local arr = {}
for k, v in pairs(samples) do table.insert(arr, { k, v }) end
table.sort(arr, function(a, b) return a[2] > b[2] end)
for i = 1, math.min(40, #arr) do print(arr[i][2], arr[i][1]) end
