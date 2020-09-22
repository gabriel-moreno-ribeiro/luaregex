-- Test suite for regex.lua. Run with: lua test.lua
package.path = "./?.lua;" .. package.path
local Regex = require("regex")

local passed, failed = 0, 0

local function check(name, cond)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. name)
  end
end

local function eq(name, got, want)
  check(name .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")", got == want)
end

local function list_eq(name, got, want)
  local ok = #got == #want
  if ok then for i = 1, #got do if got[i] ~= want[i] then ok = false end end end
  check(name .. " (got {" .. table.concat(got, ",") .. "})", ok)
end

-- literals and anchors
eq("literal", Regex.match("abc", "xxabcxx"), "abc")
eq("no match", Regex.match("abd", "xxabcxx"), nil)
eq("bol", Regex.match("^ab", "abab"), "ab")
eq("bol fails mid string", Regex.match("^b", "ab"), nil)
eq("eol", Regex.match("ab$", "abab"), "ab")
eq("eol fails", Regex.match("a$", "ab"), nil)
eq("bol+eol whole string", Regex.test("^abc$", "abc"), true)
eq("bol+eol partial", Regex.test("^abc$", "abcd"), false)

-- dot and classes
eq("dot", Regex.match("a.c", "abc"), "abc")
eq("dot no newline", Regex.match("a.c", "a\nc"), nil)
eq("class", Regex.match("[abc]+", "xxbcaxx"), "bca")
eq("range", Regex.match("[a-c]+", "xxbcaxx"), "bca")
eq("negated class", Regex.match("[^a-z]+", "abc123def"), "123")
eq("class with escape", Regex.match("[\\d.]+", "v1.2.3"), "1.2.3")
eq("class literal ]", Regex.match("[]a]+", "]a]b"), "]a]")
eq("class literal -", Regex.match("[a-]+", "a-a-b"), "a-a-")
eq("\\d", Regex.match("\\d+", "abc 123 def"), "123")
eq("\\w", Regex.match("\\w+", "  hello_1 "), "hello_1")
eq("\\s", Regex.match("a\\s+b", "a   b"), "a   b")
eq("\\D", Regex.match("\\D+", "12ab34"), "ab")
eq("\\W", Regex.match("\\W+", "ab, cd"), ", ")
eq("\\S", Regex.match("\\S+", "  xy z"), "xy")
eq("escaped metachar", Regex.match("a\\.b", "a.b axb"), "a.b")
eq("escaped metachar 2", Regex.match("\\(\\d+\\)", "f(12)"), "(12)")
eq("\\n", Regex.match("a\\nb", "a\nb"), "a\nb")
eq("\\t", Regex.match("\\t", "a\tb"), "\t")

-- quantifiers
eq("star", Regex.match("ab*c", "ac"), "ac")
eq("star many", Regex.match("ab*c", "abbbc"), "abbbc")
eq("plus", Regex.match("ab+c", "ac"), nil)
eq("plus many", Regex.match("ab+c", "abbc"), "abbc")
eq("question", Regex.match("colou?r", "color"), "color")
eq("question 2", Regex.match("colou?r", "colour"), "colour")
eq("exact count", Regex.match("a{3}", "aaaa"), "aaa")
eq("exact count fails", Regex.match("a{3}", "aa"), nil)
eq("min count", Regex.match("a{2,}", "aaaa"), "aaaa")
eq("range count", Regex.match("a{2,3}", "aaaa"), "aaa")
eq("brace literal", Regex.match("a{x}", "a{x}"), "a{x}")
eq("greedy", Regex.match("<.+>", "<a><b>"), "<a><b>")
eq("lazy", Regex.match("<.+?>", "<a><b>"), "<a>")
eq("lazy star", Regex.match("a.*?b", "aXbYb"), "aXb")
eq("lazy question", Regex.match("ab??", "ab"), "a")
eq("lazy range", Regex.match("a{2,3}?", "aaaa"), "aa")
eq("nested repetition", Regex.match("(?:ab)+", "ababab"), "ababab")
eq("group in repetition keeps last capture", Regex.match("(ab)+", "ababab"), "ab")
eq("empty loop terminates", Regex.match("(?:a*)*b", "aab"), "aab")
eq("empty loop terminates 2", Regex.test("(a*)*$", "bbb"), true)
eq("backtracking", Regex.match("a.*b", "axxbyyb"), "axxbyyb")
eq("backtracking 2", Regex.match("(a|ab)(c|bcd)(d*)", "abcd"), "a")

-- groups and alternation
eq("alternation", Regex.match("cat|dog", "hotdog"), "dog")
eq("alternation first wins", Regex.match("a|ab", "ab"), "a")
eq("group capture", Regex.match("(\\d+)-(\\d+)", "tel 555-1234"), "555")
local a, b = Regex.match("(\\d+)-(\\d+)", "tel 555-1234")
eq("group capture 2", b, "1234")
eq("non-capturing", Regex.match("(?:ab)+(c)", "ababc"), "c")
eq("nested groups", select(2, Regex.match("((a)b)", "ab")), "a")
eq("optional group unmatched is false", select(2, Regex.match("(a)(b)?", "a")), false)
eq("group in alternation", Regex.match("(x|y)z", "yz"), "y")
eq("backreference", Regex.match("(\\w)\\1", "abccd"), "c")
eq("backreference word", Regex.match("\\b(\\w+) \\1\\b", "the the cat"), "the")
eq("backreference fails", Regex.match("(a)\\1", "ab"), nil)

-- word boundaries
eq("word boundary", Regex.match("\\bcat\\b", "concat cat"), "cat")
local s, e = Regex.find("\\bcat\\b", "concat cat")
eq("word boundary position", s, 8)
eq("non word boundary", Regex.match("\\Bcat", "concat cat"), "cat")
eq("non word boundary pos", (Regex.find("\\Bcat", "concat cat")), 4)

-- flags
eq("case insensitive", Regex.compile("hello", "i"):match("Say HeLLo"), "HeLLo")
eq("case insensitive class", Regex.compile("[a-z]+", "i"):match("ABC"), "ABC")
eq("case sensitive default", Regex.match("hello", "HELLO"), nil)

-- find / init
s, e = Regex.find("b+", "aabbbcc")
eq("find start", s, 3)
eq("find end", e, 5)
eq("find with init", (Regex.find("a", "abca", 2)), 4)
eq("find negative init", (Regex.find("a", "abca", -1)), 4)
eq("find empty match", (Regex.find("x*", "abc")), 1)
eq("find empty match end", select(2, Regex.find("x*", "abc")), 0)

-- gmatch
local words = {}
for w in Regex.gmatch("\\w+", "one two  three") do words[#words + 1] = w end
list_eq("gmatch words", words, { "one", "two", "three" })
local pairs_ = {}
for k, v in Regex.gmatch("(\\w+)=(\\d+)", "a=1, b=22") do pairs_[#pairs_ + 1] = k .. ":" .. v end
list_eq("gmatch captures", pairs_, { "a:1", "b:22" })
local empties = {}
for w in Regex.gmatch("a*", "baa") do empties[#empties + 1] = w end
list_eq("gmatch empty matches", empties, { "", "aa", "" })

-- gsub
eq("gsub string", (Regex.gsub("\\d+", "a1b22c333", "#")), "a#b#c#")
eq("gsub count", select(2, Regex.gsub("\\d+", "a1b22c333", "#")), 3)
eq("gsub backrefs", (Regex.gsub("(\\w+)@(\\w+)", "me@host you@there", "%2/%1")), "host/me there/you")
eq("gsub whole match", (Regex.gsub("\\d", "a1b2", "<%0>")), "a<1>b<2>")
eq("gsub function", (Regex.gsub("\\d+", "a1b22", function(n) return tostring(tonumber(n) * 2) end)), "a2b44")
eq("gsub table", (Regex.gsub("\\$(\\w+)", "$name is $age", { name = "Bo", age = 7 })), "Bo is 7")
eq("gsub table missing keeps", (Regex.gsub("\\$(\\w+)", "$x", {})), "$x")
eq("gsub max", (Regex.gsub("a", "aaa", "b", 2)), "bba")
eq("gsub empty pattern", (Regex.gsub("x*", "abc", "-")), "-a-b-c-")

-- split
list_eq("split", Regex.split(",\\s*", "a, b,c ,d"), { "a", "b", "c ", "d" })
list_eq("split limit", Regex.split(",", "a,b,c", 2), { "a", "b,c" })
list_eq("split no match", Regex.split(";", "abc"), { "abc" })

-- real-world patterns
local email = Regex.compile("^[\\w.+-]+@[\\w-]+(\\.[\\w-]+)+$")
eq("email ok", email:test("first.last+tag@mail.example.co"), true)
eq("email bad", email:test("not an email"), false)
local ipv4 = Regex.compile("^(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})$")
local o1, o2, o3, o4 = ipv4:match("192.168.0.1")
eq("ipv4 octets", o1 .. o2 .. o3 .. o4, "19216801")
local date = Regex.compile("(\\d{4})-(\\d{2})-(\\d{2})")
eq("date rewrite", (date:gsub("due 2020-09-22 and 2021-01-31", "%3/%2/%1")), "due 22/09/2020 and 31/01/2021")
local hex = Regex.compile("#([0-9a-f]{6}|[0-9a-f]{3})\\b", "i")
eq("hex color", hex:match("color: #FFaa00;"), "FFaa00")

-- errors
local function fails(name, pat)
  local ok, err = pcall(Regex.compile, pat)
  check(name, not ok and err:find("regex:") ~= nil)
end
fails("unbalanced (", "(abc")
fails("unbalanced )", "abc)")
fails("missing ]", "[abc")
fails("nothing to repeat", "*a")
fails("bad range", "[z-a]")
fails("bad quantifier range", "a{3,1}")
fails("trailing backslash", "abc\\")

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
