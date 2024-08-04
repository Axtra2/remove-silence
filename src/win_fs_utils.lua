---@type fun(path: string): boolean
local function exists(path)
    ---@type string
    local cmd_format = "IF NOT EXIST \"%s\" exit 1"
    ---@type string
    local cmd = cmd_format:format(path)
    local _, _, code = os.execute(cmd)
    return code ~= nil and code == 0
end

---@type fun(name: string): suc: boolean?, exitcode: ("exit"|"signal")?, code: integer?
local function mkdir(name)
    local cmd_format = "mkdir \"%s\""
    local cmd = cmd_format:format(name)
    return os.execute(cmd)
end

---@type fun(full_filename: string): name: string?, ext: string?
local function split_filename(full_filename)
    local name, ext = full_filename:match("(.*)%.(.*)$")
    return name, ext
end

return {
    split_filename=split_filename,
    exists=exists,
    mkdir=mkdir
}