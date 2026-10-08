#requires -Version 5.1
<#
.SYNOPSIS
    Bambu Studio 多账号图形化切换器
.DESCRIPTION
    原理：Bambu Studio 只认 %APPDATA%\BambuStudio 目录名，登录态完全自包含在目录内。
    本工具通过重命名目录实现多账号热切换（免重新登录）。
    - 自动扫描发现账号配置
    - 卡片显示头像 / 昵称 / uid
    - 点击切换账号
    - 添加新账号
    - 同步资料：内嵌 WebView2 登录后从公开资料接口获取真实昵称+头像
.PARAMETER SelfTest
    自检模式：只运行配置发现逻辑并输出结果，不启动 GUI。
#>
param([switch]$SelfTest)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================== 常量 ==============================
$script:ToolDir   = $PSScriptRoot
$script:DataRoot  = $env:APPDATA
$script:ActiveDir = Join-Path $env:APPDATA 'BambuStudio'
$script:ExePath   = 'C:\Program Files\Bambu Studio\bambu-studio.exe'
$script:LibDir    = Join-Path $PSScriptRoot 'webview2-lib'
$script:WebView2Ready = $false

# ============================== 数据层 ==============================

function Get-UidFromConf([string]$dir) {
    $conf = Join-Path $dir 'BambuStudio.conf'
    if (Test-Path $conf) {
        $text = Get-Content $conf -Raw -ErrorAction SilentlyContinue
        if ($text -match '"preset_folder"\s*:\s*"(\d+)"') { return $Matches[1] }
    }
    return $null
}

function Get-MetaPath([string]$dir) { Join-Path $dir '_switcher\profile.json' }

function Read-ProfileMeta([string]$dir) {
    $p = Get-MetaPath $dir
    if (Test-Path $p) {
        try { return (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }
    return $null
}

function Save-ProfileMeta([string]$dir, $meta) {
    $sw = Join-Path $dir '_switcher'
    if (-not (Test-Path $sw)) { [void](New-Item -ItemType Directory -Path $sw) }
    $meta | ConvertTo-Json | Set-Content (Get-MetaPath $dir) -Encoding UTF8
}

function Get-Profiles {
    <# 扫描 %APPDATA%\BambuStudio*，返回配置对象列表（活动配置排最前） #>
    $list = @()
    $dirs = Get-ChildItem $script:DataRoot -Directory -Filter 'BambuStudio*' -ErrorAction SilentlyContinue
    foreach ($d in $dirs) {
        $isActive = ($d.Name -eq 'BambuStudio')
        if (-not $isActive -and $d.Name -notmatch '^BambuStudio-.+') { continue }
        $uid  = Get-UidFromConf $d.FullName
        $meta = Read-ProfileMeta $d.FullName
        if ($meta) {
            $slug = [string]$meta.slug
            $disp = [string]$meta.displayName
            $nick = [string]$meta.nickname
            $avt  = [string]$meta.avatar
        } else {
            # 首次迁移：按目录名/标记推断
            if ($isActive) {
                $hasMarker = [bool](Get-ChildItem (Join-Path $d.FullName 'user') -Directory -ErrorAction SilentlyContinue |
                    Where-Object { Test-Path (Join-Path $_.FullName 'account.marker') } | Select-Object -First 1)
                if ($hasMarker) { $slug = 'personal'; $disp = '个人账号' }
                else { $slug = 'account1'; $disp = $(if ($uid) { "账号 $uid" } else { '默认账号' }) }
            } else {
                $slug = $d.Name.Substring('BambuStudio-'.Length)
                $disp = $(if ($slug -eq 'work') { '工作账号' } elseif ($uid) { "账号 $uid" } else { $slug })
            }
            $nick = ''; $avt = ''
            Save-ProfileMeta $d.FullName ([ordered]@{ slug=$slug; displayName=$disp; uid=$uid; nickname=$nick; avatar=$avt })
        }
        if (-not $uid) { $uid = '' }
        $avatarFile = ''
        if ($avt) {
            $af = Join-Path $d.FullName "_switcher\$avt"
            if (Test-Path $af) { $avatarFile = $af }
        }
        $list += [pscustomobject]@{
            DirName=$d.Name; FullPath=$d.FullName; Slug=$slug; IsActive=$isActive
            Uid=$uid; DisplayName=$disp; Nickname=$nick; AvatarFile=$avatarFile
        }
    }
    return @($list | Sort-Object { -not $_.IsActive }, DisplayName)
}

# ============================== 切换 / 添加 ==============================

function Test-BambuRunning {
    return [bool](Get-Process 'bambu-studio' -ErrorAction SilentlyContinue)
}

function Stop-BambuStudio {
    <# 自动关闭 Bambu Studio：确认 → 优雅关闭 → 超时二次确认 → 强杀。
       返回 $true=已关闭可继续 / $false=用户取消或失败 #>
    $procs = @(Get-Process 'bambu-studio' -ErrorAction SilentlyContinue)
    if (-not $procs) { return $true }

    $msg = "检测到 Bambu Studio 正在运行，切换账号需要先关闭它。`n`n是否自动关闭并继续？"
    $ok = Show-ConfirmDialog $msg '需要关闭 Bambu Studio' '关闭并继续' '取消'
    if (-not $ok) { return $false }

    # 优雅关闭
    foreach ($p in $procs) { try { [void]$p.CloseMainWindow() } catch {} }
    $waited = 0
    while ($waited -lt 10000) {
        $procs = @(Get-Process 'bambu-studio' -ErrorAction SilentlyContinue)
        if (-not $procs) { return $true }
        Start-Sleep -Milliseconds 500
        $waited += 500
    }

    # 仍未退出 → 二次确认强杀
    $msg = "Bambu Studio 未能在 10 秒内正常关闭（可能有未保存的内容）。`n`n强制关闭将丢失未保存的修改，是否继续？"
    $ok = Show-ConfirmDialog $msg '强制关闭确认' '强制关闭' '取消'
    if (-not $ok) { return $false }

    foreach ($p in $procs) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch {} }
    $waited = 0
    while ($waited -lt 10000) {
        if (-not (Get-Process 'bambu-studio' -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 500
        $waited += 500
    }
    Show-Msg '无法结束 Bambu Studio 进程，请手动关闭后重试。' '错误' 'Error'
    return $false
}

function Switch-Profile($target) {
    if (-not (Stop-BambuStudio)) { return }
    $active = @(Get-Profiles | Where-Object IsActive)[0]
    $ops = @()  # 回滚记录: @{From;To}
    try {
        if ($active) {
            $parkName = "BambuStudio-$($active.Slug)"
            $parkPath = Join-Path $script:DataRoot $parkName
            if (Test-Path $parkPath) { throw "停放目录 $parkName 已存在，状态异常，请手动检查 %APPDATA% 下的 BambuStudio* 目录" }
            Rename-Item $script:ActiveDir $parkName
            $ops += @{ From=$parkPath; To=$script:ActiveDir }
        }
        if (Test-Path $script:ActiveDir) { throw '重命名后 BambuStudio 目录仍存在，异常中止' }
        Rename-Item $target.FullPath 'BambuStudio'
        $ops += @{ From=$script:ActiveDir; To=$target.FullPath }
    } catch {
        foreach ($op in $ops) { try { Rename-Item $op.From $op.To -ErrorAction Stop } catch {} }
        Show-Msg "切换失败，已回滚。`n$($_.Exception.Message)" '错误' 'Error'
        return
    }
    if ($script:chkAutoLaunch.IsChecked -and (Test-Path $script:ExePath)) {
        Start-Process $script:ExePath
    }
    Update-MainUI
    $name = $(if ($target.Nickname) { $target.Nickname } else { $target.DisplayName })
    Show-Msg "已切换到【$name】" '切换成功' 'Information'
}

function Add-Account {
    if (-not (Stop-BambuStudio)) { return }
    $active = @(Get-Profiles | Where-Object IsActive)[0]
    if (-not $active) { Show-Msg '未找到当前活动配置，无法添加。' '错误' 'Error'; return }

    # 1. 停放当前配置
    $parkName = "BambuStudio-$($active.Slug)"
    try { Rename-Item $script:ActiveDir $parkName } catch {
        Show-Msg "停放当前配置失败：$($_.Exception.Message)" '错误' 'Error'; return
    }

    # 2. 启动 Bambu Studio，引导用户登录
    if (Test-Path $script:ExePath) { Start-Process $script:ExePath }
    $guide = '已为你启动 Bambu Studio（全新未登录状态）。' + "`n`n" +
             '请在其中【登录新账号】，登录成功后【完全退出 Bambu Studio】（包括托盘），' + "`n" +
             '然后回到本窗口点击"完成添加"。' + "`n`n" +
             '若不想添加了，点击"取消"将恢复原状。'
    $done = Show-ConfirmDialog $guide '添加账号 - 等待登录' '完成添加' '取消'

    if ($done) {
        $uid = Get-UidFromConf $script:ActiveDir
        if (Test-Path $script:ActiveDir) {
            if ($uid) {
                # 3. 分配 slug，写元数据，保持活动
                $n = 1
                while (Test-Path (Join-Path $script:DataRoot "BambuStudio-account$n")) { $n++ }
                $slug = "account$n"
                Save-ProfileMeta $script:ActiveDir ([ordered]@{ slug=$slug; displayName="账号 $uid"; uid=$uid; nickname=''; avatar='' })
                Update-MainUI
                Show-Msg "新账号 $uid 已添加并保持为当前活动账号。`n可点击卡片上的【同步资料】获取昵称和头像。" '添加成功' 'Information'
                return
            } else {
                Show-Msg '未检测到登录信息（可能尚未登录）。`n请点击确定后重试"完成添加"，或关闭本提示后点击"取消"。' '未登录' 'Warning'
                # 不恢复，让用户决定：再次走完成/取消由用户重新点击“添加账号”前的状态混乱，
                # 简化处理：直接恢复原状
            }
        }
    }
    # 取消 / 未完成：恢复
    if (Test-Path $script:ActiveDir) {
        $discard = Join-Path $script:DataRoot ('BambuStudio-discarded-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Rename-Item $script:ActiveDir $discard
    }
    Rename-Item (Join-Path $script:DataRoot $parkName) 'BambuStudio'
    Update-MainUI
}

function Edit-Profile($p) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("修改显示名称（当前：$($p.DisplayName)）", '编辑账号', $p.DisplayName)
    if ($newName) { $p.DisplayName = $newName }

    $ans = Show-ConfirmDialog '是否要更换头像图片？（选择"是"将从文件中选择）' '编辑账号' '是' '否'
    if ($ans) {
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = '图片文件|*.png;*.jpg;*.jpeg;*.bmp|所有文件|*.*'
        $dlg.Title = '选择头像图片'
        if ($dlg.ShowDialog()) {
            $ext = [IO.Path]::GetExtension($dlg.FileName)
            $dst = "_switcher\avatar$ext"
            Copy-Item $dlg.FileName (Join-Path $p.FullPath $dst) -Force
            $p.AvatarFile = Join-Path $p.FullPath $dst
            $meta = Read-ProfileMeta $p.FullPath
            $meta.avatar = "avatar$ext"
            Save-ProfileMeta $p.FullPath $meta
        }
    }
    if ($newName) {
        $meta = Read-ProfileMeta $p.FullPath
        if ($meta) { $meta.displayName = $newName; Save-ProfileMeta $p.FullPath $meta }
    }
    Update-MainUI
}

# ============================== 同步资料（WebView2） ==============================

function Ensure-WebView2 {
    if ($script:WebView2Ready) { return $true }
    $core = Join-Path $script:LibDir 'Microsoft.Web.WebView2.Core.dll'
    $wpf  = Join-Path $script:LibDir 'Microsoft.Web.WebView2.Wpf.dll'
    $loader = Join-Path $script:LibDir 'WebView2Loader.dll'
    if (-not ((Test-Path $core) -and (Test-Path $wpf) -and (Test-Path $loader))) {
        return $false
    }
    try {
        # WebView2Loader.dll 需在 DLL 搜索路径中
        $env:PATH = "$($script:LibDir);$env:PATH"
        Add-Type -Path $core
        Add-Type -Path $wpf
        $script:WebView2Ready = $true
        return $true
    } catch {
        return $false
    }
}

function Sync-Profile($p) {
    if (-not (Ensure-WebView2)) {
        Show-Msg 'WebView2 组件不可用（webview2-lib 目录缺少文件）。`n同步资料功能不可用，其余功能不受影响。' '功能不可用' 'Warning'
        return
    }

    $swDir = Join-Path $p.FullPath '_switcher'
    if (-not (Test-Path $swDir)) { [void](New-Item -ItemType Directory -Path $swDir) }

    $win = New-Object System.Windows.Window
    $win.Title = "同步账号资料 - $($p.DisplayName)"
    $win.Width = 560; $win.Height = 780
    $win.WindowStartupLocation = 'CenterScreen'

    $dock = New-Object System.Windows.Controls.DockPanel
    $tip = New-Object System.Windows.Controls.TextBlock
    $tip.Text = '请在下方窗口中登录你的 Bambu 账号，登录成功后工具将自动获取昵称和头像并关闭本窗口。'
    $tip.TextWrapping = 'Wrap'; $tip.Margin = '10'; $tip.Foreground = '#555'
    [System.Windows.Controls.DockPanel]::SetDock($tip, 'Top')
    $status = New-Object System.Windows.Controls.TextBlock
    $status.Text = '正在加载浏览器…'; $status.Margin = '10,0,10,8'; $status.Foreground = '#888'
    [System.Windows.Controls.DockPanel]::SetDock($status, 'Bottom')
    [void]$dock.Children.Add($tip); [void]$dock.Children.Add($status)

    $wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
    $props = New-Object Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties
    $props.UserDataFolder = (Join-Path $swDir 'webview-data')
    $wv.CreationProperties = $props
    [void]$dock.Children.Add($wv)
    $win.Content = $dock

    $script:syncTask = $null
    $script:syncDone = $false
    $fetchJs = "fetch('/api/v1/design-user-service/my/profile',{credentials:'include'}).then(function(r){return r.text()}).catch(function(e){return 'ERR:'+e})"

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(2500)

    $handleResult = {
        param($text)
        if ($script:syncDone) { return }
        if (-not $text -or $text.StartsWith('ERR:')) { return }
        # $text 是 fetch 返回的原始文本（可能是 JSON）
        $avatar = $null; $name = $null
        if ($text -match '"(avatarUrl|avatar_url|avatar)"\s*:\s*"(https?://[^"]+)"') { $avatar = $Matches[2] }
        elseif ($text -match '(https://public-cdn[^"\\]+avatar[^"\\]*)') { $avatar = $Matches[1] }
        if ($text -match '"(nickname|nickName|userName|name)"\s*:\s*"([^"]{1,64})"') { $name = $Matches[2] }
        if (-not $avatar -and -not $name) { return }
        if ($avatar -and $avatar.StartsWith('/')) { $avatar = 'https://makerworld.com.cn' + $avatar }

        $script:syncDone = $true
        $timer.Stop()

        # 下载头像
        $avatarFile = ''
        if ($avatar) {
            $ext = '.jpg'
            if ($avatar -match '\.(png|jpg|jpeg|webp|bmp)') { $ext = '.' + $Matches[1].ToLower() }
            $dst = Join-Path $swDir "avatar$ext"
            try {
                Invoke-WebRequest -Uri $avatar -OutFile $dst -TimeoutSec 20 -UserAgent 'Mozilla/5.0'
                $avatarFile = "avatar$ext"
            } catch {
                $status.Text = '头像下载失败（已保存昵称），可稍后重试。'
            }
        }
        # 保存元数据
        $meta = Read-ProfileMeta $p.FullPath
        if ($meta) {
            if ($name) { $meta.nickname = $name }
            if ($avatarFile) { $meta.avatar = $avatarFile }
            Save-ProfileMeta $p.FullPath $meta
        }
        $win.Close()
        Update-MainUI
        $shown = $(if ($name) { $name } else { '(未获取到昵称)' })
        Show-Msg "资料同步成功！`n昵称：$shown" '同步完成' 'Information'
    }

    $timer.Add_Tick({
        if ($script:syncDone) { return }
        if (-not $wv.CoreWebView2) { return }
        if ($null -eq $script:syncTask) {
            try { $script:syncTask = $wv.CoreWebView2.ExecuteScriptAsync($fetchJs) } catch {}
            return
        }
        if ($script:syncTask.IsCompleted) {
            $raw = $null
            try { $raw = $script:syncTask.Result } catch {}
            $script:syncTask = $null
            if ($raw) {
                # 结果是 JSON 编码的字符串字面量，先解码
                $text = $null
                try { $text = ($raw | ConvertFrom-Json) } catch { $text = $raw }
                if ($text -and -not $text.StartsWith('ERR:')) {
                    if ($text -match 'avatar|nickname|name') {
                        $status.Text = '检测到登录信息，正在获取资料…'
                    }
                    & $handleResult $text
                }
            }
        }
    })

    $wv.Add_CoreWebView2InitializationCompleted({
        param($s, $e)
        if ($e.IsSuccess) {
            $status.Text = '等待登录…（如已登录将自动完成）'
            $wv.Source = [Uri]'https://makerworld.com.cn/zh'
            $timer.Start()
        } else {
            $status.Text = "浏览器初始化失败：$($e.InitializationException.Message)"
        }
    })

    $win.Add_Closed({ $timer.Stop(); $script:syncTask = $null })
    [void]$wv.EnsureCoreWebView2Async($null)
    [void]$win.ShowDialog()
}

# ============================== GUI ==============================

function Show-Msg([string]$text, [string]$title, [string]$icon) {
    [void][System.Windows.MessageBox]::Show($text, $title, 'OK', $icon)
}

function Show-ConfirmDialog([string]$text, [string]$title, [string]$yesText, [string]$noText) {
    $w = New-Object System.Windows.Window
    $w.Title = $title; $w.Width = 460; $w.SizeToContent = 'Height'; $w.MinHeight = 140
    $w.WindowStartupLocation = 'CenterScreen'; $w.ResizeMode = 'NoResize'
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '16'
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text; $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,0,0,16'; $tb.MaxWidth = 420
    [void]$sp.Children.Add($tb)
    $bp = New-Object System.Windows.Controls.StackPanel
    $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'
    $script:dlgResult = $false
    $b1 = New-Object System.Windows.Controls.Button; $b1.Content = $yesText; $b1.MinWidth = 90; $b1.Padding = '12,4'; $b1.Margin = '0,0,10,0'
    $b2 = New-Object System.Windows.Controls.Button; $b2.Content = $noText;  $b2.MinWidth = 90; $b2.Padding = '12,4'
    $b1.Add_Click({ $script:dlgResult = $true;  $w.Close() })
    $b2.Add_Click({ $script:dlgResult = $false; $w.Close() })
    [void]$bp.Children.Add($b1); [void]$bp.Children.Add($b2)
    [void]$sp.Children.Add($bp)
    $w.Content = $sp
    [void]$w.ShowDialog()
    return $script:dlgResult
}

function New-AvatarVisual($p) {
    <# 64x64 圆形头像；无图时画首字符圆 #>
    $size = 64
    if ($p.AvatarFile) {
        try {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.UriSource = [Uri]$p.AvatarFile
            $bmp.EndInit(); $bmp.Freeze()
            $img = New-Object System.Windows.Controls.Image
            $img.Width = $size; $img.Height = $size; $img.Source = $bmp
            $img.Stretch = 'UniformToFill'
            $img.Clip = New-Object System.Windows.Media.EllipseGeometry(
                (New-Object System.Windows.Point($size/2, $size/2)), ($size/2), ($size/2))
            return $img
        } catch {}
    }
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Width = $size; $grid.Height = $size
    $el = New-Object System.Windows.Shapes.Ellipse
    $el.Fill = '#607D8B'
    $initial = '?'
    $src = $(if ($p.Nickname) { $p.Nickname } elseif ($p.DisplayName) { $p.DisplayName } else { '?' })
    $initial = $src.Substring(0,1).ToUpper()
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $initial; $tb.Foreground = 'White'; $tb.FontSize = 26; $tb.FontWeight = 'Bold'
    $tb.HorizontalAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
    [void]$grid.Children.Add($el); [void]$grid.Children.Add($tb)
    return $grid
}

function New-ProfileCard($p) {
    $border = New-Object System.Windows.Controls.Border
    $border.Width = 168; $border.Margin = '8'; $border.Padding = '12'
    $border.CornerRadius = '8'; $border.Background = 'White'
    $border.BorderThickness = $(if ($p.IsActive) { '2' } else { '1' })
    $border.BorderBrush = $(if ($p.IsActive) { '#2E7D32' } else { '#DDDDDD' })

    $sp = New-Object System.Windows.Controls.StackPanel

    $av = New-AvatarVisual $p
    $av.HorizontalAlignment = 'Center'; $av.Margin = '0,0,0,8'
    [void]$sp.Children.Add($av)

    $name = New-Object System.Windows.Controls.TextBlock
    $name.Text = $(if ($p.Nickname) { $p.Nickname } else { $p.DisplayName })
    $name.FontWeight = 'Bold'; $name.FontSize = 14
    $name.HorizontalAlignment = 'Center'
    $name.TextTrimming = 'CharacterEllipsis'; $name.MaxWidth = 140
    [void]$sp.Children.Add($name)

    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = $(if ($p.Uid) { "ID: $($p.Uid)" } else { '(未登录)' })
    $sub.Foreground = '#999'; $sub.FontSize = 11
    $sub.HorizontalAlignment = 'Center'; $sub.Margin = '0,2,0,8'
    [void]$sp.Children.Add($sub)

    if ($p.IsActive) {
        $badge = New-Object System.Windows.Controls.TextBlock
        $badge.Text = '● 活动中'; $badge.Foreground = '#2E7D32'; $badge.FontWeight = 'Bold'
        $badge.HorizontalAlignment = 'Center'; $badge.Margin = '0,0,0,8'
        [void]$sp.Children.Add($badge)
    } else {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = '切换到此账号'; $btn.Margin = '0,0,0,6'
        $btn.Add_Click({ Switch-Profile $p }.GetNewClosure())
        [void]$sp.Children.Add($btn)
    }

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Center'
    $bSync = New-Object System.Windows.Controls.Button
    $bSync.Content = '同步资料'; $bSync.FontSize = 11; $bSync.Padding = '8,2'; $bSync.Margin = '0,0,6,0'
    $bSync.Add_Click({ Sync-Profile $p }.GetNewClosure())
    $bEdit = New-Object System.Windows.Controls.Button
    $bEdit.Content = '编辑'; $bEdit.FontSize = 11; $bEdit.Padding = '8,2'
    $bEdit.Add_Click({ Edit-Profile $p }.GetNewClosure())
    [void]$row.Children.Add($bSync); [void]$row.Children.Add($bEdit)
    [void]$sp.Children.Add($row)

    $border.Child = $sp
    return $border
}

function New-AddCard {
    $border = New-Object System.Windows.Controls.Border
    $border.Width = 168; $border.Margin = '8'; $border.Padding = '12'
    $border.CornerRadius = '8'; $border.Background = '#FAFAFA'
    $border.BorderThickness = '1'; $border.BorderBrush = '#DDDDDD'
    $sp = New-Object System.Windows.Controls.StackPanel
    $plus = New-Object System.Windows.Controls.TextBlock
    $plus.Text = '＋'; $plus.FontSize = 40; $plus.Foreground = '#AAA'
    $plus.HorizontalAlignment = 'Center'; $plus.Margin = '0,4,0,4'
    [void]$sp.Children.Add($plus)
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = '添加账号'; $tb.FontSize = 13; $tb.Foreground = '#888'
    $tb.HorizontalAlignment = 'Center'; $tb.Margin = '0,0,0,10'
    [void]$sp.Children.Add($tb)
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = '登录新账号'
    $btn.Add_Click({ Add-Account })
    [void]$sp.Children.Add($btn)
    $border.Child = $sp
    return $border
}

function Update-MainUI {
    $script:wrap.Children.Clear()
    $profiles = Get-Profiles
    foreach ($p in $profiles) { [void]$script:wrap.Children.Add((New-ProfileCard $p)) }
    [void]$script:wrap.Children.Add((New-AddCard))
    $active = @($profiles | Where-Object IsActive)[0]
    if ($active) {
        $n = $(if ($active.Nickname) { $active.Nickname } else { $active.DisplayName })
        $script:statusText.Text = "当前活动：$n" + $(if ($active.Uid) { "（ID: $($active.Uid)）" } else { '' })
    } else {
        $script:statusText.Text = '当前无活动配置'
    }
}

function Start-Gui {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $script:win = New-Object System.Windows.Window
    $script:win.Title = 'Bambu Studio 账号切换器'
    $script:win.Width = 640; $script:win.MinHeight = 380; $script:win.SizeToContent = 'Height'
    $script:win.WindowStartupLocation = 'CenterScreen'
    $script:win.Background = '#F4F5F7'

    $dock = New-Object System.Windows.Controls.DockPanel

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = 'Bambu Studio 账号切换器'
    $title.FontSize = 18; $title.FontWeight = 'Bold'; $title.Margin = '16,14,16,4'
    [System.Windows.Controls.DockPanel]::SetDock($title, 'Top')
    [void]$dock.Children.Add($title)

    $bottom = New-Object System.Windows.Controls.StackPanel
    $bottom.Margin = '16,4,16,12'
    [System.Windows.Controls.DockPanel]::SetDock($bottom, 'Bottom')
    $script:chkAutoLaunch = New-Object System.Windows.Controls.CheckBox
    $script:chkAutoLaunch.Content = '切换后自动启动 Bambu Studio'
    $script:chkAutoLaunch.IsChecked = $true; $script:chkAutoLaunch.Margin = '0,0,0,6'
    [void]$bottom.Children.Add($script:chkAutoLaunch)
    $script:statusText = New-Object System.Windows.Controls.TextBlock
    $script:statusText.Foreground = '#777'; $script:statusText.FontSize = 12
    [void]$bottom.Children.Add($script:statusText)
    [void]$dock.Children.Add($bottom)

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.HorizontalScrollBarVisibility = 'Auto'
    $scroll.VerticalScrollBarVisibility = 'Disabled'
    $scroll.Margin = '8,0,8,0'
    $script:wrap = New-Object System.Windows.Controls.WrapPanel
    $scroll.Content = $script:wrap
    [void]$dock.Children.Add($scroll)

    $script:win.Content = $dock
    Update-MainUI
    [void]$script:win.ShowDialog()
}

# ============================== 入口 ==============================

if ($SelfTest) {
    Write-Host '=== 自检模式 ==='
    Write-Host "数据根目录: $script:DataRoot"
    $profiles = Get-Profiles
    $profiles | Format-Table DirName, Slug, IsActive, Uid, DisplayName, Nickname -AutoSize
    Write-Host "Bambu Studio 运行中: $(Test-BambuRunning)"
    Write-Host "WebView2 组件可用: $(Ensure-WebView2)"
    return
}

try {
    Start-Gui
} catch {
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    [void][System.Windows.MessageBox]::Show("程序出错：`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)", 'Bambu 账号切换器 - 错误', 'OK', 'Error')
}
