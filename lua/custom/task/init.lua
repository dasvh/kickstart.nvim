local M = {}

M._win = nil
M._buf = nil
M._last_task = nil
M._options = {}

local defaults = {
  float = {
    width = 0.8,
    height = 0.8,
    border = 'rounded',
  },
  scroll = {
    auto = true,
  },
  keymaps = {
    rerun = '<leader>rt'
  },
}

local function setup_global_keymaps()
  if M._options.keymaps and M._options.keymaps.rerun then
    vim.keymap.set('n', M._options.keymaps.rerun, function()
      if M._last_task then
        M.execute_task(M._last_task)
      else
        vim.notify('No task has been run yet.', vim.log.levels.WARN)
      end
    end, { desc = '[R]erun last [T]ask' })
  end
end

function M.setup(opts)
  vim.validate({
    opts = { opts, 'table', true }
  })
  M._options = vim.tbl_deep_extend('force', {}, defaults, opts or {})

  if M._options.keymaps ~= false then
    setup_global_keymaps()
  end
end

local function float_size()
  local cfg = M._options.float
  local width = math.floor(vim.o.columns * (cfg.width or 0.8))
  local height = math.floor(vim.o.lines * (cfg.height or 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  return width, height, row, col, cfg.border or 'rounded'
end

local function scroll_to_bottom()
  vim.schedule(function()
    pcall(vim.cmd, 'normal! G')
  end)
end

local function create_terminal_window()
  local width, height, row, col, border = float_size()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = border,
  })
  vim.api.nvim_set_current_buf(buf)
  return buf, win
end

local function cleanup_terminal()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_close(M._win, true)
  end
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    vim.api.nvim_buf_delete(M._buf, { force = true })
  end
end

local function run_task_in_terminal(buf, task)
  local opts = {}
  if M._options.scroll.auto then
    opts.on_stdout = scroll_to_bottom
    opts.on_stderr = scroll_to_bottom
    opts.on_exit = scroll_to_bottom
  end

  local term_opts = next(opts) and opts or vim.empty_dict()
  vim.fn.termopen('task ' .. task, term_opts)
end

local function set_quit_key(buf, win)
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true, silent = true })
end

function M.execute_task(task)
  cleanup_terminal()
  local buf, win = create_terminal_window()
  M._buf, M._win, M._last_task = buf, win, task
  run_task_in_terminal(buf, task)
  set_quit_key(buf, win)
end

function M.get_tasks()
  if vim.fn.executable('task') ~= 1 then
    vim.notify("'task' executable not found in PATH", vim.log.levels.ERROR)
    return {}
  end
  local response = vim.fn.system 'task --list --json'
  if vim.v.shell_error ~= 0 then
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

function M.on_choice(item)
  if not item or not item.name then
    vim.notify('Invalid task selection', vim.log.levels.WARN)
    return
  end
  M.execute_task(item.name)
end

function M.open_window()
  local tasks = M.get_tasks()
  if #tasks == 0 then
    vim.notify('No tasks available', vim.log.levels.WARN)
    return
  end
  vim.ui.select(tasks, {
    prompt = 'Task:',
    format_item = function(task)
      return string.format('%-20s %s', task.name, task.desc or '')
    end,
  }, M.on_choice)
end

local function complete(ArgLead, _, _)
  local matches = {}
  for _, task in ipairs(M.get_tasks()) do
    if task.name:lower():match('^' .. ArgLead:lower()) then
      table.insert(matches, task.name)
    end
  end
  table.sort(matches)
  return matches
end

vim.api.nvim_create_user_command('Task', function(input)
  if input.args ~= '' then
    M.execute_task(input.args)
  else
    M.open_window()
  end
end, { bang = true, desc = 'Run tasks defined in a Taskfile', nargs = '?', complete = complete })

vim.api.nvim_create_user_command('TaskRerun', function()
  if not M._last_task then
    vim.notify('No task has been run yet.', vim.log.levels.WARN)
    return
  end
  M.execute_task(M._last_task)
end, { desc = 'Rerun last Task' })

return M
