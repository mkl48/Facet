-- Generates dist/install.luau: a single, self-contained script that recreates the entire
-- Facet module tree (folders + ModuleScripts with embedded source) under ReplicatedStorage
-- when pasted into the Roblox Studio command bar. The real .luau files in src/ are the ONE
-- source of truth - run `lune run scripts/build-installer` to refresh.
--
-- Mapping: src/init.luau -> ModuleScript "Facet"; src/X.luau -> child ModuleScript "X";
-- src/Y/init.luau -> child ModuleScript "Y" (with its own children); src/Z.server.luau -> child
-- Script "Z" (Enabled = false - see below); src/Z.client.luau -> child LocalScript "Z"; a
-- folder without an init.luau becomes a Folder. Source is embedded as a long-bracket string
-- with a safe `=` level (see longString below), so it reads verbatim and takes no escapes.
--
-- Script/LocalScript children are created Enabled = false: most of them (e.g. Workers' worker
-- templates) are only ever meant to run after being cloned into a purpose-built Actor at
-- runtime, not as-installed. Worker.server.luau specifically gets bundled twice - "Worker"
-- (RunContext = Server) and "WorkerClient" (RunContext = Client) - since RunContext can't be
-- set from a live game script later (Studio/Plugin-only capability); see Workers/init.luau.

local fs = require("@lune/fs")

local SRC = "src"
local OUT_DIR = "dist"
local OUT = OUT_DIR .. "/install.luau"
local BOOT = OUT_DIR .. "/bootstrap.luau"
-- Raw URL the bootstrap fetches the full installer from. Adjust the branch if needed.
local RAW_URL = "https://raw.githubusercontent.com/mkl48/Facet/master/dist/install.luau"

local body: { string } = {}
local function emit(line: string)
	table.insert(body, line)
end

local counter = 0
local function nextVar(): string
	counter += 1
	return "_" .. counter
end

-- A short Luau string literal for a simple value (module names).
local function q(s: string): string
	return string.format("%q", s)
end

-- Embed arbitrary Luau source as a long-bracket string [==[ ... ]==], picking an `=` level
-- whose closing bracket doesn't occur in the source. Long strings take NO escapes, so the
-- code is embedded verbatim and reads cleanly - the right tool for porting source. A
-- leading newline is added (Luau strips exactly one after the open bracket) so source that
-- begins with `[` or a newline survives intact.
local function longString(s: string): string
	local level = 0
	while string.find(s, `]{string.rep("=", level)}]`, 1, true) do
		level += 1
	end
	local eq = string.rep("=", level)
	return `[{eq}[\n{s}]{eq}]`
end

local function isDir(path: string): boolean
	local ok = pcall(fs.readDir, path)
	return ok
end

local function exists(path: string): boolean
	local ok = pcall(fs.readFile, path)
	return ok
end

local moduleCount = 0
local folderCount = 0

-- A module folder is one with an init.lua / init.luau (vendored deps use .lua).
local function moduleInit(dir: string): string?
	for _, name in { "init.luau", "init.lua" } do
		local path = dir .. "/" .. name
		if exists(path) then
			return path
		end
	end
	return nil
end

-- A bundlable source file: *.lua / *.luau, excluding init and demo/test scripts.
local function isSourceFile(entry: string): boolean
	if entry == "init.lua" or entry == "init.luau" then
		return false
	end
	if string.find(entry, "%.spec%.") or string.find(entry, "%.story%.") then
		return false
	end
	return string.match(entry, "%.luau?$") ~= nil
end

-- "X.server.luau" -> Script, "X.client.luau" -> LocalScript, anything else -> ModuleScript.
local function classNameFor(entry: string): string
	if string.find(entry, "%.server%.") then
		return "Script"
	elseif string.find(entry, "%.client%.") then
		return "LocalScript"
	end
	return "ModuleScript"
end

-- Strips both the realm suffix (.server/.client) and the extension: "Worker.server.luau" -> "Worker".
local function childNameFor(entry: string): string
	local name = string.gsub(entry, "%.luau?$", "")
	name = string.gsub(name, "%.server$", "")
	name = string.gsub(name, "%.client$", "")
	return name
end

-- Emit the creation of `dir` as a node parented to `parentVar`, then recurse. Returns the
-- local variable name bound to the created instance (so children can parent to it).
local function build(dir: string, parentVar: string, name: string): string
	local var = nextVar()
	local init = moduleInit(dir)

	if init then
		moduleCount += 1
		emit(`local {var} = mod({q(name)}, {parentVar}, {longString(fs.readFile(init))})`)
	else
		folderCount += 1
		emit(`local {var} = folder({q(name)}, {parentVar})`)
	end

	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if isDir(path) then
			build(path, var, entry)
		elseif isSourceFile(entry) then
			moduleCount += 1
			local childName = childNameFor(entry)
			local className = classNameFor(entry)
			if className == "ModuleScript" then
				emit(`mod({q(childName)}, {var}, {longString(fs.readFile(path))})`)
			elseif childName == "Worker" and entry == "Worker.server.luau" then
				-- RunContext can only be set from Studio/Plugin capability (the command bar
				-- counts), never at live game runtime - so bake both realm templates here
				-- instead of leaving Workers/init.luau to mutate RunContext later.
				local source = longString(fs.readFile(path))
				emit(`inst({q(className)}, {q("Worker")}, {var}, {source}, "Server")`)
				moduleCount += 1
				emit(`inst({q(className)}, {q("WorkerClient")}, {var}, {source}, "Client")`)
			else
				emit(`inst({q(className)}, {q(childName)}, {var}, {longString(fs.readFile(path))})`)
			end
		end
	end

	return var
end

build(SRC, "RS", "Facet")

local header = [[
-- Facet installer - GENERATED by scripts/build-installer.luau. Do not edit by hand.
--
-- Paste this whole script into the Roblox Studio command bar to (re)install Facet into
-- ReplicatedStorage. A previous install named "Facet" is replaced.

local RS = game:GetService("ReplicatedStorage")

local function mod(name, parent, source)
	local m = Instance.new("ModuleScript")
	m.Name = name
	m.Source = source
	m.Parent = parent
	return m
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Script/LocalScript children (e.g. Workers' worker templates) - left Enabled = false since
-- they're only meant to run after being cloned into a purpose-built Actor at runtime. The
-- command bar runs with Studio/Plugin capability, so setting RunContext here (once, at install
-- time) works - a live game script mutating it later would not.
local function inst(className, name, parent, source, runContext)
	local s = Instance.new(className)
	s.Name = name
	s.Source = source
	s.Enabled = false
	if runContext then
		s.RunContext = Enum.RunContext[runContext]
	end
	s.Parent = parent
	return s
end

local old = RS:FindFirstChild("Facet")
if old then
	old:Destroy()
end
]]

-- `return true` lets the bootstrap's require-fallback run the installer as a ModuleScript.
local footer = `\nprint("[Facet] installed {moduleCount} modules under ReplicatedStorage.Facet")\nreturn true\n`

pcall(fs.writeDir, OUT_DIR)
fs.writeFile(OUT, header .. "\n" .. table.concat(body, "\n") .. "\n" .. footer)

-- The tiny bootstrap: paste THIS into the command bar instead of the full installer. It
-- HTTP-fetches the installer and runs it (loadstring if available, else a temp ModuleScript
-- require). Needs Game Settings -> Security -> Allow HTTP Requests = ON.
local bootstrap = [[
-- Facet bootstrap - paste into the Roblox Studio command bar.
-- Fetches and runs the full installer over HTTP (no giant paste).
-- Requires: Game Settings -> Security -> Allow HTTP Requests = ON.
local HttpService = game:GetService("HttpService")
local URL = "]] .. RAW_URL .. [["

local ok, body = pcall(function()
	return HttpService:GetAsync(URL)
end)
if not ok then
	warn("[Facet] HTTP fetch failed (enable Allow HTTP Requests in Game Settings): " .. tostring(body))
	return
end

if loadstring then
	local fn, err = loadstring(body)
	if fn then
		fn()
		return
	end
	warn("[Facet] loadstring failed, trying ModuleScript fallback: " .. tostring(err))
end

local m = Instance.new("ModuleScript")
m.Name = "FacetInstaller"
m.Source = body
m.Parent = game:GetService("ReplicatedStorage")
local okr, err = pcall(require, m)
m:Destroy()
if not okr then
	warn("[Facet] install failed: " .. tostring(err))
end
]]
fs.writeFile(BOOT, bootstrap)

print(`Wrote {OUT} ({moduleCount} modules) and {BOOT}.`)
