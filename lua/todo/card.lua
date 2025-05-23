local map   = vim.keymap.set
local opts  = { buffer = 0, noremap = true, silent = true }

local lyaml = require("lyaml")

local M     = {}

-- parse a Markdown file into a object:
-- {
--   meta = {...},
--   description = "...",
--   checklists = {...},
--   attachments = {...}
-- }
--
function M.parse_card_markdown(path)
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
        local ok, parsed_meta = pcall(lyaml.load, fm_text)
        if ok then
            meta = parsed_meta
        else
            vim.notify("Error parsing frontmatter: " .. parsed_meta, vim.log.levels.ERROR)
        end
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

function M.attach_mappings()
    -- Prompt for a new checklist item, append to "# Checklists"
    map("n", "<leader>ci", function()
        local item = vim.fn.input("New checklist item: ")
        if item ~= "" then
            vim.fn.append(vim.fn.search("# Checklists"), "- [ ] " .. item)
        end
    end, opts)


    -- Toggle [ ] ↔ [x] under the cursor (fixed)
    map("n", "<leader>ct", function()
        local row  = vim.fn.line(".")
        local line = vim.fn.getline(row)

        if line:match("%[ %]") then
            vim.fn.setline(row, line:gsub("%[ %]", "[x]", 1))
        elseif line:match("%[x%]") then
            vim.fn.setline(row, line:gsub("%[x%]", "[ ]", 1))
        end
    end, opts)


    map("n", "<leader>cc", function()
        local comment = vim.fn.input("Comment: ")
        vim.fn.append(vim.fn.search("# Description"), "> " .. comment)
    end, opts)

    vim.bo.completefunc = "v:lua.todo_card_completefunc"
    for _, trigger in ipairs({ "#", "+", "@", "[" }) do
        vim.keymap.set("i", trigger, function()
            vim.api.nvim_feedkeys(trigger, "in", true)
            local seq = vim.api.nvim_replace_termcodes("<C-x><C-u>", true, false, true)
            vim.api.nvim_feedkeys(seq, "n", true)
        end, { buffer = 0, noremap = true, silent = true })
    end
end

return M
