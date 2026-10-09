dofile("sv11.lua")
-- TSM buys
local buys = {}
local f = io.open("../tests/fixtures/tsm_buys_all.csv")
for line in f:lines() do
  local realm, item, stack, qty, price, other, player, t, src = line:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")
  player = player .. "-" .. realm
  t = tonumber(t)
  if t and t > 1785000000 then
    table.insert(buys, { id = tonumber(item:match("i:(%d+)")), stack = tonumber(stack), qty = tonumber(qty), price = tonumber(price), other = other, player = player, t = t, src = src, total = tonumber(price) * tonumber(qty) })
  end
end
-- reagentes conhecidos
local reag = {}
for _, es in pairs(LucroCraftDB.chars or {}) do for _, e in pairs(es) do for _, list in ipairs({ e.rows or {}, e.unknown or {} }) do for _, r in ipairs(list) do
  for _, p in ipairs(r.parts or {}) do for _, id in ipairs(p.qualityItems or {}) do reag[id] = true end; if p.itemID then reag[p.itemID] = true end end
end end end end
local function isMat(b)
  if b.id and reag[b.id] then return true end
  if b.other == "Multiple Sellers" or b.qty > 1 then return true end
  return false
end
local stats = { dep = 0, depN = 0, buy = 0, item = 0, vmat = 0, vend = 0 }
local minT
for char, c in pairs(LucroLivroDB.chars) do
  local name = char:gsub("'", "")
  for _, e in ipairs(c.journal or {}) do
    if not minT or e.t < minT then minT = e.t end
    if (e.a == "4.3.02" or e.a == "4.3.01") and e.v < 0 then
      local need = -e.v
      local cands = {}
      for _, b in ipairs(buys) do
        if not b.used and b.player == name and b.t >= e.t - 20 and b.t <= e.t + 5 and ((e.a == "4.3.02") == (b.src == "Auction")) then table.insert(cands, b) end
      end
      table.sort(cands, function(x, y) return math.abs(x.t - e.t) < math.abs(y.t - e.t) end)
      local sum, mat, itm = 0, 0, 0
      for _, b in ipairs(cands) do
        if sum >= need * 0.97 then break end
        b.used = true; sum = sum + b.total
        if isMat(b) then mat = mat + b.total else itm = itm + b.total; ITEMS = ITEMS or {}; ITEMS[b.id] = (ITEMS[b.id] or 0) + b.total end
      end
      local to
      if e.a == "4.3.02" then to = (sum == 0) and "ahdep" or (mat >= itm and "ahbuy" or "ahitem")
      else to = (sum > 0 and mat >= itm) and "vendmat" or nil end
      if to then OUT = OUT or {}; table.insert(OUT, string.format("\t{ %q, %d, %d, %q, %q },", char, e.t, e.v, e.a, to)) end
      if e.a == "4.3.02" then
        if sum == 0 then stats.dep = stats.dep + need; stats.depN = stats.depN + 1; if need > 2000000 then print("big unmatched", char, os.date("!%m-%d %H:%M:%S", e.t - 10800), need / 10000, e.h) end
        elseif mat >= itm then stats.buy = stats.buy + need else stats.item = stats.item + need end
      else
        if sum > 0 and mat >= itm then stats.vmat = stats.vmat + need else stats.vend = stats.vend + need end
      end
    end
  end
end
print("journal desde", os.date("!%Y-%m-%d", minT - 10800))
for k, v in pairs(stats) do print(k, k == "depN" and v or v / 10000) end
-- out.ah total por dia (todos)
local tot, early = 0, 0
for char, c in pairs(LucroLivroDB.chars) do for d, day in pairs(c.days or {}) do if day.out and day.out.ah then tot = tot + day.out.ah; if d < os.date("!%Y-%m-%d", minT - 10800) then early = early + day.out.ah end end end end
print("out.ah total", tot / 10000, "antes do diario", early / 10000)

for id, v in pairs(ITEMS) do print("ITEM", id, v / 10000) end

local fo = io.open("../RoyalRevenue/Livro/Reclass.lua", "w")
fo:write("local ADDON, root = ...\nroot.Livro = root.Livro or {}\nlocal ns = root.Livro\n\n")
fo:write("-- Reclassificação única dos gastos antigos na casa de leilões / vendedor (antes da v1.19 tudo ia para 4.3.02/4.3.01).\n")
fo:write("-- Gerada a partir do histórico de compras do TSM (csvBuys de cada reino) em 07/10/2026:\n")
fo:write("--   compra casada com commodity/reagente → ahbuy (material) · com item avulso → ahitem (uso) · sem compra → ahdep (depósito)\n")
fo:write("-- { personagem, hora, valor, conta antiga, chave nova }\n")
fo:write("ns.RECLASS1 = {\n" .. table.concat(OUT, "\n") .. "\n}\n")
fo:close()
print("linhas", #OUT)
