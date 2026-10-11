-- v1.32.1: equipamento "vinculado ao bando até equipar" aparecia na aba Vender e o botão Postar
-- não fazia nada (o jogo recusa anunciar). O filtro da bolsa só olhava info.isBound, que é falso
-- enquanto o item ainda não foi equipado.
dofile("harness11.lua")
local C = RR.Craft

-- bolsa: poção empilhável, equipamento normal e equipamento vinculado ao bando
local BAG = { [0] = {
	[1] = { itemID = 241305, stackCount = 20, quality = 1, isBound = false, hyperlink = "|Hitem:241305|h[Poção]|h" },
	[2] = { itemID = 900100, stackCount = 1, quality = 3, isBound = false, hyperlink = "|Hitem:900100|h[Elmo normal]|h" },
	[3] = { itemID = 900200, stackCount = 1, quality = 3, isBound = false, hyperlink = "|Hitem:900200|h[Elmo do bando]|h" },
	[4] = { itemID = 900300, stackCount = 1, quality = 3, isBound = true, hyperlink = "|Hitem:900300|h[Elmo equipado]|h" },
} }
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
	GetContainerItemInfo = function(bag, slot) return (BAG[bag] or {})[slot] end,
}
-- o 14º retorno do GetItemInfo é o tipo de vínculo: 8 = vinculado ao bando
C_Item.GetItemInfo = function(id)
	id = tonumber(id) or 0
	local bind = (id == 900200) and 8 or 0
	local maxStack = (id == 241305) and 20 or 1
	return "Item" .. id, "|Hitem:" .. id .. "|h", 3, 0, 0, "", "", maxStack, "", 0, 0, 4, 0, bind, 10
end
-- todo equipamento com preço, para não ser escondido por falta de preço
C.Pricing.SaleByLink = function() return 500000, 1 end

print("=== tipo de vínculo ===")
for _, id in ipairs({ 241305, 900100, 900200 }) do
	print(string.format("  IsAuctionable(%d) = %s", id, tostring(C.IsAuctionable(id))))
end

print("")
print("=== o que entra na lista da aba Vender ===")
local res = C.Sell.Build()
local vistos = {}
for _, m in ipairs(res.items or {}) do
	vistos[m.id] = true
	print(string.format("  %d  gear=%s", m.id, tostring(m.gear)))
end
print(string.format("  escondidos: %d", res.hidden or 0))

local okPocao = vistos[241305] == true          -- commodity: sempre pode
local okNormal = vistos[900100] == true         -- equipamento normal: pode
local okBando = vistos[900200] == nil           -- vinculado ao bando: NÃO pode
local okEquipado = vistos[900300] == nil        -- já vinculado: nunca entrou
print("")
print((okPocao and okNormal and okBando and okEquipado)
	and "OK: só entra o que o jogo deixa anunciar"
	or string.format("FALHA (poção=%s normal=%s bando=%s equipado=%s)",
		tostring(okPocao), tostring(okNormal), tostring(okBando), tostring(okEquipado)))
