-- v1.33.0: coluna Lucro/ouro na aba Sem concentração, e as colunas de concentração só na
-- aba Concentração.
dofile("harness11.lua")
local C = RR.Craft
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
for _, profs in pairs(LucroCraftDB.chars) do
	for _, e in pairs(profs) do if e.rows then C.Scanner.ApplyABC(e.rows) end end
end
LucroCraftDB.config.onlyProfit = false
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end

print("=== colunas visíveis em cada aba ===")
local porAba = {}
for _, key in ipairs({ "conc", "noconc" }) do
	C.UI.SetRecipeList(key)
	C.UI.ShowTab(1)
	C.UI.Refresh()
	local cols, tem = {}, {}
	for _, h in ipairs(LucroCraftFrame.headers or {}) do
		if h:IsShown() then
			local t = strip(h.text._text):gsub(" [v^]%d*$", "")
			cols[#cols + 1] = t
			tem[h.key] = true
		end
	end
	porAba[key] = tem
	print("  " .. key .. ": " .. table.concat(cols, " | "))
end
local okConc = porAba.conc.concCost and porAba.conc.perConc and not porAba.conc.perGold
local okNo = porAba.noconc.perGold and not porAba.noconc.concCost and not porAba.noconc.perConc
print("  " .. ((okConc and okNo) and "OK: cada coluna só na aba dela"
	or string.format("FALHA (conc=%s noconc=%s)", tostring(okConc), tostring(okNo))))

print("")
print("=== Lucro/ouro = ouro de lucro por 1 ouro de material ===")
C.UI.SetRecipeList("noconc")
C.UI.ShowTab(1)
C.UI.Refresh()
local n, bate = 0, true
for _, row in ipairs(LucroCraftFrame.rows or {}) do
	local c = row.cols
	local nome = strip(c.name and c.name._text or "")
	if nome ~= "" and n < 5 then
		n = n + 1
		local r = row.data
		local pg = C.UI.PerGold(r)
		-- a coluna é a mesma razão da Margem: 94% -> 0,94o
		if pg and r.margin and math.abs(pg / 10000 - r.margin) > 0.001 then bate = false end
		print(string.format("  %-28s margem=%-6s Lucro/ouro=%s", nome:sub(1, 28),
			strip(c.margin._text), strip(c.perGold._text)))
	end
end
print("  " .. (bate and "OK: bate com a margem" or "FALHA: Lucro/ouro não bate com a margem"))

print("")
print("=== ordenação pela coluna nova ===")
C.UI.SortByColumn("perGold")
C.UI.Refresh()
local vals = {}
for _, row in ipairs(LucroCraftFrame.rows or {}) do
	local r = row.data
	if r and C.UI.PerGold(r) then vals[#vals + 1] = math.floor(C.UI.PerGold(r)) end
	if #vals >= 5 then break end
end
print("  primeiros valores: " .. table.concat(vals, ", "))
