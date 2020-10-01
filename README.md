# luaregex

> 🇺🇸 [English version below](#english)

Um motor de expressões regulares escrito do zero em Lua. Sem C, sem LPeg, sem `string.find` escondido: parser feito à mão e um matcher com backtracking, em umas 400 linhas.

Fiz porque eu usava regex há anos sem saber o que acontecia lá dentro. Depois disso, "catastrophic backtracking" deixou de ser uma frase de blog e virou uma coisa que eu vi acontecer no meu próprio código, linha por linha.

| O que tem | Sintaxe |
| --- | --- |
| literais e escapes | `abc`, `\.`, `\n`, `\t` |
| qualquer caractere | `.` (menos quebra de linha) |
| âncoras | `^`, `$`, `\b`, `\B` |
| classes | `[abc]`, `[a-z]`, `[^0-9]`, `\d \w \s \D \W \S` |
| quantificadores | `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}` e as versões lazy `*?` `+?` `??` |
| grupos | `( )` com captura, `(?: )` sem |
| backreferences | `\1` até `\9` |
| alternação | `a\|b` |
| flag | `"i"` pra ignorar maiúsculas |

```lua
local Regex = require("regex")
local re = Regex.compile("(\d{4})-(\d{2})-(\d{2})")
re:test("2020-09-22")                     --> true
re:match("due 2020-09-22")                --> "2020", "09", "22"
re:gsub("due 2020-09-22", "%3/%2/%1")     --> "due 22/09/2020", 1
for w in Regex.gmatch("\w+", "one two three") do print(w) end
Regex.split(",\s*", "a, b,c")            --> { "a", "b", "c" }
```

Toda função também funciona "one-shot" com o padrão como primeiro argumento (`Regex.match("\d+", "abc 123")`), e o `gsub` aceita string com `%0`..`%9`, função ou tabela, igual ao `string.gsub` nativo.

## A ideia central

O parser gera uma árvore (`seq`, `alt`, `rep`, `group`, `class`, ...). O matcher é em *continuation-passing style*: cada nó recebe uma função `k(proxima_posicao, capturas)` que representa "o que precisa casar depois de mim". Se um nó devolve `nil`, esse caminho falhou e quem chamou simplesmente tenta a próxima alternativa. Isso é backtracking, e cabe em umas 30 linhas quando você para de lutar contra a linguagem. Greedy tenta "mais uma iteração" antes de parar, lazy faz o contrário, e uma iteração que não consome nada encerra o loop, senão `(a*)*` roda pra sempre.

Testes: `lua test.lua`.

---

## English

A regular expression engine written from scratch in Lua. No C, no LPeg, no hidden `string.find`: a hand-made parser and a backtracking matcher, in about 400 lines.

I did it because I had been using regex for years without knowing what happened inside. After this, "catastrophic backtracking" stopped being a blog-post phrase and became something I watched happen in my own code, line by line.

| What's there | Syntax |
| --- | --- |
| literals and escapes | `abc`, `\.`, `\n`, `\t` |
| any character | `.` (except line break) |
| anchors | `^`, `$`, `\b`, `\B` |
| classes | `[abc]`, `[a-z]`, `[^0-9]`, `\d \w \s \D \W \S` |
| quantifiers | `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}` and the lazy versions `*?` `+?` `??` |
| groups | `( )` capturing, `(?: )` not |
| backreferences | `\1` up to `\9` |
| alternation | `a\|b` |
| flag | `"i"` to ignore case |

```lua
local Regex = require("regex")
local re = Regex.compile("(\d{4})-(\d{2})-(\d{2})")
re:test("2020-09-22")                     --> true
re:match("due 2020-09-22")                --> "2020", "09", "22"
re:gsub("due 2020-09-22", "%3/%2/%1")     --> "due 22/09/2020", 1
for w in Regex.gmatch("\w+", "one two three") do print(w) end
Regex.split(",\s*", "a, b,c")            --> { "a", "b", "c" }
```

Every function also works "one-shot" with the pattern as the first argument (`Regex.match("\d+", "abc 123")`), and `gsub` accepts a string with `%0`..`%9`, a function or a table, same as the native `string.gsub`.

## The central idea

The parser produces a tree (`seq`, `alt`, `rep`, `group`, `class`, ...). The matcher is in *continuation-passing style*: each node receives a function `k(next_position, captures)` that represents "what needs to match after me". If a node returns `nil`, that path failed and the caller simply tries the next alternative. That is backtracking, and it fits in about 30 lines once you stop fighting the language. Greedy tries "one more iteration" before stopping, lazy does the opposite, and an iteration that consumes nothing ends the loop, otherwise `(a*)*` runs forever.

Tests: `lua test.lua`.

MIT.
