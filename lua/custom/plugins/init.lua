-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
-- nvim/lua/custom/plugins/taskfile.lua
return {
  'dasvh/taskfile.nvim',
  lazy = false,
  config = function()
    require('taskfile').setup {
      float = {
        width = 0.6,
        height = 0.5,
        border = 'single',
      },
    }
  end,
}
