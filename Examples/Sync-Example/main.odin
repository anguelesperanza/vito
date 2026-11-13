package sync_example

// The kernel's synchronisation objects, each used between two real threads,
// plus thread information, timing and the frame timer from lib/vito.
//
// Every check prints PASS or FAIL on screen and in the log. Every wait has a
// timeout, so a broken call shows as FAIL instead of freezing the program.
//
//   Start  exit

import "core:fmt"
import "core:log"

import sce  "../../lib/sce"
import v2d  "../../lib/vita2d"
import vito "../../lib/vito"

WHITE  :: u32(0xFFFFFFFF)
GREEN  :: u32(0xFF40E040)
RED    :: u32(0xFF4040FF)
YELLOW :: u32(0xFF00DCFF)
GREY   :: u32(0xFF909090)

Result :: struct {
    name:   string,
    ok:     bool,
    detail: string,
}
results: [dynamic]Result

report :: proc(name: string, ok: bool, format: string, args: ..any) {
    detail := fmt.aprintf(format, ..args)
    append(&results, Result{name, ok, detail})
    vito.printf("%s %s: %s\n", "PASS" if ok else "FAIL", name, detail)
}

// Timeouts are in microseconds and are passed by pointer: the kernel writes
// the time that was left back into the variable, so use a fresh one per call.
SECOND :: 1_000_000

timeout :: proc "contextless" (microseconds: u32) -> u32 {
    return microseconds
}

// Starts `entry` on a new thread. `arg` is copied onto the thread's stack.
start :: proc "contextless" (name: cstring, entry: sce.KernelThreadEntry, arg: i32 = 0,
                             priority: i32 = sce.THREAD_DEFAULT_PRIORITY_USER,
                             affinity: i32 = sce.THREAD_CPU_AFFINITY_MASK_DEFAULT) -> sce.UID {
    thid := sce.sceKernelCreateThread(name, entry, priority, sce.THREAD_DEFAULT_STACK_SIZE, 0, affinity, nil)
    if thid < 0 do return thid
    value := arg
    sce.sceKernelStartThread(thid, size_of(value), &value)
    return thid
}

// Waits for a thread to end (at most 5 s) and deletes it. Returns its exit
// status, or the error from the wait.
join :: proc "contextless" (thid: sce.UID) -> i32 {
    if thid < 0 do return thid
    status: i32
    t := timeout(5 * SECOND)
    r := sce.sceKernelWaitThreadEnd(thid, &status, &t)
    sce.sceKernelDeleteThread(thid)
    return status if r >= 0 else r
}

LOOPS :: 20000

// ---------------------------------------------------------------
// 1. Mutex: two threads add to a plain (non-atomic) counter
// ---------------------------------------------------------------
mutex:         sce.UID
mutex_counter: i32

mutex_worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    for _ in 0 ..< LOOPS {
        if sce.sceKernelLockMutex(mutex, 1, nil) < 0 do return -1
        mutex_counter += 1
        sce.sceKernelUnlockMutex(mutex, 1)
    }
    return 0
}

// Tries to take the mutex without waiting and returns what the call said.
mutex_try_worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    r := sce.sceKernelTryLockMutex(mutex, 1)
    if r >= 0 do sce.sceKernelUnlockMutex(mutex, 1)
    return r
}

test_mutex :: proc() {
    mutex = sce.sceKernelCreateMutex("vito_mutex", 0, 0, nil)
    if mutex < 0 {
        report("mutex", false, "create failed 0x%08X", u32(mutex))
        return
    }
    mutex_counter = 0
    worker := start("mutex_worker", mutex_worker)
    for _ in 0 ..< LOOPS {
        sce.sceKernelLockMutex(mutex, 1, nil)
        mutex_counter += 1
        sce.sceKernelUnlockMutex(mutex, 1)
    }
    status := join(worker)
    report("mutex", status == 0 && mutex_counter == 2 * LOOPS, "counter %d (want %d)", mutex_counter, 2 * LOOPS)

    // While this thread holds it, another thread's try-lock must fail.
    sce.sceKernelLockMutex(mutex, 1, nil)
    held_result := join(start("mutex_try", mutex_try_worker))
    sce.sceKernelUnlockMutex(mutex, 1)
    free_result := join(start("mutex_try", mutex_try_worker))
    report("mutex try-lock", held_result < 0 && free_result >= 0, "while held 0x%08X, while free 0x%08X", u32(held_result), u32(free_result))
    sce.sceKernelDeleteMutex(mutex)
}

// ---------------------------------------------------------------
// 2. Lightweight mutex: lives in our memory, no kernel call when uncontended
// ---------------------------------------------------------------
lw_mutex:   sce.KernelLwMutexWork
lw_counter: i32

lw_worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    for _ in 0 ..< LOOPS {
        if sce.sceKernelLockLwMutex(&lw_mutex, 1, nil) < 0 do return -1
        lw_counter += 1
        sce.sceKernelUnlockLwMutex(&lw_mutex, 1)
    }
    return 0
}

test_lw_mutex :: proc() {
    r := sce.sceKernelCreateLwMutex(&lw_mutex, "vito_lwmutex", 0, 0, nil)
    if r < 0 {
        report("lw mutex", false, "create failed 0x%08X", u32(r))
        return
    }
    lw_counter = 0
    worker := start("lw_worker", lw_worker)
    for _ in 0 ..< LOOPS {
        sce.sceKernelLockLwMutex(&lw_mutex, 1, nil)
        lw_counter += 1
        sce.sceKernelUnlockLwMutex(&lw_mutex, 1)
    }
    status := join(worker)
    report("lw mutex", status == 0 && lw_counter == 2 * LOOPS, "counter %d (want %d)", lw_counter, 2 * LOOPS)
    sce.sceKernelDeleteLwMutex(&lw_mutex)
}

// ---------------------------------------------------------------
// 3. Semaphore: a worker hands out permits, the main thread collects them
// ---------------------------------------------------------------
sema: sce.UID
PERMITS :: 5

sema_worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    for _ in 0 ..< PERMITS {
        sce.sceKernelDelayThread(5000)
        if sce.sceKernelSignalSema(sema, 1) < 0 do return -1
    }
    return 0
}

test_semaphore :: proc() {
    sema = sce.sceKernelCreateSema("vito_sema", 0, 0, PERMITS, nil)
    if sema < 0 {
        report("semaphore", false, "create failed 0x%08X", u32(sema))
        return
    }
    worker := start("sema_worker", sema_worker)
    got := 0
    for _ in 0 ..< PERMITS {
        t := timeout(2 * SECOND)
        if sce.sceKernelWaitSema(sema, 1, &t) >= 0 do got += 1
    }
    status := join(worker)
    report("semaphore", status == 0 && got == PERMITS, "collected %d of %d permits", got, PERMITS)

    // Nothing left: a poll fails at once and a wait runs into its timeout.
    poll := sce.sceKernelPollSema(sema, 1)
    before := vito.time_us()
    t := timeout(50_000)
    wait := sce.sceKernelWaitSema(sema, 1, &t)
    took := i32((vito.time_us() - before) / 1000)
    ok := poll < 0 && wait == sce.KERNEL_ERROR_WAIT_TIMEOUT && took >= 40 && took < 300
    report("semaphore timeout", ok, "poll 0x%08X, wait 0x%08X after %d ms (asked for 50)", u32(poll), u32(wait), took)
    sce.sceKernelDeleteSema(sema)
}

// ---------------------------------------------------------------
// 4. Event flag: wait until two bits, set at different times, are both set
// ---------------------------------------------------------------
event: sce.UID

event_worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    sce.sceKernelDelayThread(10_000)
    sce.sceKernelSetEventFlag(event, 0x1)
    sce.sceKernelDelayThread(10_000)
    sce.sceKernelSetEventFlag(event, 0x2)
    return 0
}

test_event_flag :: proc() {
    event = sce.sceKernelCreateEventFlag("vito_event", sce.EVENT_WAITMULTIPLE, 0, nil)
    if event < 0 {
        report("event flag", false, "create failed 0x%08X", u32(event))
        return
    }
    worker := start("event_worker", event_worker)
    pattern: u32
    t := timeout(2 * SECOND)
    // Wait for bit 0 AND bit 1, then clear the flag.
    wait := sce.sceKernelWaitEventFlag(event, 0x3, sce.EVENT_WAITAND | sce.EVENT_WAITCLEAR, &pattern, &t)
    join(worker)
    // Cleared by the wait, so a poll for either bit now fails.
    after: u32
    poll := sce.sceKernelPollEventFlag(event, 0x3, sce.EVENT_WAITOR, &after)
    report("event flag", wait >= 0 && pattern & 0x3 == 0x3 && poll < 0,
        "wait 0x%08X pattern 0x%X, poll after clear 0x%08X", u32(wait), pattern, u32(poll))
    sce.sceKernelDeleteEventFlag(event)
}

// ---------------------------------------------------------------
// 5. Condition variable: sleep until another thread says the data is ready
// ---------------------------------------------------------------
cond_mutex: sce.UID
cond:       sce.UID
cond_ready: bool

cond_worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    result: i32 = 0
    sce.sceKernelLockMutex(cond_mutex, 1, nil)
    // The wait releases the mutex while sleeping and takes it again on wake.
    for !cond_ready {
        t := timeout(2 * SECOND)
        result = sce.sceKernelWaitCond(cond, &t)
        if result < 0 do break
    }
    sce.sceKernelUnlockMutex(cond_mutex, 1)
    return result
}

test_cond :: proc() {
    cond_mutex = sce.sceKernelCreateMutex("vito_cond_mutex", 0, 0, nil)
    cond = sce.sceKernelCreateCond("vito_cond", 0, cond_mutex, nil)
    if cond_mutex < 0 || cond < 0 {
        report("condition variable", false, "create failed mutex 0x%08X cond 0x%08X", u32(cond_mutex), u32(cond))
        return
    }
    cond_ready = false
    worker := start("cond_worker", cond_worker)
    sce.sceKernelDelayThread(20_000) // let the worker reach its wait
    sce.sceKernelLockMutex(cond_mutex, 1, nil)
    cond_ready = true
    signal := sce.sceKernelSignalCond(cond)
    sce.sceKernelUnlockMutex(cond_mutex, 1)
    status := join(worker)
    report("condition variable", signal >= 0 && status == 0, "signal 0x%08X, worker woke with 0x%08X", u32(signal), u32(status))
    sce.sceKernelDeleteCond(cond)
    sce.sceKernelDeleteMutex(cond_mutex)
}

// ---------------------------------------------------------------
// 6. Read/write lock
// ---------------------------------------------------------------
rwlock: sce.UID

rw_try_write_worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    r := sce.sceKernelTryLockWriteRWLock(rwlock)
    if r >= 0 do sce.sceKernelUnlockWriteRWLock(rwlock)
    return r
}

rw_try_read_worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    r := sce.sceKernelTryLockReadRWLock(rwlock)
    if r >= 0 do sce.sceKernelUnlockReadRWLock(rwlock)
    return r
}

test_rwlock :: proc() {
    rwlock = sce.sceKernelCreateRWLock("vito_rwlock", 0, nil)
    if rwlock < 0 {
        report("rw lock", false, "create failed 0x%08X", u32(rwlock))
        return
    }
    t := timeout(SECOND)
    read := sce.sceKernelLockReadRWLock(rwlock, &t)
    // Readers share; a writer has to wait for them.
    other_read  := join(start("rw_read", rw_try_read_worker))
    other_write := join(start("rw_write", rw_try_write_worker))
    sce.sceKernelUnlockReadRWLock(rwlock)
    free_write := join(start("rw_write", rw_try_write_worker))
    ok := read >= 0 && other_read >= 0 && other_write < 0 && free_write >= 0
    report("rw lock", ok, "second reader 0x%08X, writer while read-held 0x%08X, writer when free 0x%08X",
        u32(other_read), u32(other_write), u32(free_write))
    sce.sceKernelDeleteRWLock(rwlock)
}

// ---------------------------------------------------------------
// 7. Message pipe: bytes from one thread to another
// ---------------------------------------------------------------
pipe: sce.UID
PIPE_MESSAGE :: "hello from the worker"

pipe_worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    message := PIPE_MESSAGE
    t := timeout(2 * SECOND)
    return sce.sceKernelSendMsgPipe(pipe, raw_data(message), u32(len(message)), 0, nil, &t)
}

test_msg_pipe :: proc() {
    // The SDK header's own notes: type 0x40, attr 12, buffer in 4 KiB steps.
    pipe = sce.sceKernelCreateMsgPipe("vito_pipe", 0x40, 12, 0x1000, nil)
    if pipe < 0 {
        report("message pipe", false, "create failed 0x%08X", u32(pipe))
        return
    }
    worker := start("pipe_worker", pipe_worker)
    buf: [64]u8
    t := timeout(2 * SECOND)
    received := sce.sceKernelReceiveMsgPipe(pipe, &buf[0], len(PIPE_MESSAGE), 0, nil, &t)
    sent := join(worker)
    text := string(buf[:len(PIPE_MESSAGE)])
    report("message pipe", sent >= 0 && received >= 0 && text == PIPE_MESSAGE, "send 0x%08X receive 0x%08X %q", u32(sent), u32(received), text)
    sce.sceKernelDeleteMsgPipe(pipe)
}

// ---------------------------------------------------------------
// 8. Thread information, priority and CPU affinity
// ---------------------------------------------------------------
sleeper_stop: sce.UID // a semaphore the sleeper waits on

sleeper :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    t := timeout(3 * SECOND)
    sce.sceKernelWaitSema(sleeper_stop, 1, &t)
    return 7
}

test_thread_info :: proc() {
    me := sce.sceKernelGetThreadId()
    info: sce.KernelThreadInfo
    info.size = size_of(info) // the kernel checks this field
    got := sce.sceKernelGetThreadInfo(me, &info)
    stack_free := sce.sceKernelCheckThreadStack()
    report("thread info", me > 0 && got >= 0 && info.stackSize > 0 && stack_free > 0,
        "main thread \"%s\" priority 0x%X stack %d KiB (%d KiB free) cpu %d",
        cstring(raw_data(info.name[:])), info.currentPriority, info.stackSize / 1024, stack_free / 1024, info.currentCpuId)

    // A second thread pinned to core 1; change its priority while it sleeps.
    sleeper_stop = sce.sceKernelCreateSema("vito_sleeper", 0, 0, 1, nil)
    thid := start("sleeper", sleeper, affinity = sce.KERNEL_CPU_MASK_USER_1)
    sce.sceKernelDelayThread(10_000)
    NEW_PRIORITY :: sce.THREAD_DEFAULT_PRIORITY_USER + 16
    changed := sce.sceKernelChangeThreadPriority(thid, NEW_PRIORITY)
    other: sce.KernelThreadInfo
    other.size = size_of(other)
    sce.sceKernelGetThreadInfo(thid, &other)
    mask := sce.sceKernelGetThreadCpuAffinityMask(thid)
    sce.sceKernelSignalSema(sleeper_stop, 1)
    exit_status := join(thid)
    sce.sceKernelDeleteSema(sleeper_stop)
    // Priorities are reported without the 0x10000000 "user default" base.
    ok := changed >= 0 && exit_status == 7 && mask == sce.KERNEL_CPU_MASK_USER_1 && other.currentPriority != info.currentPriority
    report("priority/affinity", ok, "change 0x%08X, priority now 0x%X, affinity 0x%X, exit status %d",
        u32(changed), other.currentPriority, mask, exit_status)
}

// ---------------------------------------------------------------
// 9. Timing and the rest
// ---------------------------------------------------------------
test_timing :: proc() {
    before := vito.time_us()
    vito.sleep_ms(100)
    took := i32((vito.time_us() - before) / 1000)
    report("delay + clock", took >= 95 && took < 200, "sleep_ms(100) took %d ms", took)

    // Tells the system the app is active, which holds off auto-suspend.
    tick := sce.sceKernelPowerTick(.DISABLE_AUTO_SUSPEND)
    report("power tick", tick >= 0, "0x%08X", u32(tick))

    // The SDK's own atomics (Odin's intrinsics are checked in Runtime-Example).
    value: i32 = 40
    after := sce.sceKernelAtomicAddAndGet32(&value, 2)
    report("sceKernelAtomic", after == 42 && value == 42, "40 + 2 = %d", after)
}

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()

    if v2d.Init() < 0 {
        vito.println("vita2d: Init failed")
        return sce.sceKernelExitProcess(1)
    }
    v2d.SetClearColor(v2d.RGBA8(0x10, 0x12, 0x20, 0xFF))
    vito.input_init({})

    test_mutex()
    test_lw_mutex()
    test_semaphore()
    test_event_flag()
    test_cond()
    test_rwlock()
    test_msg_pipe()
    test_thread_info()
    test_timing()

    passed := 0
    for r in results do passed += int(r.ok)
    log.infof("%d of %d checks passed", passed, len(results))

    input: vito.Input
    timer: vito.Frame_Timer

    for {
        vito.input_update(&input)
        if vito.pressed(input, vito.BUTTON_START) do break
        vito.frame_tick(&timer)

        v2d.StartDrawing()
        v2d.ClearScreen()

        v2d.DrawText(24, 40, WHITE, 1.3, "Sync example")
        v2d.DrawText(24, 66, GREY, 0.8, "Kernel sync objects between two threads, thread info, timing")

        y := i32(100)
        for r in results {
            v2d.DrawText(24, y, GREEN if r.ok else RED, 0.9, "PASS" if r.ok else "FAIL")
            v2d.DrawText(90, y, WHITE, 0.9, fmt.ctprintf("%s", r.name))
            v2d.DrawText(300, y, GREY, 0.7, fmt.ctprintf("%s", r.detail))
            y += 26
        }
        v2d.DrawText(24, y + 14, GREEN if passed == len(results) else RED, 1.0, fmt.ctprintf("%d of %d passed", passed, len(results)))

        v2d.DrawText(24, 496, YELLOW, 0.9,
            fmt.ctprintf("frame timer: %.1f fps   delta %.2f ms   frame %d   %.1f s", timer.fps, timer.delta * 1000, timer.frame, timer.elapsed))
        v2d.DrawText(24, 522, GREY, 0.8, "Start: exit")

        v2d.EndDrawing()
        v2d.SwapBuffers()
        free_all(context.temp_allocator)
    }

    v2d.WaitRenderingDone()
    v2d.FreeSizedFonts()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
