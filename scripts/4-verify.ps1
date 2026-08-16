# ============================================================
# 4-verify.ps1 — 环境检测工具（循环菜单）
# 功能：按需检测（1-8 单项/组合/全部）+ 每项原理说明 + 退出
# 用法：双击运行（菜单循环，[0] 退出；[9] 或回车 = 全部检测）
#       或参数一次执行：-Only "1,4,7"
# 原则：每一项检测都标注【目的】——这项配置是干嘛的、为什么重要
# ============================================================
param([string]$Only = "")

$ErrorActionPreference = "Continue"
$pass = 0; $fail = 0

# Check：name=检测名  ok=结果  detail=失败时的修复提示  why=目的说明
function Check([string]$name, [bool]$ok, [string]$detail = "", [string]$why = "") {
    if ($ok) { Write-Host "  [PASS] $name" -ForegroundColor Green; $script:pass++ }
    else     { Write-Host "  [FAIL] $name  $detail" -ForegroundColor Red; $script:fail++ }
    if ($why) { Write-Host ("          目的：{0}" -f $why) -ForegroundColor DarkGray }
}

# ---------------- Keil 安装目录查询（与 2-setup 同一套逻辑） ----------------
function Get-KeilPaths {
    $r = @{ C51 = $null; MDK = $null; GNU = $null }
    $settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
    if (Test-Path $settingsPath) {
        $s = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($s.'EIDE.C51.INI.Path') {
            $ini = $s.'EIDE.C51.INI.Path'
            if ($ini -match "TOOLS\.INI$" -and (Test-Path $ini)) {
                $line = Select-String -Path $ini -Pattern '^PATH="([^"]+)"' | Select-Object -First 1
                if ($line) { $r.C51 = Join-Path ($line.Matches[0].Groups[1].Value.TrimEnd('\')) "INC" }
            } elseif ($ini -match "UV4\.exe$" -and (Test-Path $ini)) {
                $r.C51 = Join-Path (Split-Path (Split-Path $ini -Parent) -Parent) "C51\INC"
            }
        }
        if ($s.'EIDE.ARM.INI.Path') {
            $ini = $s.'EIDE.ARM.INI.Path'
            if ($ini -match "TOOLS\.INI$" -and (Test-Path $ini)) {
                $line = Select-String -Path $ini -Pattern '^PATH="([^"]+)"' | Select-Object -First 1
                if ($line) { $r.MDK = Split-Path ($line.Matches[0].Groups[1].Value.TrimEnd('\')) -Parent }
            }
        }
    }
    $bases = @("D:\Keil5", "C:\Keil_v5", "C:\Keil", "D:\Keil", "E:\Keil5", "D:\Keil5_x")
    if (-not $r.C51) {
        foreach ($b in $bases) {
            if (Test-Path (Join-Path $b "C51\C51\BIN\C51.exe")) { $r.C51 = Join-Path $b "C51\C51\INC"; break }
        }
    }
    if (-not $r.MDK) {
        foreach ($b in $bases) {
            if (Test-Path (Join-Path $b "MDK\ARM\ARMCLANG\bin\armclang.exe")) { $r.MDK = $b; break }
        }
    }
    if (-not $r.GNU) {
        $g = Get-ChildItem "C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi" -Directory -ErrorAction SilentlyContinue |
             Sort-Object Name -Descending | Select-Object -First 1
        if ($g) { $r.GNU = $g.FullName }
    }
    return $r
}

# ---------------- 各检测项 ----------------
function Run-Section([int]$id) {
    switch ($id) {

        1 {
            Write-Host ""
            Write-Host "============== 1. 扩展（13 个）==============" -ForegroundColor Cyan
            Write-Host "  原理：扩展装好后在 %USERPROFILE%\.vscode\extensions\ 生成同名文件夹，" -ForegroundColor DarkGray
            Write-Host "        检查文件夹是否存在即判定安装状态。" -ForegroundColor DarkGray
            $extDir = Join-Path $env:USERPROFILE ".vscode\extensions"
            # 每个扩展的【用途 + 缺失后果】，why 列在检测行下方
            $map = @{
                "cl.eide" = @{ use = "编译/烧录中枢"; why = "51/STM32 工程的编译、烧录全靠它，缺失则无法构建下载" }
                "llvm-vs-code-extensions.vscode-clangd" = @{ use = "代码补全/跳转/诊断"; why = "唯一的代码智能引擎，缺失则补全跳转全部失效" }
                "ms-vscode.vscode-serial-monitor" = @{ use = "串口调试"; why = "51 没有断点调试，printf 输出全靠串口监视器" }
                "ms-ceintl.vscode-language-pack-zh-hans" = @{ use = "界面中文化"; why = "英文界面不影响功能，只是看得费劲" }
                "zhuangtongfa.material-theme" = @{ use = "One Dark Pro 主题"; why = "缺失时回退默认主题，不影响功能" }
                "pkief.material-icon-theme" = @{ use = "文件图标"; why = "缺失时回退默认图标，不影响功能" }
                "usernamehw.errorlens" = @{ use = "错误行内显示"; why = "报错直接标在代码行尾，不用切输出面板" }
                "christian-kohler.path-intellisense" = @{ use = "#include 路径补全"; why = "敲 #include 时自动补路径，省去手敲易错" }
                "intellsmi.comment-translate" = @{ use = "英文注释翻译"; why = "看 Keil/STM32 英文头文件注释必备" }
                "mhutchie.git-graph" = @{ use = "Git 历史可视化"; why = "提交历史图形化，学 Git 必备" }
                "ms-python.python" = @{ use = "Python 支持"; why = "上位机/数据分析用；stcgal 也依赖 Python" }
                "alefragnani.project-manager" = @{ use = "多工程切换"; why = "51/STM32/实验工程一键切换，不用反复打开文件夹" }
                "bierner.markdown-preview-github-styles" = @{ use = "Markdown 预览样式"; why = "笔记预览套 GitHub 样式，更好看" }
            }
            foreach ($e in $map.Keys) {
                Check ("扩展 {0}（{1}）" -f $e, $map[$e].use) (Test-Path (Join-Path $extDir "$e*")) "运行 1-安装扩展.bat" $map[$e].why
            }
        }

        2 {
            Write-Host ""
            Write-Host "============== 2. 用户设置 ==============" -ForegroundColor Cyan
            Write-Host "  原理：检查 settings.json 关键键值是否符合推荐配置。" -ForegroundColor DarkGray
            $settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
            if (Test-Path $settingsPath) {
                $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                Check "files.autoGuessEncoding = true" ($settings.'files.autoGuessEncoding' -eq $true) "设置为 true" "打开文件自动识别编码，GBK/UTF-8 都不乱码"
                Check "clangd.arguments 已配" ($null -ne $settings.'clangd.arguments') "补充 clangd.arguments" "clangd 启动参数（不自动插#include、后台索引提速）"
                Check "editor.renderWhitespace = all" ($settings.'editor.renderWhitespace' -eq "all") "设置为 all" "空格显示为点、Tab 为箭头，缩进一眼看清"
                Check "chat.disableAIFeatures = true" ($settings.'chat.disableAIFeatures' -eq $true) "设置为 true" "关闭 VSCode 内置 AI，界面干净、不干扰"
                Check "EIDE.DisplayLanguage = zh-cn" ($settings.'EIDE.DisplayLanguage' -eq "zh-cn") "设置为 zh-cn" "EIDE 插件界面中文化"
                Check "EIDE.Option.EnableClangdConfigGenerator = false" ($settings.'EIDE.Option.EnableClangdConfigGenerator' -eq $false) "设置为 false" "防止 EIDE 自动生成 .clangd 覆盖手写配置"
                Check "文件/文件夹 单击选中双击打开" (($settings.'workbench.list.openMode' -eq "doubleClick") -and ($settings.'workbench.tree.expandMode' -eq "doubleClick")) "设置为 doubleClick" "资源管理器单击只选中、双击才打开/展开，避免误触"
            } else { Check "settings.json 存在" $false "未找到 $settingsPath" "VSCode 用户设置文件，所有全局配置的载体" }
        }

        3 {
            Write-Host ""
            Write-Host "============== 3. 快捷键 ==============" -ForegroundColor Cyan
            Write-Host "  原理：手动格式化快捷键写在 keybindings.json，检查是否含 Ctrl+Alt+L。" -ForegroundColor DarkGray
            $kbPath = Join-Path $env:APPDATA "Code\User\keybindings.json"
            if (Test-Path $kbPath) {
                $kb = Get-Content $kbPath -Raw -Encoding UTF8
                Check "Ctrl+Alt+L 格式化" ($kb -match "ctrl\+alt\+l") "加入该绑定" "手动格式化快捷键（C 文件关闭了自动格式化，靠它）"
            } else { Check "keybindings.json 存在" $false "未找到 $kbPath" "快捷键绑定的存放文件" }
        }

        4 {
            Write-Host ""
            Write-Host "============== 4. 全局 clangd 配置 ==============" -ForegroundColor Cyan
            Write-Host "  原理：clangd 在 Windows 固定读取 %LOCALAPPDATA%\clangd\config.yaml，" -ForegroundColor DarkGray
            Write-Host "        注意：现在每个工程都有自足的 .clangd，此项是可选兜底，" -ForegroundColor DarkGray
            Write-Host "        缺失不影响任何已配好的工程（只有没放 .clangd 的工程才受影响）。" -ForegroundColor DarkGray
            $gcfg = Join-Path $env:LOCALAPPDATA "clangd\config.yaml"
            $ok = Test-Path $gcfg
            Check "config.yaml 存在（可选兜底）" $ok "运行 2-自动配置.bat 生成（可跳过）" "工程 .clangd 已自足；此项仅兜底，缺失无碍"
            if ($ok) {
                $c = Get-Content $gcfg -Raw -Encoding UTF8
                Check "包含 PathMatch 匹配条件" ($c -match "PathMatch") "补 PathMatch" "只对路径含 C51 的工程生效，防止宏污染 STM32"
                Check "包含 Keil 头文件 -I 路径" ($c -match "-I") "补 -I 路径" "找不到 Keil 头文件会报错成片、补全全废"
                Check "包含 Suppress 抑制清单" ($c -match "Suppress") "补 Suppress" "隐藏 sbit/interrupt 等 C51 语法误报"
                Check "包含 ferror-limit=100" ($c -match "ferror-limit") "补 ferror-limit" "被隐藏的误报仍计数，默认上限 19 会被 REG52.H 打爆"
            }
        }

        5 {
            Write-Host ""
            Write-Host "============== 5. 工具链 ==============" -ForegroundColor Cyan
            Write-Host "  原理：Python/stcgal/Git 装好后在 PATH 留下命令，能查到即已安装。" -ForegroundColor DarkGray
            $py = Get-Command python -ErrorAction SilentlyContinue
            Check "Python" ($null -ne $py) "winget install Python.Python.3.12（装完重开终端）" "stcgal 的运行环境，没有它无法一键烧录"
            $stc = Get-Command stcgal -ErrorAction SilentlyContinue
            Check "stcgal" ($null -ne $stc) "pip install stcgal" "STC 芯片一键烧录工具（EIDE 内置烧录器依赖）"
            $gt = Get-Command git -ErrorAction SilentlyContinue
            Check "Git" ($null -ne $gt) "winget install Git.Git" "项目版本管理与跨机器同步"
        }

        6 {
            Write-Host ""
            Write-Host "============== 6. Keil 路径（自动查询）==============" -ForegroundColor Cyan
            Write-Host "  原理：从 EIDE 设置（TOOLS.INI 的 [C51] PATH / UV4.exe 目录推导）" -ForegroundColor DarkGray
            Write-Host "        或扫 6 个常见位置，最后验证编译器真实存在。" -ForegroundColor DarkGray
            $paths = Get-KeilPaths
            $keilInc = $paths.C51
            if (-not $keilInc) { $keilInc = "D:\Keil5\C51\C51\INC" }
            Check "Keil C51 INC 目录 ($keilInc)" (Test-Path $keilInc) "装 Keil 或运行 2-自动配置" "Keil 头文件目录（REGX52.H 等），找不到则 clangd 全报错"
            $c51exe = Join-Path (Split-Path $keilInc -Parent) "BIN\C51.exe"
            Check "C51.exe ($c51exe)" (Test-Path $c51exe) "检查 Keil C51 安装" "51 编译器本体，EIDE 编译/烧录依赖"
            if ($paths.MDK) { Check "Keil MDK ($($paths.MDK))" $true "" "STM32 编译器（armclang），大二阶段用" }
            else { Check "Keil MDK" $false "未检测到 MDK（STM32 阶段才需要）" "STM32 编译器，现在没有不影响 51" }
            if ($paths.GNU) { Check "GNU Arm 工具链 ($($paths.GNU))" $true "" "可选的 ARM GCC 编译器，没有可让 EIDE 自动下载" }
            else { Write-Host "  [SKIP] GNU Arm（可选，未安装）" -ForegroundColor Yellow }
            $script:keilInc = $keilInc
            $script:c51exe = $c51exe
        }

        7 {
            Write-Host ""
            Write-Host "============== 7. clangd 代码检测 ==============" -ForegroundColor Cyan
            Write-Host "  原理：clangd --check 分析 C51检测工程\main.c——该文件故意包含" -ForegroundColor DarkGray
            Write-Host "        sbit/_at_/interrupt/stdio 全部疑难语法，0 诊断 = 配置全生效。" -ForegroundColor DarkGray
            if (-not $script:keilInc) { $paths = Get-KeilPaths; $script:keilInc = $paths.C51; if (-not $script:keilInc) { $script:keilInc = "D:\Keil5\C51\C51\INC" } }
            $proj = Join-Path $PSScriptRoot "..\C51检测工程"
            # 按检测到的 Keil 路径重新生成检测工程的 .clangd（换机器也能测）
            $clangdCfg = @"
CompileFlags:
  Add:
    - -ferror-limit=100
    - -D__C51__
    - -D__VSCODE_C51__
    - -Dreentrant=
    - -Dcompact=
    - -Dsmall=
    - -Dlarge=
    - -Ddata=
    - -Didata=
    - -Dpdata=
    - -Dbdata=
    - -Dxdata=
    - -Dcode=
    - -Dbit=char
    - -Dsbit=char
    - -Dsfr=char
    - -Dsfr16=int
    - -Dsfr32=int
    - -Dinterrupt(x)=
    - -Dusing(x)=
    - -D_at_(x)=
    - -D_priority_(x)=
    - -D_task_(x)=
    - -I$($script:keilInc)\Atmel
    - -I$($script:keilInc)
  Remove: []
Diagnostics:
  Suppress:
    - init_element_not_constant
    - redefinition_different_typedef
    - expected_fn_body
    - invalid_token_after_toplevel_declarator
"@
            [System.IO.File]::WriteAllText((Join-Path $proj ".clangd"), $clangdCfg, [System.Text.UTF8Encoding]::new($false))

            $clangd = $null
            $settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
            if (Test-Path $settingsPath) {
                $s = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($s.'clangd.path' -and (Test-Path $s.'clangd.path')) { $clangd = $s.'clangd.path' }
            }
            if (-not $clangd) {
                $glob = Get-ChildItem (Join-Path $env:APPDATA "Code\User\globalStorage\llvm-vs-code-extensions.vscode-clangd\install") -Recurse -Filter "clangd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($glob) { $clangd = $glob.FullName }
            }
            if (-not $clangd) { $clangd = (Get-Command clangd -ErrorAction SilentlyContinue).Source }
            Check "找到 clangd 本体" ($null -ne $clangd) "检查 clangd.path 设置或扩展是否安装" "clangd 程序本体，没有它代码分析无法进行"
            if ($clangd) {
                $out = & $clangd --check=(Join-Path $proj "main.c") 2>&1
                $diag = @($out | Select-String -Pattern "^[EW]\[")
                Check "clangd 检测工程 0 诊断" ($diag.Count -eq 0) "仍有 $($diag.Count) 条" "疑难语法文件零报错 = 宏定义/头文件路径/抑制清单全部生效"
                $diag | Select-Object -First 3 | ForEach-Object { Write-Host "     $_" -ForegroundColor Yellow }
            }
        }

        8 {
            Write-Host ""
            Write-Host "============== 8. Keil 编译检测 ==============" -ForegroundColor Cyan
            Write-Host "  原理：直接调用 C51.exe 真实编译检测工程 main.c（0 错误=通过），" -ForegroundColor DarkGray
            Write-Host "        比 clangd 更严格（真实工具链全链路；只编译不链接）。" -ForegroundColor DarkGray
            if (-not $script:c51exe) { $paths = Get-KeilPaths; $script:keilInc = $paths.C51; if (-not $script:keilInc) { $script:keilInc = "D:\Keil5\C51\C51\INC" }; $script:c51exe = Join-Path (Split-Path $script:keilInc -Parent) "BIN\C51.exe" }
            $proj = Join-Path $PSScriptRoot "..\C51检测工程"
            if (Test-Path $script:c51exe) {
                $comp = & $script:c51exe (Join-Path $proj "main.c") 'OMF2' 'TABS(4)' 'CODE' 'NOCOND' 'SYMBOLS' "INCDIR($($script:keilInc)\Atmel;$($script:keilInc))" 'DEFINE(__UVISION_VERSION=526)' 'OPTIMIZE(8,SPEED)' 'SMALL' 'ROM(LARGE)' 2>&1 | Out-String
                Check "Keil 编译 0 错误" ($comp -match "0 ERROR") "见上方编译输出" "真实工具链验证：编译器+头文件+语法全链路通过才算环境就绪"
                if ($comp -notmatch "0 ERROR") { Write-Host $comp.Substring([Math]::Max(0, $comp.Length - 300)) -ForegroundColor Yellow }
            } else { Check "Keil 编译 0 错误" $false "未找到 C51.exe" "编译器不存在则无法验证编译链路" }
        }

        default { Write-Host "  未知检测项编号: $id（可用 1-8）" -ForegroundColor Yellow }
    }
}

# ---------------- 汇总 ----------------
function Show-Summary {
    Write-Host ""
    Write-Host "============ 结果：PASS=$pass  FAIL=$fail ============" -ForegroundColor Cyan
    if ($fail -eq 0) { Write-Host "  所选检测项全部通过！" -ForegroundColor Green }
    else { Write-Host "  有 $fail 项未通过，对照《开发环境重建指南.md》修复后重跑" -ForegroundColor Red }
}

# ---------------- 参数模式 ----------------
if ($Only) {
    $ids = @($Only -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { [int]$_ })
    foreach ($id in $ids) { Run-Section $id }
    Show-Summary
    exit
}

# ---------------- 菜单循环 ----------------
:menu while ($true) {
    $pass = 0; $fail = 0
    Write-Host ""
    Write-Host "==================== 环境检测工具 ====================" -ForegroundColor Cyan
    Write-Host "  [1] 扩展（13 个扩展的安装状态 + 各自用途）"
    Write-Host "  [2] 用户设置（每项关键配置 + 目的说明）"
    Write-Host "  [3] 快捷键（Ctrl+Alt+L 手动格式化）"
    Write-Host "  [4] 全局 clangd 配置（四个关键段 + 各自作用）"
    Write-Host "  [5] 工具链（python/stcgal/git + 各自用途）"
    Write-Host "  [6] Keil 路径（C51/MDK 编译器验证 + 用途）"
    Write-Host "  [7] clangd 代码检测（疑难语法文件 0 诊断）"
    Write-Host "  [8] Keil 编译检测（真实编译 0 错误）"
    Write-Host "  [9] 全部检测（1-8 全跑）"
    Write-Host "  [0] 退出"
    Write-Host "  也可输入编号组合，如 1,4,7"
    $sel = Read-Host "  选择"
    if ($null -eq $sel) { Write-Host "  输入结束，退出。"; break menu }
    $sel = ([string]$sel).Trim()
    if ($sel -eq "0") { Write-Host "  退出。"; break menu }
    if ($sel -eq "9" -or $sel -eq "") { $ids = 1..8 }
    elseif ($sel) { $ids = @($sel -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
    else { $ids = 1..8 }
    foreach ($id in $ids) { Run-Section $id }
    Show-Summary
}
