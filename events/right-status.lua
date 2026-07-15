local wezterm = require('wezterm')
local umath = require('utils.math')
local Cells = require('utils.cells')
local OptsValidator = require('utils.opts-validator')

---@alias Event.RightStatusOptions { date_format?: string }

---Setup options for the right status bar
local EVENT_OPTS = {}

---@type OptsSchema
EVENT_OPTS.schema = {
   {
      name = 'date_format',
      type = 'string',
      default = '%a %H:%M:%S',
   },
}
EVENT_OPTS.validator = OptsValidator:new(EVENT_OPTS.schema)

local nf = wezterm.nerdfonts
local attr = Cells.attr

local M = {}

local ICON_SEPARATOR = nf.oct_dash
local ICON_DATE = nf.fa_calendar
local ICON_USAGE = '✳️' -- Claude 品牌星标（emoji 呈现）

-- claude 用量快照（由 claude-hud 的 externalUsageWritePath 写出）
local USAGE_SNAPSHOT = '/.claude/usage-snapshot.json'
local USAGE_REMOTE_INTERVAL = 60 -- 远程拉取节流（秒）
local USAGE_STALE_SECS = 30 * 60 -- 超过此时长未更新视为过期（灰显）

---@type string[]
local discharging_icons = {
   nf.md_battery_10,
   nf.md_battery_20,
   nf.md_battery_30,
   nf.md_battery_40,
   nf.md_battery_50,
   nf.md_battery_60,
   nf.md_battery_70,
   nf.md_battery_80,
   nf.md_battery_90,
   nf.md_battery,
}
---@type string[]
local charging_icons = {
   nf.md_battery_charging_10,
   nf.md_battery_charging_20,
   nf.md_battery_charging_30,
   nf.md_battery_charging_40,
   nf.md_battery_charging_50,
   nf.md_battery_charging_60,
   nf.md_battery_charging_70,
   nf.md_battery_charging_80,
   nf.md_battery_charging_90,
   nf.md_battery_charging,
}

---@type table<string, Cells.SegmentColors>
-- stylua: ignore
local colors = {
   date        = { fg = '#fab387', bg = 'rgba(0, 0, 0, 0.4)' },
   battery     = { fg = '#f9e2af', bg = 'rgba(0, 0, 0, 0.4)' },
   separator   = { fg = '#74c7ec', bg = 'rgba(0, 0, 0, 0.4)' },
   usage_ok    = { fg = '#a6e3a1', bg = 'rgba(0, 0, 0, 0.4)' },
   usage_warn  = { fg = '#f9e2af', bg = 'rgba(0, 0, 0, 0.4)' },
   usage_high  = { fg = '#f38ba8', bg = 'rgba(0, 0, 0, 0.4)' },
   usage_stale = { fg = '#6c7086', bg = 'rgba(0, 0, 0, 0.4)' },
}

local cells = Cells:new()

cells
   :add_segment('usage_icon', ICON_USAGE .. ' ', colors.usage_ok)
   :add_segment('usage_text', '', colors.usage_ok, attr(attr.intensity('Bold')))
   :add_segment('usage_sep', ' ' .. ICON_SEPARATOR .. '  ', colors.separator)
   :add_segment('date_icon', ICON_DATE .. '  ', colors.date, attr(attr.intensity('Bold')))
   :add_segment('date_text', '', colors.date, attr(attr.intensity('Bold')))
   :add_segment('separator', ' ' .. ICON_SEPARATOR .. '  ', colors.separator)
   :add_segment('battery_icon', '', colors.battery)
   :add_segment('battery_text', '', colors.battery, attr(attr.intensity('Bold')))

---解析 ISO 时间戳为 epoch（按 UTC 字段解释；与 now_utc() 同偏差，相减即真实差值）
local function parse_iso(ts)
   local y, mo, d, h, mi, s = ts:match('^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
   if not y then
      return nil
   end
   return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
end

local function now_utc()
   return os.time(os.date('!*t'))
end

local usage_cache = { data = nil, remote_at = 0 }

local function read_local_snapshot()
   local file = io.open(wezterm.home_dir .. USAGE_SNAPSHOT, 'r')
   if not file then
      return nil
   end
   local content = file:read('*a')
   file:close()
   local ok, data = pcall(wezterm.json_parse, content)
   return ok and data or nil
end

local function fetch_remote_snapshot(host)
   local ok, stdout = wezterm.run_child_process({
      'ssh',
      '-o',
      'BatchMode=yes',
      '-o',
      'ConnectTimeout=2',
      host,
      'cat "$HOME' .. USAGE_SNAPSHOT .. '" 2>/dev/null',
   })
   if not ok or stdout == '' then
      return nil
   end
   local ok2, data = pcall(wezterm.json_parse, stdout)
   return ok2 and data or nil
end

---读取用量快照：本地优先；无本地文件时，若当前 pane 在 ssh domain 则节流拉取远端
local function usage_info(pane)
   local data = read_local_snapshot()
   if data then
      return data
   end
   local host = pane and pane:get_domain_name():match('^ssh:(.+)$')
   if host then
      local now = os.time()
      if now - usage_cache.remote_at >= USAGE_REMOTE_INTERVAL then
         usage_cache.remote_at = now
         usage_cache.data = fetch_remote_snapshot(host) or usage_cache.data
      end
      return usage_cache.data
   end
   return nil
end

---@return string, Cells.SegmentColors
local function usage_segment(data)
   local five = data.five_hour and data.five_hour.used_percentage
   local seven = data.seven_day and data.seven_day.used_percentage
   local text = string.format('5h %s%% 7d %s%%', five or '-', seven or '-')

   local updated = data.updated_at and parse_iso(data.updated_at)
   if not updated or (now_utc() - updated) > USAGE_STALE_SECS then
      return text, colors.usage_stale
   end
   local peak = math.max(five or 0, seven or 0)
   if peak >= 80 then
      return text, colors.usage_high
   elseif peak >= 60 then
      return text, colors.usage_warn
   end
   return text, colors.usage_ok
end

---@return string, string
local function battery_info()
   -- ref: https://wezfurlong.org/wezterm/config/lua/wezterm/battery_info.html

   local charge = ''
   local icon = ''

   for _, b in ipairs(wezterm.battery_info()) do
      local idx = umath.clamp(umath.round(b.state_of_charge * 10), 1, 10)
      charge = string.format('%.0f%%', b.state_of_charge * 100)

      if b.state == 'Charging' then
         icon = charging_icons[idx]
      else
         icon = discharging_icons[idx]
      end
   end

   return charge, icon .. ' '
end

---@param opts? Event.RightStatusOptions Default: {date_format = '%a %H:%M:%S'}
M.setup = function(opts)
   local valid_opts, err = EVENT_OPTS.validator:validate(opts or {})

   if err then
      wezterm.log_error(err)
   end

   wezterm.on('update-right-status', function(window, pane)
      local battery_text, battery_icon = battery_info()

      cells
         :update_segment_text('date_text', wezterm.strftime(valid_opts.date_format))
         :update_segment_text('battery_icon', battery_icon)
         :update_segment_text('battery_text', battery_text)

      local segments = { 'date_icon', 'date_text', 'separator', 'battery_icon', 'battery_text' }

      local usage = usage_info(pane)
      if usage then
         local text, color = usage_segment(usage)
         cells
            :update_segment_text('usage_text', text)
            :update_segment_colors('usage_icon', color)
            :update_segment_colors('usage_text', color)
         segments = {
            'usage_icon',
            'usage_text',
            'usage_sep',
            'date_icon',
            'date_text',
            'separator',
            'battery_icon',
            'battery_text',
         }
      end

      window:set_right_status(wezterm.format(cells:render(segments)))
   end)
end

return M
