# 第三方声明

本游戏以 Godot Engine 4.7.2 构建并分发。程序化生成的占位美术与音频为本项目原创，可自由替换或用于正式素材。

---

## 1. Godot Engine

Copyright © 2014-present Godot Engine contributors.
Copyright © 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## 2. WenQuanYi Zen Hei 字体

`assets/fonts/ui.ttc` 为 WenQuanYi Zen Hei（文泉驿正黑），随游戏分发。

- 版权：2007-2009 Qianqian Fang 与 The WenQuanYi Project Board of Trustees；1998-2004 Koanughi Un；
  1999-2004 Tsong-Min Wu、Tsong-Huey Wu；2005 Tsong-Min Wu、Tsong-Huey Wu、Edward G.J. Lee；
  2004 Firefly；2002-2008 M+ FONTS PROJECT
- 许可：**GPL-2 with Font embedding exception** 与 M+ FONTS License
- 上游：<http://wenq.org/>
- 完整许可文本：`licenses/WenQuanYi-ZenHei.txt`

字体嵌入例外允许在文档/应用中嵌入该字体而不使应用整体受 GPL 约束；本游戏按此分发未修改的字体文件。
如果你需要替换字体，请同时替换此许可文件。

---

## 3. 美术与音频

- `assets/world/*.png`、`assets/ui/*.png`：由本项目的 Python 脚本（PIL + numpy）程序化生成；
- `assets/audio/*.wav`：由本项目的 `tools/gen_audio.py`（numpy 合成）生成；
- 均为**占位素材**，不含任何第三方图片、采样或音源。你可以直接替换为正式美术/音频，
  替换后的素材版权由你自行确认。

---

## 4. 设计文档

游戏按《Escape Gravity（暂定名）设计文档》实现；该文档由项目方提供，不属于本仓库的第三方依赖。

---

## 5. 构建工具（不随游戏分发）

构建时使用 Godot 导出模板、OpenJDK 17（Temurin）、Android SDK/Build-Tools。
这些工具不包含在游戏的 `dist/` 包中；其许可分别遵循各自项目。
