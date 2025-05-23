local api = vim.api
local fn = vim.fn
local fmt = string.format
local card = require("todo.card")

local M = { config = {} }

local function slugify(title)
    return title:lower()
        :gsub("%s+", "-")
        :gsub("[^%w%-]", "")
end

local function load_config_file(cfg_path, type)
    if fn.filereadable(cfg_path) == 1 then
        local chunk, err = loadfile(cfg_path)
        if not chunk then
            vim.notify(fmt("Error loading %s config: %s", type, err), vim.log.levels.ERROR)
            return nil
        end
        local ok, config = pcall(chunk)
        if not ok then
            vim.notify(fmt("Error executing %s config: %s", type, config), vim.log.levels.ERROR)
            return nil
        end
        return config
    else
        vim.notify(fmt("%s config file not found: %s", type, cfg_path), vim.log.levels.WARN)
        return nil
    end
end

local function load_global_config()
    local cfg_file = vim.fn.stdpath("data") .. "/nvim_todo/config.lua"

    return load_config_file(cfg_file, "global")
end

local function load_board_config(board_path)
    local cfg_file = board_path .. "/config.lua"

    return load_config_file(cfg_file, "board")
end

local function merge_configs(global_config, board_config)
    local merged = { triggers = {} }

    if global_config and global_config.triggers then
        for k, v in pairs(global_config.triggers) do
            merged.triggers[k] = v
        end
    end

    if board_config and board_config.triggers then
        for k, v in pairs(board_config.triggers) do
            merged.triggers[k] = v
        end
    end

    return merged
end

function M.save_board_config(board_path)
    local cfg_file = board_path .. "/config.lua"

    local content = { "return {" }

    table.insert(content, " triggers = {")

    if M.config and M.config.triggers then
        for trigger_key, options in pairs(M.config.triggers) do
            table.insert(content, fmt(" [%q] = {", trigger_key))

            if type(options) == "function" then
                if trigger_key == "@" then
                    table.insert(content, ' today = function() return os.date("%Y-%m-%d") end,')

                    table.insert(content,
                        ' tomorrow = function() return os.date("%Y-%m-%d", os.time() + 86400) end,')

                    table.insert(content,
                        ' yesterday = function() return os.date("%Y-%m-%d", os.time() - 86400) end,')
                else
                    vim.notify(fmt("Skipping saving function for trigger %q", trigger_key), vim.log.levels.WARN)
                end
            elseif type(options) == "table" then
                for k, v in pairs(options) do
                    if type(k) == "number" then
                        table.insert(content, fmt(" %q,", v))
                    else
                        if type(v) == "string" then
                            table.insert(content, fmt(" %s = %q,", k, v))
                        elseif type(v) == "function" then
                            if k == "today" then
                                table.insert(content, ' today = function() return os.date("%Y-%m-%d") end,')
                            elseif k == "tomorrow" then
                                table.insert(content,
                                    ' tomorrow = function() return os.date("%Y-%m-%d", os.time() + 86400) end,')
                            elseif k == "yesterday" then
                                table.insert(content,
                                    ' yesterday = function() return os.date("%Y-%m-%d", os.time() - 86400) end,')
                            else
                                vim.notify(fmt("Skipping saving function %s for trigger %q", k, trigger_key),
                                    vim.log.levels.WARN)
                            end
                        end
                    end
                end
            end

            table.insert(content, " },")
        end
    end

    table.insert(content, " },")

    table.insert(content, "}")


    local ok, err = pcall(fn.writefile, content, cfg_file, "b")

    if not ok then
        return vim.notify("Error writing board config: " .. err, vim.log.levels.ERROR)
    end
end

function M.completefunc(findstart, base)
    if findstart == 1 then
        local line = vim.fn.getline(".")
        local col = vim.fn.col(".") - 1
        local start = col
        while start > 0 and line:sub(start, start):match("[%w@#+%[%]-]") do
            start = start - 1
        end
        return start + 1
    else
        local line = vim.fn.getline(".")
        local col = vim.fn.col(".") - 1
        local trigger = line:sub(col, col)
        local config = M.config

        if not config or not config.triggers or not config.triggers[trigger] then
            return {}
        end

        local trigger_def = config.triggers[trigger]
        local options

        if type(trigger_def) == "function" then
            options = trigger_def(base)
        else
            options = trigger_def
        end

        local matches = {}
        for label, func in pairs(options) do
            if type(label) == "number" and type(func) == "string" then
                label = func
                func = func
            end

            if label:match("^" .. vim.pesc(base)) then
                local item = {
                    word = type(func) == "function" and func() or func,
                    menu = "[nvim_todo]"
                }
                if type(func) == "function" then
                    item.abbr = label
                end
                table.insert(matches, item)
            end
        end
        return matches
    end
end

function M.open_card_config()
    local win = api.nvim_get_current_win()
    local row = select(1, unpack(api.nvim_win_get_cursor(win)))
    local line = api.nvim_buf_get_lines(api.nvim_get_current_buf(), row - 1, row, false)[1]
    local title = line:match("^-%s*(.+)")
    if not title then
        return vim.notify("Not on a card header (- …)", vim.log.levels.WARN)
    end

    local board_name = fn.expand("%:t:r")
    local slug = slugify(title)
    local cfg_dir = fn.stdpath("data") .. "/nvim_todo/boards/" .. board_name
    local cfg_file = fmt("%s/%s.md", cfg_dir, slug)

    local global_config = load_global_config()
    local board_config = load_board_config(cfg_dir)
    local config = merge_configs(global_config, board_config)
    M.config = config

    if fn.isdirectory(cfg_dir) == 0 then
        fn.mkdir(cfg_dir, "p")
    end

    if fn.filereadable(cfg_file) == 0 then
        local tmpl = {
            "---",
            fmt('title: %q', title),
            "labels: []",
            "status: todo",
            "due: ''",
            "members: []",
            "custom_fields: {}",
            "---",
            "",
            "# Description",
            "",
            "# Checklists",
            "",
            "# Attachments",
            "",
        }
        local ok, err = pcall(fn.writefile, tmpl, cfg_file, "b")
        if not ok then
            return vim.notify("Error writing new card file: " .. err, vim.log.levels.ERROR)
        end
    end

    local card_data = card.parse_card_markdown(cfg_file)

    api.nvim_command("rightbelow split " .. fn.fnameescape(cfg_file))

    api.nvim_buf_set_var(0, "card_meta", card_data.meta)
    api.nvim_buf_set_var(0, "card_description", card_data.description)
    api.nvim_buf_set_var(0, "card_checklists", card_data.checklists)
    api.nvim_buf_set_var(0, "card_attachments", card_data.attachments)

    if card_data.meta and card_data.meta.members then
        local current_members = M.config.triggers["+"] or {}
        local new_members = {}

        for _, member in ipairs(card_data.meta.members) do
            local name = member:gsub("^%+", "")

            table.insert(new_members, name)
        end

        local merged_members = {}
        local seen = {}

        for _, member in ipairs(current_members) do
            if not seen[member] then
                table.insert(merged_members, member)

                seen[member] = true
            end
        end


        for _, member in ipairs(new_members) do
            if not seen[member] then
                table.insert(merged_members, member)

                seen[member] = true
            end
        end


        M.config.triggers["+"] = merged_members
        M.save_board_config(cfg_dir)
    end


    card.attach_mappings()
end

_G.todo_card_completefunc = M.completefunc

return M
