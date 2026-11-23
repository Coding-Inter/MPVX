<div align="center">

# 🎬 MPVX

**基于官方 mpv 的中文便携播放器**

开箱即用 · 现代界面 · 智能跳过片头片尾 · 一键着色器

</div>

---

## ✨ 特性

- 🀄 **全中文界面** —— OSC 控制栏、统计面板、右键菜单全部汉化
- 🖥️ **现代 OSC** —— 基于 [ModernZ](https://github.com/Samillion/ModernZ)，进度条支持彩色片段高亮
- ⏭️ **智能跳过** —— 接入 [TheIntroDB](https://theintrodb.org/)，自动识别并跳过片头 / 前情回顾 / 片尾 / 预告
- 🎨 **着色器一键切换** —— 内置 Anime4K、FSRCNNX、AMD FSR、去色带等 20+ 着色器，右键即开即关
- ⚡ **预设组** —— 插帧、补帧、省电、高画质，一键套用；HDR / 低码率 / 变速等场景自动适配
- 📋 **右键菜单** —— 播放控制、轨道切换、着色器、预设、工具一应俱全

---

## 🚀 快速开始

> MPVX 是 mpv 的**便携版配置**，`mpv.exe` 本身是官方原版，仓库不随附。

1. 从 [mpv.io](https://mpv.io/installation/) 下载 Windows 版 mpv，把 `mpv.exe` 放到项目根目录
2. 打开 `portable_config\script-opts\theintrodb.conf.example`，复制为 `theintrodb.conf` 并填入自己的 [API Key](https://theintrodb.org/)
3. 双击 `mpv.exe`，或把视频文件拖到窗口上即可播放

> 可选：双击 `mpv-register.bat` 将 mpv 注册到右键菜单「打开方式」。

---

## 📁 目录结构

```
MPVX/
├── mpv.exe                     # 官方原版（需自行放置，不随仓库）
├── mpv-register.bat            # 注册到系统右键菜单
├── mpv-unregister.bat          # 取消注册
└── portable_config/            # 便携配置目录
    ├── mpv.conf                # 主配置
    ├── profiles.conf           # 预设组
    ├── input.conf              # 快捷键
    ├── menu.conf               # 右键菜单（中文）
    ├── script-opts/            # 脚本选项
    │   ├── modernz.conf        # OSC 界面与配色
    │   └── theintrodb.conf     # 跳过脚本配置（含密钥，不入库）
    ├── scripts/                # 脚本
    │   ├── modernz.lua         # OSC 控制栏（中文 + 彩色片段）
    │   ├── theintrodb.lua      # 片头片尾跳过
    │   ├── stats.lua           # 统计面板（中文）
    │   ├── open_clipboard.lua  # 从剪贴板打开
    │   ├── autoload.lua        # 自动加载目录
    │   ├── pip_lite.lua        # 画中画
    │   └── thumbfast.lua       # 进度条缩略图
    └── shaders/                # 着色器库
```

---

## 🎛️ 核心功能

### 现代 OSC 界面

默认关闭 mpv 内置 OSC，改用汉化的 [ModernZ](https://github.com/Samillion/ModernZ)。界面语言、布局、图标、配色均可在 `modernz.conf` 中调整。

进度条支持**彩色片段高亮**：片头、前情回顾、片尾、预告分别以不同颜色标注，一眼看清影片结构。

| 片段 | 默认配色 |
| ---- | -------- |
| 片头 | 🔵 蓝 `#4FA3FF` |
| 前情回顾 | 🟡 黄 `#F2D25C` |
| 片尾 | 🟣 紫 `#8C5BC7` |
| 预告 | 🟢 薄荷 `#7FE3A0` |

### 片头片尾智能跳过

接入 [TheIntroDB](https://theintrodb.org/) 数据库，播放时自动获取片头 / 前情回顾 / 片尾 / 预告的时间段，支持：

- **自动跳过**片头与前情回顾（可开关）
- **手动跳过**任意片段
- **屏幕按钮栏**（可切换显示）

### 着色器一键切换

内置 20+ 着色器，右键菜单 → `视频` → `着色器` 即时切换，无需重启：

- **放大**：FSRCNNX、nnedi3、CuNNy、AMD FSR
- **动漫**：Anime4K 全系（去噪 / 修复 / 放大 / 一体化）
- **降噪 / 去色带**：非局部均值、hdeband
- **锐化**：自适应锐化、QCOM、FSR RCAS

### 预设组

在 `profiles.conf` 中定义，右键菜单 → `预设` 一键套用：

| 预设 | 作用 |
| ---- | ---- |
| `interp` | 插帧，平滑运动 |
| `film` | 补帧，24fps 整数倍插值 |
| `hq` | 高画质，进一步提升缩放质量 |
| `battery` | 省电，降低 GPU 开销 |

另有**自动预设**按条件触发：HDR 片源、低码率、变速播放、已看 90% 等场景自动适配。

---

## ⌨️ 快捷键

| 按键 | 功能 |
| ---- | ---- |
| `Alt`+`i` | 跳过片头 |
| `Alt`+`r` | 跳过前情回顾 |
| `Alt`+`u` | 跳过片尾 |
| `n` | 跳到下一片段 |
| `Ctrl`+`Alt`+`i` | 切换跳过按钮栏 |
| `Alt`+`a` | 切换自动跳过 |
| `1`–`5` | 统计面板页面切换（面板内） |

> 统计面板可通过右键菜单 → `查看` → `播放统计信息` 打开。

---

## 🌿 分支

| 分支 | 用途 |
| ---- | ---- |
| `main` | 稳定版本 |
| `dev` | 实验开发，新功能先在此分支 |

---

## 🙏 致谢

- [mpv](https://mpv.io/) —— 播放器核心
- [ModernZ](https://github.com/Samillion/ModernZ) —— OSC 界面
- [mpv-stats](https://github.com/Argon-/mpv-stats) —— 统计面板
- [TheIntroDB](https://theintrodb.org/) —— 片头片尾数据库
- [Anime4K](https://github.com/bloc97/Anime4K) 等 —— 着色器

---

<div align="center">

<sub>MIT License · 仅供学习研究</sub>

</div>
