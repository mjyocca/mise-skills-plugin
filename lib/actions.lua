local file = require("file")
local log = require("log")
local package_contract = require("lib.package")
local state = require("lib.state")
local cli = require("lib.cli")

local M = {}

-- Apply and upgrade share pin semantics. update refreshes manager metadata;
-- this manager has no metadata cache and never interprets it as force-repair.
function M.install(ctx)
  local specs = package_contract.parse_batch(ctx.packages)
  local lock = state.read_lock()
  local pending = {}
  for _, spec in ipairs(specs) do
    local entry, present = state.inspect(lock, spec)
    if not present or entry.ref ~= spec.pin then
      pending[#pending + 1] = spec
    end
  end
  if ctx.dry_run then
    for _, spec in ipairs(pending) do
      log.info("Would install globally: " .. spec.name .. "@" .. spec.pin)
    end
    return
  end
  if #pending == 0 then
    return
  end
  cli.check_version()
  for _, group in ipairs(package_contract.group(pending)) do
    -- Recheck immediately before each non-transactional CLI operation.
    lock = state.read_lock()
    for _, spec in ipairs(group.specs) do
      state.inspect(lock, spec)
      log.info("Install globally: " .. spec.name .. "@" .. spec.pin)
    end
    cli.add(group)
    lock = state.read_lock()
    for _, spec in ipairs(group.specs) do
      local entry, present = state.inspect(lock, spec)
      if not present or entry.ref ~= spec.pin then
        error("CLI did not record the requested source/ref and entrypoint for " .. spec.skill)
      end
    end
  end
end

function M.remove(ctx)
  local specs = package_contract.parse_batch(ctx.packages)
  local lock = state.read_lock()
  -- Preflight the entire batch before allowing the first removal.
  local function owned(spec)
    local entry = state.inspect(lock, spec)
    if entry and entry.ref ~= spec.pin then
      error("Different ref in global lock for " .. spec.skill .. "; not removing")
    end
    return entry
  end
  for _, spec in ipairs(specs) do
    owned(spec)
  end
  local checked = false
  for _, spec in ipairs(specs) do
    lock = state.read_lock()
    if owned(spec) then
      if ctx.dry_run then
        log.info("Would remove globally: " .. spec.name)
      else
        if not checked then
          cli.check_version()
          checked = true
        end
        cli.remove(spec)
        lock = state.read_lock()
        if (lock and lock[spec.skill] ~= nil) or file.stat(state.target(spec)) then
          error(
            "CLI did not fully remove "
              .. spec.skill
              .. "; inspect remaining agent usage before retrying"
          )
        end
      end
    end
  end
end

return M
