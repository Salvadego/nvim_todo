local api  = vim.api
local fn   = vim.fn
local fmt  = string.format
local card = require("todo.card")

local M    = {}

local function slugify(title)
    return title:lower()
        :gsub("%s+", "-")
        :gsub("[^%w%-]", "")
end


local function load_global_config()
    local cfg_file = vim.fn.stdpath("config") .. "/nvim_todo/config.lua"
    if vim.fn.filereadable(cfg_file) == 1 then
        local chunk, err = loadfile(cfg_file)
        if not chunk then
            vim.notify("Error loading global config: " .. err, vim.log.levels.ERROR)
            return nil
        end
        local ok, config = pcall(chunk)
        if not ok then
            vim.notify("Error executing global config: " .. config, vim.log.levels.ERROR)
            return nil
        end
        return config
    else
        vim.notify("Global config file not found: " .. cfg_file, vim.log.levels.WARN)
        return nil
    end
end

local function load_board_config(board_path)
    local cfg_file = board_path .. "/config.lua"

    if fn.filereadable(cfg_file) == 1 then
        local chunk, err = loadfile(cfg_file)
        if not chunk then
            vim.notify("Error loading config: " .. err, vim.log.levels.ERROR)
            return nil
        end
        local ok, config = pcall(chunk)
        if not ok then
            vim.notify("Error executing config: " .. config, vim.log.levels.ERROR)
            return nil
        end
        return config
    else
        vim.notify("Config file not found: " .. cfg_file, vim.log.levels.WARN)
        return nil
    end
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

function M.completefunc(findstart, base)
    if findstart == 1 then
        local line = vim.fn.getline(".")
        local col = vim.fn.col(".") - 1
        local start = col
        while start > 0 and line:sub(start, start):match("[%w@#+%[%]-]") do
            start = start - 1
        end
        return start
    else
        local line = vim.fn.getline(".")
        local col = vim.fn.col(".") - 1
        local trigger = line:sub(col, col)
        local board_name = vim.fn.expand("%:t:r")
        local global_config = load_global_config()
        local board_config = load_board_config(board_name)
        local config = merge_configs(global_config, board_config)

        if not config or not config.triggers or not config.triggers[trigger] then
            return {}
        end

        local options = config.triggers[trigger](base)
        local matches = {}
        for label, func in pairs(options) do
            if label:match("^" .. vim.pesc(base)) then
                table.insert(matches, label)
            end
        end
        return matches
    end
end

function M.open_card_config()
    local win   = api.nvim_get_current_win()
    local row   = select(1, unpack(api.nvim_win_get_cursor(win)))
    local line  = api.nvim_buf_get_lines(api.nvim_get_current_buf(), row - 1, row, false)[1]
    local title = line:match("^###%s*(.+)")
    if not title then
        return vim.notify("Not on a card header (### …)", vim.log.levels.WARN)
    end

    local board_name = fn.expand("%:t:r")
    local slug       = slugify(title)
    local cfg_dir    = fn.stdpath("data") .. "/nvim_todo/boards/" .. board_name
    local cfg_file   = fmt("%s/%s.md", cfg_dir, slug)

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

    api.nvim_command("rightbelow vsplit " .. fn.fnameescape(cfg_file))

    api.nvim_buf_set_var(0, "card_meta", card_data.meta)
    api.nvim_buf_set_var(0, "card_description", card_data.description)
    api.nvim_buf_set_var(0, "card_checklists", card_data.checklists)
    api.nvim_buf_set_var(0, "card_attachments", card_data.attachments)

    card.attach_mappings()
end

_G.todo_card_completefunc = M.completefunc

return M
