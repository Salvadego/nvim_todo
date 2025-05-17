-- map from trigger key (string) → list of callback functions
local M = {
    registry = {},
}

--- Register a callback for a given trigger key.
--- @param key   string, e.g. "#", "@", etc.
--- @param fn    function(base: string) -> string | {string,...}
function M.register(key, fn)
    M.registry[key] = M.registry[key] or {}
    table.insert(M.registry[key], fn)
end

--- Given a trigger and the current base, call all fns and flatten results.
--- @param key    string
--- @param base   string
--- @return string[]
function M.complete(key, base)
    local cands = {}
    for _, fn in ipairs(M.registry[key] or {}) do
        local res = fn(base)
        if type(res) == "string" then
            table.insert(cands, res)
        elseif type(res) == "table" then
            for _, v in ipairs(res) do table.insert(cands, v) end
        end
    end
    return cands
end

return M
