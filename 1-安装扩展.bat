@echo off
chcp 65001 >nul
REM ============================================================
REM 1-安装扩展.bat - 安装 VSCode 扩展（第 1 步） 
REM 原理：VSCode 扩展用命令行批量安装，比手动点 13 个快且不遗漏 
REM 用法：双击运行，等脚本跑完自动暂停 
REM 注意：需要 VSCode 已安装，装完后重启 VSCode
REM ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\1-install-extensions.ps1" %*
pause