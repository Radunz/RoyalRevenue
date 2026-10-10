-- v1.32.0: trocar o reagente por uma QUALIDADE diferente (fabricar sai mais barato que comprar)
-- muda perícia, qualidade de saída e concentração — que ficavam com os valores do scan.
-- Caso real: Devouring Banding mostrava custo da q1 com concentração 180 (da q2); o jogo pedia 379.
dofile("harness11.lua")
local S = RR.Craft.Scanner

-- scan escolheu a q2 (244636, 69,16g na AH); fabricar a q1 (244635) sai por 63,30g
local function Linha()
	return {
		recipeID = 1237579, name = "Devouring Banding", itemID = 900002, quality = 1, maxQuality = 2,
		qIDs = { [1] = 900001, [2] = 900002 },
		skill = 440, concCost = 180, concQuality = 2, concItemID = 900002,
		buyCost = 719703, cost = 719703, expCost = 719703, sale = 188749,
		parts = {
			{ itemID = 236952, buyItem = 236952, buyUnit = 2810, unit = 2810, qty = 10, slot = 1,
				qualityItems = { 236952 } },
			{ itemID = 244636, buyItem = 244636, buyUnit = 691603, unit = 691603, qty = 1, slot = 1,
				qualityItems = { 244635, 244636 } },
		},
	}
end
local map = { [244635] = { unit = 633041, name = "Sin'dorei Armor Banding", char = "Uriuri", inputs = {} } }
LucroCraftDB.config.useCrafted = true

print("=== antes: o que o scan deixou ===")
local base = Linha()
print(string.format("  reagente=%s skill=%s concCost=%s", tostring(base.parts[2].itemID),
	tostring(base.skill), tostring(base.concCost)))

print("")
print("=== A) profissão aberta: a API responde, então recalcula ===")
C_TradeSkillUI.GetCraftingOperationInfo = function()
	return { craftingQuality = 1, baseSkill = 240, bonusSkill = 0, concentrationCost = 379, ingenuityRefund = 162 }
end
local a = Linha()
S.ApplyCraftedReagents({ a }, map)
print(string.format("  depois da troca: reagente=%s (opDirty=%s)", tostring(a.parts[2].itemID), tostring(a.opDirty)))
S.RefreshOps({ a })
print(string.format("  recalculado:     reagente=%s skill=%s concCost=%s concQuality=%s",
	tostring(a.parts[2].itemID), tostring(a.skill), tostring(a.concCost), tostring(a.concQuality)))
local okA = a.parts[2].itemID == 244635 and a.skill == 240 and a.concCost == 379

print("")
print("=== B) outro personagem: a API não responde, então desfaz a troca ===")
C_TradeSkillUI.GetCraftingOperationInfo = function() return nil end
local b = Linha()
S.ApplyCraftedReagents({ b }, map)
S.RefreshOps({ b })
print(string.format("  revertido:       reagente=%s skill=%s concCost=%s custo=%s",
	tostring(b.parts[2].itemID), tostring(b.skill), tostring(b.concCost), tostring(b.cost)))
local okB = b.parts[2].itemID == 244636 and b.skill == 440 and b.concCost == 180

print("")
print("=== C) troca que NÃO muda a qualidade não marca para recalcular ===")
local mesmaQ = { [244636] = { unit = 600000, name = "Sin'dorei Armor Banding", char = "Uriuri", inputs = {} } }
local c = Linha()
S.ApplyCraftedReagents({ c }, mesmaQ)
print(string.format("  reagente=%s opDirty=%s (fabricou a MESMA qualidade, mais barato)",
	tostring(c.parts[2].itemID), tostring(c.opDirty)))
local okC = c.parts[2].itemID == 244636 and not c.opDirty

print("")
print((okA and okB and okC)
	and "OK: custo e concentração sempre da mesma qualidade"
	or string.format("FALHA (A=%s B=%s C=%s)", tostring(okA), tostring(okB), tostring(okC)))
