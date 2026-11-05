package sce

// Thread management bindings (psp2/kernel/threadmgr). Signatures were checked
// against psp2/kernel/threadmgr/thread.h and psp2common/kernel/threadmgr.h.
// sceKernelDelayThread is declared in sce.odin.
//
// Link with -lSceLibKernel_stub and -lSceKernelThreadMgr_stub.

foreign import sce_thread_kernel "system:SceLibKernel_stub"
foreign import sce_thread_mgr    "system:SceKernelThreadMgr_stub"

// The header's own example creates threads with priority 0x10000100 and a
// 0x10000 byte stack. A lower priority number means higher priority.
THREAD_DEFAULT_PRIORITY_USER :: i32(0x10000100)
THREAD_DEFAULT_STACK_SIZE    :: u32(0x10000)

// Inherit the calling process's CPU affinity.
THREAD_CPU_AFFINITY_MASK_DEFAULT :: i32(0)

// Thread entry point: int (*)(SceSize args, void *argp). 'argp' points to a
// copy of the 'argp' passed to sceKernelStartThread (of 'arglen' bytes).
ThreadEntry :: #type proc "c" (args: u32, argp: rawptr) -> i32

@(default_calling_convention = "c")
foreign sce_thread_kernel {
    // Returns the thread's UID, or < 0 on error. 'option' may be nil.
    sceKernelCreateThread  :: proc(name: cstring, entry: ThreadEntry, init_priority: i32,
                                   stack_size: u32, attr: u32, cpu_affinity_mask: i32,
                                   option: rawptr) -> i32 ---
    sceKernelStartThread   :: proc(thid: i32, arglen: u32, argp: rawptr) -> i32 ---

    // Blocks until the thread ends. 'stat' receives its exit status; 'timeout'
    // (microseconds, may be nil) is both the limit and, on return, the time left.
    sceKernelWaitThreadEnd :: proc(thid: i32, stat: ^i32, timeout: ^u32) -> i32 ---
}

@(default_calling_convention = "c")
foreign sce_thread_mgr {
    sceKernelDeleteThread     :: proc(thid: i32) -> i32 ---
    sceKernelExitThread       :: proc(status: i32) -> i32 ---
    sceKernelExitDeleteThread :: proc(status: i32) -> i32 ---
}
