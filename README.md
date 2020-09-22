# luaregex

A regular expression engine written from scratch in Lua. No C, no LPeg,
no `string.find` tricks: a hand-written parser and a backtracking matcher in
about 400 lines.

I wrote it to understand what actually happens inside a regex engine:
how a pattern becomes a syntax tree, how backtracking works, why lazy and
greedy quantifiers differ, and where catastrophic patterns come from.

## Supported syntax

| Feature | Syntax |
| --- | --- |
| Literals and escapes | `abc`, `\.`, `\n`, `\t` |
| Any character | `.` (does not match newline) |
| Anchors | `^`, `$`, `\b`, `\B` |
| Classes | `[abc]`, `[a-z]`, `[^0-9]`, `\d \w \s \D \W \S` |
| Quantifiers | `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}` |
| Lazy quantifiers | `*?`, `+?`, `??`, `{n,m}?` |
| Groups | `( )` capturing, `(?: )` non-capturing |
| Back-references | `\1` .. `\9` |
| Alternation | `a\|b` |
| Flags | `"i"` case-insensitive |

## API

```lua
local Regex = require("regex")

local re = Regex.compile("(\d{4})-(\d{2})-(\d{2})")
re:test("2020-09-22")                       --> true
re:match("due 2020-09-22")                  --> "2020", "09", "22"
re:find("due 2020-09-22")                   --> 5, 14, "2020", "09", "22"
re:gsub("due 2020-09-22", "%3/%2/%1")       --> "due 22/09/2020", 1

for word in Regex.gmatch("\w+", "one two three") do print(word) end
Regex.split(",\s*", "a, b,c")              --> { "a", "b", "c" }
Regex.compile("hello", "i"):match("HeLLo")  --> "HeLLo"
```

Every method also works as a one-shot function with the pattern as the first
argument: `Regex.match("\d+", "abc 123")`.

`gsub` accepts a string with `%0`..`%9` references, a function receiving the
captures, or a table indexed by the first capture, mirroring Lua's own
`string.gsub`.

## How it works

1. **Parser** (`Parser:parse_alternation` and friends): a recursive-descent
   parser produces an AST of `seq`, `alt`, `rep`, `group`, `class`, `char`,
   `bol`, `eol`, `wordb` and `backref` nodes.
2. **Matcher** (`m`): each node type is matched in continuation-passing
   style. A node receives a function `k(next_index, captures)` describing
   "what has to match after me". Returning `nil` from a node means the
   current path failed, and the caller simply tries its next alternative,
   which is all backtracking is.
3. **Repetition** (`match_rep`): greedy quantifiers try one more iteration
   before trying to stop; lazy ones do the opposite. An iteration that
   consumes nothing ends the loop so `(a*)*` cannot spin forever.
4. **Captures** are stored as `{start, end}` pairs and restored on
   backtracking, so `(a|ab)(c|bcd)(d*)` reports the right groups.

## Tests

```sh
lua test.lua
```

## License

MIT
