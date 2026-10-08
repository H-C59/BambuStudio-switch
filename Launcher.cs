// Bambu Studio 账号切换器 - 单文件启动器
// 内嵌: BambuAccountSwitcher.ps1 + WebView2 托管 DLL
// 功能: 解压资源 → 检测/补齐运行环境(.NET 4.6.2+, WebView2 Runtime) → 启动 GUI
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class Launcher
{
    private const string AppName = "Bambu Studio 账号切换器";
    private const string DotNetUrl = "https://go.microsoft.com/fwlink/?linkid=2088631";       // .NET 4.8 web 安装包
    private const string WebView2Url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";   // WebView2 引导安装器
    private const string WebView2ClientId = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";

    private static readonly string ExtractDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BambuStudio-switch");

    [STAThread]
    private static int Main()
    {
        Application.EnableVisualStyles();
        try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; } catch { } // TLS 1.2

        try
        {
            if (!EnsureDotNet()) return 1;
            if (!EnsureWebView2Runtime()) return 1;
            ExtractResources();
            LaunchGui();
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("启动失败：\r\n" + ex.Message, AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    // ---------------- 环境检测与补齐 ----------------

    private static bool EnsureDotNet()
    {
        object rel = Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full", "Release", null);
        int release = rel is int ? (int)rel : 0;
        if (release >= 461808) return true; // >= .NET 4.6.2

        DialogResult r = MessageBox.Show(
            "本工具需要 .NET Framework 4.6.2 或更高版本（当前系统版本过低）。\r\n\r\n是否自动下载并安装 .NET Framework 4.8？（约 110MB，需要联网，安装过程可能弹出系统权限确认）",
            AppName + " - 环境检测", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (r != DialogResult.Yes) return false;

        string installer = Path.Combine(Path.GetTempPath(), "ndp48-web.exe");
        if (!Download(DotNetUrl, installer, ".NET Framework 4.8 安装包")) return false;
        RunAndWait(installer, "");
        rel = Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full", "Release", null);
        release = rel is int ? (int)rel : 0;
        if (release >= 461808) return true;

        MessageBox.Show(".NET Framework 安装尚未完成。请完成安装后重新运行本程序。", AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
        return false;
    }

    private static bool WebView2Installed()
    {
        string[] roots = new string[]
        {
            @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\" + WebView2ClientId,
            @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\EdgeUpdate\Clients\" + WebView2ClientId,
            @"HKEY_CURRENT_USER\SOFTWARE\Microsoft\EdgeUpdate\Clients\" + WebView2ClientId,
        };
        foreach (string k in roots)
        {
            object pv = Registry.GetValue(k, "pv", null);
            string v = pv as string;
            if (!string.IsNullOrEmpty(v) && v != "0.0.0.0") return true;
        }
        return false;
    }

    private static bool EnsureWebView2Runtime()
    {
        if (WebView2Installed()) return true;

        DialogResult r = MessageBox.Show(
            "检测到系统缺少 WebView2 Runtime（账号资料同步功能需要它）。\r\n\r\n是否自动下载并安装？（微软官方组件，约 150MB，需要联网）",
            AppName + " - 环境检测", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (r != DialogResult.Yes) return false;

        string installer = Path.Combine(Path.GetTempPath(), "MicrosoftEdgeWebview2Setup.exe");
        if (!Download(WebView2Url, installer, "WebView2 Runtime 安装器")) return false;

        RunAndWait(installer, "/silent /install");
        for (int i = 0; i < 30 && !WebView2Installed(); i++) Thread.Sleep(2000);
        if (WebView2Installed()) return true;

        // 静默安装失败 → 用交互方式再试一次（让用户看到安装界面/权限提示）
        RunAndWait(installer, "");
        for (int i = 0; i < 30 && !WebView2Installed(); i++) Thread.Sleep(2000);
        if (WebView2Installed()) return true;

        MessageBox.Show("WebView2 Runtime 安装未完成。\r\n可稍后手动安装：https://developer.microsoft.com/microsoft-edge/webview2/",
            AppName, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        return false;
    }

    // ---------------- 资源解压与启动 ----------------

    private static void ExtractResources()
    {
        Directory.CreateDirectory(ExtractDir);
        Directory.CreateDirectory(Path.Combine(ExtractDir, "webview2-lib"));
        Extract("app.ps1", Path.Combine(ExtractDir, "BambuAccountSwitcher.ps1"));
        Extract("Microsoft.Web.WebView2.Core.dll", Path.Combine(ExtractDir, "webview2-lib", "Microsoft.Web.WebView2.Core.dll"));
        Extract("Microsoft.Web.WebView2.Wpf.dll", Path.Combine(ExtractDir, "webview2-lib", "Microsoft.Web.WebView2.Wpf.dll"));
        Extract("WebView2Loader.dll", Path.Combine(ExtractDir, "webview2-lib", "WebView2Loader.dll"));
    }

    private static void Extract(string resName, string dst)
    {
        Assembly asm = Assembly.GetExecutingAssembly();
        using (Stream src = asm.GetManifestResourceStream(resName))
        {
            if (src == null) throw new Exception("内嵌资源缺失: " + resName);
            try
            {
                using (FileStream fs = new FileStream(dst, FileMode.Create, FileAccess.Write))
                    src.CopyTo(fs);
            }
            catch (IOException)
            {
                // 文件被占用（GUI 正在运行）→ 沿用已解压的旧版本，不视为错误
            }
        }
    }

    private static void LaunchGui()
    {
        string ps1 = Path.Combine(ExtractDir, "BambuAccountSwitcher.ps1");
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ps1 + "\"";
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        Process.Start(psi);
    }

    // ---------------- 工具 ----------------

    private static bool Download(string url, string dst, string what)
    {
        try
        {
            using (WebClient wc = new WebClient())
            {
                wc.Headers.Add("User-Agent", "Mozilla/5.0");
                wc.DownloadFile(url, dst);
            }
            return true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(what + "下载失败，请检查网络连接后重试。\r\n\r\n" + ex.Message,
                AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return false;
        }
    }

    private static void RunAndWait(string exe, string args)
    {
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = exe;
        psi.Arguments = args;
        psi.UseShellExecute = true;
        Process p = Process.Start(psi);
        if (p != null) p.WaitForExit();
    }
}
