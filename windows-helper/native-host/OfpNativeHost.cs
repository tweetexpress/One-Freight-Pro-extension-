// ONE Freight Pro native messaging host.
// Replaces the dathelper: protocol handler (browser -> PowerShell) that
// Malwarebytes flagged as Exploit.PayloadProcessBlock. The browser extension
// talks to this exe over stdio (Chrome native messaging); only the extension
// ID listed in the host manifest's allowed_origins can launch it.
//
// Message in:  { "to": "...", "cc": "...", "subject": "...", "body": "...", "mode": "draft"|"send" }
//          or  { "action": "log", "email": "..." }
// Message out: { "ok": true } or { "ok": false, "error": "..." }

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace OfpNativeHost
{
    static class Program
    {
        [DllImport("user32.dll")]
        static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

        static void Log(string message)
        {
            try
            {
                File.AppendAllText(Path.Combine(Path.GetTempPath(), "ofp-native-host.log"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + message + "\r\n");
            }
            catch { }
        }

        [STAThread]
        static int Main()
        {
            try
            {
                Dictionary<string, object> message = ReadMessage();
                if (message == null) return 0;
                WriteMessage(Handle(message));
                return 0;
            }
            catch (Exception ex)
            {
                Log("ERROR: " + ex);
                try
                {
                    WriteMessage(new Dictionary<string, object> { { "ok", false }, { "error", ex.Message } });
                }
                catch { }
                return 1;
            }
        }

        // ── Native messaging framing: 4-byte little-endian length + UTF-8 JSON ──

        static Dictionary<string, object> ReadMessage()
        {
            Stream stdin = Console.OpenStandardInput();
            byte[] lengthBytes = ReadExact(stdin, 4);
            if (lengthBytes == null) return null;
            int length = BitConverter.ToInt32(lengthBytes, 0);
            if (length <= 0 || length > 1024 * 1024) return null;
            byte[] buffer = ReadExact(stdin, length);
            if (buffer == null) return null;
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            return serializer.Deserialize<Dictionary<string, object>>(Encoding.UTF8.GetString(buffer));
        }

        static byte[] ReadExact(Stream stream, int count)
        {
            byte[] buffer = new byte[count];
            int read = 0;
            while (read < count)
            {
                int n = stream.Read(buffer, read, count - read);
                if (n <= 0) return null;
                read += n;
            }
            return buffer;
        }

        static void WriteMessage(Dictionary<string, object> obj)
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            byte[] bytes = Encoding.UTF8.GetBytes(serializer.Serialize(obj));
            Stream stdout = Console.OpenStandardOutput();
            stdout.Write(BitConverter.GetBytes(bytes.Length), 0, 4);
            stdout.Write(bytes, 0, bytes.Length);
            stdout.Flush();
        }

        // ── Message handling ─────────────────────────────────────────────────

        static string Str(Dictionary<string, object> d, string key)
        {
            object v;
            return d.TryGetValue(key, out v) && v != null ? v.ToString() : "";
        }

        static Dictionary<string, object> Ok()
        {
            return new Dictionary<string, object> { { "ok", true } };
        }

        static Dictionary<string, object> Handle(Dictionary<string, object> msg)
        {
            if (Str(msg, "action") == "log")
            {
                File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "broken-patterns.txt"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + Str(msg, "email") + "\r\n");
                return Ok();
            }

            string to = Str(msg, "to");
            string cc = Str(msg, "cc");
            string subject = Str(msg, "subject");
            string body = Str(msg, "body");
            string mode = Str(msg, "mode");
            if (mode == "") mode = "draft";
            if (to == "") throw new Exception("Missing recipient email.");

            Type outlookType = Type.GetTypeFromProgID("Outlook.Application");
            if (outlookType == null) throw new Exception("Outlook is not installed.");
            dynamic outlook = Activator.CreateInstance(outlookType);
            dynamic mail = outlook.CreateItem(0); // olMailItem

            mail.To = to;
            if (cc != "") mail.CC = cc;
            mail.Subject = subject;

            if (mode == "send")
            {
                // Use Outlook's Word editor, just like draft mode, so the default
                // signature and linked/embedded images finish hydrating before Send().
                dynamic inspector = mail.GetInspector;
                mail.Display(false);
                WaitForOutlookSignature(mail, 1200, 4500);
                InsertContentInEditor(inspector, body);
                mail.Save();
                Thread.Sleep(750);
                mail.Send();
                try { Marshal.ReleaseComObject(inspector); } catch { }
            }
            else
            {
                // Initialize the editor before showing the draft so Outlook inserts the
                // signature and our text is already in place when the compose window appears.
                dynamic inspector = mail.GetInspector;
                InsertContentInEditor(inspector, body);
                mail.Display(false);
                Thread.Sleep(150);
                BringInspectorToFront(inspector);
            }

            return Ok();
        }

        static void InsertContentInEditor(dynamic inspector, string text)
        {
            dynamic range = inspector.WordEditor.Range(0, 0);
            range.InsertBefore(text + "\r\n\r\n");
        }

        static void WaitForOutlookSignature(dynamic mail, int minMilliseconds, int maxMilliseconds)
        {
            DateTime started = DateTime.Now;
            int lastLength = -1;
            int stableReads = 0;

            do
            {
                Thread.Sleep(250);
                double elapsed = (DateTime.Now - started).TotalMilliseconds;
                string html = "";
                try { html = (string)mail.HTMLBody; } catch { }
                int length = (html ?? "").Length;

                if (length > 0 && length == lastLength)
                {
                    stableReads++;
                }
                else
                {
                    stableReads = 0;
                    lastLength = length;
                }

                if (elapsed >= minMilliseconds && stableReads >= 2) return;
            } while ((DateTime.Now - started).TotalMilliseconds < maxMilliseconds);
        }

        static void BringInspectorToFront(dynamic inspector)
        {
            try { inspector.Activate(); } catch { }
            try
            {
                IntPtr hwnd = new IntPtr(Convert.ToInt64(inspector.HWND));
                if (hwnd != IntPtr.Zero)
                {
                    ShowWindowAsync(hwnd, 5); // SW_SHOW
                    SetForegroundWindow(hwnd);
                }
            }
            catch { }
        }
    }
}
