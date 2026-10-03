# 拾光日记 · Dayfolio

一款原生 macOS 日记软件。以三栏布局整理记录，在富文本编辑器中写作，把照片、文档、音频和视频收进日记，随时导出。

## 使用

需要 macOS 14 或更新版本。项目不依赖第三方库，不需要服务器或账号。

```bash
./scripts/build-app.sh
open dist/Dayfolio.app
```

构建需要 Apple Command Line Tools：`xcode-select --install`。也可以使用完整 Xcode。构建脚本生成本机架构的应用和 ZIP 包；Apple Silicon Mac 生成 arm64，Intel Mac 生成 x86_64。应用使用本地临时签名，尚未经过 Apple 公证。

## 已实现

- 日记新增、删除、收藏、标题、标签、心情；全部 / 今天 / 收藏筛选；搜索标题、正文、标签。
- 原生富文本编辑、撤销 / 重做、字体、字号、文字颜色、粗体、斜体、下划线；自然、暖纸和浅绿纸张背景。
- 字符统计（含 / 不含空白）、中日韩字与西文字词统计、段落和估算阅读时间；累计字数。
- 日记日期与时间可修改，创建时间和最后修改时间自动记录。
- 记录累计写作时长：编辑器获得焦点、应用处于前台且最近 30 秒内有输入时计时；闲置、切换应用或日记后暂停。不是键盘输入秒数的精确测量。
- 文本更改 0.6 秒后自动保存，退出前保存；计时期间每约 10 秒保存。
- 菜单 / 按钮 / 拖放导入文件；图片缩略图、素材打开、图片插入正文、附件移除。
- 完整备份与恢复。导入时遇到重复日记 ID 会建立副本，避免覆盖已有内容。

## 导入与导出

| 格式 | 导入 | 导出 |
| --- | --- | --- |
| TXT | UTF-8 / UTF-16 文本 | 正文与日期、时间等元信息 |
| Markdown | 源文本，不自动渲染 Markdown | 标题、正文、元信息、附件名称 |
| HTML | 原生富文本转换 | 保留文字样式，图片内嵌，附带素材下载链接 |
| RTF | 原生富文本 | 文字样式和元信息 |
| Word DOCX | 原生富文本转换 | 文字样式和元信息 |
| PDF | 提取可选中的文字，同时保留原 PDF 附件 | A4 分页文字，图片作为后续独立页面 |
| JSON / `.dayfolio` | Dayfolio 专用归档 | 保留日记、富文本、全部素材与时间信息 |
| 图片 / 音频 / 视频 / 其他文件 | 添加为当前日记的素材 | 完整保存于 JSON / `.dayfolio` 备份 |

复杂 Word / HTML 排版不保证原样转换。扫描 PDF 没有文字识别功能。RTF / DOCX 不作为附件备份格式；TXT / Markdown 仅列出附件名称。HTML 将图片附在正文后，内嵌图片的正文位置以提示代替。PDF 图片附页可能同时包含正文图片与素材区图片。需要完整恢复时，使用 **完整备份**。

单次素材导入文件上限 50 MB，一篇日记附件总量上限 300 MB，JSON / Dayfolio 归档导入上限 1 GB。所有附件保存在归档中，不依赖原文件路径。

## 数据位置

默认：`~/Library/Application Support/Dayfolio/journal.json`。侧边栏有“本机数据目录”按钮。保存采用原子写入，并保留上一版 `journal.json.previous`。如果原文件读取失败，应用暂停写入，避免覆盖；可退出后用上一版恢复。

日记以未加密的本地文件保存，应用不会上传内容。公开的 GitHub 仓库仅存源码。打开附件时，会在系统临时目录 `Dayfolio-Preview` 创建预览副本。完整备份中包含正文与附件，请将备份存放在你信任的位置。

可以通过 `DAYFOLIO_DATA_DIR` 指定独立数据目录，用于测试或便携使用：

```bash
DAYFOLIO_DATA_DIR=/tmp/dayfolio-demo dist/Dayfolio.app/Contents/MacOS/Dayfolio
```

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| ⌘N | 新建日记 |
| ⌘I | 导入文档或素材 |
| ⌘S | 立即保存 |
| ⌘⇧B | 导出完整备份 |
| ⌘Z / ⌘⇧Z | 正文撤销 / 重做 |

文字样式按钮作用于选中的文本；没有选中文字时，设置之后输入的文字样式。

## 开发与验证

```bash
./scripts/swift.sh build
./scripts/swift.sh run DiaryCoreChecks
./scripts/swift.sh run Dayfolio --self-test
./scripts/build-app.sh
```

核心测试覆盖混合文字统计、包含附件的备份往返、原子保存及上一版恢复、无效归档校验、导入副本、HTML 转义和损坏存储保护。测试使用独立可执行程序，不依赖完整 Xcode 的 XCTest 框架。`--self-test` 验证七种导出格式、中文、内嵌图片、PDF 分页、Word / RTF 重新读取与 JSON 往返。GitHub Actions 在 macOS 构建和测试，并提供应用 ZIP 构建产物。

结构：`DiaryCore` 管理模型、统计和归档；`Dayfolio` 使用 SwiftUI / AppKit 构建界面与富文本编辑器，CoreText / PDFKit 处理 PDF。

MIT License。
