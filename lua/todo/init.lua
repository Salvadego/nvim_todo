local autocmd = vim.api.nvim_create_autocmd
local autogrp = vim.api.nvim_create_augroup

local board   = require("todo.board")
local M       = {}

function M.setup(opts)
    vim.api.nvim_create_user_command("BoardConfig", function()
        local board_name = vim.fn.expand("%:t:r")
        local cfg_dir = vim.fn.stdpath("data") .. "/nvim_todo/boards/" .. board_name
        local cfg_file = cfg_dir .. "/config.lua"

        if vim.fn.isdirectory(cfg_dir) == 0 then
            vim.fn.mkdir(cfg_dir, "p")
        end

        if vim.fn.filereadable(cfg_file) == 0 then
            local default_config = {
                "return {",
                "  triggers = {",
                "    [\"@\"] = function(base)",
                "      return {",
                "        today = function() return os.date(\"%Y-%m-%d\") end,",
                "        tomorrow = function() return os.date(\"%Y-%m-%d\", os.time() + 86400) end,",
                "      }",
                "    end,",
                "  },",
                "}",
            }
            vim.fn.writefile(default_config, cfg_file)
        end

        vim.cmd("edit " .. cfg_file)
    end, {})
end

autocmd({ 'BufRead', 'BufNewFile' }, {
    pattern = '*.board.md',
    group = autogrp("BoardFiletype", { clear = true }),
    callback = function()
        M.attach_mappings()
    end
})

function M.attach_mappings()
    vim.keymap.set("n", "<CR>", board.open_card_config, { noremap = true, buffer = 0 })
end

return M
