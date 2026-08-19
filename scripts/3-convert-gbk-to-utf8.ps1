# ============================================================
# 3-convert-gbk-to-utf8.ps1 — 编码转换工具（循环菜单）
# 功能：状态查看 / 转换 / 还原 / 清理备份 / 退出
# 用法：复制到【工程根目录】后双击运行（菜单循环，[0] 退出）
#       或参数一次执行：-Mode status / convert / restore / clean
# 说明：转换前自动备份原文件；已是 UTF-8 的自动跳过
# 为什么：clangd 只认 UTF-8；且必须无 BOM（Keil C51 把 BOM 当非法字符）
# ============================================================
param([string]$Mode = "")

$script:NI = [bool]$Mode   # 参数模式 = 非交互，跳过二次确认

# 健壮输入：输入流结束（EOF）返回 $null
function Get-Input([string]$prompt) {
    $v = Read-Host $prompt
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

$gbk  = [System.Text.Encoding]::GetEncoding(936)
$utf8 = [System.Text.UTF8Encoding]::new($false)   # $false = 不带 BOM

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $PWD.Path "_gbk_backup"
$backupDir  = Join-Path $backupRoot $ts

function Get-SourceFiles { Get-ChildItem -Recurse -File | Where-Object { $_.Extension -in '.c','.h' -and $_.FullName -notlike "$backupRoot*" } }

function Test-IsUtf8([byte[]]$bytes) {
    try { $null = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes); return $true } catch { return $false }
}

# ---------------- 状态查看（只读） ----------------
function Show-Status {
    Write-Host ""
    Write-Host "==================== 编码状态 ====================" -ForegroundColor Cyan
    Write-Host "  原理：逐文件用严格 UTF-8 解码尝试——" -ForegroundColor DarkGray
    Write-Host "        能解出 = UTF-8（无需转），解不出 = GBK（需要转）。" -ForegroundColor DarkGray
    $files = Get-SourceFiles
    if (-not $files) {
        Write-Host ("  当前目录（{0}）没有 .c/.h 文件" -f $PWD.Path) -ForegroundColor Yellow
        return
    }
    Write-Host ""
    $gbkCount = 0
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($PWD.Path.Length).TrimStart('\')
        if (Test-IsUtf8 ([System.IO.File]::ReadAllBytes($f.FullName))) {
            Write-Host ("  [UTF-8] {0}" -f $rel) -ForegroundColor Green
        } else {
            Write-Host ("  [GBK  ] {0}" -f $rel) -ForegroundColor Red
            $gbkCount++
        }
    }
    Write-Host ""
    Write-Host ("  共 {0} 个文件，其中 {1} 个 GBK 需要转换" -f $files.Count, $gbkCount) -ForegroundColor Yellow
    $dirs = Get-ChildItem $backupRoot -Directory -ErrorAction SilentlyContinue
    if ($dirs) { Write-Host ("  有备份可还原：{0} 份（最新: {1}）" -f $dirs.Count, $dirs[0].Name) -ForegroundColor Green }
    else { Write-Host "  暂无备份（转换过才生成）" -ForegroundColor DarkGray }
}

# ---------------- 转换 ----------------
function Convert-Now {
    Write-Host ""
    Write-Host "==================== 转换 GBK → UTF-8 ====================" -ForegroundColor Cyan
    Write-Host "  只转确实为 GBK 的文件；转换前把原文备份到 _gbk_backup\<时间戳>\" -ForegroundColor DarkGray
    $files = Get-SourceFiles
    $todo = @($files | Where-Object { -not (Test-IsUtf8 ([System.IO.File]::ReadAllBytes($_.FullName))) })
    if ($todo.Count -eq 0) {
        Write-Host "  没有需要转换的 GBK 文件（都已是 UTF-8）" -ForegroundColor Green
        return
    }
    Write-Host ("  将转换以下 {0} 个文件：" -f $todo.Count) -ForegroundColor Yellow
    foreach ($f in $todo) { Write-Host ("    - {0}" -f $f.FullName.Substring($PWD.Path.Length).TrimStart('\')) }
    if (-not $script:NI) {
        $y = Get-Input "  确认转换？(Y/n，回车=转换)"
        if ($null -eq $y) { Write-Host "  已取消" -ForegroundColor Yellow; return }
        if ($y -ne "" -and $y -notmatch '^[Yy]$') { Write-Host "  已取消" -ForegroundColor Yellow; return }
    }
    foreach ($f in $todo) {
        $b = [System.IO.File]::ReadAllBytes($f.FullName)
        $rel = $f.FullName.Substring($PWD.Path.Length).TrimStart('\')
        $dest = Join-Path $backupDir $rel
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        Copy-Item $f.FullName $dest -Force
        [System.IO.File]::WriteAllText($f.FullName, $gbk.GetString($b), $utf8)
        Write-Host ("  转换: {0}" -f $rel)
    }
    Write-Host ("  完成。原文件备份在: {0}" -f $backupDir) -ForegroundColor Green
}

# ---------------- 还原（撤回） ----------------
function Restore-Now {
    Write-Host ""
    Write-Host "==================== 还原上次转换 ====================" -ForegroundColor Cyan
    Write-Host "  从最新一份备份恢复 GBK 原文（撤销转换）。" -ForegroundColor DarkGray
    $dirs = Get-ChildItem $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    if (-not $dirs) { Write-Host "  没有可还原的备份（_gbk_backup 不存在、为空或被手动删除）——无法还原，只能重新转换" -ForegroundColor Yellow; return }
    Write-Host ("  备份来源: {0}" -f $dirs[0].FullName)
    if (-not $script:NI) {
        $y = Get-Input "  确认还原？(Y/n，回车=还原)"
        if ($null -eq $y) { Write-Host "  已取消" -ForegroundColor Yellow; return }
        if ($y -ne "" -and $y -notmatch '^[Yy]$') { Write-Host "  已取消" -ForegroundColor Yellow; return }
    }
    $src = $dirs[0].FullName
    $n = 0
    Get-ChildItem $src -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length).TrimStart('\')
        $dest = Join-Path $PWD.Path $rel
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        Copy-Item $_.FullName $dest -Force
        $n++
    }
    Write-Host ("  已还原 {0} 个文件（GBK 原文）" -f $n) -ForegroundColor Green
}

# ---------------- 清理备份 ----------------
function Clean-Now {
    Write-Host ""
    Write-Host "==================== 清理备份 ====================" -ForegroundColor Cyan
    Write-Host "  强制删除 _gbk_backup 全部备份，之后无法再还原。" -ForegroundColor DarkGray
    if (-not (Test-Path $backupRoot)) { Write-Host "  _gbk_backup 不存在，无需清理" -ForegroundColor Yellow; return }
    if (-not $script:NI) {
        $y = Get-Input "  确认删除全部备份？不可恢复！(y/N，回车=取消)"
        if ($null -eq $y -or $y -notmatch '^[Yy]$') { Write-Host "  已取消" -ForegroundColor Yellow; return }
    }
    Remove-Item $backupRoot -Recurse -Force
    Write-Host ("  已删除: {0}" -f $backupRoot) -ForegroundColor Yellow
}

# ---------------- 参数模式 ----------------
if ($Mode) {
    switch ($Mode) {
        "status"  { Show-Status }
        "convert" { Convert-Now }
        "restore" { Restore-Now }
        "clean"   { Clean-Now }
        default   { Write-Host "未知模式: $Mode（可用 status / convert / restore / clean）" -ForegroundColor Yellow }
    }
    exit
}

# ---------------- 菜单循环 ----------------
:menu while ($true) {
    Write-Host ""
    Write-Host ("=============== 编码转换工具 ===============") -ForegroundColor Cyan
    Write-Host ("  当前目录: {0}" -f $PWD.Path) -ForegroundColor DarkGray
    Write-Host "  [1] 查看编码状态"
    Write-Host "      哪些文件是 GBK 需要转；是否有备份"
    Write-Host "  [2] 转换 GBK → UTF-8 无 BOM"
    Write-Host "      已转换的跳过；先列清单再确认；原文自动备份"
    Write-Host "  [3] 还原上次转换"
    Write-Host "      从最新备份恢复 GBK 原文（撤回）"
    Write-Host "  [4] 清理备份"
    Write-Host "      强制删除 _gbk_backup；不可恢复；需确认"
    Write-Host "  [0] 退出"
    $sel = Get-Input "  选择"
    if ($null -eq $sel) { Write-Host "  输入结束，退出。"; break menu }
    switch ($sel) {
        "1" { Show-Status }
        "2" { Convert-Now }
        "3" { Restore-Now }
        "4" { Clean-Now }
        "0" { Write-Host "  退出。"; break menu }
        default { Write-Host "  无效输入，请输入 0-4" -ForegroundColor Yellow }
    }
}
