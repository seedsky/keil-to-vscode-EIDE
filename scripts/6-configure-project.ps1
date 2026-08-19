# ============================================================
# 6-configure-project.ps1 — 一键配置项目（输入项目目录 → 自动检查并添加对应文件）
#
# 用法：双击 一键配置项目.bat，输入项目目录（或把文件夹拖到 bat 上）
#       交互菜单：[1] 配置项目  [2] 复原上次配置  [0] 退出
#       参数模式：-Project "D:\xxx"           → 直接配置（非交互）
#                 -Project "D:\xxx" -Rollback → 直接复原（非交互）
#
# 流程（每一步都说明：做了什么 / 为什么 / 后果）：
#   [1] 校验目录    必须是 EIDE 工程（有 .eide\eide.yml）
#   [2] 判断类型    读取 toolchain（SDCC / Keil_C51）和 targets（Target 1 / Debug）
#   [3] 放 .clangd  从工具包「常用文件」复制，并自动把 CompilationDatabase
#                    改成 ./build\<目标名>（目标名从 eide.yml 自动读出，不用你猜）
#   [4] 放 .clang-format  从「常用文件」复制（VS 风格格式化）
#   [5] 修 eide.yml 工具链/源文件注册/包含目录（改前自动备份 .eide\eide.yml.bak）
#   [6] 总结报告    列出所有改动 + 复原方法 + 下一步
#
# 复原（[2] / -Rollback）：从 .clangd.bak / .clang-format.bak / eide.yml.bak 恢复；
#   备份被移除/不存在时逐项明确告知（不会静默失败）。
#
# 备份原则：任何修改前都先备份；配置前不存在的文件，复原时如实告知"配置前不存在"。
# ============================================================
param([string]$Project = "", [switch]$Rollback)

$ErrorActionPreference = "Stop"

# 健壮输入：输入流结束（EOF）返回 $null
function Get-Input([string]$prompt) {
    $v = Read-Host $prompt
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

# 按行解析 eide.yml 的列表块（srcDirs / incList）
function Get-ListAfter($lines, [string]$key) {
    $result = @()
    $inBlock = $false
    foreach ($l in $lines) {
        $t = $l.Trim()
        if (-not $inBlock) {
            if ($t -match "^$([regex]::Escape($key)):") { $inBlock = $true }
        }
        else {
            if ($t -match '^-\s+(\S+)') { $result += $Matches[1] }
            elseif ($t -ne "" -and $t -notmatch '^#') { break }
        }
    }
    return $result
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path   # scripts\ 目录
$toolkit = Split-Path -Parent $scriptDir                        # 工具包根目录
$commonDir = Join-Path $toolkit "常用文件"

# ---------------- 复原单个文件（备份缺失时明确告知）----------------
function Restore-One([string]$file, [string]$bak, [string]$label) {
    if (Test-Path $bak) {
        Copy-Item $bak $file -Force
        Write-Host "  [✓] 已复原 $label（来源：$bak）" -ForegroundColor Green
        return $true
    }
    Write-Host "  [✗] $label 无法复原：备份 $bak 不存在" -ForegroundColor Red
    Write-Host "      可能原因：本次配置没有修改该项（无备份生成）、备份被手动删除、或配置前该文件本来就不存在" -ForegroundColor DarkGray
    Write-Host "      若该文件是脚本生成的且配置前不存在：手动删除它即可回到原状态" -ForegroundColor DarkGray
    return $false
}

# ---------------- 复原上次配置（[2] / -Rollback）----------------
function Rollback-Project([string]$p) {
    Write-Host ""
    Write-Host "================ 复原上次配置 ================" -ForegroundColor Cyan
    $n = 0
    $n += [int](Restore-One (Join-Path $p ".clangd")         (Join-Path $p ".clangd.bak")         ".clangd")
    $n += [int](Restore-One (Join-Path $p ".clang-format")   (Join-Path $p ".clang-format.bak")   ".clang-format")
    $n += [int](Restore-One (Join-Path $p ".eide\eide.yml")  (Join-Path $p ".eide\eide.yml.bak")  "eide.yml")
    Write-Host ""
    if ($n -eq 3) {
        Write-Host "  全部 3 项已复原为配置前的状态" -ForegroundColor Green
    }
    elseif ($n -gt 0) {
        Write-Host "  复原了 $n 项；未复原的见上方红色提示（备份缺失）" -ForegroundColor Yellow
    }
    else {
        Write-Host "  没有任何可复原的备份——备份可能都被移除了，或本工程从未用本脚本配置过。" -ForegroundColor Red
        Write-Host "  后果：无法自动还原，请手动检查工程文件；之后配置时脚本会重新生成备份。" -ForegroundColor DarkGray
    }
    Write-Host "  复原后：Ctrl+Shift+P → clangd: Restart language server" -ForegroundColor DarkGray
}

# ---------------- 配置项目（[1] / 默认参数模式）----------------
function Configure-Project([string]$p) {
    $eideFile = Join-Path $p ".eide\eide.yml"
    $ymlLines = Get-Content $eideFile -Encoding UTF8
    $ymlRaw = Get-Content $eideFile -Raw -Encoding UTF8

    # ---------- 判断类型（工具链 + 目标名）----------
    $toolchain = if ($ymlRaw -match '(?m)^\s*toolchain:\s*(\S+)') { $Matches[1] } else { "" }
    $target = if ($ymlRaw -match '(?m)^targets:\s*\r?\n\s{2}(\S[^\r\n:]*):') { $Matches[1].Trim() } else { "" }
    $srcDirs = Get-ListAfter $ymlLines "srcDirs"
    $incList = Get-ListAfter $ymlLines "incList"

    Write-Host ""
    Write-Host "---- 类型判断（自动读取）----" -ForegroundColor DarkGray
    Write-Host ("  工具链：{0}（{1}）" -f $(if ($toolchain) { $toolchain } else { "未知" }), $(if ($toolchain -eq "Keil_C51") { "✓ 正确" } elseif ($toolchain -eq "SDCC") { "⚠️ 是 SDCC，需切换" } else { "需确认" })) -ForegroundColor $(if ($toolchain -eq "Keil_C51") { "Green" } else { "Yellow" })
    Write-Host ("  目标名：{0}（决定编译数据库路径 ./build\{0}\）" -f $(if ($target) { $target } else { "未知" })) -ForegroundColor $(if ($target) { "Green" } else { "Yellow" })
    Write-Host ("  srcDirs：[{0}]    incList：[{1}]" -f ($srcDirs -join ', '), ($incList -join ', ')) -ForegroundColor DarkGray

    # ---------- 放 .clangd 并修正 CompilationDatabase ----------
    Write-Host ""
    Write-Host "---- [3] 配置 .clangd ----" -ForegroundColor Cyan
    $clangdFile = Join-Path $p ".clangd"
    $srcClangd = Join-Path $commonDir ".clangd"
    $changed = @()
    # 备份原则：修改前必备份（无论原文件是否存在，存在才备份；不存在则复原时如实告知）
    if (Test-Path $clangdFile) {
        Copy-Item $clangdFile "$clangdFile.bak" -Force
        Write-Host "  已备份旧 .clangd → .clangd.bak" -ForegroundColor DarkGray
    } else {
        Write-Host "  原 .clangd 不存在（配置后若需复原：手动删除即可回到原状态）" -ForegroundColor DarkGray
    }
    Copy-Item $srcClangd $clangdFile -Force
    Write-Host "  已从「常用文件」复制标准 .clangd" -ForegroundColor Green
    # 修正 CompilationDatabase：标准版自带 ./build/Target 1——
    #   目标名正好是 Target 1 → 零改动（标准版就是对的）
    #   目标名是别的（如 Debug）→ 删除所有旧配置行（含注释行），在 CompileFlags 后插入唯一正确行
    if ($target -and $target -ne "Target 1") {
        $lines = Get-Content $clangdFile -Encoding UTF8
        $out = @()
        $inserted = $false
        foreach ($l in $lines) {
            if ($l -match '^\s*#?\s*CompilationDatabase:') { continue }   # 删旧配置行和注释行
            if (-not $inserted -and $l -match '^CompileFlags:') {          # 块内插入唯一正确行
                $out += $l
                $out += "  CompilationDatabase: ./build/$target"
                $inserted = $true
                continue
            }
            $out += $l
        }
        if (-not $inserted) { $out += "CompileFlags:"; $out += "  CompilationDatabase: ./build/$target" }
        [System.IO.File]::WriteAllText($clangdFile, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  已自动写入 CompilationDatabase: ./build/$target（目标名来自 eide.yml，不用手填）" -ForegroundColor Green
    }
    else {
        Write-Host "  目标名 $target 与标准版一致，CompilationDatabase 无需修改" -ForegroundColor Green
    }
    $changed += ".clangd：复制标准版 + CompilationDatabase = ./build/$target"

    # ---------- 放 .clang-format ----------
    Write-Host ""
    Write-Host "---- [4] 配置 .clang-format ----" -ForegroundColor Cyan
    $fmtFile = Join-Path $p ".clang-format"
    $srcFmt = Join-Path $commonDir ".clang-format"
    if (Test-Path $fmtFile) { Copy-Item $fmtFile "$fmtFile.bak" -Force; Write-Host "  已备份旧 .clang-format → .clang-format.bak" -ForegroundColor DarkGray }
    else { Write-Host "  原 .clang-format 不存在（配置后若需复原：手动删除即可回到原状态）" -ForegroundColor DarkGray }
    Copy-Item $srcFmt $fmtFile -Force
    Write-Host "  已从「常用文件」复制 .clang-format（VS 风格：4 空格缩进 + 大括号另起一行）" -ForegroundColor Green
    $changed += ".clang-format：VS 风格格式化配置"

    # ---------- 修 eide.yml（改前备份，每项说明后果）----------
    Write-Host ""
    Write-Host "---- [5] 修正 eide.yml（自动备份后修改）----" -ForegroundColor Cyan
    $ymlChanged = @()
    # 5a. 工具链
    if ($toolchain -and $toolchain -ne "Keil_C51") {
        $ymlRaw = $ymlRaw -replace '(?m)^(\s*toolchain:\s*)\S+', "`$1Keil_C51"
        $ymlChanged += "toolchain：$toolchain → Keil_C51"
        Write-Host "  [改] 工具链 $toolchain → Keil_C51" -ForegroundColor Yellow
        Write-Host "       原因：机器上只装了 Keil，SDCC 会报'找不到编译器'。" -ForegroundColor DarkGray
        Write-Host "       后果：toolchainConfigMap 里旧的 SDCC 配置块还在，建议之后在 EIDE 项目设置里重新选一次 Keil_C51（会重建配置块）。" -ForegroundColor DarkGray
    }
    # 5b. srcDirs：补含 .c 的目录
    $cDirs = @()
    Get-ChildItem $p -Recurse -Filter "*.c" -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '\\build\\|\\\.eide\\|\\\.git\\|\\\.vscode\\'
    } | ForEach-Object {
        $rel = $_.DirectoryName.Substring($p.Length).TrimStart('\')
        if ($rel -and $cDirs -notcontains $rel) { $cDirs += $rel }
    }
    $unregistered = $cDirs | Where-Object { $srcDirs -notcontains $_ }
    if ($unregistered.Count -gt 0) {
        foreach ($d in $unregistered) {
            # 追加行的缩进 = 原列表缩进 + 2 空格（$1 捕获缩进，不能写死——嵌套键缩进不同会坏 YAML）
            $ymlRaw = $ymlRaw -replace '(?m)^(\s*)(srcDirs:\s*\r?\n)((?:\s*-\s*[^\r\n]+\r?\n)*)', ('${1}${2}${3}' + '${1}  - ' + $d + "`r`n")
        }
        $ymlChanged += "srcDirs 补：$($unregistered -join '、')"
        Write-Host "  [改] srcDirs 补注册：$($unregistered -join '、')" -ForegroundColor Yellow
        Write-Host "       原因：这些目录里有 .c 但没注册，不编译 = 链接报 L127 UNRESOLVED。" -ForegroundColor DarkGray
        Write-Host "       后果：目录里的 .c 参与编译；EIDE 打开工程会自动识别。" -ForegroundColor DarkGray
    }
    # 5c. incList：补 Atmel（必要头文件目录）
    $hasAtmel = $incList | Where-Object { $_ -match 'Atmel' }
    if (-not $hasAtmel) {
        # 追加行的缩进 = 原列表缩进 + 2 空格（$1 捕获缩进——SDCC 模板的 incList 嵌套在
        # cppPreprocessAttrs 下是 8 空格缩进，写死 4 空格会破坏 YAML 导致 EIDE 解析失败）
        $ymlRaw = $ymlRaw -replace '(?m)^(\s*)(incList:\s*\r?\n)((?:\s*-\s*[^\r\n]+\r?\n)*)', ('${1}${2}${3}' + '${1}  - D:/Keil5/C51/C51/INC/Atmel' + "`r`n")
        $ymlChanged += "incList 补：D:/Keil5/C51/C51/INC/Atmel"
        Write-Host "  [改] incList 补 Atmel（REGX52.H 所在目录）" -ForegroundColor Yellow
        Write-Host "       原因：REGX52.H 住在 INC\Atmel\ 子目录，不加它 #include <REGX52.H> 必报错。" -ForegroundColor DarkGray
        Write-Host "       后果：Keil 标准头文件可找到；换机器时改 Keil 路径。" -ForegroundColor DarkGray
    }
    if ($ymlChanged.Count -gt 0) {
        # 备份原则：eide.yml 修改前必备份
        Copy-Item $eideFile "$eideFile.bak" -Force
        Write-Host "  已备份 eide.yml → .eide\eide.yml.bak" -ForegroundColor DarkGray
        [System.IO.File]::WriteAllText($eideFile, $ymlRaw, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  eide.yml 已更新（$($ymlChanged.Count) 处）" -ForegroundColor Green
    }
    else {
        Write-Host "  eide.yml 无需修改（工具链/注册/包含目录都正确）" -ForegroundColor Green
    }

    # ---------- 总结报告 ----------
    Write-Host ""
    Write-Host "================ 配置完成 ================" -ForegroundColor Cyan
    if ($changed.Count -gt 0 -or $ymlChanged.Count -gt 0) {
        Write-Host "  本次改动：" -ForegroundColor Green
        ($changed + $ymlChanged) | ForEach-Object { Write-Host "    • $_" -ForegroundColor Green }
    } else {
        Write-Host "  没有需要改动的（工程配置已完整）" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  为什么这么做：EIDE 模板/导入的工程默认缺 .clangd、.clang-format、" -ForegroundColor DarkGray
    Write-Host "    工具链/注册/包含目录也可能不对——一键脚本把这些补齐，不用手动复制粘贴。" -ForegroundColor DarkGray
    Write-Host "  复原：重新运行本脚本选 [2] 复原（或参数 -Rollback），从备份恢复" -ForegroundColor Yellow
    Write-Host "  下一步（按顺序）：" -ForegroundColor Yellow
    Write-Host "    1. Ctrl+Shift+B 编译一次（生成编译数据库）" -ForegroundColor Yellow
    Write-Host "    2. Ctrl+Shift+P → clangd: Restart language server" -ForegroundColor Yellow
    Write-Host "    3. 复制「检测工程配置」跑一遍确认全绿（可选）" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================
# 主流程
# ============================================================
$proj = $Project
if (-not $proj) {
    Write-Host ""
    Write-Host "================ 一键配置项目 ================" -ForegroundColor Cyan
    $proj = Get-Input "  请输入项目目录（或直接回车用当前目录）"
    if ($null -eq $proj -or $proj -eq "") { $proj = (Get-Location).Path }
}
$proj = $proj.Trim().TrimEnd('\')
$eideFile = Join-Path $proj ".eide\eide.yml"
if (-not (Test-Path $eideFile)) {
    Write-Host "  [✗] 不是 EIDE 工程：$eideFile 不存在" -ForegroundColor Red
    Write-Host "      原因：一键配置只服务 EIDE 工程（EIDE 新建或 Keil 导入的都有 .eide 文件夹）" -ForegroundColor Yellow
    Write-Host "      后果：无法自动判断工具链/目标名，停止。请确认目录后重试。" -ForegroundColor DarkGray
    Read-Host "  按回车退出"
    exit 1
}
Write-Host "  [✓] 项目目录：$proj" -ForegroundColor Green

if ($Rollback) { Rollback-Project $proj; exit 0 }

# 参数模式（-Project 指定）：直接配置，不弹菜单
if ($Project) { Configure-Project $proj; exit 0 }

# 交互菜单
:menu while ($true) {
    Write-Host ""
    Write-Host "================ 一键配置项目（菜单）================" -ForegroundColor Cyan
    Write-Host "  [1] 配置项目"
    Write-Host "      复制 .clangd/.clang-format + 修正 eide.yml；改前全部备份"
    Write-Host "  [2] 复原上次配置"
    Write-Host "      从备份恢复；备份被移除会明确告知"
    Write-Host "  [0] 退出"
    $sel = Get-Input "  选择"
    if ($null -eq $sel) { Write-Host "  输入结束，退出。"; break menu }
    switch ($sel) {
        "1" { Configure-Project $proj }
        "2" { Rollback-Project $proj }
        "0" { Write-Host "  退出。"; break menu }
        default { Write-Host "  无效输入，请输入 0-2" -ForegroundColor Yellow }
    }
}
