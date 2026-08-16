@echo off
chcp 65001 >nul
REM ============================================================
REM 4-一键检测.bat - 环境自检（换机器或报错时先跑这个） 
REM 原理：逐项验证扩展、Keil 路径、clangd 配置、Python、编码、 
REM       工程结构等，每项都有目的说明 
REM 用法：在 VSCode 终端跑，或直接双击，按提示输入编号 
REM 注意：报错时把输出发出来，比看一屏红色报错快得多 
REM ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\4-verify.ps1" %*
pause