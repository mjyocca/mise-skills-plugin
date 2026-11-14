-- Independent fake git for offline fixtures. Answers only `ls-remote <url> HEAD`;
-- the shim script forwards every other subcommand to the real git executable.
local json = require("dkjson")
local fs = require("tests.support.fs")

assert(arg[1] == "ls-remote", "fake git only supports ls-remote")
assert(arg[3] == "HEAD", "fake git expects: ls-remote <url> HEAD")
assert(os.getenv("GIT_TERMINAL_PROMPT") == "0")

local home = assert(os.getenv("HOME"))
local arguments = setmetatable({}, { __jsontype = "array" })
for i = 1, #arg do
  arguments[i] = arg[i]
end
fs.write(home .. "/git-calls.jsonl", json.encode(arguments) .. "\n", "ab")

if os.getenv("SKILLS_TEST_GIT_FAIL") then
  io.stderr:write("fixture git resolution failed\n")
  os.exit(1)
end
print((os.getenv("SKILLS_TEST_HEAD") or string.rep("c", 40)) .. "\tHEAD")
