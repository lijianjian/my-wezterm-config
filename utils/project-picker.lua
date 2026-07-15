local wezterm = require('wezterm')
local act = wezterm.action

local M = {}

-- 项目根目录（相对 $HOME），其下一级子目录作为项目候选，本地/远程 domain 通用
local project_roots = {
   'workspace/agents',
   'workspace/my-tools',
   'IdeaProjects',
   'vcProjects',
}

-- 直接作为候选的单个项目目录（相对 $HOME），不扫其子目录
local direct_projects = {
   'workspace/vp-note',
   'workspace/vp-platform-analytics',
}

-- 候选排除规则（Lua pattern，对本地/远程结果统一生效）
local exclude_patterns = {
   '%.worktrees$',
}

local function excluded(path)
   for _, pat in ipairs(exclude_patterns) do
      if path:match(pat) then
         return true
      end
   end
   return false
end

local function add_choice(choices, path)
   if not excluded(path) then
      table.insert(choices, { id = path, label = path:match('([^/]+/[^/]+)$') })
   end
end

-- wezterm.glob 会同时返回文件；读目录必报错（EISDIR），空文件读 EOF 不报错，借此区分
local function is_dir(path)
   local file = io.open(path, 'r')
   if not file then
      return false
   end
   local _, err = file:read(1)
   file:close()
   return err ~= nil
end

local function sort_by_label(choices)
   table.sort(choices, function(a, b)
      return a.label < b.label
   end)
   return choices
end

-- 本地 domain：直接 glob 扫描 GUI 所在机器的文件系统
local function local_choices()
   local choices = {}
   for _, root in ipairs(project_roots) do
      for _, path in ipairs(wezterm.glob(wezterm.home_dir .. '/' .. root .. '/*')) do
         if is_dir(path) then
            add_choice(choices, path)
         end
      end
   end
   for _, proj in ipairs(direct_projects) do
      local path = wezterm.home_dir .. '/' .. proj
      if is_dir(path) then
         add_choice(choices, path)
      end
   end
   return sort_by_label(choices)
end

-- ssh domain：在 GUI 机器上执行 ssh <host> find，列出远端项目目录
local function remote_choices(host)
   local roots = {}
   for _, root in ipairs(project_roots) do
      table.insert(roots, '"$HOME/' .. root .. '"')
   end
   local directs = {}
   for _, proj in ipairs(direct_projects) do
      table.insert(directs, '"$HOME/' .. proj .. '"')
   end
   -- 2>/dev/null + 结尾 true：个别根目录在某主机不存在时不至于整体失败
   local cmd = 'find '
      .. table.concat(roots, ' ')
      .. ' -mindepth 1 -maxdepth 1 -type d 2>/dev/null; find '
      .. table.concat(directs, ' ')
      .. ' -maxdepth 0 -type d 2>/dev/null; true'
   local ok, stdout, stderr = wezterm.run_child_process({
      'ssh',
      '-o',
      'BatchMode=yes',
      host,
      cmd,
   })
   if not ok then
      wezterm.log_error('project-picker: ssh ' .. host .. ' failed: ' .. (stderr or ''))
      return {}
   end
   local choices = {}
   for path in stdout:gmatch('[^\r\n]+') do
      add_choice(choices, path)
   end
   return sort_by_label(choices)
end

-- 选中项目后在 pane 里执行的启动命令；fish -l -C 保证命令退出后留在交互 shell
local launch_cmds = {
   claude = 'claude',
   ['claude-resume'] = 'claude --resume || claude',
}

-- assume_shell = 'Unknown' 时 wezterm 无法为 ssh domain 设置 cwd，用显式命令进入目录
local function build_spawn(domain, host, dir, launch)
   local cmd = launch_cmds[launch]
   if host then
      local shell = cmd and ("exec fish -l -C '" .. cmd .. "'") or 'exec "$SHELL" -l'
      return {
         domain = { DomainName = domain },
         args = { 'bash', '-c', 'cd "' .. dir .. '" && ' .. shell },
      }
   end
   local spawn = { domain = { DomainName = domain }, cwd = dir }
   if cmd then
      spawn.args = { 'fish', '-l', '-C', cmd }
   end
   return spawn
end

-- 第二步动作菜单：id 格式为 open_mode 或 open_mode+launch，按数字直选
local open_actions = {
   { id = 'tab', label = '1. Tab + shell（临时）' },
   { id = 'tab+claude', label = '2. Tab + claude 新会话' },
   { id = 'tab+claude-resume', label = '3. Tab + claude --resume' },
   { id = 'pane-right', label = '4. Pane→ + shell（右分屏）' },
   { id = 'pane-right+claude', label = '5. Pane→ + claude 新会话' },
   { id = 'pane-right+claude-resume', label = '6. Pane→ + claude --resume' },
   { id = 'pane-down', label = '7. Pane↓ + shell（下分屏）' },
   { id = 'pane-down+claude', label = '8. Pane↓ + claude 新会话' },
   { id = 'pane-down+claude-resume', label = '9. Pane↓ + claude --resume' },
   { id = 'workspace', label = '0. Workspace + shell' },
   { id = 'workspace+claude-resume', label = 'a. Workspace + claude --resume（继续项目）' },
}

local function open_project(win, p, domain, host, dir, label, action_id)
   local open_mode, launch = action_id:match('^([^+]+)%+?(.*)$')
   local spawn = build_spawn(domain, host, dir, launch ~= '' and launch or nil)
   if open_mode == 'workspace' then
      local ws_name = host and (host .. '/' .. label) or label
      win:perform_action(act.SwitchToWorkspace({ name = ws_name, spawn = spawn }), p)
   elseif open_mode == 'pane-right' then
      win:perform_action(act.SplitHorizontal(spawn), p)
   elseif open_mode == 'pane-down' then
      win:perform_action(act.SplitVertical(spawn), p)
   else
      win:perform_action(act.SpawnCommandInNewTab(spawn), p)
   end
end

---打开项目选择器；自动适配当前 pane 所在 domain（本地 or ssh:xxx）
---两步交互：先模糊选项目，再选打开动作（tab/workspace × shell/claude）
function M.pick()
   return wezterm.action_callback(function(window, pane)
      local domain = pane:get_domain_name()
      local host = domain:match('^ssh:(.+)$')
      local choices = host and remote_choices(host) or local_choices()

      window:perform_action(
         act.InputSelector({
            title = 'InputSelector: Open Project',
            choices = choices,
            fuzzy = true,
            fuzzy_description = 'Open project [' .. domain .. ']: ',
            -- 注意：内层回调统一使用按键时刻捕获的真实 pane（外层 pane），
            -- 而不是回调参数里的 pane——后者可能是选择器的 TermWiz overlay pane，
            -- 对其执行 spawn/split 会破坏 mux attach（wezterm connect）窗口的连接
            action = wezterm.action_callback(function(win, _p, id, label)
               if not id then
                  return
               end
               win:perform_action(
                  act.InputSelector({
                     title = label,
                     choices = open_actions,
                     alphabet = '1234567890a',
                     description = label .. ' — 按数字选择打开方式，Esc 取消',
                     action = wezterm.action_callback(function(w, _pn, action_id)
                        if not action_id then
                           return
                        end
                        open_project(w, pane, domain, host, id, label, action_id)
                     end),
                  }),
                  pane
               )
            end),
         }),
         pane
      )
   end)
end

return M
