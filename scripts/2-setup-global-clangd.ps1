# ============================================================
# 2-setup-global-clangd.ps1 — EIDE/clangd 配置工具（循环菜单 + 二级菜单）
# 功能：状态查看 / 正常配置 / 强制重配 / 撤回 / 清除 /
#       全局 clangd 配置（二级菜单：状态/生成/删除）/ 退出
# 用法：双击运行（菜单循环，[0] 退出；[6] 进二级菜单，[0] 返回上级）
#       或参数一次执行：-Mode status / auto / force / rollback / clean /
#                       global（二级菜单）/ global-status / global-write / global-rm
#                       -Root "D:\Keil5" 直接给 Keil 根目录（跳过询问）
# 说明：写任何配置前自动备份；已知 Keil 目录可直接输入跳过搜索
# 备份：%LOCALAPPDATA%\clangd\backup\（[4] 撤回 = 从备份恢复）
# 定位：EIDE 设置（工具链路径等）= 必选，自动写入；
#       全局 clangd 配置（config.yaml）= 可选兜底（每个工程自带的 .clangd 已自足），
#       在 [6] 二级菜单里成对管理：查看 / 生成 / 删除
# ============================================================
param([string]$Root = "", [string]$Mode = "")

$ErrorActionPreference = "Stop"
$script:NI = [bool]$Mode   # 参数模式 = 非交互，跳过二次确认

# 健壮输入：输入流结束（EOF）返回 $null
function Get-Input([string]$prompt) {
    $v = Read-Host $prompt
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

$cfgPath      = Join-Path $env:LOCALAPPDATA "clangd\config.yaml"
$settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
$backupDir    = Join-Path $env:LOCALAPPDATA "clangd\backup"

# ---------------- 备份 / 撤回 ----------------
function Backup-Now {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    if (Test-Path $settingsPath) { Copy-Item $settingsPath (Join-Path $backupDir "settings.json.bak") -Force }
    if (Test-Path $cfgPath)      { Copy-Item $cfgPath      (Join-Path $backupDir "config.yaml.bak") -Force }
    Write-Host "  已备份当前配置 → $backupDir" -ForegroundColor DarkGray
}
function Restore-Backup {
    $n = 0
    if (Test-Path (Join-Path $backupDir "settings.json.bak")) {
        Copy-Item (Join-Path $backupDir "settings.json.bak") $settingsPath -Force
        Write-Host "  已恢复 settings.json" -ForegroundColor Green; $n++
    }
    if (Test-Path (Join-Path $backupDir "config.yaml.bak")) {
        Copy-Item (Join-Path $backupDir "config.yaml.bak") $cfgPath -Force
        Write-Host "  已恢复 config.yaml" -ForegroundColor Green; $n++
    }
    if ($n -eq 0) { Write-Host "  没有可撤回的备份（$backupDir 为空或备份被手动删除）——无法复原，只能重新配置" -ForegroundColor Yellow }
}

# ---------------- Keil 安装目录查询 ----------------
function Get-KeilPaths {
    # 返回 @{ C51 / MDK / AC5 / GNU }（找不到为 $null）
    $r = @{ C51 = $null; MDK = $null; AC5 = $null; GNU = $null }

    # 0) 用户手动指定的根目录优先
    if ($script:Root) {
        if (Test-Path (Join-Path $script:Root "C51\TOOLS.INI")) { $r.C51 = Join-Path $script:Root "C51\C51\INC" }
        if (Test-Path (Join-Path $script:Root "MDK\TOOLS.INI")) { $r.MDK = Join-Path $script:Root "MDK" }
    }
    # 1) 已有 EIDE 设置优先
    if (Test-Path $settingsPath) {
        $s = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $r.C51 -and $s.'EIDE.C51.INI.Path') {
            $ini = $s.'EIDE.C51.INI.Path'
            if ($ini -match "TOOLS\.INI$" -and (Test-Path $ini)) {
                $line = Select-String -Path $ini -Pattern '^PATH="([^"]+)"' | Select-Object -First 1
                if ($line) { $r.C51 = Join-Path ($line.Matches[0].Groups[1].Value.TrimEnd('\')) "INC" }
            } elseif ($ini -match "UV4\.exe$" -and (Test-Path $ini)) {
                $r.C51 = Join-Path (Split-Path (Split-Path $ini -Parent) -Parent) "C51\INC"
            }
        }
        if (-not $r.MDK -and $s.'EIDE.ARM.INI.Path') {
            $ini = $s.'EIDE.ARM.INI.Path'
            if ($ini -match "TOOLS\.INI$" -and (Test-Path $ini)) {
                $line = Select-String -Path $ini -Pattern '^PATH="([^"]+)"' | Select-Object -First 1
                if ($line) { $r.MDK = Split-Path ($line.Matches[0].Groups[1].Value.TrimEnd('\')) -Parent }
            }
        }
    }
    # 2) 常见安装位置兜底
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
    if ($r.MDK) {
        $ac5 = Join-Path $r.MDK "ARM\ARMCC"
        if (Test-Path (Join-Path $ac5 "bin\armcc.exe")) { $r.AC5 = $ac5 }
    }
    $g = Get-ChildItem "C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi" -Directory -ErrorAction SilentlyContinue |
         Sort-Object Name -Descending | Select-Object -First 1
    if ($g) { $r.GNU = $g.FullName }
    return $r
}

# ---------------- 设置/新增键（PSCustomObject 新增属性必须 Add-Member）---------------
function Set-EideKey($obj, [string]$name, $value) {
    $prop = $obj.PSObject.Properties[$name]
    if ($prop) { $prop.Value = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

# ---------------- 每个配置项的用途说明（输出时标注"管什么"）---------------
function Get-EidePurpose([string]$key) {
    switch ($key) {
        'EIDE.C51.INI.Path'                    { return 'Keil C51 工具链位置，51 编译必需' }
        'EIDE.ARM.INI.Path'                    { return 'Keil MDK 位置，STM32 编译用' }
        'EIDE.ARM.ARMCC6.InstallDirectory'     { return 'STM32 编译器 armclang 目录' }
        'EIDE.ARM.ARMCC5.InstallDirectory'     { return '旧版 AC5 编译器目录（可选）' }
        'EIDE.ARM.GCC.InstallDirectory'        { return 'GNU Arm 工具链目录（可选）' }
        'EIDE.STLink.ExePath'                  { return 'ST-Link 命令行工具（STM32 烧录）' }
        'EIDE.OpenOCD.ExePath'                 { return 'OpenOCD（STM32 烧录/调试）' }
        'EIDE.JLink.InstallDirectory'          { return 'J-Link 调试器目录（可选）' }
        'EIDE.Cppcheck.ExecutablePath'         { return '静态检查工具 cppcheck 位置' }
        'EIDE.DisplayLanguage'                 { return 'EIDE 界面语言' }
        'EIDE.Option.EnableClangdConfigGenerator' { return '防自动生成 .clangd 覆盖手写配置' }
        'workbench.list.openMode'              { return '文件：单击选中/双击打开' }
        'workbench.tree.expandMode'            { return '文件夹：单击选中/双击展开' }
        default                                { return '' }
    }
}

# ---------------- 清除 EIDE 键 ----------------
function Remove-EideKeys($obj) {
    $new = [pscustomobject]@{}
    foreach ($p in $obj.PSObject.Properties) {
        if ($p.Name -notlike "EIDE.*") { $new | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    }
    return $new
}

# ---------------- 状态查看（只读） ----------------
function Show-Status {
    Write-Host ""
    Write-Host "==================== 状态查看 ====================" -ForegroundColor Cyan
    Write-Host "  原理：Keil 路径从 EIDE 设置或常见安装位置推导，" -ForegroundColor DarkGray
    Write-Host "        文件真实存在才算检测到；设置读自 settings.json。" -ForegroundColor DarkGray
    $paths = Get-KeilPaths

    Write-Host ""
    Write-Host "---- Keil 检测 ----"
    if ($paths.C51) { Write-Host ("  [OK]   Keil C51 : {0}" -f $paths.C51) -ForegroundColor Green }
    else            { Write-Host "  [!!]   Keil C51 : 未检测到（选[2]时输入根目录）" -ForegroundColor Red }
    if ($paths.MDK) { Write-Host ("  [OK]   Keil MDK : {0}" -f $paths.MDK) -ForegroundColor Green }
    else            { Write-Host "  [..]   Keil MDK : 未检测到（STM32 才需要，可后补）" -ForegroundColor Yellow }
    if ($paths.GNU) { Write-Host ("  [OK]   GNU Arm  : {0}" -f $paths.GNU) -ForegroundColor Green }
    else            { Write-Host "  [..]   GNU Arm  : 未安装（可选）" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "---- EIDE 设置（settings.json）----"
    $s = $null
    if (Test-Path $settingsPath) { $s = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    $eideKeys = @(
        @{ k = 'EIDE.C51.INI.Path';                 why = 'Keil C51 工具链位置（51 编译必需）' },
        @{ k = 'EIDE.ARM.INI.Path';                 why = 'Keil MDK 位置（STM32 编译）' },
        @{ k = 'EIDE.ARM.ARMCC6.InstallDirectory';  why = 'STM32 编译器 armclang 目录' },
        @{ k = 'EIDE.DisplayLanguage';              why = 'EIDE 界面语言' },
        @{ k = 'workbench.list.openMode';           why = '文件：单击选中/双击打开' },
        @{ k = 'workbench.tree.expandMode';         why = '文件夹：单击选中/双击展开' }
    )
    foreach ($e in $eideKeys) {
        $v = $s.$($e.k)
        if ($null -ne $v) { Write-Host ("  [已配] {0} = {1}（用途：{2}）" -f $e.k, $v, $e.why) -ForegroundColor Green }
        else              { Write-Host ("  [未配] {0}（用途：{1}）" -f $e.k, $e.why) -ForegroundColor Yellow }
    }

    Write-Host ""
    Write-Host "---- 全局 clangd 配置 ----"
    if (Test-Path $cfgPath) {
        $c = Get-Content $cfgPath -Raw -Encoding UTF8
        Write-Host "  [OK]   config.yaml 存在" -ForegroundColor Green
        Write-Host ("        关键段：PathMatch={0}  -I={1}  Suppress={2}  ferror-limit={3}" -f $c.Contains('PathMatch'), $c.Contains('  - -I'), $c.Contains('Suppress'), $c.Contains('ferror-limit'))
    } else { Write-Host "  [!!]   config.yaml 不存在（可选兜底；工程 .clangd 已自足，可跳过）" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "---- 备份 ----"
    if (Test-Path (Join-Path $backupDir "settings.json.bak")) { Write-Host "  [OK]   有备份可撤回（settings.json.bak / config.yaml.bak）" -ForegroundColor Green }
    else { Write-Host "  [..]   暂无备份（配置过之后自动生成）" -ForegroundColor Yellow }
}

# ---------------- 主配置流程 ----------------
function Do-Configure {
    # 询问 Keil 根目录（知道就直接输入，省去自动搜索）
    if (-not $script:Root) {
        Write-Host ""
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "  已知 Keil 安装根目录？直接输入后回车（例如 D:\Keil5）" -ForegroundColor Yellow
        Write-Host "  不知道？直接按回车，自动检测常见安装位置" -ForegroundColor Yellow
        Write-Host "==================================================" -ForegroundColor Cyan
        $script:Root = ([string](Read-Host "  Keil 根目录（回车跳过）")).Trim().TrimEnd('\')
    }
    $paths = Get-KeilPaths

    # --- 写入 EIDE 设置 ---
    if (Test-Path $settingsPath) { $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    else { $settings = [pscustomobject]@{} }
    $changed = @(); $notes = @()

    if ($paths.C51) {
        $iniPath = Join-Path (Split-Path (Split-Path $paths.C51 -Parent) -Parent) "TOOLS.INI"
        if (-not (Test-Path $iniPath)) { $iniPath = Join-Path (Split-Path (Split-Path $paths.C51 -Parent) -Parent) "UV4\UV4.exe" }
        if (Test-Path $iniPath) { Set-EideKey $settings 'EIDE.C51.INI.Path' $iniPath; $changed += "EIDE.C51.INI.Path = $iniPath" }
    } else { $notes += "EIDE.C51.INI.Path：未检测到 Keil C51！" }

    if ($paths.MDK) {
        $iniPath = Join-Path $paths.MDK "TOOLS.INI"
        if (Test-Path $iniPath) { Set-EideKey $settings 'EIDE.ARM.INI.Path' $iniPath; $changed += "EIDE.ARM.INI.Path = $iniPath" }
        $ac6 = Join-Path $paths.MDK "ARM\ARMCLANG"
        if (Test-Path (Join-Path $ac6 "bin\armclang.exe")) { Set-EideKey $settings 'EIDE.ARM.ARMCC6.InstallDirectory' $ac6; $changed += "EIDE.ARM.ARMCC6.InstallDirectory = $ac6" }
        if ($paths.AC5) { Set-EideKey $settings 'EIDE.ARM.ARMCC5.InstallDirectory' $paths.AC5; $changed += "EIDE.ARM.ARMCC5.InstallDirectory = $paths.AC5" }
        else { $notes += "AC5 编译器未安装（用 AC6 即可，无需处理）" }
        $stcli = Join-Path $paths.MDK "ARM\STLink\ST-LINK_CLI.exe"
        if (Test-Path $stcli) { Set-EideKey $settings 'EIDE.STLink.ExePath' $stcli; $changed += "EIDE.STLink.ExePath = $stcli" }
        else { $notes += "ST-LINK_CLI.exe 未找到（烧录用 OpenOCD 也行）" }
    } else { $notes += "Keil MDK 未检测到（STM32 阶段才需要，可后补）" }

    if ($paths.GNU) { Set-EideKey $settings 'EIDE.ARM.GCC.InstallDirectory' $paths.GNU; $changed += "EIDE.ARM.GCC.InstallDirectory = $paths.GNU" }
    else { $notes += "GNU Arm 未安装（可选；winget install Arm.GnuArmEmbeddedToolchain）" }

    $ocd = Get-ChildItem (Join-Path $env:USERPROFILE ".eide\tools") -Directory -Filter "openocd_*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ocd) {
        $ocdExe = Get-ChildItem $ocd.FullName -Recurse -Filter "openocd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ocdExe) { Set-EideKey $settings 'EIDE.OpenOCD.ExePath' $ocdExe.FullName; $changed += "EIDE.OpenOCD.ExePath = $($ocdExe.FullName)" }
    } else { $notes += "OpenOCD 未安装（可选；EIDE 选 OpenOCD 烧录器时自动下载）" }

    $jlink = Get-ChildItem "C:\Program Files (x86)\SEGGER", "C:\Program Files\SEGGER" -Directory -Filter "JLink*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($jlink) { Set-EideKey $settings 'EIDE.JLink.InstallDirectory' $jlink.FullName; $changed += "EIDE.JLink.InstallDirectory = $($jlink.FullName)" }
    else { $notes += "J-Link 未安装（可选；没有 J-Link 硬件就不需要）" }

    $sdcc = Get-ChildItem (Join-Path $env:USERPROFILE ".eide\tools") -Directory -Filter "sdcc*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sdcc) { $notes += "SDCC 由 EIDE 自动管理（~/.eide/tools），无需手动配置" }
    else { $notes += "SDCC 未安装（可选；想摆脱 Keil 时让 EIDE 自动下载）" }

    $cpp = Get-Command cppcheck -ErrorAction SilentlyContinue
    if ($cpp) { Set-EideKey $settings 'EIDE.Cppcheck.ExecutablePath' $cpp.Source; $changed += "EIDE.Cppcheck.ExecutablePath = $($cpp.Source)" }
    else { $notes += "cppcheck 未安装（可选；winget install cppcheck 后重跑自动配置）" }

    # --- 固定项：语言 / 别开自动生成 / 单击选中双击打开 ---
    Set-EideKey $settings 'EIDE.DisplayLanguage' "zh-cn"
    Set-EideKey $settings 'EIDE.Option.EnableClangdConfigGenerator' $false
    Set-EideKey $settings 'workbench.list.openMode'  "doubleClick"   # 文件：单击选中，双击打开
    Set-EideKey $settings 'workbench.tree.expandMode' "doubleClick"  # 文件夹：单击选中，双击展开
    $changed += "EIDE.DisplayLanguage = zh-cn"
    $changed += "EIDE.Option.EnableClangdConfigGenerator = false"
    $changed += "workbench.list.openMode = doubleClick"
    $changed += "workbench.tree.expandMode = doubleClick"

    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8

    Write-Host ""
    Write-Host "============ 已配置的 EIDE 设置 ============" -ForegroundColor Green
    $changed | ForEach-Object {
        $keyPart = ($_ -split ' = ')[0]
        $purpose = Get-EidePurpose $keyPart
        if ($purpose) { Write-Host ("  {0}（用途：{1}）" -f $_, $purpose) -ForegroundColor Green }
        else          { Write-Host ("  {0}" -f $_) -ForegroundColor Green }
    }
    if ($notes.Count -gt 0) {
        Write-Host ""
        Write-Host "============ 未配置项的说明 ============" -ForegroundColor Cyan
        $notes | ForEach-Object { Write-Host ("  - {0}" -f $_) -ForegroundColor Cyan }
    }

    Write-Host ""
    Write-Host "  [可选] 全局 clangd 配置（config.yaml）未处理——它是可选兜底：" -ForegroundColor DarkGray
    Write-Host "         每个工程自带的 .clangd 已完全自足，不需要全局配置。" -ForegroundColor DarkGray
    Write-Host "         想生成它（仅兜底用）：回菜单选 [6]，或参数 -Mode global。" -ForegroundColor DarkGray
}

# ---------------- 全局 clangd 配置：查看状态（只读）----------------
function Show-GlobalStatus {
    Write-Host ""
    Write-Host "---- 全局 clangd 配置状态 ----"
    if (Test-Path $cfgPath) {
        $c = Get-Content $cfgPath -Raw -Encoding UTF8
        Write-Host "  [OK]   config.yaml 存在" -ForegroundColor Green
        Write-Host ("        关键段：PathMatch={0}  -I={1}  Suppress={2}  ferror-limit={3}" -f $c.Contains('PathMatch'), $c.Contains('  - -I'), $c.Contains('Suppress'), $c.Contains('ferror-limit'))
    } else { Write-Host "  [..]   config.yaml 不存在（可选兜底；工程 .clangd 已自足）" -ForegroundColor Yellow }
}

# ---------------- 生成全局 clangd 配置（可选兜底，需确认）----------------
function Write-GlobalClangd {
    Write-Host ""
    Write-Host "============ 生成全局 clangd 配置（可选兜底）============" -ForegroundColor Cyan
    Write-Host "  说明：每个工程自带的 .clangd 已自足，此项只是兜底——" -ForegroundColor DarkGray
    Write-Host "        只对'忘了放 .clangd 的工程'起作用，跳过完全不影响正常工程。" -ForegroundColor DarkGray
    if (-not $script:NI) {
        $y = Get-Input "  确认生成？(y/N，回车=跳过)"
        if ($null -eq $y -or $y -notmatch '^[Yy]$') { Write-Host "  已跳过（全局配置保持现状）" -ForegroundColor Yellow; return }
    }
    Backup-Now
    $paths = Get-KeilPaths
    $FallbackC51 = "D:\Keil5\C51\C51\INC"
    $KeilInc = $paths.C51
    if (-not $KeilInc) {
        $KeilInc = $FallbackC51
        Write-Host ""
        Write-Host "  警告：未检测到 Keil C51，clangd 配置按默认路径生成" -ForegroundColor Yellow
        Write-Host "        $FallbackC51（不对请改脚本 `$FallbackC51 变量后重跑）" -ForegroundColor Yellow
    }
    $cfg = @"
If:
  PathMatch:
    - .*[/\\]C51[/\\].*
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
    - -I$KeilInc\Atmel
    - -I$KeilInc
    - -Iinc
    - -Iinclude
Diagnostics:
  Suppress:
    - init_element_not_constant
    - redefinition_different_typedef
    - expected_fn_body
    - invalid_token_after_toplevel_declarator
"@
    New-Item -ItemType Directory -Path (Split-Path $cfgPath) -Force | Out-Null
    [System.IO.File]::WriteAllText($cfgPath, $cfg, [System.Text.UTF8Encoding]::new($false))
    Write-Host ""
    Write-Host "  已生成: $cfgPath" -ForegroundColor Green
    Write-Host "  Keil C51 头文件: $KeilInc" -ForegroundColor Green
}

# ---------------- 删除全局 clangd 配置（[6] 的撤销；只删 config.yaml，不动 EIDE 设置）----------------
function Remove-GlobalClangd {
    Write-Host ""
    Write-Host "============ 删除全局 clangd 配置 ============" -ForegroundColor Cyan
    if (-not (Test-Path $cfgPath)) { Write-Host "  config.yaml 不存在，无需删除" -ForegroundColor Yellow; return }
    Write-Host "  将删除: $cfgPath" -ForegroundColor DarkGray
    Write-Host "  说明：工程 .clangd 已自足，删除全局配置不影响任何正常工程；" -ForegroundColor DarkGray
    Write-Host "        删除前会自动备份，选[4]可随时撤回。" -ForegroundColor DarkGray
    if (-not $script:NI) {
        $y = Get-Input "  确认删除？(y/N，回车=取消)"
        if ($null -eq $y -or $y -notmatch '^[Yy]$') { Write-Host "  已取消" -ForegroundColor Yellow; return }
    }
    Backup-Now
    Remove-Item $cfgPath -Force
    Write-Host "  已删除: $cfgPath" -ForegroundColor Green
    Write-Host "  （备份已存于 $backupDir，选[4]可撤回）" -ForegroundColor DarkGray
}

# ---------------- 二级菜单：全局 clangd 配置（生成/删除/状态，[0] 返回上级）----------------
function Show-GlobalClangdMenu {
    :global while ($true) {
        Write-Host ""
        Write-Host "============ 全局 clangd 配置（可选兜底）============" -ForegroundColor Cyan
        Write-Host "  说明：每个工程自带的 .clangd 已自足，此项仅兜底；" -ForegroundColor DarkGray
        Write-Host "        生成/删除前都会自动备份，可回主菜单 [4] 撤回。" -ForegroundColor DarkGray
        Write-Host "  [1] 查看状态"
        Write-Host "  [2] 生成（覆盖式，需确认）"
        Write-Host "  [3] 删除（需确认）"
        Write-Host "  [0] 返回上级菜单"
        $sel = Get-Input "  选择"
        if ($null -eq $sel) { Write-Host "  输入结束，返回上级。"; break global }
        switch ($sel) {
            "1" { Show-GlobalStatus }
            "2" { Write-GlobalClangd }
            "3" { Remove-GlobalClangd }
            "0" { break global }
            default { Write-Host "  无效输入，请输入 0-3" -ForegroundColor Yellow }
        }
    }
}

# ---------------- 正常配置 ----------------
function Invoke-Auto {
    Write-Host ""
    Write-Host "==================== 正常配置 ====================" -ForegroundColor Cyan
    Write-Host "  已配置完整则跳过；有缺失才补（写前自动备份）。" -ForegroundColor DarkGray
    Write-Host "  （只处理 EIDE 设置；全局 clangd 配置是可选项，见菜单[6]）" -ForegroundColor DarkGray
    $already = $false
    if (Test-Path $settingsPath) {
        $s = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $ini = $s.'EIDE.C51.INI.Path'
        if ($ini -and (Test-Path $ini)) { $already = $true }
    }
    if ($already) { Write-Host "  已检测到完整配置，跳过（强制重配请选[3]）" -ForegroundColor Green }
    else { Backup-Now; Do-Configure }
}

# ---------------- 强制重配 ----------------
function Invoke-Force {
    Write-Host ""
    Write-Host "==================== 强制重新配置 ====================" -ForegroundColor Cyan
    Write-Host "  备份当前配置后，重新检测 Keil 并全部覆盖写入。" -ForegroundColor DarkGray
    Write-Host "  用途：Keil 换路径、设置被改乱时。" -ForegroundColor DarkGray
    Backup-Now
    Do-Configure
}

# ---------------- 清除配置 ----------------
function Invoke-Clean {
    Write-Host ""
    Write-Host "==================== 清除配置 ====================" -ForegroundColor Cyan
    Write-Host "  从 settings.json 移除全部 EIDE.* 键；若存在则一并删除 config.yaml。" -ForegroundColor DarkGray
    if (-not $script:NI) {
        $y = Get-Input "  确认清除？(y/N，回车=取消)"
        if ($null -eq $y -or $y -notmatch '^[Yy]$') { Write-Host "  已取消" -ForegroundColor Yellow; return }
    }
    if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force; Write-Host "  已删除: $cfgPath" -ForegroundColor Yellow }
    else { Write-Host "  config.yaml 不存在，无需删除" }
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $clean = Remove-EideKeys $settings
        $clean | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-Host "  已从 settings.json 移除全部 EIDE.* 键" -ForegroundColor Yellow
    }
}

# ---------------- 参数模式 ----------------
if ($Mode) {
    switch ($Mode) {
        "status"   { Show-Status }
        "auto"     { Invoke-Auto }
        "force"    { Invoke-Force }
        "rollback" { Restore-Backup }
        "clean"    { Invoke-Clean }
        "global"   { Show-GlobalClangdMenu }
        "global-status" { Show-GlobalStatus }
        "global-write"  { Write-GlobalClangd }
        "global-rm"     { Remove-GlobalClangd }
        default    { Write-Host "未知模式: $Mode（可用 status / auto / force / rollback / clean / global / global-status / global-write / global-rm）" -ForegroundColor Yellow }
    }
    exit
}

# ---------------- 菜单循环 ----------------
:menu while ($true) {
    Write-Host ""
    Write-Host "================ EIDE / clangd 配置工具 ================" -ForegroundColor Cyan
    Write-Host "  [1] 查看状态"
    Write-Host "      只读检查：Keil 检测 / EIDE 设置 / clangd 配置 / 备份"
    Write-Host "  [2] 正常配置"
    Write-Host "      只处理 EIDE 设置（必选）；缺什么补什么；写前自动备份"
    Write-Host "  [3] 强制重新配置"
    Write-Host "      备份后全部覆盖 EIDE 设置；Keil 换路径后用它"
    Write-Host "  [4] 撤回上次配置"
    Write-Host "      从备份恢复 settings.json 和 config.yaml"
    Write-Host "  [5] 清除配置"
    Write-Host "      移除全部 EIDE 键 + 删除 config.yaml；需确认"
    Write-Host "  [6] 全局 clangd 配置（可选兜底）"
    Write-Host "      进入二级菜单：查看状态 / 生成 / 删除（成对管理）"
    Write-Host "  [0] 退出"
    $sel = Get-Input "  选择"
    if ($null -eq $sel) { Write-Host "  输入结束，退出。"; break menu }
    switch ($sel) {
        "1" { Show-Status }
        "2" { Invoke-Auto }
        "3" { Invoke-Force }
        "4" { Restore-Backup }
        "5" { Invoke-Clean }
        "6" { Show-GlobalClangdMenu }
        "0" { Write-Host "  退出。"; break menu }
        default { Write-Host "  无效输入，请输入 0-6" -ForegroundColor Yellow }
    }
}
