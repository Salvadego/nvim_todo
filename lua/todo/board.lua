local uv   = vim.loop
local api  = vim.api
local fn   = vim.fn
local fmt  = string.format
local yaml = require("yaml")

local M    = {}

local function slugify(title)
    return title:lower()
        :gsub("%s+", "-")
        :gsub("[^%w%-]", "")
end

-- parse a Markdown file into a object:
-- {
--   meta = {...},
--   description = "...",
--   checklists = {...},
--   attachments = {...}
-- }
--
local function parse_card_markdown(path)
    local lines = {}
    for line in io.lines(path) do
        table.insert(lines, line)
    end

    local fm_lines   = {}
    local body_lines = {}
    local i          = 1

    if lines[1] == "---" then
        i = 2
        while i <= #lines do
            if lines[i] == "---" then
                i = i + 1
                break
            else
                table.insert(fm_lines, lines[i])
            end
            i = i + 1
        end
    end

    for j = i, #lines do
        table.insert(body_lines, lines[j])
    end

    local meta = {}
    if #fm_lines > 0 then
        local fm_text = table.concat(fm_lines, "\n")
        meta = yaml.load(fm_text)
    end

    local section = nil
    local text_acc = {}
    local descr = ""
    local checklists = {}
    local attachments = {}

    local function finish_section()
        if not section then return end
        local content = text_acc
        if section == "description" then
            descr = table.concat(content, "\n")
        elseif section == "checklists" then
            for _, l in ipairs(content) do
                local checked, item = l:match("^%-%s*%[([ xX])%]%s*(.+)")
                if item then
                    table.insert(checklists, { text = item, done = (checked ~= " ") })
                end
            end
        elseif section == "attachments" then
            for _, l in ipairs(content) do
                local url, label = l:match("%[(.-)%]%((.-)%)")
                if url then
                    table.insert(attachments, { label = label, url = url })
                end
            end
        end
        text_acc = {}
    end

    for _, l in ipairs(body_lines) do
        local hdr = l:match("^#%s*(%a+)")
        if hdr then
            finish_section()
            local h = hdr:lower()
            if h == "description" or h == "checklists" or h == "attachments" then
                section = h
            else
                section = nil
            end
        elseif section then
            table.insert(text_acc, l)
        end
    end
    finish_section()

    return {
        meta        = meta,
        description = descr,
        checklists  = checklists,
        attachments = attachments,
    }
end

function M.open_card_config()
    local win   = api.nvim_get_current_win()
    local buf   = api.nvim_get_current_buf()
    local row   = api.nvim_win_get_cursor(win)[1]
    local line  = api.nvim_buf_get_lines(buf, row - 1, row, false)[1]

    local title = string.match(line, "^###%s*(.+)")
    -- vim.print(title)
    if not title then
        vim.notify("Not on a card header (### …)", vim.log.levels.WARN)
        return
    end

    local board_name = fn.expand("%:t:r")
    local slug       = slugify(title)
    local cfg_dir    = fn.stdpath("data") .. "/nvim_todo/boards/" .. board_name
    local cfg_file   = fmt("%s/%s.md", cfg_dir, slug)

    vim.cmd(fmt("w ++p %s", cfg_dir))

    if not uv.fs_stat(cfg_file) then
        local tmpl = table.concat({
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
        }, "\n")

        local fd = 644
        if not fd then
            return vim.notify("Could not open config file: " .. err, vim.log.levels.ERROR)
        end

        local written, werr = uv.fs_write(fd, tmpl, -1)
        uv.fs_close(fd)
        if not written then
            return vim.notify("Could not write config template: " .. werr, vim.log.levels.ERROR)
        end
    end

    api.nvim_command("rightbelow vsplit " .. fn.fnameescape(cfg_file))

    local card = parse_card_markdown(cfg_file)
    api.nvim_buf_set_var(0, slug, card)
    -- e.g. now you can do: vim.b.slug.meta, .description, .checklists, .attachments
end

return M
