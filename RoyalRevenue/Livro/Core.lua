local ADDON, root = ...
local print = function(...) return root.Out(...) end   -- mensagens vão para a aba de log
root.Livro = root.Livro or {}
local ns = root.Livro
ns.root = root
local L = ns.L

-- inicialização, comando /livro e API para o LucroCraft abrir as vendas
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, name)
	if name ~= ADDON then return end
	LucroLivroDB = LucroLivroDB or {}
	LucroLivroDB.chars = LucroLivroDB.chars or {}
	LucroLivroDB.config = LucroLivroDB.config or {}
	if ns.Minimap then pcall(ns.Minimap.Init) end
	if ns.Options then pcall(ns.Options.Register) end
end)

SLASH_LUCROLIVRO1 = "/livro"
SLASH_LUCROLIVRO2 = "/lucrolivro"
SlashCmdList.LUCROLIVRO = function(msg)
	local cmd = (msg or ""):lower():match("^(%S*)")
	if cmd == "limpar" or cmd == "clear" then
		LucroLivroDB.chars[ns.CharKey()] = nil
		print("|cffd4af37Royal Revenue|r: " .. L["histórico deste personagem apagado."])
	elseif cmd == "opcoes" or cmd == "opções" or cmd == "options" or cmd == "config" then
		ns.Options.Open()
	elseif cmd == "minimapa" or cmd == "minimap" then
		ns.Minimap.Toggle()
	elseif cmd == "vendas" or cmd == "sales" then
		ns.UI.Show(6)
	elseif cmd == "ajuda" or cmd == "help" or cmd == "?" then
		print("|cffd4af37Royal Revenue|r: " .. L["/livro — abre/fecha o painel · /livro minimapa — mostra/esconde o ícone · /livro limpar — apaga o histórico deste personagem"])
	else
		ns.UI.Toggle()
	end
end

-- outros addons (LucroCraft) podem abrir o painel: LucroLivro.Show(tab)
LucroLivro = { Show = function(tab) ns.UI.Show(tab) end, SALES = 6 }
