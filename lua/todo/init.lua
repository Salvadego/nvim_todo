local autocmd = vim.api.nvim_create_autocmd
local autogrp = vim.api.nvim_create_augroup
local uv      = vim.loop
local fn      = vim.fn

local board   = require("todo.board")
local M       = {}

function M.setup(opts)
    local cfg_dir    = fn.stdpath("data") .. "/nvim_todo"
    local boards_dir = cfg_dir .. "/boards/"
    local directory  = tonumber(644, 8)
    if directory == nil then return end

    uv.fs_mkdir(cfg_dir, directory)
    uv.fs_mkdir(boards_dir, directory)
    -- vim.print(opts)
end

autocmd({ 'BufRead', 'BufNewFile' }, {
    group = autogrp("BoardFiletype", { clear = true }),
    callback = function()
        M.attach_mappings()
    end
})

function M.attach_mappings()
    vim.keymap.set("n", "<CR>", board.open_card_config, { noremap = true, buffer = 0 })
end

return M
