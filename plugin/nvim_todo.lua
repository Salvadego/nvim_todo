if vim.g.loaded_nvim_ui then
    return
end
vim.g.loaded_nvim_ui = true

function setup(opts)
    require("todo").setup(opts)
end


