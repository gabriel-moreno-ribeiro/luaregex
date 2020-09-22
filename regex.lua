--- regex.lua - a regular expression engine written from scratch in Lua.
--
-- Two stages:
--   1. parse(pattern)  -> AST (sequence / alternation / repetition / group / class ...)
--   2. match(ast, s)   -> backtracking matcher written in continuation-passing
--                         style: every node receives "what to do next" as a
--                         function, so backtracking falls out of plain returns.
--
-- Supported syntax:
--   literals, .  ^  $  \b \B  \d \w \s \D \W \S  \n \t  escaped metachars
--   [abc] [a-z] [^...] with escapes and \d \w \s inside classes
--   * + ? {n} {n,} {n,m} and lazy variants *? +? ?? {n,m}?
--   ( ... ) capturing, (?: ... ) non-capturing, \1..\9 back-references
--   a|b alternation
-- Flags: "i" (ignore case)

local Regex = {}
Regex.__index = Regex

------------------------------------------------------------------------------
-- Character sets
------------------------------------------------------------------------------

local function is_digit(c) return c >= "0" and c <= "9" end
local function is_word(c) return c:match("^[%w_]$") ~= nil end
local function is_space(c) return c:match("^%s$") ~= nil end

local CLASS_ESCAPES = {
  d = is_digit, w = is_word, s = is_space,
  D = function(c) return not is_digit(c) end,
  W = function(c) return not is_word(c) end,
  S = function(c) return not is_space(c) end,
}

local CHAR_ESCAPES = { n = "\n", t = "\t", r = "\r", f = "\f", v = "\v", ["0"] = "\0" }

------------------------------------------------------------------------------
-- Parser: pattern string -> AST
------------------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local function parse_error(msg, pos)
  error(("regex: %s at position %d"):format(msg, pos), 0)
end

function Parser.new(pattern)
  return setmetatable({ src = pattern, pos = 1, ngroups = 0 }, Parser)
end

function Parser:peek(offset)
  local p = self.pos + (offset or 0)
  return self.src:sub(p, p)
end

function Parser:next()
  local c = self:peek()
  self.pos = self.pos + 1
  return c
end

function Parser:eof() return self.pos > #self.src end

-- alternation := sequence ('|' sequence)*
function Parser:parse_alternation()
  local alts = { self:parse_sequence() }
  while self:peek() == "|" do
    self:next()
    alts[#alts + 1] = self:parse_sequence()
  end
  if #alts == 1 then return alts[1] end
  return { type = "alt", alts = alts }
end

-- sequence := (atom quantifier?)*
function Parser:parse_sequence()
  local items = {}
  while not self:eof() and self:peek() ~= "|" and self:peek() ~= ")" do
    local atom = self:parse_atom()
    atom = self:parse_quantifier(atom)
    items[#items + 1] = atom
  end
  return { type = "seq", items = items }
end

function Parser:parse_quantifier(atom)
  local c = self:peek()
  local min, max
  if c == "*" then min, max = 0, math.huge
  elseif c == "+" then min, max = 1, math.huge
  elseif c == "?" then min, max = 0, 1
  elseif c == "{" then
    local body, close = self.src:match("^{([%d,]*)}()", self.pos)
    if not body then return atom end
    local a, comma, b = body:match("^(%d*)(,?)(%d*)$")
    if not a or (a == "" and b == "") then return atom end
    min = tonumber(a) or 0
    if comma == "" then max = min else max = tonumber(b) or math.huge end
    if max < min then parse_error("invalid range in quantifier", self.pos) end
    self.pos = close - 1
  else
    return atom
  end
  local start = self.pos
  self:next()
  if atom.type == "bol" or atom.type == "eol" or atom.type == "wordb" or atom.type == "nwordb" then
    parse_error("nothing to repeat", start)
  end
  local lazy = false
  if self:peek() == "?" then self:next(); lazy = true end
  return { type = "rep", node = atom, min = min, max = max, lazy = lazy }
end

function Parser:parse_atom()
  local start = self.pos
  local c = self:next()
  if c == "(" then
    local capture = true
    if self:peek() == "?" and self:peek(1) == ":" then
      self.pos = self.pos + 2
      capture = false
    end
    local index
    if capture then
      self.ngroups = self.ngroups + 1
      index = self.ngroups
    end
    local inner = self:parse_alternation()
    if self:next() ~= ")" then parse_error("missing )", start) end
    return { type = "group", node = inner, index = index }
  elseif c == "[" then
    return self:parse_class(start)
  elseif c == "." then return { type = "any" }
  elseif c == "^" then return { type = "bol" }
  elseif c == "$" then return { type = "eol" }
  elseif c == "\\" then
    if self:eof() then parse_error("trailing backslash", start) end
    local e = self:next()
    if e == "b" then return { type = "wordb" } end
    if e == "B" then return { type = "nwordb" } end
    if CLASS_ESCAPES[e] then return { type = "class", test = CLASS_ESCAPES[e] } end
    if CHAR_ESCAPES[e] then return { type = "char", c = CHAR_ESCAPES[e] } end
    if e:match("%d") and e ~= "0" then return { type = "backref", n = tonumber(e) } end
    return { type = "char", c = e }
  elseif c == "*" or c == "+" or c == "?" then
    parse_error("nothing to repeat", start)
  elseif c == ")" then
    parse_error("unmatched )", start)
  end
  return { type = "char", c = c }
end

-- [...] character class
function Parser:parse_class(start)
  local negate = false
  if self:peek() == "^" then self:next(); negate = true end
  local ranges, tests, chars = {}, {}, {}
  local first = true
  while true do
    if self:eof() then parse_error("missing ]", start) end
    local c = self:next()
    if c == "]" and not first then break end
    first = false
    if c == "\\" then
      local e = self:next()
      if CLASS_ESCAPES[e] then
        tests[#tests + 1] = CLASS_ESCAPES[e]
        goto continue
      end
      c = CHAR_ESCAPES[e] or e
    end
    if self:peek() == "-" and self:peek(1) ~= "]" and self:peek(1) ~= "" then
      self:next()
      local hi = self:next()
      if hi == "\\" then local e = self:next(); hi = CHAR_ESCAPES[e] or e end
      if hi < c then parse_error("invalid class range", start) end
      ranges[#ranges + 1] = { c, hi }
    else
      chars[c] = true
    end
    ::continue::
  end
  local function test(ch)
    if chars[ch] then return true end
    for _, r in ipairs(ranges) do
      if ch >= r[1] and ch <= r[2] then return true end
    end
    for _, t in ipairs(tests) do
      if t(ch) then return true end
    end
    return false
  end
  if negate then
    return { type = "class", test = function(ch) return not test(ch) end }
  end
  return { type = "class", test = test }
end

local function parse(pattern)
  local p = Parser.new(pattern)
  local ast = p:parse_alternation()
  if not p:eof() then parse_error("unmatched )", p.pos) end
  return ast, p.ngroups
end

------------------------------------------------------------------------------
-- Matcher (continuation-passing backtracking)
--   m(node, s, i, caps, k) tries to match `node` at index i and, on success,
--   calls k(j, caps) with the index just after the match. Returning nil means
--   "failed, try something else".
------------------------------------------------------------------------------

local m -- forward declaration

local function match_seq(items, idx, s, i, caps, k, ctx)
  if idx > #items then return k(i, caps) end
  return m(items[idx], s, i, caps, function(j, c)
    return match_seq(items, idx + 1, s, j, c, k, ctx)
  end, ctx)
end

local function match_rep(node, s, i, caps, k, ctx)
  local inner, min, max, lazy = node.node, node.min, node.max, node.lazy
  local function try(count, pos, c)
    local function more()
      if count >= max then return nil end
      return m(inner, s, pos, c, function(j, c2)
        if j == pos and count >= min then return nil end -- empty iteration: stop looping
        return try(count + 1, j, c2)
      end, ctx)
    end
    local function stop()
      if count < min then return nil end
      return k(pos, c)
    end
    if lazy then
      return stop() or more()
    else
      return more() or stop()
    end
  end
  return try(0, i, caps)
end

local function chars_equal(a, b, ctx)
  if ctx.icase then return a:lower() == b:lower() end
  return a == b
end

local function at_word_boundary(s, i)
  local before = i > 1 and is_word(s:sub(i - 1, i - 1))
  local after = i <= #s and is_word(s:sub(i, i))
  return before ~= after
end

m = function(node, s, i, caps, k, ctx)
  local t = node.type
  if t == "char" then
    if i <= #s and chars_equal(s:sub(i, i), node.c, ctx) then return k(i + 1, caps) end
    return nil
  elseif t == "any" then
    if i <= #s and s:sub(i, i) ~= "\n" then return k(i + 1, caps) end
    return nil
  elseif t == "class" then
    if i > #s then return nil end
    local ch = s:sub(i, i)
    if node.test(ch) or (ctx.icase and (node.test(ch:lower()) or node.test(ch:upper()))) then
      return k(i + 1, caps)
    end
    return nil
  elseif t == "seq" then
    return match_seq(node.items, 1, s, i, caps, k, ctx)
  elseif t == "alt" then
    for _, alt in ipairs(node.alts) do
      local r = m(alt, s, i, caps, k, ctx)
      if r then return r end
    end
    return nil
  elseif t == "rep" then
    return match_rep(node, s, i, caps, k, ctx)
  elseif t == "group" then
    if not node.index then return m(node.node, s, i, caps, k, ctx) end
    local idx = node.index
    return m(node.node, s, i, caps, function(j, c)
      local saved = c[idx]
      c[idx] = { i, j - 1 }
      local r = k(j, c)
      if r == nil then c[idx] = saved end
      return r
    end, ctx)
  elseif t == "backref" then
    local cap = caps[node.n]
    if not cap then return nil end
    local text = s:sub(cap[1], cap[2])
    local candidate = s:sub(i, i + #text - 1)
    if #candidate == #text and chars_equal(candidate, text, ctx) then return k(i + #text, caps) end
    return nil
  elseif t == "bol" then
    if i == 1 then return k(i, caps) end
    return nil
  elseif t == "eol" then
    if i == #s + 1 then return k(i, caps) end
    return nil
  elseif t == "wordb" then
    if at_word_boundary(s, i) then return k(i, caps) end
    return nil
  elseif t == "nwordb" then
    if not at_word_boundary(s, i) then return k(i, caps) end
    return nil
  end
  error("regex: unknown node " .. tostring(t))
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

--- Compile a pattern. flags: "i" for case-insensitive matching.
function Regex.compile(pattern, flags)
  if type(pattern) ~= "string" then error("regex: pattern must be a string", 2) end
  local ast, ngroups = parse(pattern)
  local self = setmetatable({
    source = pattern,
    ast = ast,
    ngroups = ngroups,
    ctx = { icase = (flags or ""):find("i", 1, true) ~= nil },
  }, Regex)
  return self
end

-- Try to match starting exactly at position i. Returns end index and captures.
function Regex:match_at(s, i)
  local caps = {}
  local finish = m(self.ast, s, i, caps, function(j, c)
    return j
  end, self.ctx)
  if finish then return finish, caps end
  return nil
end

local function capture_values(s, caps, n)
  local out = {}
  for g = 1, n do
    local c = caps[g]
    out[g] = c and s:sub(c[1], c[2]) or false
  end
  return out
end

--- Like string.find: returns start, end, captures... or nil.
function Regex:find(s, init)
  init = init or 1
  if init < 0 then init = #s + init + 1 end
  if init < 1 then init = 1 end
  for i = init, #s + 1 do
    local finish, caps = self:match_at(s, i)
    if finish then
      return i, finish - 1, table.unpack(capture_values(s, caps, self.ngroups))
    end
    if self.ast.type == "seq" and self.ast.items[1] and self.ast.items[1].type == "bol" then break end
  end
  return nil
end

--- Like string.match: returns captures, or the whole match when there are none.
function Regex:match(s, init)
  local results = { self:find(s, init) }
  if results[1] == nil then return nil end
  if self.ngroups == 0 then return s:sub(results[1], results[2]) end
  return table.unpack(results, 3, 2 + self.ngroups)
end

--- Boolean test.
function Regex:test(s)
  return self:find(s) ~= nil
end

--- Iterator over all non-overlapping matches (like string.gmatch).
function Regex:gmatch(s)
  local pos = 1
  return function()
    if pos > #s + 1 then return nil end
    local results = { self:find(s, pos) }
    if results[1] == nil then pos = #s + 2; return nil end
    local start, finish = results[1], results[2]
    pos = finish >= start and finish + 1 or start + 1
    if self.ngroups == 0 then return s:sub(start, finish) end
    return table.unpack(results, 3, 2 + self.ngroups)
  end
end

--- Replace matches. repl may be a string with %0..%9 references, a function
--- receiving the captures (or whole match), or a table keyed by first capture.
function Regex:gsub(s, repl, max_n)
  local out, count, pos = {}, 0, 1
  while pos <= #s + 1 do
    if max_n and count >= max_n then break end
    local results = { self:find(s, pos) }
    if results[1] == nil then break end
    local start, finish = results[1], results[2]
    local whole = s:sub(start, finish)
    local caps = { table.unpack(results, 3, 2 + self.ngroups) }
    out[#out + 1] = s:sub(pos, start - 1)
    local replacement
    if type(repl) == "string" then
      replacement = repl:gsub("%%(%d)", function(d)
        d = tonumber(d)
        if d == 0 then return whole end
        return caps[d] or ""
      end)
    elseif type(repl) == "function" then
      if self.ngroups == 0 then replacement = repl(whole) else replacement = repl(table.unpack(caps, 1, self.ngroups)) end
    elseif type(repl) == "table" then
      replacement = repl[self.ngroups == 0 and whole or caps[1]]
    end
    if replacement == nil or replacement == false then replacement = whole end
    out[#out + 1] = tostring(replacement)
    count = count + 1
    if finish >= start then
      pos = finish + 1
    else
      -- empty match: copy one char and move on to avoid looping forever
      out[#out + 1] = s:sub(start, start)
      pos = start + 1
    end
  end
  out[#out + 1] = s:sub(pos)
  return table.concat(out), count
end

--- Split a string by the pattern.
function Regex:split(s, limit)
  local parts, pos = {}, 1
  while true do
    if limit and #parts >= limit - 1 then break end
    local start, finish = self:find(s, pos)
    if not start or finish < start then break end
    parts[#parts + 1] = s:sub(pos, start - 1)
    pos = finish + 1
  end
  parts[#parts + 1] = s:sub(pos)
  return parts
end

-- Convenience one-shot helpers: Regex.find(pattern, s) etc.
for _, name in ipairs({ "find", "match", "test", "gmatch", "gsub", "split" }) do
  local method = Regex[name]
  Regex[name] = function(self_or_pattern, ...)
    if type(self_or_pattern) == "string" then
      return method(Regex.compile(self_or_pattern), ...)
    end
    return method(self_or_pattern, ...)
  end
end

return Regex
