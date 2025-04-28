local Module = {}

Module.setup = function() end

local function centered_float_size()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  return width, height, row, col
end

Module.get_tasks = function()
  local response = vim.fn.system 'task --list --json'
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify('Task command failed (missing Taskfile?)', vim.log.levels.ERROR)
    return {}
  end

  local ok, data = pcall(vim.fn.json_decode, response)
  if not ok or not data or not data.tasks then
    vim.notify('Failed to parse task output.', vim.log.levels.ERROR)
    return {}
  end

  return data.tasks
end

Module.execute_task = function(task)
  local width, height, row, col = centered_float_size()

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
  })

  vim.api.nvim_set_current_buf(buf)
  vim.fn.termopen('task ' .. task, {
    on_stdout = function(_, _, _)
      vim.api.nvim_command 'normal! G'
    end,
    on_stderr = function(_, _, _)
      vim.api.nvim_command 'normal! G'
    end,
    on_exit = function()
      vim.api.nvim_command 'normal! G'
    end,
  })

  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true, silent = true })
end

Module.on_choice = function(item)
  Module.execute_task(item.name)
end

Module.open_window = function()
  local tasks = Module.get_tasks()
  if #tasks == 0 then
    vim.notify('No tasks available', vim.log.levels.WARN)
    return
  end

  local formatter = function(task)
    return string.format('%-20s %s', task.name, task.desc or '')
  end

  vim.ui.select(tasks, { prompt = 'Task:', format_item = formatter }, Module.on_choice)
end

local complete = function(ArgLead, _, _)
  local matches = {}
  for _, task in ipairs(Module.get_tasks()) do
    if task.name:lower():match('^' .. ArgLead:lower()) then
      table.insert(matches, task.name)
    end
  end
  table.sort(matches)
  return matches
end

vim.api.nvim_create_user_command('Task', function(input)
  if input.args ~= '' then
    Module.execute_task(input.args)
  else
    Module.open_window()
  end
end, { bang = true, desc = 'Run tasks defined in a Taskfile', nargs = '?', complete = complete })

return Module
