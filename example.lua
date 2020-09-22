-- Small tour of the API. Run with: lua example.lua
package.path = "./?.lua;" .. package.path
local Regex = require("regex")

local date = Regex.compile("(\\d{4})-(\\d{2})-(\\d{2})")
print(date:test("2020-09-22"))                          --> true
print(date:match("due 2020-09-22"))                     --> 2020  09  22
print(date:gsub("due 2020-09-22", "%3/%2/%1"))          --> due 22/09/2020  1

for word in Regex.gmatch("\\w+", "one two three") do
  io.write(word, "|")                                   --> one|two|three|
end
print()

print(table.concat(Regex.split(",\\s*", "a, b,c"), "/"))  --> a/b/c
print(Regex.compile("hello", "i"):match("Say HeLLo"))   --> HeLLo
print(Regex.gsub("(\\w+)@(\\w+)", "me@host", "%2/%1"))  --> host/me  1
