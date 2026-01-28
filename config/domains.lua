local platform = require('utils.platform')
local wezterm = require('wezterm')

-- 公共用户名
local common_user = 'shalii'

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
