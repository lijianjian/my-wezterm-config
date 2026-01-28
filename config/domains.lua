local platform = require('utils.platform')
local wezterm = require('wezterm')

-- 获取当前系统用户名
local function get_current_user()
   if platform.is_win then
      return os.getenv('USERNAME') or 'user'
   else
      return os.getenv('USER') or os.getenv('LOGNAME') or 'user'
   end
end

local current_user = get_current_user()
local home_dir = wezterm.home_dir

local options = {
   -- ref: https://wezfurlong.org/wezterm/config/lua/SshDomain.html
   ssh_domains = {},

   -- ref: https://wezfurlong.org/wezterm/multiplexing.html#unix-domains
   unix_domains = {},

   -- ref: https://wezfurlong.org/wezterm/config/lua/WslDomain.html
   wsl_domains = {},
}

if platform.is_win then
   options.ssh_domains = {
      {
         name = 'ssh:wsl',
         remote_address = 'localhost',
         multiplexing = 'None',
         default_prog = { 'fish', '-l' },
         assume_shell = 'Posix',
      },
   }

   options.wsl_domains = {
      {
         name = 'wsl:ubuntu-fish',
         distribution = 'Ubuntu',
         username = current_user,
         default_cwd = '/home/' .. current_user,
         default_prog = { 'fish', '-l' },
      },
      {
         name = 'wsl:ubuntu-bash',
         distribution = 'Ubuntu',
         username = current_user,
         default_cwd = '/home/' .. current_user,
         default_prog = { 'bash', '-l' },
      },
   }
end

return options
