#!/usr/bin/env python3
"""Confere as tabelas de tradução do addon.

Regra 3 do CLAUDE.md: a chave é o texto em PT e toda chave nova precisa da tradução EN.
Isso escapava com facilidade — numa única sessão duas chaves novas foram escritas sem EN, e o
acumulado passava de 240 sem ninguém notar, porque em cliente ptBR `L[k]` devolve a própria chave
e nada quebra.

Uso:
    python tools/loccheck.py                 # confere Craft e Livro
    python tools/loccheck.py --strict        # sai com erro se faltar alguma (para o check.sh)
    python tools/loccheck.py --unused        # lista também as chaves do Locale que ninguém usa

Limite conhecido: só enxerga `L["texto"]` literal. Rótulo passado por variável (o `OHead(..., "Conc")`
da tabela de pedidos, que faz `L[label]` lá dentro) não é detectado — por isso o --unused é
informativo, não um erro.
"""
import io
import os
import re
import sys

# o console do Windows e cp1252 e engasga em "-" (U+2212) e afins: a saida se faz UTF-8 sozinha
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULOS = ("Craft", "Livro")

USO = re.compile(r'L\["((?:[^"\\]|\\.)*)"\]')
DEF = re.compile(r'^\t\["((?:[^"\\]|\\.)*)"\]\s*=', re.M)
DEFV = re.compile(r'^\t\["((?:[^"\\]|\\.)*)"\]\s*=\s*(.*?),?\s*$', re.M)


def ler(caminho):
    return io.open(caminho, encoding="utf-8").read()


def fontes(modulo):
    pasta = os.path.join(RAIZ, modulo)
    for nome in sorted(os.listdir(pasta)):
        if nome.endswith(".lua") and nome != "Locale.lua":
            yield os.path.join(modulo, nome)


def confere(modulo, listar_sem_uso):
    locale = os.path.join(modulo, "Locale.lua")
    texto = ler(os.path.join(RAIZ, locale))
    definidas = DEF.findall(texto)
    tem = set(definidas)

    # duplicada com o MESMO valor é só redundância (a segunda sobrescreve com o mesmo texto);
    # com valor diferente é bug de verdade: a última silenciosamente ganha.
    valores = {}
    for k, v in DEFV.findall(texto):
        valores.setdefault(k, []).append(v)
    duplicadas = sorted(k for k, v in valores.items() if len(v) > 1)
    conflitantes = sorted(k for k, v in valores.items() if len(set(v)) > 1)

    usadas = {}
    for rel in fontes(modulo):
        for k in USO.findall(ler(os.path.join(RAIZ, rel))):
            usadas.setdefault(k, rel)

    faltando = sorted(k for k in usadas if k not in tem)
    sem_uso = sorted(k for k in tem if k not in usadas)

    print("%s: %d chaves no Locale, %d usadas no codigo" % (modulo, len(tem), len(usadas)))
    if faltando:
        print("  SEM TRADUCAO EN: %d" % len(faltando))
        for k in faltando:
            print("     [%s] %s" % (usadas[k], k))
    else:
        print("  sem traducao EN: 0")
    if duplicadas:
        print("  chaves duplicadas no Locale: %d (%d com valores diferentes)"
              % (len(duplicadas), len(conflitantes)))
        for k in duplicadas:
            marca = "  <-- VALORES DIFERENTES" if k in conflitantes else ""
            print("     %s%s" % (k, marca))
    if listar_sem_uso and sem_uso:
        print("  chaves do Locale sem uso literal: %d (pode ser rotulo passado por variavel)" % len(sem_uso))
        for k in sem_uso[:40]:
            print("     %s" % k)
    return len(faltando), len(conflitantes)


def main(argv):
    estrito = "--strict" in argv
    listar = "--unused" in argv
    faltam = dup = 0
    for modulo in MODULOS:
        f, d = confere(modulo, listar)
        faltam += f
        dup += d
    if faltam or dup:
        print("locale: %d sem EN, %d duplicadas" % (faltam, dup))
    else:
        print("locale ok")
    return 1 if (estrito and faltam) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
