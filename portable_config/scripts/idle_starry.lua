-- idle_starry.lua —— mpv 空闲界面的星空背景
--
-- 原理：空闲时用两个 ASS 叠加层画图
--   1) 静态层：夜空渐变 + 银河辉光 + 不闪烁的星星（只在窗口尺寸变化时重画）
--   2) 动态层：会呼吸闪烁的星星 + 亮星光晕 + 偶尔划过的流星（按 fps 刷新）
-- 播放文件后自动移除，不影响正片画面。
--
-- 配合 modernz.conf 的 idlescreen=no 使用，否则自带的 mpv 图标和提示文字会叠在上面。
--
-- 改完 idle_starry.conf 里的配色后，按 Ctrl+Alt+i 热重载（脚本自己绑定，无需改 input.conf）

local mp   = require 'mp'
local msg  = require 'mp.msg'
local opts = require 'mp.options'

local o = {
    enabled                = true,
    fps                    = 20,         -- 动态层刷新率，20 足够顺滑且很省电
    star_count             = 210,        -- 均匀散布的星星
    band_stars             = 150,        -- 银河带里额外聚集的星星
    bright_stars           = 9,          -- 带十字光晕的亮星
    twinkle_ratio          = 0.30,       -- 会闪烁的星星占比
    twinkle_speed          = 1.0,
    band_count             = 120,        -- 背景渐变分层数

    bg_top                 = "#0B1330",  -- 夜空顶部
    bg_mid                 = "#070C22",  -- 中段
    bg_bottom              = "#02030A",  -- 底部

    band_enabled           = true,       -- 银河带
    band_angle             = 22,         -- 银河带倾角（度），正值从左上去右下
    band_spread            = 0.115,      -- 银河带宽度（相对屏幕短边）
    band_glow              = 26,         -- 银河雾状辉光光斑数量（0 = 关闭，纯靠星星密度）
    band_color             = "#5A6BAE",  -- 银河辉光颜色
    band_blur              = 22,         -- 辉光模糊强度，越大越柔

    star_color             = "#FFFFFF",
    star_color_cool        = "#B9CCFF",
    star_color_warm        = "#FFE6BE",
    bright_star_color      = "#DCEBFF",
    glow                   = true,

    shooting_star          = true,
    shooting_star_interval = 13,
    shooting_star_color    = "#CFE4FF",
}
opts.read_options(o, 'idle_starry')

---------------------------------------------------------------------------
-- 工具
---------------------------------------------------------------------------

local function parse_hex(h)
    local s = tostring(h or ""):gsub("%s", ""):gsub("^#", "")
    if #s == 3 then
        s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
    end
    if #s < 6 then return { 255, 255, 255 } end
    return {
        tonumber(s:sub(1, 2), 16) or 0,
        tonumber(s:sub(3, 4), 16) or 0,
        tonumber(s:sub(5, 6), 16) or 0,
    }
end

-- #RRGGBB -> ASS 的 &HBBGGRR&
local function bgr(rgb)
    return string.format("&H%02X%02X%02X&", rgb[3], rgb[2], rgb[1])
end

local function mix(c1, c2, t)
    return {
        math.floor(c1[1] + (c2[1] - c1[1]) * t + 0.5),
        math.floor(c1[2] + (c2[2] - c1[2]) * t + 0.5),
        math.floor(c1[3] + (c2[3] - c1[3]) * t + 0.5),
    }
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function gauss()
    -- Box-Muller，只要一个分量
    local u1 = math.max(1e-9, math.random())
    local u2 = math.random()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

---------------------------------------------------------------------------
-- ASS drawing 基元
---------------------------------------------------------------------------

local function circle(x, y, r)
    local k = 0.5523 * r
    return string.format(
        "m %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f " ..
        "b %.2f %.2f %.2f %.2f %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f",
        x - r, y,
        x - r, y - k, x - k, y - r, x, y - r,
        x + k, y - r, x + r, y - k, x + r, y,
        x + r, y + k, x + k, y + r, x, y + r,
        x - k, y + r, x - r, y + k, x - r, y)
end

-- 小于 1.25px 的一律用方块，肉眼分辨不出，还能省一大截字符串
local function shape(x, y, r)
    if r < 1.25 then
        return string.format("m %.2f %.2f l %.2f %.2f l %.2f %.2f l %.2f %.2f",
            x - r, y - r, x + r, y - r, x + r, y + r, x - r, y + r)
    end
    return circle(x, y, r)
end

---------------------------------------------------------------------------
-- 星图（归一化坐标，窗口缩放时图案不变）
---------------------------------------------------------------------------

local stars, brights, blobs = {}, {}, {}
local W, H = 0, 0

local function gen_pattern()
    stars, brights, blobs = {}, {}, {}
    math.randomseed(os.time() + math.floor(os.clock() * 1e6))

    local white = parse_hex(o.star_color)
    local cool  = parse_hex(o.star_color_cool)
    local warm  = parse_hex(o.star_color_warm)

    local function new_star(nx, ny, dim)
        local roll = math.random()
        local col = white
        if roll < 0.20 then
            col = cool
        elseif roll > 0.93 then
            col = warm
        end
        local r = 0.55 + math.random() * 0.70
        if math.random() < 0.07 then
            r = r + math.random() * 0.80
        end
        local b = 0.28 + math.random() * 0.72
        if dim then b = b * dim end
        return {
            nx = nx, ny = ny, r = r, col = col, b = b,
        }
    end

    -- 均匀散布
    local n = math.max(0, math.floor(o.star_count))
    for i = 1, n do
        stars[#stars + 1] = new_star(
            0.003 + math.random() * 0.994,
            0.003 + math.random() * 0.958)
    end

    -- 银河带内聚集（垂直于带中线的高斯偏移）
    if o.band_enabled then
        local nb = math.max(0, math.floor(o.band_stars))
        local a = math.rad(o.band_angle)
        local ca, sa = math.cos(a), math.sin(a)
        for _ = 1, nb do
            local t = -0.75 + math.random() * 1.55          -- 沿带方向
            local d = gauss() * o.band_spread * 0.5         -- 垂直偏移
            local nx = 0.5 + ca * t - sa * d
            local ny = 0.5 + sa * t * 0.6 + ca * d * 0.6
            if nx > 0.003 and nx < 0.997 and ny > 0.003 and ny < 0.961 then
                stars[#stars + 1] = new_star(nx, ny, 0.72)
            end
        end
    end

    -- 闪烁标记
    local total = #stars
    local nt = math.floor(total * clamp(o.twinkle_ratio, 0, 1))
    local used, cnt = {}, 0
    while cnt < nt and total > 1 do
        local idx = math.random(1, total)
        if not used[idx] then
            used[idx] = true
            cnt = cnt + 1
            stars[idx].tw = {
                phase = math.random() * math.pi * 2,
                amp   = 0.20 + math.random() * 0.34,
                spd   = 0.6 + math.random() * 0.95,
            }
        end
    end

    -- 亮星
    for i = 1, math.max(0, math.floor(o.bright_stars)) do
        brights[i] = {
            nx  = 0.05 + math.random() * 0.90,
            ny  = 0.04 + math.random() * 0.68,
            r   = 1.45 + math.random() * 1.05,
            col = parse_hex(o.bright_star_color),
            tw  = {
                phase = math.random() * math.pi * 2,
                amp   = 0.09 + math.random() * 0.12,
                spd   = 0.35 + math.random() * 0.5,
            },
        }
    end

    -- 银河辉光的光斑（归一化位置 + 半径比例）
    if o.band_enabled then
        local a = math.rad(o.band_angle)
        local ca, sa = math.cos(a), math.sin(a)
        local gcol = parse_hex(o.band_color)
        for _ = 1, math.max(0, math.floor(o.band_glow)) do
            local t  = -0.80 + math.random() * 1.65
            local d  = gauss() * o.band_spread * 0.42
            blobs[#blobs + 1] = {
                nx  = 0.5 + ca * t - sa * d,
                ny  = 0.5 + sa * t * 0.6 + ca * d * 0.6,
                rr  = 0.060 + math.random() * 0.095,   -- 相对屏幕短边
                col = gcol,
                alpha = string.format("%02X", 0xEE + math.random(0, 10)),
            }
        end
    end
end

---------------------------------------------------------------------------
-- 静态层
---------------------------------------------------------------------------

local function gradient_events()
    local ev = {}
    local nb = math.max(2, math.floor(o.band_count))
    local c1, c2, c3 = parse_hex(o.bg_top), parse_hex(o.bg_mid), parse_hex(o.bg_bottom)
    local bh = H / nb

    for i = 0, nb - 1 do
        local t = i / (nb - 1)
        local c
        if t < 0.45 then
            c = mix(c1, c2, t / 0.45)
        else
            c = mix(c2, c3, (t - 0.45) / 0.55)
        end
        -- 上下各多画 1px，压掉 ASS 边缘抗锯齿造成的一像素暗缝
        ev[#ev + 1] = string.format(
            "{\\an7\\pos(0,%.2f)\\p1\\bord0\\shad0\\1c%s}m 0 0 l %.2f 0 l %.2f %.2f l 0 %.2f",
            i * bh - 1, bgr(c), W, W, bh + 2, bh + 2)
    end
    return ev
end

local function glow_events()
    local ev = {}
    if not o.band_enabled or #blobs == 0 then return ev end

    local short = math.min(W, H)
    local blur = clamp(math.floor(o.band_blur), 1, 60)

    -- 每块辉光就是一个大圆 + \blur 模糊边缘。
    -- \blur 是 libass 的边缘模糊，比叠同心圆省事件，也不会有硬边和「云朵」感。
    -- 静态层只渲染一次，模糊开销可以忽略。
    for i = 1, #blobs do
        local b = blobs[i]
        local x, y = b.nx * W, b.ny * H
        local r = b.rr * short
        if r > 3 then
            ev[#ev + 1] = string.format(
                "{\\an7\\pos(0,0)\\p1\\bord0\\shad0\\blur%.1f\\1c%s\\alpha&H%s&}%s",
                blur, bgr(b.col), b.alpha, circle(x, y, r))
        end
    end
    return ev
end

local function star_events()
    local ev = {}
    local groups, order = {}, {}

    for i = 1, #stars do
        local s = stars[i]
        if not s.tw then
            local a = math.floor((1 - clamp(s.b, 0, 1)) * 255 + 0.5)
            local bucket = math.floor(a / 24)
            local key = s.col[1] .. "," .. s.col[2] .. "," .. s.col[3] .. ":" .. bucket
            local g = groups[key]
            if not g then
                g = {
                    col   = bgr(s.col),
                    alpha = clamp(bucket * 24 + 12, 0, 255),
                    parts = {},
                }
                groups[key] = g
                order[#order + 1] = g
            end
            g.parts[#g.parts + 1] = shape(s.nx * W, s.ny * H, s.r)
        end
    end

    for _, g in ipairs(order) do
        ev[#ev + 1] = string.format(
            "{\\an7\\pos(0,0)\\p1\\bord0\\shad0\\1c%s\\alpha&H%02X&}%s",
            g.col, g.alpha, table.concat(g.parts))
    end
    return ev
end

local function build_static()
    if W <= 0 or H <= 0 then return "" end
    local ev = gradient_events()
    for _, e in ipairs(glow_events()) do ev[#ev + 1] = e end
    for _, e in ipairs(star_events()) do ev[#ev + 1] = e end
    return table.concat(ev, "\n")
end

---------------------------------------------------------------------------
-- 动态层
---------------------------------------------------------------------------

local shoot = { active = false, next = 1e9 }

local function reset_shoot(T)
    shoot.active = false
    local base = math.max(0, o.shooting_star_interval)
    shoot.next = T + base * (0.5 + math.random() * 1.2)
end

local function step_shoot(T)
    if not o.shooting_star or o.shooting_star_interval <= 0 then return nil end

    if not shoot.active then
        if T < shoot.next then return nil end
        local dx, dy = -(0.80 + math.random() * 0.15), (0.55 + math.random() * 0.20)
        local norm = math.sqrt(dx * dx + dy * dy)
        shoot.active = true
        shoot.t0   = T
        shoot.dur  = 0.85 + math.random() * 0.55
        shoot.x    = (0.08 + math.random() * 0.86) * W
        shoot.y    = (0.02 + math.random() * 0.30) * H
        shoot.dx   = dx / norm
        shoot.dy   = dy / norm
        shoot.len  = 90 + math.random() * 130
        shoot.trav = 240 + math.random() * 240
        shoot.wd   = 1.8 + math.random() * 1.8
    end

    local p = (T - shoot.t0) / shoot.dur
    if p >= 1 then
        reset_shoot(T)
        return nil
    end

    local d = shoot.trav * p
    local hx, hy = shoot.x + shoot.dx * d, shoot.y + shoot.dy * d
    local tx, ty = hx - shoot.dx * shoot.len, hy - shoot.dy * shoot.len
    local fade = math.min(1, p / 0.12) * (1 - p) ^ 0.7

    return {
        hx = hx, hy = hy, tx = tx, ty = ty,
        px = -shoot.dy * shoot.wd, py = shoot.dx * shoot.wd,
        alpha = clamp(math.floor((1 - fade) * 255 + 0.5), 0, 255),
    }
end

local function build_dyn(T)
    local ev = {}

    for i = 1, #stars do
        local s = stars[i]
        if s.tw then
            local v = s.b + s.tw.amp * math.sin(s.tw.phase + T * o.twinkle_speed * s.tw.spd)
            v = clamp(v, 0.05, 1)
            ev[#ev + 1] = string.format(
                "{\\an7\\pos(0,0)\\p1\\bord0\\shad0\\1c%s\\alpha&H%02X&}%s",
                bgr(s.col), math.floor((1 - v) * 255 + 0.5),
                shape(s.nx * W, s.ny * H, s.r))
        end
    end

    for i = 1, #brights do
        local b = brights[i]
        local v = clamp(0.82 + b.tw.amp * math.sin(b.tw.phase + T * o.twinkle_speed * b.tw.spd), 0.2, 1)
        local x, y = b.nx * W, b.ny * H
        local col = bgr(b.col)

        if o.glow then
            local L = b.r * 5.0
            local w = math.max(0.5, b.r * 0.42)
            local ga = clamp(math.floor((1 - v * 0.5) * 255 + 0.5), 0, 255)
            ev[#ev + 1] = string.format(
                "{\\an7\\pos(0,0)\\p1\\bord0\\shad0\\1c%s\\alpha&H%02X&}" ..
                "m %.2f %.2f l %.2f %.2f l %.2f %.2f l %.2f %.2f",
                col, ga, x - L, y, x, y - w, x + L, y, x, y + w)
            ev[#ev + 1] = string.format(
                "{\\an7\\pos(0,0)\\p1\\bord0\\shad0\\1c%s\\alpha&H%02X&}" ..
                "m %.2f %.2f l %.2f %.2f l %.2f %.2f l %.2f %.2f",
                col, ga, x, y - L, x + w, y, x, y + L, x - w, y)
        end

        ev[#ev + 1] = string.format(
            "{\\an7\\pos(0,0)\\p1\\bord0\\shad0\\1c%s\\alpha&H%02X&}%s",
            col, clamp(math.floor((1 - v) * 255 + 0.5) - 40, 0, 255), circle(x, y, b.r))
    end

    local sh = step_shoot(T)
    if sh then
        local col = bgr(parse_hex(o.shooting_star_color))
        -- 尾巴比头细，做出锥形拖尾；再叠一点 \blur 去掉硬边
        ev[#ev + 1] = string.format(
            "{\\an7\\pos(0,0)\\p1\\bord0\\shad0\\blur2.2\\1c%s\\alpha&H%02X&}" ..
            "m %.2f %.2f l %.2f %.2f l %.2f %.2f",
            col, sh.alpha,
            sh.hx + sh.px, sh.hy + sh.py,
            sh.tx, sh.ty,
            sh.hx - sh.px, sh.hy - sh.py)
    end

    return table.concat(ev, "\n")
end

---------------------------------------------------------------------------
-- 叠加层与生命周期
---------------------------------------------------------------------------

local ov_static = mp.create_osd_overlay("ass-events")
local ov_dyn    = mp.create_osd_overlay("ass-events")
ov_static.z = 1
ov_dyn.z    = 2

local timer, running, T = nil, false, 0
local interval = 1 / clamp(o.fps, 1, 60)

local function dims()
    local d = mp.get_property_native("osd-dimensions")
    if d and d.w and d.h and d.w > 0 and d.h > 0 then
        return math.floor(d.w), math.floor(d.h)
    end
    return 0, 0
end

local function rebuild()
    local w, h = dims()
    if w == 0 then return false end
    W, H = w, h
    ov_static.res_x, ov_static.res_y = W, H
    ov_dyn.res_x,    ov_dyn.res_y    = W, H
    ov_static.data = build_static()
    ov_static:update()
    return true
end

local function tick()
    if not running then return end
    T = T + interval
    ov_dyn.data = build_dyn(T)
    ov_dyn:update()
end

local start, stop

function start()
    if running or not o.enabled then return end
    if not rebuild() then return end
    running = true
    T = 0
    reset_shoot(T)
    shoot.next = 2 + math.random() * 4
    tick()
    timer = mp.add_periodic_timer(interval, tick)
end

function stop()
    running = false
    if timer then
        timer:kill()
        timer = nil
    end
    ov_static:remove()
    ov_dyn:remove()
end

mp.observe_property("idle-active", "bool", function(_, v)
    if v then start() else stop() end
end)

mp.observe_property("osd-dimensions", "native", function()
    if running then
        rebuild()
        tick()
    elseif mp.get_property_native("idle-active") then
        start()
    end
end)

local function reload()
    opts.read_options(o, 'idle_starry')
    interval = 1 / clamp(o.fps, 1, 60)
    stop()
    gen_pattern()
    if o.enabled and mp.get_property_native("idle-active") then
        start()
    end
    msg.info("reloaded")
end

mp.add_key_binding("Ctrl+alt+i", "reload", reload)
mp.register_script_message("reload", reload)

gen_pattern()
if mp.get_property_native("idle-active") then
    start()
end
