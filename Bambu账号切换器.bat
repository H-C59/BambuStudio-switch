@echo off
REM ============================================
REM  Bambu Studio 账号切换器 - 启动器
REM  双击运行；GUI 主程序为同目录下的 ps1
REM ============================================
powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0BambuAccountSwitcher.ps1"
if errorlevel 1 (
    echo 启动失败，请检查 BambuAccountSwitcher.ps1 是否存在于同目录。
    pause
)
