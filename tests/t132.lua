-- v1.40.0: correio de pedido de fabricacao -- cliente nao e receita (bug achado nos dados reais).
--
-- O Livro lancava TODO item que chega por correio de pedido como receita ("Recompensas pelo
-- correio", 3.2.13). Mas sao dois casos opostos:
--   - voce FABRICOU para alguem: a comissao e a recompensa sao receita de verdade;
--   - voce ENCOMENDOU: o item que chega e producao que voce pagou (reagente + comissao). Lancar
--     como receita conta DUAS VEZES, porque a venda na casa de leiloes vem depois.
--
-- Nos dados do Rafael: 1.487 Light's Potential encomendados nos proprios alts (pagou 25,02o de taxa
-- em 13/10) entraram como 19.005,74o de receita fantasma.
--
-- O jogo distingue: C_Mail.GetCraftingOrderMailInfo devolve crafterName quando a outra parte e o
-- fabricante (logo o cliente sou eu) e customerName quando a outra parte e o cliente.
dofile("harness13.lua")
local L = RR.Livro
local Ledger = L.Ledger
local CONV = Ledger.ITEMCONV_CODE

local ITEM = 241309   -- Light's Potential Q1, o do caso real
local function Nome(id) return "Item" .. id end

-- O harness nao define os globais de mensagem de loot, entao o Ledger.BuildPatterns monta uma lista
-- vazia e nenhuma mensagem casa. Define e refaz (BuildPatterns roda no PLAYER_LOGIN).
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You received bonus loot: %sx%d."
LOOT_ITEM_BONUS_ROLL_SELF = "You received bonus loot: %s."
-- o harness nao tem GetItemInfoInstant, e o OnLootMsg sai logo se ele nao resolver o link
C_Item.GetItemInfoInstant = function(link)
	local s = tostring(link)
	local id = tonumber(s:match("item:(%d+)")) or tonumber(s:match("Item(%d+)")) or tonumber(s)
	-- itemID, type, subType, equipLoc, icon, classID, subClassID
	return id, nil, nil, nil, 134400, 0, 0
end
FIRE("PLAYER_LOGIN")

-- ===== correio simulado =====
local caixa = {}
GetInboxNumItems = function() return #caixa end
GetInboxHeaderInfo = function(i)
	local m = caixa[i]
	if not m then return end
	-- packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, itemCount
	return nil, nil, m.sender, m.subject, m.money or 0, 0, 25, m.itemCount or 0
end
GetInboxItem = function(i, j)
	local m = caixa[i]
	if not m or not m.itens or not m.itens[j] then return end
	local it = m.itens[j]
	return Nome(it.id), it.id, nil, it.count
end
GetInboxInvoiceInfo = function(i)
	local m = caixa[i]
	return m and m.invoice or nil
end
C_Mail = C_Mail or {}
C_Mail.GetCraftingOrderMailInfo = function(i)
	local m = caixa[i]
	return m and m.order or nil
end
local FULFILL = Enum.RcoCloseReason.RcoCloseFulfill

-- conta os lancamentos do personagem logado
local function Journal()
	local c = LucroLivroDB.chars[L.CharKey()]
	return (c and c.journal) or {}
end
local function Ultimo()
	local j = Journal()
	return j[#j]
end
local function Loot(id, qty)
	FIRE("MAIL_SHOW")
	Ledger.ScanInbox()
	FIRE("CHAT_MSG_LOOT", string.format("You receive loot: [%s]x%d.", Nome(id), qty))
end

print("=== 1. EU ENCOMENDEI (crafterName preenchido) -> conversao, nao receita ===")
caixa = { { sender = "Crafting Order", subject = "Crafting Order Fulfilled", money = 0, itemCount = 1,
	itens = { { id = ITEM, count = 200 } },
	order = { reason = FULFILL, crafterName = "Madunz", recipeName = "Light's Potential" } } }
local antes = #Journal()
Loot(ITEM, 200)
local e = Ultimo()
local ok1 = e and tostring(e.a) == CONV and (e.v or 0) == 0 and e.i == ITEM and e.q == 200
print(string.format("   lancamentos novos: %d", #Journal() - antes))
print(string.format("   conta=%s (esperado %s) · valor=%s (esperado 0) · x(informativo)=%s · qtd=%s",
	tostring(e and e.a), CONV, tostring(e and e.v), tostring(e and e.x), tostring(e and e.q)))
print(string.format("   historico: %s", tostring(e and e.h)))
print(string.format("   -> %s", ok1 and "ok (nao entrou no resultado)" or "FALHA"))

print("")
print("=== 2. EU FABRIQUEI (customerName preenchido) -> receita de pedido, como antes ===")
caixa = { { sender = "Crafting Order", subject = "Crafting Order Fulfilled", money = 5000, itemCount = 1,
	itens = { { id = ITEM, count = 5 } },
	order = { reason = FULFILL, customerName = "Freguês", commissionPaid = 5000,
		recipeName = "Light's Potential" } } }
antes = #Journal()
Loot(ITEM, 5)
e = Ultimo()
local ok2 = e and tostring(e.a):find("^3%.2%.") and e.i == ITEM and e.q == 5
print(string.format("   conta=%s (esperado 3.2.x) · valor=%s · qtd=%s · historico=%s",
	tostring(e and e.a), tostring(e and e.v), tostring(e and e.q), tostring(e and e.h)))
print(string.format("   -> %s", ok2 and "ok (continua receita)" or "FALHA"))

print("")
print("=== 3. pedido que NAO se completou (expirou) -> material proprio voltando ===")
caixa = { { sender = "Crafting Order", subject = "Crafting Order Expired", money = 0, itemCount = 1,
	itens = { { id = ITEM, count = 12 } },
	order = { reason = FULFILL + 1, recipeName = "Light's Potential" } } }
antes = #Journal()
Loot(ITEM, 12)
e = Ultimo()
local ok3 = e and tostring(e.a) == CONV and (e.v or 0) == 0
print(string.format("   conta=%s · valor=%s  -> %s", tostring(e and e.a), tostring(e and e.v),
	ok3 and "ok (conversao)" or "FALHA"))

print("")
print("=== 4. leilao que nao vendeu e voltou pelo correio -> nada de receita ===")
-- O Rafael lembrou disso. Correio da casa de leilao nao casa com ORDER_WORDS, e o caminho de item
-- do correio ja saia antes de lancar (a linha "compras, correio, trocas e bancos nao sao ganho").
caixa = { { sender = "Auction House", subject = "Auction expired: Light's Potential", money = 0,
	itemCount = 1, itens = { { id = ITEM, count = 300 } } } }
antes = #Journal()
Loot(ITEM, 300)
local depois = #Journal()
print(string.format("   lancamentos novos: %d  -> %s", depois - antes,
	depois == antes and "ok (ignorado, nao e receita)" or "FALHA"))
local ok4 = depois == antes

print("")
print("=== 5. sem a API do jogo o comportamento antigo se mantem (nao quebra) ===")
local guarda = C_Mail.GetCraftingOrderMailInfo
C_Mail.GetCraftingOrderMailInfo = nil
caixa = { { sender = "Crafting Order", subject = "Crafting Order Fulfilled", money = 0, itemCount = 1,
	itens = { { id = ITEM, count = 7 } } } }
antes = #Journal()
local okChamada = pcall(Loot, ITEM, 7)
e = Ultimo()
local ok5 = okChamada and e and tostring(e.a):find("^3%.2%.")
print(string.format("   rodou=%s · conta=%s  -> %s", tostring(okChamada), tostring(e and e.a),
	ok5 and "ok (cai no antigo, sem erro)" or "FALHA"))
C_Mail.GetCraftingOrderMailInfo = guarda

print("")
print("=== 6. o efeito no DRE ===")
-- 200 unidades encomendadas x valor de mercado NAO podem aparecer como receita bruta
local c = LucroLivroDB.chars[L.CharKey()]
local dia = c.days[RR.DayKey(time())]
local conv = 0
for id, q in pairs((dia or {}).itemConv or {}) do conv = conv + q end
print(string.format("   unidades em conversao no dia: %d (as encomendadas + o pedido expirado)", conv))
local orders = (dia and dia.act and dia.act.orders) or nil
local recOrd = 0
for id, q in pairs((orders or {}).items or {}) do recOrd = recOrd + q end
print(string.format("   unidades em receita de pedidos no dia: %d (so o que eu fabriquei)", recOrd))
local ok6 = conv >= 212 and recOrd <= 12
print(string.format("   -> %s", ok6 and "ok" or "FALHA"))

print("")
local ok = ok1 and ok2 and ok3 and ok4 and ok5 and ok6
print(ok and "OK: correio de pedido separa o que eu encomendei do que eu fabriquei"
	or string.format("FALHA (1=%s 2=%s 3=%s 4=%s 5=%s 6=%s)", tostring(ok1), tostring(ok2),
		tostring(ok3), tostring(ok4), tostring(ok5), tostring(ok6)))

print("")
print("=== 7. o count do invoice da venda: 11o retorno, nao o 10o ===")
-- Nos dados reais as 13 vendas de Light's Potential no log proprio estavam TODAS com qty=0 e o
-- price guardando o total da carta. Causa: o `count` do GetInboxInvoiceInfo e o 11o retorno (o 10o
-- e o etaMin, que vem 0), e `count or 1` nao cai no padrao porque 0 e verdadeiro em Lua.
LucroCraftDB.salesLog = nil
caixa = {}
GetInboxInvoiceInfo = function(i)
	local m = caixa[i]
	if not m then return end
	-- invoiceType, itemName, playerName, bid, buyout, deposit, consignment, _, etaHour, etaMin, count
	return "seller", m.nome, "Comprador", m.bid, m.bid, 0, 0, 0, 0, 0, m.count
end
caixa = { { sender = "Auction House", subject = "Auction successful", money = 1000000, itemCount = 0,
	nome = "Light's Potential", bid = 2470000, count = 200 } }
FIRE("MAIL_SHOW")
FIRE("MAIL_INBOX_UPDATE")
RUNTIMERS()
local vendas = RR.Craft.Own.Sales()
local v = vendas[#vendas]
local ok7 = v and v.qty == 200 and math.abs(v.price - 2470000 / 200) < 1
print(string.format("   bid 247o de 200 unidades -> qty=%s preco unit=%s (esperado 200 e 1,23o)  %s",
	tostring(v and v.qty), v and string.format("%.2fo", v.price / 10000) or "-",
	ok7 and "ok" or "FALHA"))
-- carta sem count (venda de item unico): cai no 1 como antes
caixa = { { sender = "Auction House", subject = "Auction successful", money = 1000,
	nome = "Outro Item", bid = 50000, count = nil } }
FIRE("MAIL_INBOX_UPDATE")
RUNTIMERS()
vendas = RR.Craft.Own.Sales()
local v2
for _, x in ipairs(vendas) do if x.name == "Outro Item" then v2 = x end end
local ok7b = v2 and v2.qty == 1 and v2.price == 50000
print(string.format("   carta sem count -> qty=%s preco=%s  %s", tostring(v2 and v2.qty),
	v2 and string.format("%.2fo", v2.price / 10000) or "-", ok7b and "ok (cai no 1)" or "FALHA"))

print("")
print(((ok1 and ok2 and ok3 and ok4 and ok5 and ok6 and ok7 and ok7b)
	and "OK (completo): correio de pedido separado e count do invoice corrigido"
	or string.format("FALHA no bloco 7 (ok7=%s ok7b=%s)", tostring(ok7), tostring(ok7b))))
