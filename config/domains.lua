local platform = require('utils.platform')
local wezterm = require('wezterm')

-- 公共用户名
local common_user = 'shalii'

-- 解析 SSH 配置文件
local function parse_ssh_config()
   local ssh_domains = {}
   local config_path = os.getenv('HOME') .. '/.ssh/config'
   
   -- 检查 SSH 配置文件是否存在
   local file = io.open(config_path, 'r')
   if not file then
      return ssh_domains
   end
   
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
      })
   end
   
   file:close()
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

return options
