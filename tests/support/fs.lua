-- Real filesystem helpers for disposable fixtures; never use production adapters.
local lfs = require("lfs")
local M = {}

function M.exists(path)
  return lfs.symlinkattributes(path) ~= nil
end

function M.mkdir(path)
  if lfs.attributes(path, "mode") == "directory" then
    return
  end
  local parent = path:match("^(.*)/[^/]+$")
  if parent and parent ~= "" then
    M.mkdir(parent)
  end
  assert(lfs.mkdir(path))
end

function M.read(path)
  local handle = assert(io.open(path, "rb"))
  local content = assert(handle:read("*a"))
  assert(handle:close())
  return content
end

function M.write(path, content, mode)
  M.mkdir(assert(path:match("^(.*)/[^/]+$")))
  local handle = assert(io.open(path, mode or "wb"))
  assert(handle:write(content))
  assert(handle:close())
end

function M.copy(source, target)
  local mode = assert(lfs.symlinkattributes(source, "mode"))
  if mode == "directory" then
    M.mkdir(target)
    for name in lfs.dir(source) do
      if name ~= "." and name ~= ".." then
        M.copy(source .. "/" .. name, target .. "/" .. name)
      end
    end
  else
    assert(mode == "file", "Refusing to copy a symlink or special file: " .. source)
    M.write(target, M.read(source))
  end
end

-- Every caller must supply its disposable root. Check ancestors before walking,
-- and unlink symlinks themselves, including broken ones, rather than following.
function M.remove(path, root)
  assert(root:sub(1, 1) == "/" and root ~= "/", "Expected a disposable absolute root")
  for _, value in ipairs({ root, path }) do
    for segment in value:gmatch("[^/]+") do
      assert(segment ~= "." and segment ~= "..", "Dot segments are unsafe for cleanup")
    end
  end
  assert(path == root or path:sub(1, #root + 1) == root .. "/", "Cleanup outside fixture")
  local ancestor = path:match("^(.*)/[^/]+$")
  while ancestor and ancestor ~= "" do
    assert(lfs.symlinkattributes(ancestor, "mode") ~= "link", "Symlinked cleanup ancestor")
    ancestor = ancestor:match("^(.*)/[^/]+$")
  end
  local function remove(current)
    local mode = lfs.symlinkattributes(current, "mode")
    if mode == "directory" then
      for name in lfs.dir(current) do
        if name ~= "." and name ~= ".." then
          remove(current .. "/" .. name)
        end
      end
      assert(lfs.rmdir(current))
    elseif mode then
      assert(os.remove(current))
    end
  end
  remove(path)
end

return M
