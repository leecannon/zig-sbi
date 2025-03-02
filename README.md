# zig-sbi

Zig wrapper around the [RISC-V SBI specification](https://github.com/riscv-non-isa/riscv-sbi-doc).

Compatible with SBI Specification v3.0-rc1.

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
