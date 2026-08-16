# ============================================================
# 检测工程配置.ps1 — 工程配置检测（复制到工程根目录，双击 检测工程配置.bat 运行）
#
# 检测内容（每一项：状态 → 原因 → 解决方法）：
#   [1] 工程识别    是否 EIDE 工程（.eide/eide.yml 存在）
#   [2] 工具链      是否为 Keil_C51（否则报"找不到编译器 SDCC"）
#   [3] 目标名      目标名 = eide.yml targets 下的名字（决定编译数据库路径）
#   [4] 源文件注册  srcDirs 是否覆盖所有含 .c 的目录（否则 C Files 少 / 链接 L127）
#   [5] 包含目录    incList 是否含 inc 和 Atmel（否则 can't open file）
#   [6] .clangd     是否存在 + 关键项（缩进 / 目标名 / 宏 / -I / Suppress）
#   [7] 编译数据库  build\<目标名>\compile_commands.json 是否存在（先编译一次）
#   [8] 源码编码    .c/.h 是否 UTF-8 无 BOM（否则 clangd 满屏红 / Keil 第一行失效）
#   [9] clangd 实测 用 clangd --check 跑真实诊断
#
# 输出：每项 [✓]/[✗] + 原因 + 解决方法；结尾汇总所有待修复项
# ============================================================

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$eideFile = Join-Path $root ".eide\eide.yml"
$clangdFile = Join-Path $root ".clangd"

$script:pass = 0
$script:fail = 0
$script:fixes = @()

# 健壮输入：输入流结束（EOF）返回 $null（管道/重定向运行时不会死循环）
function Get-Input([string]$prompt) {
    $v = Read-Host $prompt
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

# 输出一项检测结果：名称 / 是否通过 / 说明 / 解决方法
function Show-Check([string]$name, [bool]$ok, [string]$detail, [string]$fix) {
    if ($ok) {
        Write-Host ("  [✓] {0}：{1}" -f $name, $detail) -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host ("  [✗] {0}：{1}" -f $name, $detail) -ForegroundColor Red
        if ($fix) {
            Write-Host ("      解决：{0}" -f $fix) -ForegroundColor Yellow
            $script:fixes += "• $name：$fix"
        }
        $script:fail++
    }
}

Write-Host ""
Write-Host "================ 工程配置检测 ================" -ForegroundColor Cyan
Write-Host ("  工程目录：{0}" -f $root) -ForegroundColor DarkGray

# ---------- [1] 工程识别 ----------
if (-not (Test-Path $eideFile)) {
    Write-Host ""
    Write-Host "  [✗] 这不是 EIDE 工程：$eideFile 不存在" -ForegroundColor Red
    Write-Host "      解决：脚本要复制到 EIDE 工程根目录（有 .eide 文件夹的那一层）再运行" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  （其他检测项无法继续，退出）" -ForegroundColor DarkGray
    Read-Host "  按回车退出"
    exit 1
}
$yml = Get-Content $eideFile -Raw -Encoding UTF8
Write-Host "  [✓] 工程识别：EIDE 工程（.eide/eide.yml 存在）" -ForegroundColor Green
$script:pass++

# ---------- [2] 工具链 ----------
$tc = if ($yml -match '(?m)^\s*toolchain:\s*(\S+)') { $Matches[1] } else { "" }
Show-Check "工具链" ($tc -eq "Keil_C51") "当前 = $tc（应为 Keil_C51）" `
    "右键工程名 → 项目设置 → 工具链 → 选 Keil_C51；或改 eide.yml 的 toolchain 为 Keil_C51。不改会报'无法找到编译器 SDCC'"

# ---------- [3] 目标名 ----------
$target = if ($yml -match '(?m)^targets:\s*\r?\n\s{2}(\S[^\r\n:]*):') { $Matches[1].Trim() } else { "" }
Show-Check "目标名" ($target -ne "") "targets 下 = $target（编译数据库在 build\$target\）" `
    "eide.yml 的 targets: 下没有目标名？正常工程至少有一个（Target 1 或 Debug）"

# ---------- 按行解析 eide.yml 的列表块（srcDirs / incList / libList）----------
# 原理：找到 "xxx:" 行后，收集后续以 "- " 开头的行，遇到非列表行即块结束
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
$ymlLines = Get-Content $eideFile -Encoding UTF8

# ---------- [4] 源文件注册 ----------
$srcDirs = Get-ListAfter $ymlLines "srcDirs"
# 找所有实际含 .c 的目录（工程根下递归，排除 build/.eide/.git/.vscode）
$cDirs = @()
Get-ChildItem $root -Recurse -Filter "*.c" -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch '\\build\\|\\\.eide\\|\\\.git\\|\\\.vscode\\'
} | ForEach-Object {
    $rel = $_.DirectoryName.Substring($root.Length).TrimStart('\')
    if ($rel -and $cDirs -notcontains $rel) { $cDirs += $rel }
}
$unregistered = $cDirs | Where-Object { $srcDirs -notcontains $_ }
$cCount = (Get-ChildItem $root -Recurse -Filter "*.c" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\build\\|\\\.eide\\|\\\.git\\|\\\.vscode\\' }).Count
if ($unregistered.Count -eq 0) {
    Show-Check "源文件注册" $true "srcDirs = [$($srcDirs -join ', ')]，覆盖全部 $cCount 个 .c" ""
}
else {
    Show-Check "源文件注册" $false "srcDirs = [$($srcDirs -join ', ')]，但以下目录里的 .c 没注册：$($unregistered -join ', ')" `
        "右键工程名 → 添加目录 → 选 $($unregistered -join '、')；或 eide.yml 的 srcDirs 加上。不注册 = 该目录 .c 不编译 = 链接报 L127 UNRESOLVED（?C_START）"
}

# ---------- [5] 包含目录 ----------
$incList = Get-ListAfter $ymlLines "incList"
$hasInc = $incList | Where-Object { $_ -match '(^|/)inc$|^inc$' }
$hasAtmel = $incList | Where-Object { $_ -match 'Atmel' }
if ($hasInc -and $hasAtmel) {
    Show-Check "包含目录" $true "incList 含 inc 和 Atmel：$($incList -join '; ')" ""
}
else {
    $need = @()
    if (-not $hasInc) { $need += "inc（工程自己的头文件目录，缺它 #include ""uart.h"" 报 can't open file）" }
    if (-not $hasAtmel) { $need += "D:/Keil5/C51/C51/INC/Atmel（REGX52.H 所在，缺它报 can't open file 'REGX52.H' + 16 个 undefined）" }
    Show-Check "包含目录" $false "incList = [$($incList -join ', ')]，缺：$($need -join '；')" `
        "右键工程名 → 项目设置 → 找到「包含目录」（不是「库搜索目录」！）→ 添加缺失项。注意：REGX52.H 住在 Keil5\C51\C51\INC\Atmel\ 子目录，不加 Atmel 必报错"
}

# ---------- [6] .clangd ----------
if (-not (Test-Path $clangdFile)) {
    Show-Check ".clangd" $false "工程根目录没有 .clangd" `
        "从工具包「新建工程模板」复制 .clangd 到工程根目录；并改其中 CompilationDatabase 一行（见下一条）。没有它 = 编辑器满屏红"
    $cdbOk = $false; $macroOk = $false; $incOk = $false; $wnoOk = $false
}
else {
    $cld = Get-Content $clangdFile -Raw -Encoding UTF8
    # 缩进检查：CompilationDatabase 必须在 CompileFlags 下（行首两个空格，放顶层 clangd 直接无视）
    $indentOk = $cld -match '(?m)^\s{2}CompilationDatabase:'
    # 目标名匹配：cdb 路径里的目标名 == eide.yml 的目标名（缩进正确才读取，否则无意义）
    $cdbLine = if ($indentOk -and $cld -match '(?m)^\s{2}CompilationDatabase:\s*(.+)\r?$') { $Matches[1].Trim() } else { "" }
    $cdbTargetOk = $false
    if ($cdbLine) {
        $cdbTarget = [regex]::Match($cdbLine, '/([^/]+)$').Groups[1].Value
        if ($cdbTarget -eq $target) { $cdbTargetOk = $true }
        elseif ($target -eq "Target 1" -and $cdbTarget -eq "Target 1") { $cdbTargetOk = $true }
    }
    $macroOk  = $cld -match '-Dsbit=char' -and $cld -match '-Dsfr=char' -and $cld -match '-Dcode=const'
    $incOk    = $cld -match '-Iinc' -and $cld -match '-I\.\./inc'
    $wnoOk    = $cld -match '-Wno-main'
    $suppressOk = $cld -match 'Suppress' -and $cld -match 'expected_fn_body' -and $cld -match 'redefinition_different_typedef'

    # 失败项（全部强制）：宏 / -I / -Wno / Suppress / CompilationDatabase
    $issues = @()
    if (-not $macroOk) { $issues += "缺宏翻译（应有 -Dsbit=char / -Dsfr=char / -Dcode=const 等）" }
    if (-not $incOk) { $issues += "缺 -Iinc / -I../inc 互补路径（头文件找不到）" }
    if (-not $wnoOk) { $issues += "缺 -Wno-main（void main 会报 Return type of 'main'）" }
    if (-not $suppressOk) { $issues += "Suppress 抑制清单不完整（interrupt/_at_/size_t 误报压不住）" }
    if (-not $indentOk) {
        $issues += "CompilationDatabase 没有缩进在 CompileFlags 下（行首必须两个空格，放顶层 clangd 直接无视——多级目录工程必挂）"
    }
    elseif (-not $cdbTargetOk) {
        $issues += "CompilationDatabase 目标名是 [$cdbLine]，应为 ./build/$target（目标名看 eide.yml 的 targets:）"
    }

    if ($issues.Count -eq 0) {
        Show-Check ".clangd" $true "存在且关键项齐全（CompilationDatabase: $cdbLine）" ""
    }
    else {
        Show-Check ".clangd" $false "存在但有问题：$($issues -join '；')" ""
        # 交互修复：让用户填写目标名，自动修正 CompilationDatabase 行（含缩进）
        if (-not $script:NI -and $cld -match 'CompilationDatabase') {
            $doFix = Get-Input "  是否现在修正 CompilationDatabase？（y/N）"
            if ($null -ne $doFix -and $doFix -match '^[Yy]$') {
                $newTarget = Get-Input "  填写你的目标名（默认：$target，直接回车使用）"
                if ($null -eq $newTarget -or $newTarget -eq "") { $newTarget = $target }
                $bakFile = "$clangdFile.bak"
                Copy-Item $clangdFile $bakFile -Force
                # 备份后重写：三种情况都处理——
                #   1) 未注释的配置行 → 替换为正确缩进 + 正确目标名
                #   2) 被注释掉的旧配置行（#CompilationDatabase:）→ 删除
                #   3) 根本没有配置行 → 在 CompileFlags: 块内插入
                $lines = Get-Content $clangdFile -Encoding UTF8
                $out = @()
                $inserted = $false
                foreach ($l in $lines) {
                    if ($l -match '^\s*#\s*CompilationDatabase:') { continue }          # 删注释行
                    if ($l -match '^\s*CompilationDatabase:') {                          # 替换配置行
                        $out += "  CompilationDatabase: ./build/$newTarget"; $inserted = $true; continue
                    }
                    if (-not $inserted -and $l -match '^CompileFlags:') {                # 块内插入
                        $out += $l
                        $out += "  CompilationDatabase: ./build/$newTarget"
                        $inserted = $true
                        continue
                    }
                    $out += $l
                }
                if (-not $inserted) {                                                    # 兜底：结构异常时追加
                    $out += "CompileFlags:"
                    $out += "  CompilationDatabase: ./build/$newTarget"
                }
                $text = ($out -join "`r`n")
                [System.IO.File]::WriteAllText($clangdFile, $text, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "  ✓ 已修正：CompilationDatabase: ./build/$newTarget（原文件备份为 .clangd.bak）" -ForegroundColor Green
                Write-Host "  下一步：Ctrl+Shift+P → clangd: Restart language server 后重新检测" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  手动修法：把 CompilationDatabase 那一行改成（注意行首两个空格）：" -ForegroundColor Yellow
                Write-Host "    CompilationDatabase: ./build/$target" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  手动修法：把 CompilationDatabase 那一行改成（注意行首两个空格）：" -ForegroundColor Yellow
            Write-Host "    CompilationDatabase: ./build/$target" -ForegroundColor Yellow
            Write-Host "  其他问题（宏/-I/-Wno/Suppress）：直接用工具包「新建工程模板」里的 .clangd 覆盖整个文件" -ForegroundColor Yellow
        }
    }
}

# ---------- [7] 编译数据库 ----------
$dbPath = Join-Path $root "build\$target\compile_commands.json"
Show-Check "编译数据库" (Test-Path $dbPath) "build\$target\compile_commands.json" `
    "还没编译过！先 Ctrl+Shift+B 编译一次（编译成功会自动生成），再重启 clangd"

# ---------- [8] 源码编码 ----------
$badFiles = @()
Get-ChildItem $root -Recurse -Include "*.c", "*.h" -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch '\\build\\|\\\.eide\\|\\\.git\\|\\\.vscode\\|\\_gbk_backup\\'
} | ForEach-Object {
    $b = [System.IO.File]::ReadAllBytes($_.FullName)
    $isUtf8 = $true
    try { $null = [System.Text.UTF8Encoding]::new($false, $true).GetString($b) } catch { $isUtf8 = $false }
    $hasBom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    if (-not $isUtf8 -or $hasBom) { $badFiles += $_.FullName.Replace($root, "") }
}
if ($badFiles.Count -eq 0) {
    Show-Check "源码编码" $true "全部 .c/.h 都是 UTF-8 无 BOM" ""
}
else {
    Show-Check "源码编码" $false "以下文件不是 UTF-8 无 BOM（GBK 或带 BOM）：$($badFiles -join ', ')" `
        "GBK：用工具包 3-编码转换.bat（复制到工程根运行）；带 BOM：用 VSCode 打开 → 右下角编码 → 通过编码保存 → UTF-8（不带 BOM）。clangd 只认 UTF-8，Keil 不认 BOM"
}

# ---------- [9] clangd 实测 ----------
$clangdExe = Get-ChildItem (Join-Path $env:APPDATA "Code\User\globalStorage\llvm-vs-code-extensions.vscode-clangd\install") `
    -Recurse -Filter "clangd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $clangdExe) {
    Show-Check "clangd 实测" $false "没找到 clangd.exe（vscode-clangd 扩展没装或没下载服务器）" `
        "装 vscode-clangd 扩展后会自动下载服务器；或按指南第 1 步运行 1-安装扩展.bat"
}
else {
    $testFile = Get-ChildItem $root -Recurse -Filter "*.c" -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '\\build\\|\\\.eide\\|\\\.git\\|\\\.vscode\\'
    } | Select-Object -First 1
    if ($testFile) {
        # 用相对路径（如 src/main.c），clangd 才能按 .clangd 里的 CompilationDatabase 定位
        $relFile = $testFile.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        Push-Location $root
        $diag = & $clangdExe.FullName "--check=$relFile" 2>&1 | Out-String
        Pop-Location
        $m = [regex]::Match($diag, 'All checks completed, (\d+) errors')
        $errCount = if ($m.Success) { [int]$m.Groups[1].Value } else { -1 }
        if ($errCount -eq 0) {
            Show-Check "clangd 实测" $true "clangd --check $relFile：0 错误" ""
        }
        elseif ($errCount -gt 0) {
            Show-Check "clangd 实测" $false "clangd --check $relFile：$errCount 个错误（多为 .clangd 配置问题，看上面 [6] 的修复）" ""
        }
        else {
            Show-Check "clangd 实测" $false "clangd 无法诊断（配置解析失败？先修 [6] 再试）" ""
        }
    }
    else {
        Show-Check "clangd 实测" $false "工程里没有 .c 文件可测" ""
    }
}

# ---------- 总结 ----------
Write-Host ""
Write-Host "================ 检测结果 ================" -ForegroundColor Cyan
Write-Host ("  通过 {0} 项，失败 {1} 项" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { "Green" } else { "Red" })
if ($script:fixes.Count -gt 0) {
    Write-Host ""
    Write-Host "  待修复清单（按顺序做）：" -ForegroundColor Yellow
    $script:fixes | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
}
if ($script:fail -eq 0) {
    Write-Host ""
    Write-Host "  全部通过：编译 + 编辑器应该都正常。还红就 Ctrl+Shift+P → clangd: Restart language server" -ForegroundColor Green
}
Write-Host ""
