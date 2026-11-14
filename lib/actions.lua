local file = require("file")
local log = require("log")
local package_contract = require("lib.package")
local state = require("lib.state")
local cli = require("lib.cli")
local git = require("lib.git")

local M = {}

-- Replace each "latest" declaration with the current remote HEAD SHA, sharing
-- one ls-remote per source. Resolution is read-only, so it also runs for dry
-- runs to keep previews accurate; it never invokes the skills CLI.
local function planned(specs)
  local heads, resolved = {}, {}
  for _, spec in ipairs(specs) do
    if spec.kind == "latest" then
      local head = heads[spec.url]
      if head == nil then
        head = git.resolve_head(spec.url)
        heads[spec.url] = head
      end
      spec = package_contract.resolved(spec, head)
    end
    resolved[#resolved + 1] = spec
  end
  return resolved
end

local function label(spec)
  if spec.declared then
    return spec.name .. "@" .. spec.declared .. " (" .. spec.pin .. ")"
  end
  return spec.name .. "@" .. spec.pin
end

-- Apply and upgrade share pin semantics. update refreshes manager metadata;
-- this manager has no metadata cache and never interprets it as force-repair.
function M.install(ctx)
  local specs = planned(package_contract.parse_batch(ctx.packages))
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
      log.info("Would install globally: " .. label(spec))
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
      log.info("Install globally: " .. label(spec))
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
  -- Preflight the entire batch before allowing the first removal. Removals
  -- never resolve "latest"; the install path only records resolved SHAs for
  -- it, so any other recorded ref means ownership changed shape.
  local function owned(spec)
    local entry = state.inspect(lock, spec)
    if entry then
      if spec.kind == "latest" then
        if not package_contract.is_pin(entry.ref) then
          error(
            "Global lock for " .. spec.skill .. " does not hold a resolved commit SHA; not removing"
          )
        end
      elseif entry.ref ~= spec.pin then
        error("Different ref in global lock for " .. spec.skill .. "; not removing")
      end
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
