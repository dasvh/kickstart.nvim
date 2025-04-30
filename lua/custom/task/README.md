# Task

A simple plugin for [taskfiles](https://taskfile.dev/)

## Options

```lua
return {
  dir = vim.fn.stdpath('config') .. '/lua/custom/task',
  name = 'custom-task',
  lazy = false,
  config = function()
    require('custom.task').setup({
      float = {
        width = 0.7, -- Percentage of the screen width
        height = 0.7, -- Percentage of the screen height
        border = 'single', -- Border style
      },
      scroll = {
        auto = true, -- Automatically scroll to the bottom when new output is added
      },
      keymaps = {
        rerun = '<leader>rt' -- Keymap to rerun the last task
      },
    })
  end,
}
```

### Commands
- `:Task` — select and run a task from the Taskfile
- `:TaskRerun` — rerun the last task
