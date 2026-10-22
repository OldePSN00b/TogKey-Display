// Windows HID transport and read-only VIA 9 / Vial 6 client. No external packages.
using System;
using System.IO;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace TogKeyDisplay {
    public sealed class PadBusyException : IOException {
        public PadBusyException() : base("The pad is taking longer to reply; layer selection kept.") { }
    }
    public sealed class PadDisconnectedException : IOException {
        public PadDisconnectedException(string message,Exception inner=null) : base(message,inner) { }
    }
    public sealed class Snapshot {
        public ushort[] Keys = new ushort[36];
        public ushort[] Encoders = new ushort[8];
        public string[][] MacroTexts;
    }
    public sealed class Notice {
        public string Kind;
        public string Text;
        public Snapshot Data;
        public int Epoch;
        public Notice(string kind, string text = null, Snapshot data = null) { Kind=kind; Text=text; Data=data; }
    }

    public sealed class Hid : IDisposable {
        [StructLayout(LayoutKind.Sequential)] struct InterfaceData {
            public int Size; public Guid ClassGuid; public int Flags; public IntPtr Reserved;
        }
        [StructLayout(LayoutKind.Sequential)] struct Attributes {
            public int Size; public ushort Vendor, Product, Version;
        }
        [StructLayout(LayoutKind.Sequential)] struct Caps {
            public ushort Usage, UsagePage, InputLength, OutputLength, FeatureLength;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] Reserved;
            public ushort Nodes, InputButtons, InputValues, InputIndices, OutputButtons, OutputValues, OutputIndices, FeatureButtons, FeatureValues, FeatureIndices;
        }
        [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid guid);
        [DllImport("hid.dll")] static extern bool HidD_GetAttributes(SafeFileHandle handle, ref Attributes attributes);
        [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle handle, out IntPtr data);
        [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr data);
        [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr data, out Caps caps);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr SetupDiGetClassDevs(ref Guid guid, IntPtr enumerator, IntPtr parent, uint flags);
        [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr device, ref Guid guid, uint index, ref InterfaceData data);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref InterfaceData data, IntPtr detail, uint length, out uint needed, IntPtr device);
        [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);

        readonly Stream stream;
        readonly CancellationToken cancellation;
        public Action Waiting;
        public Action Replied;
        internal Hid(Stream reportStream,CancellationToken token) { stream=reportStream; cancellation=token; }
        Hid(string path, CancellationToken token) {
            cancellation=token;
            var handle=CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);
            if (handle.IsInvalid) { handle.Dispose(); throw new IOException("Cannot open the pad. Close Vial or its browser tab, then try again.", new Win32Exception(Marshal.GetLastWin32Error())); }
            // HID transfers are individual reports: disable FileStream's byte-stream buffering.
            try { stream=new FileStream(handle, FileAccess.ReadWrite, 1, true); }
            catch { handle.Dispose(); throw; }
        }
        public static Hid Open(CancellationToken token) {
            HidD_GetHidGuid(out Guid guid);
            IntPtr set=SetupDiGetClassDevs(ref guid, IntPtr.Zero, IntPtr.Zero, 0x12);
            if (set==new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            var paths=new List<string>();
            try {
                for (uint index=0; ; index++) {
                    token.ThrowIfCancellationRequested();
                    var entry=new InterfaceData { Size=Marshal.SizeOf<InterfaceData>() };
                    if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, index, ref entry)) {
                        int error=Marshal.GetLastWin32Error();
                        if (error==259) break;
                        throw new Win32Exception(error);
                    }
                    SetupDiGetDeviceInterfaceDetail(set, ref entry, IntPtr.Zero, 0, out uint size, IntPtr.Zero);
                    if (size<6) continue;
                    IntPtr detail=Marshal.AllocHGlobal((int)size);
                    try {
                        Marshal.WriteInt32(detail, IntPtr.Size==8 ? 8 : 6);
                        if (!SetupDiGetDeviceInterfaceDetail(set, ref entry, detail, size, out size, IntPtr.Zero)) continue;
                        string path=Marshal.PtrToStringUni(IntPtr.Add(detail,4));
                        // Do not open ordinary keyboard or unrelated HID interfaces.
                        if (path==null || path.IndexOf("vid_feed&pid_8687",StringComparison.OrdinalIgnoreCase)<0) continue;
                        using (var handle=CreateFile(path,0,3,IntPtr.Zero,3,0,IntPtr.Zero)) {
                            if (handle.IsInvalid) continue;
                            var attr=new Attributes { Size=Marshal.SizeOf<Attributes>() };
                            if (!HidD_GetAttributes(handle,ref attr) || attr.Vendor!=0xFEED || attr.Product!=0x8687) continue;
                            if (!HidD_GetPreparsedData(handle,out IntPtr pp)) continue;
                            try {
                                if (HidP_GetCaps(pp,out Caps caps)!=0x110000) continue;
                                if (caps.UsagePage==0xFF60 && caps.Usage==0x61 && caps.InputLength==33 && caps.OutputLength==33) paths.Add(path);
                            } finally { HidD_FreePreparsedData(pp); }
                        }
                    } finally { Marshal.FreeHGlobal(detail); }
                }
            } finally { SetupDiDestroyDeviceInfoList(set); }
            if (paths.Count==0) throw new PadDisconnectedException("Pad not found. Connect your TogKey Pad Plus and close Vial or its browser tab.");
            if (paths.Count>1) throw new IOException("More than one Pad Plus is connected. Leave one connected and retry.");
            return new Hid(paths[0],token);
        }
        public static bool IsReadCommand(byte[] p) {
            if (p==null || p.Length!=32) return false;
            switch (p[0]) {
                case 0x01: case 0x0C: case 0x0D: case 0x11: return true;
                case 0x0E: case 0x12: return p[3]>0 && p[3]<=28;
                case 0x02: return p[1]==3; // physical matrix read, requires unlocked Vial
                case 0xFE: return p[1]==0 || p[1]==3 || p[1]==5;
                default: return false;
            }
        }
        public byte[] Query(byte[] payload) {
            if (!IsReadCommand(payload)) throw new InvalidOperationException("This display permits read commands only.");
            cancellation.ThrowIfCancellationRequested();
            byte[] report=new byte[33]; // Windows report ID 0, then 32-byte VIA payload.
            Array.Copy(payload,0,report,1,32);
            using (var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellation)) {
                // Macro execution can block the firmware's main loop for several seconds.
                timeout.CancelAfter(6000);
                try {
                    stream.WriteAsync(report,0,report.Length,timeout.Token).GetAwaiter().GetResult();
                    byte[] input=new byte[33];
                    var pending=stream.ReadAsync(input,0,input.Length,timeout.Token);
                    bool delayed=!pending.IsCompleted && Task.WhenAny(pending,Task.Delay(400,timeout.Token)).GetAwaiter().GetResult()!=pending;
                    if(delayed) Waiting?.Invoke();
                    int count=pending.GetAwaiter().GetResult();
                    if(count==0) throw new PadDisconnectedException("The pad disconnected. Reconnect it, then match the OLED layer.");
                    if (count!=33 || input[0]!=0) throw new IOException("The pad returned an unexpected HID report.");
                    byte[] result=new byte[32]; Array.Copy(input,1,result,0,32);
                    if(delayed) Replied?.Invoke();
                    return result;
                } catch (OperationCanceledException) {
                    if (cancellation.IsCancellationRequested) throw;
                    throw new PadBusyException();
                } catch(IOException ex) {
                    int code=ex.HResult & 0xFFFF;
                    if(code==1167 || code==433 || code==6) throw new PadDisconnectedException("The pad disconnected. Reconnect it, then match the OLED layer.",ex);
                    throw;
                }
            }
        }
        public void Dispose() { stream.Dispose(); }
    }

    public static class Reader {
        static readonly byte[] ExpectedUid={0x77,0xF7,0x14,0xBB,0x74,0x32,0x66,0xE9};
        public static byte[] Packet(params byte[] bytes) {
            byte[] p=new byte[32]; Array.Copy(bytes,p,bytes.Length); return p;
        }
        static byte[] Via(Func<byte[],byte[]> query, params byte[] bytes) {
            byte[] r=query(Packet(bytes));
            if (r==null || r.Length!=32 || r[0]!=bytes[0]) throw new IOException("Unexpected VIA reply. Close other keyboard configurators and retry.");
            return r;
        }
        static byte[] Buffer(Func<byte[],byte[]> query, byte command, int length, int macroCount=0) {
            byte[] result=new byte[length];
            int terminators=0;
            for (int offset=0; offset<length; offset+=28) {
                int count=Math.Min(28,length-offset);
                var r=Via(query,command,(byte)(offset>>8),(byte)offset,(byte)count);
                if (r[1]!=(byte)(offset>>8) || r[2]!=(byte)offset || r[3]!=count) throw new IOException("Mismatched mapping reply. Close Vial and retry.");
                Array.Copy(r,4,result,offset,count);
                if(macroCount>0) {
                    for(int i=0;i<count;i++) if(r[4+i]==0) terminators++;
                    // Vial escapes zero bytes in keycode/delay operands, so NUL ends a macro.
                    if(terminators>=macroCount) { Array.Resize(ref result,offset+count); break; }
                }
            }
            return result;
        }
        public static Snapshot Read(Func<byte[],byte[]> query) {
            var version=Via(query,1);
            if ((version[1]<<8|version[2])!=9) throw new IOException("This display supports VIA protocol 9 only.");
            var id=query(Packet(0xFE,0));
            if (id==null || id.Length!=32 || BitConverter.ToUInt32(id,0)!=6) throw new IOException("This display supports Vial protocol 6 only.");
            for (int i=0;i<8;i++) if (id[4+i]!=ExpectedUid[i]) throw new IOException("The connected firmware does not identify as this TogKey Pad Plus.");
            if (Via(query,0x11)[1]!=4) throw new IOException("Expected the Pad Plus four-layer configuration.");
            var result=new Snapshot();
            var map=Buffer(query,0x12,72);
            for (int i=0;i<36;i++) result.Keys[i]=(ushort)(map[2*i]<<8|map[2*i+1]);
            for (byte layer=0;layer<4;layer++) {
                var enc=query(Packet(0xFE,3,layer,0));
                if (enc==null || enc.Length!=32) throw new IOException("Invalid encoder reply.");
                for (int d=0;d<2;d++) result.Encoders[layer*2+d]=(ushort)(enc[2*d]<<8|enc[2*d+1]);
            }
            int macros=Via(query,0x0C)[1];
            var sz=Via(query,0x0D); int size=sz[1]<<8|sz[2];
            if (macros>128 || (macros>0 && size==0)) throw new IOException("Unexpected macro storage size.");
            result.MacroTexts=DecodeMacroTexts(macros==0 ? Array.Empty<byte>() : Buffer(query,0x0E,size,macros),macros);
            return result;
        }
        public static string[][] DecodeMacroTexts(byte[] buffer,int count) {
            var macros=new List<string[]>(); var texts=new List<string>(); var text=new List<byte>();
            Action flush=()=>{ if(text.Count>0) { texts.Add(System.Text.Encoding.UTF8.GetString(text.ToArray())); text.Clear(); } };
            int i=0;
            while (i<buffer.Length && macros.Count<count) {
                byte b=buffer[i++];
                if (b==0) { flush(); macros.Add(texts.ToArray()); texts.Clear(); continue; }
                if (b!=1) { text.Add(b); continue; }
                flush();
                if (i>=buffer.Length) throw new IOException("Incomplete macro data; retry after saving in Vial.");
                byte action=buffer[i++];
                int skip=(action>=1 && action<=3) ? 1 : (action>=4 && action<=7) ? 2 : -1;
                if (skip<0 || i+skip>buffer.Length) throw new IOException("Unsupported or incomplete macro action.");
                i+=skip;
            }
            if (macros.Count<count) throw new IOException("Incomplete macro storage; retry after saving in Vial.");
            return macros.ToArray();
        }
        public static Snapshot ReadOnce() {
            using(var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(20)))
            using(var hid=Hid.Open(timeout.Token)) return Read(hid.Query);
        }
    }

    public sealed class Monitor : IDisposable {
        public volatile bool AutoRead=true;
        public volatile bool TrackKnob=false;
        public volatile bool Refresh=true;
        public int TrackingEpoch;
        readonly CancellationTokenSource stop=new CancellationTokenSource();
        readonly ConcurrentQueue<Notice> notices=new ConcurrentQueue<Notice>();
        readonly Task worker;
        public Monitor() { worker=Task.Run(Run); }
        public Notice Next() { return notices.TryDequeue(out Notice n) ? n : null; }
        void Post(string kind,string text=null,Snapshot data=null) { notices.Enqueue(new Notice(kind,text,data)); }
        void Wait(int ms) { if(stop.Token.WaitHandle.WaitOne(ms)) stop.Token.ThrowIfCancellationRequested(); }
        void Run() {
            DateTime nextRead=DateTime.MinValue;
            while(!stop.IsCancellationRequested) {
                try {
                    if(!Refresh && !AutoRead && !TrackKnob) { Wait(100); continue; }
                    Refresh=false;
                    Post("status","Connecting to pad…");
                    using(var hid=Hid.Open(stop.Token)) {
                        hid.Waiting=()=>Post("busy","Waiting for pad · layer selection kept");
                        hid.Replied=()=>Post("responsive","Pad responding · layer selection kept");
                        Snapshot snapshot=null; bool? wasDown=null; bool? unlocked=null;
                        int observedEpoch=-1;
                        DateTime nextUnlock=DateTime.MinValue;
                        while(!stop.IsCancellationRequested) {
                            if(snapshot==null || Refresh || (AutoRead && DateTime.UtcNow>=nextRead)) {
                                Refresh=false;
                                Post("status","Reading saved mappings…");
                                snapshot=Reader.Read(hid.Query);
                                Post("snapshot",null,snapshot);
                                nextRead=DateTime.UtcNow.AddSeconds(8);
                                // Reads pause physical sampling: require a fresh baseline rather than inventing a press.
                                wasDown=null;
                                if(TrackKnob) Post("tracking","Knob tracking · estimated; select a layer to sync");
                            }
                            if(TrackKnob) {
                                int epoch=Volatile.Read(ref TrackingEpoch);
                                if(epoch!=observedEpoch) { wasDown=null; observedEpoch=epoch; }
                                if(DateTime.UtcNow>=nextUnlock) {
                                    var state=hid.Query(Reader.Packet(0xFE,5));
                                    bool ready=state[0]==1 && state[1]==0;
                                    if(unlocked!=ready) {
                                        unlocked=ready; wasDown=null;
                                        Post("tracking",ready ? "Knob tracking · estimated; select a layer to sync" : "Unlock the pad in Vial, then close Vial to track the knob");
                                    }
                                    nextUnlock=DateTime.UtcNow.AddSeconds(1);
                                }
                                if(unlocked==true) {
                                    var matrix=hid.Query(Reader.Packet(2,3));
                                    if(matrix[0]!=2 || matrix[1]!=3) throw new IOException("Unexpected switch reply. Close Vial and retry.");
                                    bool down=(matrix[2]&4)!=0; // row 0, column 2: physical encoder push switch
                                    if(wasDown==false && down) notices.Enqueue(new Notice("press") { Epoch=epoch });
                                    wasDown=down;
                                }
                            } else { wasDown=null; unlocked=null; nextUnlock=DateTime.MinValue; }
                            Wait(TrackKnob ? 40 : 100);
                        }
                    }
                } catch(OperationCanceledException) { break; }
                catch(Exception ex) {
                    bool disconnected=ex is PadDisconnectedException;
                    Post(disconnected ? "disconnected" : "retry",ex.Message);
                    // Remain responsive to a user-requested retry without repeating error dialogs.
                    int steps=disconnected ? 20 : ex is PadBusyException ? 5 : 15;
                    for(int i=0;i<steps && !Refresh && !stop.IsCancellationRequested;i++) {
                        try { Wait(100); } catch(OperationCanceledException) { break; }
                    }
                    if(!stop.IsCancellationRequested) Refresh=true;
                }
            }
        }
        public void Dispose() { stop.Cancel(); }
    }
}
