# ============================================================
# 1-install-extensions.ps1 — 扩展管理工具（循环菜单）
# 功能：状态展示 / 只装缺失 / 强制重装 / 全部卸载 / 退出
# 用法：双击运行（菜单循环，[0] 退出）
#       或参数一次执行：-Mode status / auto / force / uninstall
# 原则：先展示状态再操作，安装/卸载前二次确认
# ============================================================
param([string]$Mode = "")

$script:NI = [bool]$Mode   # 参数模式 = 非交互，跳过二次确认

# 健壮输入：输入流结束（EOF）返回 $null
function Get-Input([string]$prompt) {
    $v = Read-Host $prompt
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

$exts = @(
  @{ id = "cl.eide";                                       name = "EIDE 工程管理（编译/烧录）" },
  @{ id = "llvm-vs-code-extensions.vscode-clangd";         name = "clangd 代码引擎" },
  @{ id = "ms-vscode.vscode-serial-monitor";               name = "串口监视器" },
  @{ id = "ms-ceintl.vscode-language-pack-zh-hans";        name = "界面中文化" },
  @{ id = "zhuangtongfa.material-theme";                   name = "One Dark Pro 主题" },
  @{ id = "pkief.material-icon-theme";                     name = "文件图标" },
  @{ id = "usernamehw.errorlens";                          name = "错误行内显示" },
  @{ id = "christian-kohler.path-intellisense";            name = "路径补全" },
  @{ id = "intellsmi.comment-translate";                   name = "注释翻译" },
  @{ id = "mhutchie.git-graph";                            name = "Git 历史可视化" },
  @{ id = "ms-python.python";                              name = "Python" },
  @{ id = "alefragnani.project-manager";                   name = "项目切换" },
  @{ id = "bierner.markdown-preview-github-styles";        name = "Markdown GitHub 样式" }
)

function Test-ExtInstalled([string]$id) {
    Test-Path (Join-Path "$env:USERPROFILE\.vscode\extensions" "$id*")
}

# ---------------- 状态展示 ----------------
function Show-Status {
    Write-Host ""
    Write-Host "==================== 扩展状态 ====================" -ForegroundColor Cyan
    Write-Host "  原理：扩展装好后会在 %USERPROFILE%\.vscode\extensions\" -ForegroundColor DarkGray
    Write-Host "        生成同名文件夹，检查文件夹是否存在即知安装状态。" -ForegroundColor DarkGray
    Write-Host ""
    $n = 0
    foreach ($e in $exts) {
        if (Test-ExtInstalled $e.id) {
            Write-Host ("  [已装] {0,-52} {1}" -f $e.id, $e.name) -ForegroundColor Green
            $n++
        } else {
            Write-Host ("  [缺失] {0,-52} {1}" -f $e.id, $e.name) -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host ("  共 {0}/{1} 已安装" -f $n, $exts.Count) -ForegroundColor Yellow
}

# ---------------- 只装缺失 ----------------
function Invoke-Auto {
    Write-Host ""
    Write-Host "==================== 只装缺失的 ====================" -ForegroundColor Cyan
    Write-Host "  已安装的自动跳过，只补装缺失项；先列清单再确认。" -ForegroundColor DarkGray
    $missing = @($exts | Where-Object { -not (Test-ExtInstalled $_.id) })
    if ($missing.Count -eq 0) {
        Write-Host "  全部已安装，无需操作（要重装请选[2]）" -ForegroundColor Green
        return
    }
    Write-Host ("  以下 {0} 个缺失：" -f $missing.Count) -ForegroundColor Yellow
    foreach ($m in $missing) { Write-Host ("    - {0}（{1}）" -f $m.id, $m.name) }
    if (-not $script:NI) {
        $y = Get-Input "  确认安装？(Y/n，回车=安装)"
        if ($null -eq $y) { Write-Host "  已取消" -ForegroundColor Yellow; return }
        if ($y -ne "" -and $y -notmatch '^[Yy]$') { Write-Host "  已取消" -ForegroundColor Yellow; return }
    }
    foreach ($e in $missing) { Write-Host ("  安装: {0}" -f $e.id); code --install-extension $e.id }
    Write-Host "  完成" -ForegroundColor Green
}

# ---------------- 强制重装 ----------------
function Invoke-Force {
    Write-Host ""
    Write-Host "==================== 强制全部重装 ====================" -ForegroundColor Cyan
    Write-Host "  用 --force 覆盖安装全部 $($exts.Count) 个扩展。" -ForegroundColor DarkGray
    Write-Host "  用途：版本更新、扩展文件损坏时。" -ForegroundColor DarkGray
    if (-not $script:NI) {
        $y = Get-Input "  确认重装全部？(y/N，回车=取消)"
        if ($null -eq $y -or $y -notmatch '^[Yy]$') { Write-Host "  已取消" -ForegroundColor Yellow; return }
    }
    foreach ($e in $exts) { Write-Host ("  重装: {0}" -f $e.id); code --install-extension --force $e.id }
    Write-Host "  完成" -ForegroundColor Green
}

# ---------------- 全部卸载 ----------------
function Invoke-Uninstall {
    Write-Host ""
    Write-Host "==================== 全部卸载 ====================" -ForegroundColor Cyan
    Write-Host "  卸载全部 $($exts.Count) 个扩展，并强制删除残留文件夹。" -ForegroundColor DarkGray
    Write-Host "  用途：彻底清理环境。不可恢复！" -ForegroundColor DarkGray
    if (-not $script:NI) {
        $y = Get-Input "  确认卸载全部？(y/N，回车=取消)"
        if ($null -eq $y -or $y -notmatch '^[Yy]$') { Write-Host "  已取消" -ForegroundColor Yellow; return }
    }
    foreach ($e in $exts) {
        if (Test-ExtInstalled $e.id) { Write-Host ("  卸载: {0}" -f $e.id); code --uninstall-extension $e.id }
    }
    foreach ($e in $exts) {
        Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Directory -Filter "$($e.id)*" -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  完成" -ForegroundColor Green
}

# ---------------- 参数模式 ----------------
if ($Mode) {
    switch ($Mode) {
        "status"    { Show-Status }
        "auto"      { Show-Status; Invoke-Auto }
        "force"     { Invoke-Force }
        "uninstall" { Invoke-Uninstall }
        default     { Write-Host "未知模式: $Mode（可用 status / auto / force / uninstall）" -ForegroundColor Yellow }
    }
    exit
}

# ---------------- 菜单循环 ----------------
:menu while ($true) {
    Show-Status
    Write-Host ""
    Write-Host "==================== 请选择操作 ====================" -ForegroundColor Cyan
    Write-Host "  [1] 只装缺失的"
    Write-Host "      已装跳过，只补缺失；先列清单再确认"
    Write-Host "  [2] 强制全部重装"
    Write-Host "      --force 覆盖安装；版本更新/文件损坏时用"
    Write-Host "  [3] 全部卸载"
    Write-Host "      含强制删除残留文件夹；不可恢复"
    Write-Host "  [0] 退出"
    $sel = Get-Input "  选择"
    if ($null -eq $sel) { Write-Host "  输入结束，退出。"; break menu }
    switch ($sel) {
        "1" { Invoke-Auto }
        "2" { Invoke-Force }
        "3" { Invoke-Uninstall }
        "0" { Write-Host "  退出。"; break menu }
        default { Write-Host "  无效输入，请输入 0-3" -ForegroundColor Yellow }
    }
}
