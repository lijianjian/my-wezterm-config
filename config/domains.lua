local platform = require('utils.platform')
local wezterm = require('wezterm')

-- 公共用户名
local common_user = 'shalii'

-- 获取 SSH 配置文件路径（跨系统兼容）
local function get_ssh_config_path()
   local home = os.getenv('HOME')
   if not home then
      -- Windows 环境变量
      home = os.getenv('USERPROFILE') or os.getenv('HOMEDRIVE') .. os.getenv('HOMEPATH')
   end
   return home .. '/.ssh/config'
end

-- 解析 SSH 配置文件
local function parse_ssh_config()
   local ssh_domains = {}
   local config_path = get_ssh_config_path()
   
   -- 检查 SSH 配置文件是否存在
   local file = io.open(config_path, 'r')
   if not file then
      wezterm.log_info('SSH config not found at: ' .. config_path)
      return ssh_domains
   end
   
   wezterm.log_info('Loading SSH config from: ' .. config_path)
   
   local current_host = nil
   local current_hostname = nil
   local current_user = nil
   
    for line in file:lines() do
       -- 移除前后空格
       line = line:gsub('^%s+', ''):gsub('%s+$', '')
       
       -- 跳过空行和注释
       if line ~= '' and not line:match('^#') then
          -- 匹配 Host 行
          local host = line:match('^Host%s+(.+)$')
          if host then
             -- 保存前一个主机的配置
             if current_host then
                table.insert(ssh_domains, {
                   name = 'ssh:' .. current_host,
                   remote_address = current_hostname or current_host,
                   username = current_user or 'root',
                   multiplexing = 'None',
                   assume_shell = 'Posix',
                   -- 使用 bash 作为远程 shell，避免 fish 初始化脚本问题
                   remote_wsl_distribution = nil,
                })
             end
             current_host = host
             current_hostname = nil
             current_user = nil
          else
             -- 匹配 HostName 行
             local hostname = line:match('^HostName%s+(.+)$')
             if hostname then
                current_hostname = hostname
             end
             
             -- 匹配 User 行
             local user = line:match('^User%s+(.+)$')
             if user then
                current_user = user
             end
          end
       end
    end
    
    -- 保存最后一个主机的配置
    if current_host then
       table.insert(ssh_domains, {
          name = 'ssh:' .. current_host,
          remote_address = current_hostname or current_host,
          username = current_user or 'root',
          multiplexing = 'None',
          assume_shell = 'Posix',
          -- 使用 bash 作为远程 shell，避免 fish 初始化脚本问题
          remote_wsl_distribution = nil,
       })
    end
   
   file:close()
   wezterm.log_info('Loaded ' .. #ssh_domains .. ' SSH domains')
   return ssh_domains
end

local options = {
   -- ref: https://wezfurlong.org/wezterm/config/lua/SshDomain.html
   ssh_domains = parse_ssh_config(),

   -- ref: https://wezfurlong.org/wezterm/multiplexing.html#unix-domains
   unix_domains = {},

   -- ref: https://wezfurlong.org/wezterm/config/lua/WslDomain.html
   wsl_domains = {},
}

-- Windows 特定配置
if platform.is_win then
   options.wsl_domains = {
      {
         name = 'wsl:ubuntu-fish',
         distribution = 'Ubuntu',
         username = common_user,
         default_cwd = '/home/' .. common_user,
         default_prog = { 'fish', '-l' },
      },
      {
         name = 'wsl:ubuntu-bash',
         distribution = 'Ubuntu',
         username = common_user,
         default_cwd = '/home/' .. common_user,
         default_prog = { 'bash', '-l' },
      },
   }
end

-- Linux 特定配置
if platform.is_linux then
   -- 在 Linux 上，可以添加本地 unix domain 用于 tmux/multiplexing
   options.unix_domains = {
      {
         name = 'unix',
         socket_path = '/run/user/' .. os.getenv('UID') .. '/wezterm',
      },
   }
end

-- macOS 特定配置
if platform.is_mac then
   options.unix_domains = {
      {
         name = 'unix',
         socket_path = wezterm.home_dir .. '/.local/share/wezterm/sock',
      },
   }
end

return options
