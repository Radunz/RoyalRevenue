-- Curva ABC por ITEM (v1.27.1): cada resultado da receita é classificado pelo seu próprio item.
-- Light's Potential Q1 dá prejuízo fabricado -> sem classe; o Q2 da MESMA receita entra na curva
-- do ouro/ponto. Antes as duas linhas herdavam o abc da receita, e o Q1 aparecia como A.
dofile("harness11.lua")
local C = RR.Craft
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end

local e = LucroCraftDB.chars["Radunz-Goldrinn"][2906]   -- Alquimia Midnight
C.Scanner.ApplyABC(e.rows)

print("=== resultado base (sem concentração) x resultado com concentração ===")
for _, nome in ipairs({ "Light's Potential", "Liquid Luster", "Bouquet of Herbs" }) do
	for _, r in ipairs(e.rows) do
		if r.name == nome then
			print(string.format("%s", r.name))
			print(string.format("   base item=%s lucro=%s -> abc=%s livre=%s",
				tostring(r.itemID), tostring(math.floor((r.profit or 0) / 10000)), tostring(r.abc), tostring(r.abcFree)))
			print(string.format("   conc item=%s ouro/ponto=%s -> abc=%s share=%s",
				tostring(r.concItemID), tostring(math.floor((r.perConc or 0) / 10000 * 10) / 10),
				tostring(r.concAbc), r.concAbcShare and (math.floor(r.concAbcShare * 1000) / 10 .. "%") or "nil"))
		end
	end
end

print("")
print("=== distribuição da curva (só o resultado com concentração entra em A/B/C) ===")
local c = { A = 0, B = 0, C = 0 }
local livres, fora = 0, 0
for _, r in ipairs(e.rows) do
	if r.concAbc then c[r.concAbc] = c[r.concAbc] + 1 end
	if r.abcFree then livres = livres + 1 end
	if not r.concAbc and not r.abcFree then fora = fora + 1 end
end
print(string.format("conc: A=%d B=%d C=%d · base lucrativo (livre, A)=%d · fora da curva=%d",
	c.A, c.B, c.C, livres, fora))

print("")
print("=== Recommendable usa a classe do resultado pedido ===")
for _, r in ipairs(e.rows) do
	if r.name == "Light's Potential" then
		local okBase, whyBase = C.Recommendable(r, false)
		local okConc, whyConc = C.Recommendable(r, true)
		print("base (sem conc):", tostring(okBase), tostring(whyBase))
		print("conc (com conc):", tostring(okConc), tostring(whyConc))
	end
end

print("")
print("=== item vinculado não entra (v1.26.3) ===")
local orig = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id)
	if id == 777001 then return "BoP", "|Hitem:777001|h", 1, 1, 1, "", "", 1, "", 0, 0, 1, 1, 1 end
	return orig(id)
end
local rows = {
	{ recipeID = 1, itemID = 241305, spd = 500, profit = 50000, name = "livre lucrativo" },
	{ recipeID = 2, itemID = 777001, spd = 9999, profit = 999999, perConc = 999999, concSpd = 9999, name = "vinculado (fora)" },
	{ recipeID = 3, itemID = 241301, spd = 300, profit = -10, perConc = 30000, concSpd = 300, concItemID = 241301, name = "só com conc" },
}
C.Scanner.ApplyABC(rows)
for _, r in ipairs(rows) do
	print(string.format("%-20s abc=%s livre=%s concAbc=%s vinculado=%s",
		r.name, tostring(r.abc), tostring(r.abcFree), tostring(r.concAbc), tostring(r.notAuctionable)))
end
C_Item.GetItemInfo = orig
