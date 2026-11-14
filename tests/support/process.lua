-- POSIX subprocesses: argv (no shell interpolation), clean env, independent
-- stdout/stderr files (no pipe deadlocks), and a monotonic process-group timeout.
local unistd = require("posix.unistd")
local stdlib = require("posix.stdlib")
local fcntl = require("posix.fcntl")
local wait = require("posix.sys.wait")
local signal = require("posix.signal")
local system = require("system")
local fs = require("tests.support.fs")
local M = {}

function M.which(name)
  if name:sub(1, 1) == "/" then
    return unistd.access(name, "x") and name or nil
  end
  for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
    local path = dir .. "/" .. name
    if unistd.access(path, "x") then
      return assert(stdlib.realpath(path))
    end
  end
end

function M.tempdir()
  local base = os.getenv("TMPDIR") or "/tmp"
  return assert(stdlib.realpath(assert(stdlib.mkdtemp(base .. "/mise-skills-test-XXXXXX"))))
end

function M.run(argv, options)
  options = options or {}
  local capture = M.tempdir()
  local output = assert(fcntl.open(capture .. "/stdout", fcntl.O_WRONLY + fcntl.O_CREAT, 384))
  local errors = assert(fcntl.open(capture .. "/stderr", fcntl.O_WRONLY + fcntl.O_CREAT, 384))
  local pid, fork_error = unistd.fork()
  if pid == nil then
    unistd.close(output)
    unistd.close(errors)
    fs.remove(capture, capture)
    error(fork_error)
  end
  if pid == 0 then
    local ok, message = pcall(function()
      assert(unistd.setpid("p", 0, 0))
      assert(unistd.dup2(output, 1))
      assert(unistd.dup2(errors, 2))
      unistd.close(output)
      unistd.close(errors)
      local input = assert(fcntl.open("/dev/null", fcntl.O_RDONLY))
      assert(unistd.dup2(input, 0))
      unistd.close(input)
      if options.cwd then
        assert(unistd.chdir(options.cwd))
      end
      if options.env then
        for key in pairs(stdlib.getenv()) do
          assert(stdlib.setenv(key, nil))
        end
        for key, value in pairs(options.env) do
          assert(stdlib.setenv(key, value))
        end
      end
      local args = {}
      for i = 2, #argv do
        args[#args + 1] = argv[i]
      end
      local _, err = unistd.execp(argv[1], args)
      error(err)
    end)
    if not ok then
      unistd.write(2, tostring(message) .. "\n")
    end
    unistd._exit(127)
  end
  unistd.close(output)
  unistd.close(errors)
  local deadline = system.monotime() + (options.timeout or 30)
  local reason, status, timed_out
  while true do
    local finished
    finished, reason, status = wait.wait(pid, wait.WNOHANG)
    if finished == pid then
      break
    end
    assert(finished ~= nil, reason)
    if system.monotime() >= deadline then
      timed_out = true
      -- Negative PID targets the child's process group, including CLI children.
      signal.kill(-pid, signal.SIGKILL)
      signal.kill(pid, signal.SIGKILL)
      finished, reason, status = wait.wait(pid)
      assert(finished == pid, reason)
      break
    end
    system.sleep(0.01)
  end
  local result = {
    stdout = fs.read(capture .. "/stdout"),
    stderr = fs.read(capture .. "/stderr"),
    code = reason == "exited" and status or 128 + (status or 0),
    timed_out = timed_out or false,
  }
  fs.remove(capture, capture)
  return result
end

return M
