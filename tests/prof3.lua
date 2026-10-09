-- perfil inclusivo de: login (MODE=login) ou aba do Livro (MODE=livro, TAB=n)
local incl = {}
local function hook()
  local seen = {}
  for lv = 2, 40 do
    local i = debug.getinfo(lv, "S")
    if not i then break end
    local k = (i.short_src:match("[^/]+/[^/]+$") or i.short_src) .. ":" .. i.linedefined
    if not seen[k] then seen[k] = true; incl[k] = (incl[k] or 0) + 1 end
  end
end
if MODE == "login" then debug.sethook(hook, "", 1000) end
dofile("harness12.lua")
C_Item.GetItemInfoInstant = C_Item.GetItemInfoInstant or function(id) return tonumber(id) or 1, "", "", "", 134400, 7, 5 end
C_CurrencyInfo = C_CurrencyInfo or { GetCurrencyInfo = function(id) return { name = "Moeda" .. id } end }
RUNTIMERS()
debug.sethook()
if MODE == "livro" then
  RR.Open("livro")
  local tb = LucroLivroFrame.Tabs[TAB]
  debug.sethook(hook, "", 1000)
  for i = 1, 5 do tb._scripts.OnClick(tb) end
  debug.sethook()
end
local arr = {}
for k, v in pairs(incl) do table.insert(arr, { k, v }) end
table.sort(arr, function(a, b) return a[2] > b[2] end)
for i = 1, math.min(N or 35, #arr) do print(arr[i][2], arr[i][1]) end
