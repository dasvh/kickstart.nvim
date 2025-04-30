-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  dir = vim.fn.stdpath('config') .. '/lua/custom/task',
  name = 'custom-task',
  lazy = false,
  config = function()
    require('custom.task').setup({
      float = {
        width = 0.6,
        height = 0.5,
        border = 'single',
      },
    })
  end,
}
