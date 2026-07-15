local wezterm = require('wezterm')

local M = {}

-- 首次 require 时 wezterm 会自动 clone 插件仓库（需要 GUI 机器能访问 GitHub）
M.plugin = wezterm.plugin.require('https://github.com/StephenGemin/resurrect.wezterm')

-- 在最终 config 上启用自动保存（周期 + 失焦时）与 gui-startup 恢复
function M.apply_to_config(config)
   M.plugin.setup(config, {
      keybindings = false, -- 默认键位与现有绑定冲突（Alt+W/Alt+D），在 config/bindings.lua 自定义
      status_bar = false, -- 与 events/right-status 自定义状态栏冲突
   })
end

return M
