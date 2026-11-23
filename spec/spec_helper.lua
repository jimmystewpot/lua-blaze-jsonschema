local function dirname(path)
  return (path:gsub("[/\\][^/\\]+$", ""))
end

local function this_file_dir()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return dirname(source)
end

local root = dirname(this_file_dir())
local is_windows = package.config:sub(1, 1) == "\\"
local ext = is_windows and "dll" or "so"

local function append_cpath(path)
  if not path or path == "" then
    return
  end
  local entry = path .. "/?." .. ext
  if (";" .. package.cpath .. ";"):find(";" .. entry .. ";", 1, true) then
    return
  end
  if package.cpath == "" then
    package.cpath = entry
  elseif package.cpath:sub(-1) == ";" then
    package.cpath = package.cpath .. entry
  else
    package.cpath = package.cpath .. ";" .. entry
  end
end

local env_cpath = os.getenv("LUABLAZE_CPATH")
if env_cpath and env_cpath ~= "" then
  if package.cpath == "" then
    package.cpath = env_cpath
  elseif env_cpath:sub(-1) == ";" then
    package.cpath = env_cpath .. package.cpath
  else
    package.cpath = env_cpath .. ";" .. package.cpath
  end
end

append_cpath(root .. "/build")
append_cpath(root .. "/build/Release")
append_cpath(root .. "/build/Debug")
append_cpath(root .. "/lua_install")
append_cpath(root .. "/lua_install/lib")


