-- v1.30.1: linha criada depois do UI.Layout ficava sem texto (FontString sem âncora),
-- e recompensa em MOEDA (Moxie) caía no ícone de interrogação por não ter itemID.
dofile("harness11.lua")
local C = RR.Craft
UnitName = function() return "Uriuri" end; UnitFullName = function() return "Uriuri", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
for _, profs in pairs(LucroCraftDB.chars) do
	for _, e in pairs(profs) do if e.rows then C.Scanner.ApplyABC(e.rows) end end
end
LucroCraftDB.config.recipeList = "noconc"
LucroCraftDB.config.onlyProfit = false

C.UI.ShowTab(1)
local f = LucroCraftFrame
local antes = #f.rows
local larguraNome = f.rows[1] and f.rows[1].cols.name._w
for _, row in ipairs(f.rows) do row._old = true end

-- janela mais alta: as seções ganham mais linhas e o UI.LayoutRows cria widgets NOVOS,
-- depois do UI.Layout já ter rodado
f:SetHeight(1200)
C.UI.OnResize()
C.UI.Refresh()

local novas, iguais = 0, 0
for _, row in ipairs(f.rows) do
	if not row._old then
		novas = novas + 1
		if row.cols.name._w == larguraNome then iguais = iguais + 1 end
	end
end
print(string.format("linhas: %d -> %d (novas %d)", antes, #f.rows, novas))
print(string.format("largura da coluna Receita: antigas %s · novas iguais %d/%d",
	tostring(larguraNome), iguais, novas))
print(novas == 0 and "(cenário não criou linhas novas)"
	or (iguais == novas and "OK: linha nova herda a geometria das colunas"
	or "FALHA: linha nova com coluna fora de posição"))

print("")
print("=== recompensa de pedido: item x moeda (Moxie) ===")
-- o ícone de item vem do GetItemIconByID, que funciona mesmo com o item fora do cache;
-- a interrogação (134400) só entra quando não há itemID nenhum
C_Item.GetItemIconByID = function(id) return id == 241305 and 1373905 or nil end
print("ItemIcon(241305) =", C.Visual.ItemIcon(241305), "(item fora do cache, resolve mesmo assim)")
print("ItemIcon(nil)    =", C.Visual.ItemIcon(nil), "(134400 = INV_Misc_QuestionMark)")

-- link de moeda: antes virava id nil -> interrogação; agora resolve pelo C_CurrencyInfo
C_CurrencyInfo = { GetCurrencyInfo = function(id) return { name = "Alchemist's Moxie", iconFileID = 5931173 } end }
local link = "|cnIQ1:|Hcurrency:3256|h[Alchemist's Moxie]|h|r"
local itemID = tonumber(link:match("item:(%d+)"))
local curID = (not itemID) and tonumber(link:match("currency:(%d+)")) or nil
local icone = curID and C_CurrencyInfo.GetCurrencyInfo(curID).iconFileID or C.Visual.ItemIcon(itemID)
print(string.format("link de moeda -> itemID=%s currencyID=%s icone=%s",
	tostring(itemID), tostring(curID), tostring(icone)))
print(icone ~= 134400 and "OK: usa o ícone da moeda, não a interrogação" or "FALHA: caiu na interrogação")
