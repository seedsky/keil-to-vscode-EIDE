@echo off
chcp 65001 >nul
REM ============================================================
REM 一键配置项目.bat - 输入项目目录，自动检查并配置该项目 
REM 用法：双击运行，输入项目目录；或直接把工程文件夹拖到本文件上 
REM 原理：自动读取工程类型（工具链/目标名），复制 .clangd 和 
REM       .clang-format（自动修正编译数据库路径），修正 eide.yml
REM       的工具链/文件注册/包含目录，全程自动备份可撤销 
REM 每步都会说明：做了什么 / 为什么 / 后果 
REM 注意：必须和 scripts\6-configure-project.ps1 保持同目录 
REM ============================================================
if not "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\6-configure-project.ps1" -Project "%~1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\6-configure-project.ps1"
)
pause