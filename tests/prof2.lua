dofile("harness12.lua")
C_Item.GetItemInfoInstant = C_Item.GetItemInfoInstant or function(id) return tonumber(id) or 1, "", "", "", 134400, 7, 5 end
RUNTIMERS()
local C = RR.Craft
RR.Open("craft")
local incl = {}
local function hook()
  -- inclusive: conta cada função na pilha uma vez
  local seen = {}
  for lv = 2, 30 do
    local i = debug.getinfo(lv, "S")
    if not i then break end
    local k = (i.short_src:match("[^/]+/[^/]+$") or i.short_src) .. ":" .. i.linedefined
    if not seen[k] then seen[k] = true; incl[k] = (incl[k] or 0) + 1 end
  end
end
local target = TARGET or 9
C.UI.ShowTab(target)
debug.sethook(hook, "", 1000)
for i = 1, (N or 5) do C.UI.RefreshTab(target) end
debug.sethook()
local arr = {}
for k, v in pairs(incl) do table.insert(arr, { k, v }) end
table.sort(arr, function(a, b) return a[2] > b[2] end)
for i = 1, math.min(30, #arr) do print(arr[i][2], arr[i][1]) end
