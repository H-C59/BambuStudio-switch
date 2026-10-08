@echo off
REM ============================================================
REM  Bambu Studio 双账号热切换脚本
REM
REM  原理：Bambu Studio 只认 %APPDATA%\BambuStudio 这个目录名，
REM        登录状态(token)和账号预设全部自包含在该目录内。
REM        切换 = 把两个备份目录轮流改名为 BambuStudio。
REM
REM  账号目录：
REM    BambuStudio-personal  个人账号 <PERSONAL_UID>（带 account.marker 标记）
REM    BambuStudio-work      工作账号 <WORK_UID>
REM
REM  使用规则：
REM    1. 必须【完全退出】Bambu Studio（含托盘）后再运行本脚本
REM    2. 切换时不要有打印任务 / 设备监控在进行
REM    3. 长期未用的账号 token 若过期，重新登录一次即可
REM ============================================================

REM --- 1. 检查 Bambu Studio 是否在运行 ---
tasklist /FI "IMAGENAME eq bambu-studio.exe" | %SystemRoot%\System32\find.exe /I "bambu-studio.exe" >nul
if %errorlevel%==0 (
    echo [错误] 检测到 Bambu Studio 正在运行！
    echo        请先完全退出（包括托盘图标），再运行本脚本。
    pause
    exit /b 1
)

cd /d "%APPDATA%"

REM --- 2. 判断当前活动账号并轮换 ---
if not exist BambuStudio (
    REM 两个都处于停放状态，默认激活个人账号
    ren BambuStudio-personal BambuStudio
    echo 当前无活动目录，已激活【个人账号 <PERSONAL_UID>】
) else if exist "BambuStudio\user\<PERSONAL_UID>\account.marker" (
    REM 当前是个人号 → 切到工作号
    ren BambuStudio BambuStudio-personal
    ren BambuStudio-work BambuStudio
    echo 已切换到【工作账号 <WORK_UID>】
) else (
    REM 当前是工作号 → 切回个人号
    ren BambuStudio BambuStudio-work
    ren BambuStudio-personal BambuStudio
    echo 已切换到【个人账号 <PERSONAL_UID>】
)

if errorlevel 1 (
    echo [错误] 目录重命名失败，请检查 %APPDATA% 下的 BambuStudio* 目录状态！
    pause
    exit /b 1
)

REM --- 3. 启动 Bambu Studio ---
start "" "C:\Program Files\Bambu Studio\bambu-studio.exe"
exit /b 0
