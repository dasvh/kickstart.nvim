local M = {}
local preview_ns = vim.api.nvim_create_namespace 'TaskPreview'

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
    rerun = '<leader>rt',
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
  vim.validate {
    opts = { opts, 'table', true },
  }
  M._options = vim.tbl_deep_extend('force', {}, defaults, opts or {})

  if M._options.keymaps ~= false then
    setup_global_keymaps()
  end
end

local function calculate_dimensions(percent_width, percent_height)
  local width = math.floor(vim.o.columns * percent_width)
  local height = math.floor(vim.o.lines * percent_height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  return width, height, row, col
end

local function float_size()
  local cfg = M._options.float
  local width, height, row, col = calculate_dimensions(cfg.width or 0.8, cfg.height or 0.8)
  return width, height, row, col, cfg.border or 'rounded'
end

local function scroll_to_bottom()
  vim.schedule(function()
    vim.cmd 'normal! G'
  end)
end

local function open_floating_win(buf, opts, enter)
  return vim.api.nvim_open_win(
    buf,
    enter or false,
    vim.tbl_extend('force', {
      relative = 'editor',
      style = 'minimal',
      border = 'single',
    }, opts or {})
  )
end

local function create_terminal_window()
  local width, height, row, col, border = float_size()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = open_floating_win(buf, {
    row = row,
    col = col,
    width = width,
    height = height,
    border = border,
  }, true)

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

local function clean_dry_output(lines)
  local cleaned = {}
  for _, line in ipairs(lines) do
    local cleaned_line = line:gsub('^task:%s+%[.-%]%s*', '')
    table.insert(cleaned, cleaned_line)
  end
  return cleaned
end

local function highlight_line(buf, ns, line)
  local content = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ''
  vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
    end_col = #content,
    hl_group = 'Visual',
  })
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
  if vim.fn.executable 'task' ~= 1 then
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
    vim.notify("Invalid task selection: no 'name' field", vim.log.levels.WARN)
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

function M.select_task_with_preview()
  local tasks = M.get_tasks()
  if #tasks == 0 then
    vim.notify('No tasks available', vim.log.levels.WARN)
    return
  end

  local total_width, total_height, row, col = calculate_dimensions(0.8, 0.6)
  local list_width = math.floor(total_width * 0.4)
  local preview_width = total_width - list_width - 2
  local list_buf = vim.api.nvim_create_buf(false, true)
  local preview_buf = vim.api.nvim_create_buf(false, true)

  local lines = {}
  for _, task in ipairs(tasks) do
    table.insert(lines, string.format('%-20s %s', task.name, task.desc or ''))
  end
  vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)

  local list_win = open_floating_win(list_buf, {
    row = row,
    col = col,
    width = list_width,
    height = total_height,
    title = 'Tasks',
    title_pos = 'center',
  }, true)

  local preview_win = open_floating_win(preview_buf, {
    row = row,
    col = col + list_width + 2,
    width = preview_width,
    height = total_height,
    title = 'Preview',
    title_pos = 'center',
  }, false)

  local current_line = 1
  local line = current_line - 1
  highlight_line(list_buf, preview_ns, line)

  local function update_preview(index)
    local task = tasks[index]
    if not task then
      return
    end
    local output = vim.fn.system { 'task', task.name, '--dry' }
    local cleaned_output = clean_dry_output(vim.split(output, '\n'))
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, cleaned_output)
  end

  update_preview(current_line)

  vim.keymap.set('n', '<CR>', function()
    local task = tasks[current_line]
    if task then
      vim.api.nvim_win_close(list_win, true)
      vim.api.nvim_win_close(preview_win, true)
      M.execute_task(task.name)
    end
  end, { buffer = list_buf })

  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(list_win, true)
    vim.api.nvim_win_close(preview_win, true)
  end, { buffer = list_buf })

  vim.keymap.set('n', '<Esc>', function()
    vim.api.nvim_win_close(list_win, true)
    vim.api.nvim_win_close(preview_win, true)
  end, { buffer = list_buf })

  vim.keymap.set('n', 'j', function()
    if current_line < #tasks then
      vim.api.nvim_buf_clear_namespace(list_buf, preview_ns, 0, -1)
      current_line = current_line + 1
      highlight_line(list_buf, preview_ns, current_line - 1)
      update_preview(current_line)
      vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
    end
  end, { buffer = list_buf })

  vim.keymap.set('n', 'k', function()
    if current_line > 1 then
      vim.api.nvim_buf_clear_namespace(list_buf, preview_ns, 0, -1)
      current_line = current_line - 1
      highlight_line(list_buf, preview_ns, current_line - 1)
      update_preview(current_line)
      vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
    end
  end, { buffer = list_buf })
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
    M.select_task_with_preview()
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
