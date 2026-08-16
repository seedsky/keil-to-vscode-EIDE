@echo off
chcp 65001 >nul
REM ============================================================
REM 3-编码转换.bat - 把工程源码从 GBK 转成 UTF-8 无 BOM（第 3 步） 
REM 原理：Keil 例程源码是 GBK，clangd 只认 UTF-8
REM       脚本把 .c 和 .h 统一转成 UTF-8 无 BOM（带 BOM 会破坏 C51 编译） 
REM 用法：把本文件复制到要转换的工程根目录再双击运行 
REM 注意：转换前先备份，只转 .c 和 .h 文件 
REM ============================================================
echo 请把本文件复制到要转换的工程根目录再双击运行 
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\3-convert-gbk-to-utf8.ps1" %*
pause