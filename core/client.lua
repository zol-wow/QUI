local _, ns = ...
local version, build, _, interfaceVersion = GetBuildInfo()
local isForever = type(version) == "string" and version:match("^1%.60%.") ~= nil

ns.Client = {
    isForever = isForever,
    restrictedExecutionUnavailable = isForever,
    flavor = isForever and "forever" or "retail",
    version = version,
    build = build,
    interfaceVersion = interfaceVersion,
}
