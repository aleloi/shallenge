## Zig, PTX and CUDA

Using the `nvptx64-cuda-none` backend to compile a kernel to PTX, then load it from the CUDA runtime.

Forked from github.com/Snektron/shallenge.


### Trying to get it to compile

First tried the most recent Zig at time of writing: 0.14.1. Doesn't compile because the project uses the old style deps syntax:

```bash
[alex@nixos:~/shallenge]$ zig build
/home/alex/shallenge/build.zig.zon:2:13: error: expected enum literal
    .name = "shallenge",
            ^~~~~~~~~~~
```

Tried to go back to 0.13.0, but that doesn't seem to support PTX?

```bash
[alex@nixos:~/shallenge]$ zig build -Dgpu-runtime=cuda
install
└─ install shallenge
   └─ zig build-exe shallenge Debug native
      └─ zig build-lib shallenge-kernel ReleaseFast nvptx64-cuda-none 1 errors
src/main.zig:75:17: error: builtin only available on GPU targets; targeted architecture is nvptx64
    const bid = @workGroupId(0);
                ^~~~~~~~~~~~~~~
error: the following command failed with 1 compilation errors:
/nix/store/s3nq31mhm8gxkq691p5w6q61ficw1hvr-zig-0.13.0/bin/zig build-lib -OReleaseFast -target nvptx64-cuda-none -mcpu sm_80 -Mroot=/home/alex/shallenge/src/main_device.zig -femit-asm -fno-emit-bin -fno-allow-shlib-undefined --cache-dir /home/alex/shallenge/.zig-cache --global-cache-dir /home/alex/.cache/zig --name shallenge-kernel -dynamic -fno-compiler-rt --listen=-
Build Summary: 1/5 steps succeeded; 1 failed (disable with --summary none)
install transitive failure
└─ install shallenge transitive failure
   └─ zig build-exe shallenge Debug native transitive failure
      └─ zig build-lib shallenge-kernel ReleaseFast nvptx64-cuda-none 1 errors
error: the following build command failed with exit code 1:
/home/alex/shallenge/.zig-cache/o/2f48f6ce68bef24da5ec5515d637e5f4/build /nix/store/s3nq31mhm8gxkq691p5w6q61ficw1hvr-zig-0.13.0/bin/zig /home/alex/shallenge /home/alex/shallenge/.zig-cache /home/alex/.cache/zig --seed 0x44f322eb -Z46da4b6318244f30 -Dgpu-runtime=cuda
```

Going back to 0.14.1, but let's just try to compile the kernel without fixing the build.zig:

```bash
[alex@nixos:~/shallenge]$ zig build-lib -OReleaseFast -target nvptx64-cuda-none -mcpu sm_80 -Mroot=/home/alex/shallenge/src/main_device.zig -femit-asm -fno-emit-bin -fno-allow-shlib-undefined --cache-dir /home/alex/shallenge/.zig-cache --global-cache-dir /home/alex/.cache/zig --name shallenge-kernel -dynamic -fno-compiler-rt
src/main_device.zig:14:32: error: expected pointer type, found 'fn (*addrspace(.global) const u32, *addrspace(.global) u64) callconv(builtin.CallingConvention{ .nvptx_kernel = void }) void'
    @export(@import("main.zig").shallenge, .{ .name = "shallenge" });
            ~~~~~~~~~~~~~~~~~~~^~~~~~~~~~
referenced by:
    root: /nix/store/rf2hmizxk6i2ryr08sh60yivmmpiw9l7-zig-0.14.1/lib/std/start.zig:3:22
    comptime: /nix/store/rf2hmizxk6i2ryr08sh60yivmmpiw9l7-zig-0.14.1/lib/std/start.zig:27:9
    2 reference(s) hidden; use '-freference-trace=4' to see all references
```

I know that one! The  `@export` builtin has changed in 0.14.
The  first argument has now been changed to a pointer:
```zig
@export(comptime ptr: *const anyopaque, comptime options: std.builtin.ExportOptions) void
```

Just adding a `&` solved it. 
Then let's just modernize the `build.zig.zon` by changing `"shallenge"` to `.shallenge` and adding a `.fingerprint`.

Now we get more compile errors. Comtime metaprogramming field names have changed from 0.13 to 0.14:
```bash
[alex@nixos:~/shallenge]$ zig build -Dgpu-runtime=cuda
install
└─ install shallenge
   └─ zig build-exe shallenge Debug native 3 errors
src/cuda.zig:98:56: error: no field named 'Pointer' in union 'builtin.Type'
    const actual_ptr = switch (@typeInfo(@TypeOf(ptr)).Pointer.size) {
                                                       ^~~~~~~
/nix/store/rf2hmizxk6i2ryr08sh60yivmmpiw9l7-zig-0.14.1/lib/std/builtin.zig:568:18: note: union declared here
pub const Type = union(enum) {
                 ^~~~~
src/cuda.zig:98:56: error: no field named 'Pointer' in union 'builtin.Type'
    const actual_ptr = switch (@typeInfo(@TypeOf(ptr)).Pointer.size) {
                                                       ^~~~~~~
/nix/store/rf2hmizxk6i2ryr08sh60yivmmpiw9l7-zig-0.14.1/lib/std/builtin.zig:568:18: note: union declared here
pub const Type = union(enum) {
                 ^~~~~
/nix/store/rf2hmizxk6i2ryr08sh60yivmmpiw9l7-zig-0.14.1/lib/std/std.zig:102:69: error: expected type 'std.Options', found 'main.std_options__struct_3444'
pub const options: Options = if (@hasDecl(root, "std_options")) root.std_options else .{};
                                                                ~~~~^~~~~~~~~~~~
src/main.zig:7:26: note: struct declared here
pub const std_options = .{
                        ~^
/nix/store/rf2hmizxk6i2ryr08sh60yivmmpiw9l7-zig-0.14.1/lib/std/std.zig:104:21: note: struct declared here
pub const Options = struct {
```

Some small fixes, diff so far is:

```diff
[alex@nixos:~/shallenge]$ git diff HEAD -- */*.zig *.zig*
diff --git a/build.zig.zon b/build.zig.zon
index f65a618..c9fc685 100644
--- a/build.zig.zon
+++ b/build.zig.zon
@@ -1,5 +1,6 @@
 .{
-    .name = "shallenge",
+    .name = .shallenge,
+    .fingerprint = 0x7bc9cb20a30c06bf,
     .version = "0.1.0",
     .dependencies = .{
         .hip = .{
diff --git a/src/cuda.zig b/src/cuda.zig
index eec8fef..411f5d3 100644
--- a/src/cuda.zig
+++ b/src/cuda.zig
@@ -95,8 +95,8 @@ pub fn malloc(comptime T: type, n: usize) ![]T {
 }

 pub fn free(ptr: anytype) void {
-    const actual_ptr = switch (@typeInfo(@TypeOf(ptr)).Pointer.size) {
-        .Slice => ptr.ptr,
+    const actual_ptr = switch (@typeInfo(@TypeOf(ptr)).pointer.size) {
+        .slice => ptr.ptr,
         else => ptr,
     };

diff --git a/src/main.zig b/src/main.zig
index f7e713a..4129f2f 100644
--- a/src/main.zig
+++ b/src/main.zig
@@ -4,7 +4,7 @@ const assert = std.debug.assert;

 const build_options = @import("build_options");

-pub const std_options = .{
+pub const std_options = std.Options{
     .log_level = .info,
 };

diff --git a/src/main_device.zig b/src/main_device.zig
index 4d42ab7..898f206 100644
--- a/src/main_device.zig
+++ b/src/main_device.zig
@@ -11,5 +11,5 @@ pub fn panic(msg: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize)
 }

 comptime {
-    @export(@import("main.zig").shallenge, .{ .name = "shallenge" });
+    @export(&@import("main.zig").shallenge, .{ .name = "shallenge" });
 }
```

Now building gives:
```
[alex@nixos:~/shallenge]$ zig build -Dgpu-runtime=cuda
install
└─ install shallenge
   └─ zig build-exe shallenge Debug native failure
error: warning: unable to open library directory '/usr/local/cuda/lib64': FileNotFound
```

It's due to these lines in build.zig. Would have been nice if the build system used the panic handler that shows line numbers!

```zig
exe.addIncludePath(.{ .cwd_relative = "/usr/local/cuda/include" });
exe.addLibraryPath(.{ .cwd_relative = "/usr/local/cuda/lib64" });
exe.linkSystemLibrary("cuda");
```

The include path is probably `${pkgs.cudaPackages.cudatoolkit}/include` in nix. Not sure why we need it because we never use `cImport` - the hip version does, but not CUDA. Also what's lib64? My `${pkgs.cudaPackages.cudatoolkit}` has a `lib/` and no `libcuda`. 

UPDATE after I got it to run: seems that zig build uses a stub `${pkgs.cudaPackages.cudatoolkit}/lib/stubs/libcuda.so` at build time, and then a real libcuda.so at runtime. I don't technically need anything but the stub from the cudatoolkit since Snektron/shallenge depends on the Driver API and not the Runtime API.
```bash
[alex@nixos:~/shallenge]$ ldd ./zig-out/bin/shallenge  | grep cuda
        libcuda.so.1 => /run/opengl-driver/lib/libcuda.so.1 (0x00007ffff3a00000)
```

I just remove the include and lib path:

```diff
[alex@nixos:~/shallenge]$ git diff -- build.zig
diff --git a/build.zig b/build.zig
index bfe829c..92bf1a8 100644
--- a/build.zig
+++ b/build.zig
@@ -81,8 +81,8 @@ pub fn build(b: *std.Build) void {

             const nvptx_module = nvptx_code.getEmittedAsm();

-            exe.addIncludePath(.{ .cwd_relative = "/usr/local/cuda/include" });
-            exe.addLibraryPath(.{ .cwd_relative = "/usr/local/cuda/lib64" });
+            //exe.addIncludePath(.{ .cwd_relative = "/usr/local/cuda/include" });
+            // exe.addLibraryPath(.{ .cwd_relative = "/usr/local/cuda/lib64" });
             exe.linkSystemLibrary("cuda");
             exe.root_module.addAnonymousImport("offload-bundle", .{
                 .root_source_file = nvptx_module,
```


It worked! And it runs without crashing!

### Running
```text
[alex@nixos:~/shallenge]$ ./zig-out/bin/shallenge
info: performance: 0.9406341 GH/s
info: epoch: 2327076055
info: zeros: 33 (8 digits)
info: zeros (actual): 33
info: seed: main.Seed{ .bid = 7821, .tid = 132, .item = 134, .epoch = 2327076055 }
info: string: aleloi/zig+nvptx++++nflihmekboinieig
info: hash: 0000000063b6405cac3391e69ea524ca57c6306047f697e626eaa557d0d1e49e
```

It reports 0.95 GH/s, which seems a bit below the top performers on https://shallenge.quirino.net/ (21 GH/s on RTX4090). I'm running on a 3070, and this is a debug build. I also have an LLM loaded in memory, but that shouldn't affect things - memory can't be the bottleneck here.

`zig build -Dgpu-runtime=cuda -Doptimize=ReleaseFast` did not make a difference - I guess there are no optimizations implemented for the PTX backend? Or it's the driver's PTX to SASS that does all the real optimization. Turning off ollama also didn't make a difference.

nvidia-smi reports 100% GPU utilization, cool!

```
[alex@nixos:~/shallenge]$ nvidia-smi
Tue Jul  8 18:49:36 2025
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 570.153.02             Driver Version: 570.153.02     CUDA Version: 12.8     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 3070        Off |   00000000:01:00.0  On |                  N/A |
| 68%   62C    P0            201W /  280W |    2571MiB /   8192MiB |    100%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A            7419      G   ...urrent-system/sw/bin/Hyprland       1703MiB |
|    0   N/A  N/A            7468      G   Xwayland                                 40MiB |
|    0   N/A  N/A          363858      G   ...-139.0.4/bin/.firefox-wrapped        263MiB |
|    0   N/A  N/A         1122012      G   ...current-system/sw/bin/ghostty        185MiB |
|    0   N/A  N/A         1136699      C   ./zig-out/bin/shallenge                 154MiB |
+-----------------------------------------------------------------------------------------+
```

