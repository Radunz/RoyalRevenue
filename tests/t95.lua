-- Receitas v1.28.0: abas Concentração / Sem concentração e fim da divisão por volume.
-- A lista tinha 4 seções (Volume · Baixo volume alto lucro · Sem lucro · Desconhecidas);
-- agora tem 3 (Com lucro · Sem lucro · Desconhecidas) e as ABAS separam por uso de concentração.
dofile("harness11.lua")
local C = RR.Craft
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
for _, e in pairs(LucroCraftDB.chars["Radunz-Goldrinn"]) do
	if e.rows then C.Scanner.ApplyABC(e.rows) end
end
LucroCraftDB.config.onlyProfit = false

local function strip(s)
	return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

print("aba padrão:", C.UI.RecipeList())

for _, key in ipairs({ "conc", "noconc" }) do
	C.UI.SetRecipeList(key)
	C.UI.ShowTab(1)
	C.UI.Refresh()
	local f = LucroCraftFrame
	print("")
	print("=== aba " .. key .. " ===")
	for _, b in ipairs(f.listTabs or {}) do print("  aba: [" .. strip(b.text._text) .. "]") end
	print("  seções: " .. #f.sections)
	for _, sec in ipairs(f.sections) do print("    " .. strip(sec.title._text)) end
	-- toda linha visível tem que pertencer à aba (conc = qualidade de cima, noconc = o resto)
	local errado = 0
	local amostra = {}
	for _, row in ipairs(f.rows or {}) do
		local r = row.data
		if r then
			local isConc = r.variant == "conc"
			if isConc ~= (key == "conc") then errado = errado + 1 end
			if #amostra < 4 then table.insert(amostra, (r.name or "?") .. " [" .. tostring(r.variant) .. "]") end
		end
	end
	print("  linhas na aba errada: " .. errado)
	for _, s in ipairs(amostra) do print("    " .. s) end
end

print("")
print("=== cada aba mostra o resultado certo da MESMA receita ===")
local e = LucroCraftDB.chars["Radunz-Goldrinn"][2906]
for _, r in ipairs(e.rows) do
	if r.name == "Light's Potential" then
		for _, v in ipairs(C.UI._Variants(r)) do
			print(string.format("  variant=%-5s item=%s abc=%s lucro=%s",
				tostring(v.variant), tostring(v.itemID), tostring(v.abc),
				type(v.profit) == "number" and math.floor(v.profit / 10000) or tostring(v.profit)))
		end
	end
end
