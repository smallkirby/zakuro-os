# Zakuro OS

![Zig](https://shields.io/badge/Zig-v0%2E13%2E0-blue?logo=zig&color=F7A41D&style=for-the-badge)
![EDK2 CLANGPDB](https://shields.io/badge/EDK2_CLANGPDB-Tested_on_clang--18-blue?logo=llvm&color=262D3A&style=for-the-badge)

![Lint](https://github.com/smallkirby/zakuro-os/actions/workflows/lint.yml/badge.svg)
![Test](https://github.com/smallkirby/zakuro-os/actions/workflows/test.yml/badge.svg)

Zig port of x64 [MikanOS](https://github.com/uchan-nos/mikanos): an experimental, educational, and toy OS.

**🚧 This project is a work in progress. 🚧**

## Development

The Zig build system is responsible for everything
including the dependency installation and the build.
All you need to do is:

```bash
zig build
```

To run the OS in QEMU:

```bash
zig build run -Dprettylog -Dlog_level=debug
```
