-- v1.40.1: valor secreto comparado (erro do BugGrabber no hunter, 26/10 08:46).
--
--   Craft/Gather.lua:269: attempt to compare field 'duration'
--   (a secret number value, while execution tainted by 'RoyalRevenue')
--   locals: cd = { duration=<secret number>, startTime=<secret number>, modRate=<secret number> }
--           spellID = 1270573
--
-- A armadilha fina: o codigo JA tinha guarda de tipo --
--   if ok and cd and type(cd.duration) == "number" and cd.duration > 2 then
-- -- e ela nao protege. `type()` de um numero secreto devolve "number" (os locals do relato mostram
-- literalmente `(*temporary)="number"`), entao a guarda passa e a comparacao seguinte estoura.
-- Só `issecretvalue` (root.AnySecret) protege. Regra 5 do CLAUDE.md.
--
-- Duas linhas acima, no mesmo arquivo, o `name` JA era conferido com issecretvalue. O cooldown nao.
dofile("harness13.lua")

print("=== a armadilha: guarda de tipo nao protege de valor secreto ===")
local SECRETO = 7777
issecretvalue = function(v) return v == SECRETO end
print(string.format("   type(%d) = %q  <- a guarda antiga passava por aqui", SECRETO, type(SECRETO)))
print(string.format("   (%d or 0) > 0 = %s  <- e o `or 0` tambem nao pega", SECRETO, tostring(SECRETO > 0)))
print(string.format("   root.AnySecret(%d) = %s  <- so isto pega", SECRETO, tostring(RR.AnySecret(SECRETO))))
local okTrap = type(SECRETO) == "number" and RR.AnySecret(SECRETO) == true
	and RR.AnySecret(10) == false
print(string.format("   numero normal segue passando: AnySecret(10)=%s  %s",
	tostring(RR.AnySecret(10)), okTrap and "ok" or "FALHA"))

print("")
print("=== AnySecret com varios argumentos (os retornos do GetRecipeCooldown) ===")
local casos = {
	{ { 0, 0, 0 }, false, "nada secreto" },
	{ { 0, SECRETO, 0 }, true, "o do meio secreto" },
	{ { SECRETO }, true, "o primeiro secreto" },
	{ { nil, nil, nil }, false, "tudo nil" },
}
local okMulti = true
for _, c in ipairs(casos) do
	local r = RR.AnySecret(c[1][1], c[1][2], c[1][3])
	if r ~= c[2] then okMulti = false end
	print(string.format("   %-20s -> %-5s (esperado %s) %s", c[3], tostring(r), tostring(c[2]),
		r == c[2] and "ok" or "FALHA"))
end
-- sem a API do jogo (cliente antigo) nao pode quebrar: devolve false
local guarda = issecretvalue
issecretvalue = nil
local okSemAPI = RR.AnySecret(SECRETO) == false
print(string.format("   sem issecretvalue no cliente -> %s  %s", tostring(RR.AnySecret(SECRETO)),
	okSemAPI and "ok (nao quebra)" or "FALHA"))
issecretvalue = guarda

print("")
print("=== os quatro pontos que mexem com valor que pode vir secreto ===")
local function Ler(rel)
	local f = io.open((ADDON_DIR or "../") .. rel)
	local s = f:read("*a"); f:close()
	return s
end
local pontos = {
	{ "Craft/Gather.lua", "cooldown do Overload (o do relato)",
		"root%.AnySecret%(dur%).-type%(dur%) == \"number\".-dur > 2" },
	{ "Craft/InvestView.lua", "expirationTime da aura (regra 5 cita aura)",
		"root%.AnySecret%(fim%).-type%(fim%) == \"number\"" },
	{ "Craft/Scanner.lua", "retornos do GetRecipeCooldown",
		"root%.AnySecret%(cool, charges, maxCharges%)" },
	{ "Craft/Salvage.lua", "retornos do GetRecipeCooldown",
		"root%.AnySecret%(cool, charges, maxCharges%)" },
}
local okPontos = true
for _, p in ipairs(pontos) do
	local tem = Ler(p[1]):find(p[3]) ~= nil
	if not tem then okPontos = false end
	print(string.format("   %-22s %-40s %s", p[1], p[2], tem and "guardado" or "FALHA"))
end

print("")
print("=== varredura: nenhuma chamada dessas familias sem guarda ===")
-- Impede a classe de voltar: toda chamada a cooldown de feitico/receita, e todo campo de aura usado
-- em conta, tem de ter AnySecret por perto. Se alguem acrescentar uma sem guarda, este teste cai.
local ARQS = { "Craft/Gather.lua", "Craft/Salvage.lua", "Craft/Scanner.lua", "Craft/InvestView.lua",
	"Craft/Consum.lua", "Craft/Invest.lua", "Craft/UI.lua", "Craft/Core.lua" }
local FAMILIAS = { "GetSpellCooldown", "GetRecipeCooldown", "expirationTime" }
local semGuarda = {}
for _, rel in ipairs(ARQS) do
	local linhas = {}
	for l in (Ler(rel) .. "\n"):gmatch("([^\n]*)\n") do table.insert(linhas, l) end
	for i, l in ipairs(linhas) do
		if l:match("^%s*%-%-") == nil then
			for _, fam in ipairs(FAMILIAS) do
				if l:find(fam, 1, true) then
					-- procura AnySecret/issecretvalue nas linhas ao redor. A janela e folgada de
					-- proposito: o comentario que explica a armadilha fica entre a chamada e a
					-- guarda, e com janela curta a propria linha consertada aparecia como falha.
					local perto = false
					for j = math.max(1, i - 3), math.min(#linhas, i + 9) do
						if linhas[j]:find("AnySecret", 1, true) or linhas[j]:find("issecretvalue", 1, true) then
							perto = true
						end
					end
					if not perto then
						table.insert(semGuarda, string.format("%s:%d  %s", rel, i, l:gsub("^%s+", ""):sub(1, 70)))
					end
				end
			end
		end
	end
end
print(string.format("   chamadas sem guarda por perto: %d", #semGuarda))
for _, x in ipairs(semGuarda) do print("      " .. x) end
local okVarre = #semGuarda == 0

print("")
print("=== e o erro #16 do BugGrabber (UI.lua:245, 24x em 18/10) ===")
-- "attempt to call a nil value" no laco que acompanha a receita na Auditoria, com aba=10.
-- Era estado transitorio daquele dia (sessao 155 contra 240 atual): as quatro funcoes existem.
local src = Ler("Craft/UI.lua")
local fns = { "AuditWatch", "AuditFollowing", "SelectedRecipeID", "AuditFollow" }
local okFns = true
for _, fn in ipairs(fns) do
	local tem = src:find("function UI%." .. fn .. "%(") ~= nil
	if not tem then okFns = false end
	print(string.format("   UI.%-18s %s", fn, tem and "definida" or "FALHA (chamada mas nao existe)"))
end

print("")
local ok = okTrap and okMulti and okSemAPI and okPontos and okVarre and okFns
print(ok and "OK: valor secreto nao e mais comparado, e a varredura impede a classe de voltar"
	or string.format("FALHA (trap=%s multi=%s semAPI=%s pontos=%s varre=%s fns=%s)",
		tostring(okTrap), tostring(okMulti), tostring(okSemAPI), tostring(okPontos),
		tostring(okVarre), tostring(okFns)))
