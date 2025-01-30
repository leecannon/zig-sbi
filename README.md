# zig-sbi

Zig wrapper around the RISC-V SBI specification

Implements SBI Specification v1.0.0

## Installation

Add the dependency to `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/leecannon/zig-sbi
```

Then add the following to `build.zig`:

```zig
const sbi = b.dependency("sbi", .{});
exe.root_module.addImport("sbi", sbi.module("sbi"));
```
