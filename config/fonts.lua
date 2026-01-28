local wezterm = require('wezterm')
local platform = require('utils.platform')

-- 根据系统选择合适的字体
local function get_font_config()
   if platform.is_win then
      -- Windows: 使用内置字体
      return {
         font = wezterm.font_with_fallback {
            'Consolas',
            'Courier New',
         },
         font_size = 9.75,
      }
   elseif platform.is_linux then
      -- Linux: 优先使用 JetBrains Mono，fallback 到系统字体
      return {
         font = wezterm.font_with_fallback {
            'JetBrains Mono',
            'DejaVu Sans Mono',
            'Monospace',
         },
         font_size = 10,
      }
   elseif platform.is_mac then
      -- macOS: 优先使用 JetBrains Mono
      return {
         font = wezterm.font_with_fallback {
            'JetBrains Mono',
            'Monaco',
         },
         font_size = 12,
      }
   end
end

local font_config = get_font_config()

return {
   font = font_config.font,
   font_size = font_config.font_size,

   -- ref: https://wezfurlong.org/wezterm/config/lua/config/freetype_pcf_long_family_names.html
   freetype_load_target = 'Normal', ---@type 'Normal'|'Light'|'Mono'|'HorizontalLcd'
   freetype_render_target = 'Normal', ---@type 'Normal'|'Light'|'Mono'|'HorizontalLcd'
}
