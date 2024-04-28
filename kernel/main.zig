export fn kernel_main() callconv(.Naked) noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
