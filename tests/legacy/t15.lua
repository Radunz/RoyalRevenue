dofile("t2.lua")
RR.Open("livro")
local f = LucroLivroFrame
local t = {}
for i, tab in ipairs(f.Tabs) do table.insert(t, tab._text) end
print("abas livro:", table.concat(t, " | "))
print("strip", f.rrStrip ~= nil, "titulo escondido", f.titleFS and f.titleFS._shown)
