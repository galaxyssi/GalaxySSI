using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Globalization;
using System.Runtime.InteropServices;

[ComImport, Guid("56FDF344-FD6D-11D0-958A-006097C9A090"), ClassInterface(ClassInterfaceType.None)]
class TaskbarListObject { }

[ComImport, Guid("EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface ITaskbarList3Badge {
    void HrInit();
    void AddTab(IntPtr hwnd);
    void DeleteTab(IntPtr hwnd);
    void ActivateTab(IntPtr hwnd);
    void SetActiveAlt(IntPtr hwnd);
    void MarkFullscreenWindow(IntPtr hwnd, [MarshalAs(UnmanagedType.Bool)] bool full);
    void SetProgressValue(IntPtr hwnd, ulong completed, ulong total);
    void SetProgressState(IntPtr hwnd, uint flags);
    void RegisterTab(IntPtr tab, IntPtr parent);
    void UnregisterTab(IntPtr tab);
    void SetTabOrder(IntPtr tab, IntPtr before);
    void SetTabActive(IntPtr tab, IntPtr parent, uint flags);
    void ThumbBarAddButtons(IntPtr hwnd, uint count, IntPtr buttons);
    void ThumbBarUpdateButtons(IntPtr hwnd, uint count, IntPtr buttons);
    void ThumbBarSetImageList(IntPtr hwnd, IntPtr images);
    void SetOverlayIcon(IntPtr hwnd, IntPtr icon, [MarshalAs(UnmanagedType.LPWStr)] string description);
}

public static class GalaxyTaskbarBadge {
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);

    public static Bitmap Draw(long count, int size) {
        var bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap)) {
            graphics.Clear(Color.Transparent);
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            float diameter = size * 0.7f;
            float margin = (size - diameter) / 2f;
            graphics.FillEllipse(Brushes.Black, margin, margin, diameter, diameter);
            string label = count > 99 ? "99+" : count.ToString(CultureInfo.InvariantCulture);
            float ratio = label.Length == 1 ? 0.75f : label.Length == 2 ? 0.65625f : 0.5f;
            using (var font = new Font("Segoe UI", (float)Math.Round(diameter * ratio), FontStyle.Bold, GraphicsUnit.Pixel))
            using (var format = new StringFormat(StringFormat.GenericTypographic)) {
                format.Alignment = StringAlignment.Center;
                format.LineAlignment = StringAlignment.Center;
                graphics.DrawString(label, font, Brushes.White, new RectangleF(0, 0, size, size), format);
            }
        }
        return bitmap;
    }

    public static void Run() {
        SetThreadDpiAwarenessContext(new IntPtr(-4));
        var taskbar = (ITaskbarList3Badge)new TaskbarListObject();
        try {
            taskbar.HrInit();
            Console.WriteLine("READY");
            Console.Out.Flush();
            string line;
            while ((line = Console.ReadLine()) != null) {
                var fields = line.Split('|');
                string id = fields.Length > 0 ? fields[0] : "0";
                try {
                    if (fields.Length != 3) throw new ArgumentException("Invalid request");
                    var hwnd = new IntPtr(long.Parse(fields[1], CultureInfo.InvariantCulture));
                    long count = long.Parse(fields[2], CultureInfo.InvariantCulture);
                    if (count < 0 || !IsWindow(hwnd)) throw new ArgumentException("Invalid window or count");
                    int dpi = (int)GetDpiForWindow(hwnd);
                    int size = Math.Max(16, Math.Min(128, (int)Math.Round(16.0 * dpi / 96)));
                    IntPtr icon = IntPtr.Zero;
                    try {
                        if (count > 0) using (var bitmap = Draw(count, size)) icon = bitmap.GetHicon();
                        taskbar.SetOverlayIcon(hwnd, icon, count > 0 ? count + " unread messages" : "");
                    } finally { if (icon != IntPtr.Zero) DestroyIcon(icon); }
                    Console.WriteLine("OK|" + id + "|" + size);
                } catch (Exception error) {
                    Console.WriteLine("ERR|" + id + "|" + error.GetType().Name);
                }
                Console.Out.Flush();
            }
        } finally { Marshal.FinalReleaseComObject(taskbar); }
    }
}
