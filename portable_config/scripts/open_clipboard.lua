--[[

  open_clipboard.lua

  从系统剪贴板取一个文件路径并打开。

  为什么不用 mpv 内置菜单里那条一行命令？
  内置写法是：
      update-clipboard text; loadfile ${clipboard/text}; show-text '+ ${clipboard/text}'
  它有三个实测问题：

  1) 剪贴板里没有文本时（资源管理器 Ctrl+C 复制文件、或剪贴板本来就是空的），
     ${clipboard/text} 会展开成字面量 (error)，于是 loadfile 去开一个叫
     "(error)" 的文件。失败后不会回退，当前正在播的视频被直接卸载，
     画面回到空闲状态，进度丢失。

  2) Windows「复制文件地址」得到的文本带一对半角双引号，例如
     "D:\video\a b.mkv"
     引号被当成路径的一部分，同样导致打开失败并中断播放。

  3) 复制的是文件夹或一段普通文字时，也是一样地中断播放。

  本脚本的做法：先校验，校验不过就只弹提示，绝不动当前播放。

  用法（menu.conf 里）：
      从剪贴板打开    script-binding open_clipboard/open
  input.conf 也可以绑，例如：
      Ctrl+v          script-binding open_clipboard/open

--]]

local mp    = require "mp"
local msg   = require "mp.msg"
local utils = require "mp.utils"

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 去掉 Windows「复制文件地址」带上的外层引号，以及 file:// 前缀
local function unquote(s)
    s = trim(s)

    local first, last = s:sub(1, 1), s:sub(-1)
    if (first == '"' and last == '"') or (first == "'" and last == "'") then
        s = s:sub(2, -2)
    end

    s = s:gsub("^file:///", "")
    s = s:gsub("^file://", "")

    return trim(s)
end

-- 剪贴板里可能是多行，只取第一行
local function first_line(s)
    return trim(s:match("^[^\r\n]*") or s)
end

local function open_from_clipboard()
    -- 让 mpv 去读一次系统剪贴板。这个命令是异步的，
    -- 属性不会立刻更新，所以下面要等一个 tick 再取值。
    mp.commandv("update-clipboard", "text")

    mp.add_timeout(0.08, function()
        local raw  = mp.get_property("clipboard/text", "")
        local path = first_line(unquote(raw))

        if path == "" or path == "(error)" then
            mp.osd_message("剪贴板里没有可打开的文件地址", 3)
            msg.info("clipboard has no text")
            return
        end

        local info = utils.file_info(path)
        if not info then
            mp.osd_message("剪贴板内容不是有效路径：\n" .. path, 4)
            msg.warn("not a valid path: " .. path)
            return
        end

        if info.is_dir then
            mp.osd_message("这是文件夹，不是可播放的文件：\n" .. path, 4)
            msg.warn("path is a directory: " .. path)
            return
        end

        msg.info("loading " .. path)
        mp.commandv("loadfile", path)
        mp.osd_message("+ " .. path, 3)
    end)
end

mp.add_key_binding(nil, "open", open_from_clipboard)
