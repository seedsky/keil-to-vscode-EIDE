@echo off
chcp 65001 >nul
REM ============================================================
REM 2-自动配置.bat - 检测并配置 Keil + EIDE + clangd（第 2 步） 
REM 原理：脚本读取 Keil 安装目录，写入 clangd 全局配置和 EIDE 设置 
REM       配置文件位置：%LOCALAPPDATA%\clangd\config.yaml
REM 用法：双击运行，看每项检测结果（OK 或失败原因） 
REM 注意：Keil 装好后再跑，检测失败项按提示手动处理 
REM ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\2-setup-global-clangd.ps1" %*
pause