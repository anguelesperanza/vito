package runtime_example

// Checks that ordinary Odin works on the Vita once lib/vito is set up:
// the heap, dynamic arrays, maps, strings, fmt, strconv, sort, core:log,
// the temp allocator, math, a second thread with its own context, atomics,
// and a failing assertion.
//
// Each test prints PASS or FAIL on screen and in the log.
//   Triangle  fail an assertion on purpose (crash screen + ux0:data/vito_panic.log)
//   Start     exit

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strconv"
import "core:strings"

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
    detail: string, // allocated on the heap, lives for the whole run
}

results: [dynamic]Result

report :: proc(name: string, ok: bool, format: string, args: ..any) {
    detail := fmt.aprintf(format, ..args)
    append(&results, Result{name, ok, detail})
    vito.printf("%s %s: %s\n", "PASS" if ok else "FAIL", name, detail)
}

Enemy :: struct {
    id:     int,
    hp:     f32,
    name:   string,
}

// ---------------------------------------------------------------
// Worker thread: allocates on the shared heap and bumps an atomic counter.
// ---------------------------------------------------------------
THREAD_LOOPS :: 20000

shared_counter: i32   // atomic
worker_sum:     i64   // written once by the worker before it exits
worker_done:    i32   // atomic flag

worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    context = vito.thread_context()
    nums := make([dynamic]i64)
    defer delete(nums)
    for i in 0 ..< THREAD_LOOPS {
        append(&nums, i64(i))
        intrinsics.atomic_add(&shared_counter, 1)
    }
    sum: i64
    for n in nums do sum += n
    worker_sum = sum
    intrinsics.atomic_store(&worker_done, 1)
    return 0
}

run_tests :: proc() {
    // 1. new / free
    {
        p := new(Enemy)
        ok := p != nil
        if ok {
            p.id = 7
            ok = p.id == 7 && p.hp == 0
            free(p)
        }
        report("new/free", ok, "pointer %p", p)
    }

    // 2. dynamic array of structs
    {
        enemies := make([dynamic]Enemy)
        defer delete(enemies)
        for i in 0 ..< 1000 do append(&enemies, Enemy{id = i, hp = f32(i) * 0.5})
        total := 0
        for e in enemies do total += e.id
        report("[dynamic]", len(enemies) == 1000 && total == 499500, "len %d cap %d sum %d", len(enemies), cap(enemies), total)
    }

    // 3. map
    {
        scores := make(map[string]int)
        defer delete(scores)
        scores["cross"] = 10
        scores["circle"] = 20
        scores["square"] = 30
        scores["cross"] += 5
        v, found := scores["cross"]
        _, missing := scores["triangle"]
        report("map", found && v == 15 && !missing && len(scores) == 3, "cross=%d len=%d", v, len(scores))
    }

    // 4. strings.Builder and fmt
    {
        sb := strings.builder_make()
        defer strings.builder_destroy(&sb)
        strings.write_string(&sb, "hp=")
        fmt.sbprintf(&sb, "%d/%d %s", 42, 100, "ok")
        s := strings.to_string(sb)
        report("strings.Builder", s == "hp=42/100 ok", "%q", s)
    }

    // 5. float formatting (f64 passes through Odin code only, no libm)
    {
        s := fmt.tprintf("%.3f %.1f", 3.14159, f32(-2.5))
        report("fmt floats", s == "3.142 -2.5", "%q", s)
    }

    // 6. strconv
    {
        i, i_ok := strconv.parse_int("-1234")
        f, f_ok := strconv.parse_f64("2.5")
        report("strconv", i_ok && f_ok && i == -1234 && f == 2.5, "%d %v", i, f)
    }

    // 7. sort
    {
        xs := []int{5, 3, 9, 1, 7}
        slice.sort(xs)
        report("slice.sort", slice.is_sorted(xs) && xs[0] == 1 && xs[4] == 9, "%v", xs)
    }

    // 8. aligned allocation
    {
        ptr, err := runtime.mem_alloc(1000, 64)
        addr := uintptr(raw_data(ptr))
        zeroed := true
        for b in ptr do zeroed &&= b == 0
        report("align 64", err == nil && addr % 64 == 0 && zeroed, "addr %p", raw_data(ptr))
        runtime.mem_free(raw_data(ptr))
    }

    // 9. a large allocation, and growing it
    {
        big := make([]u8, 8 * runtime.Megabyte)
        ok := len(big) == 8 * runtime.Megabyte
        if ok {
            big[len(big) - 1] = 0xAB
            ok = big[len(big) - 1] == 0xAB
        }
        delete(big)
        report("8 MiB alloc", ok, "len %d", len(big))
    }

    // 10. math through the libm bridge, and linalg
    {
        s := math.sin(f32(math.PI) / 6)                       // 0.5
        a := linalg.matrix4_translate(linalg.Vector3f32{1, 2, 3})
        b := linalg.matrix4_scale(linalg.Vector3f32{2, 2, 2})
        v := (a * b) * linalg.Vector4f32{1, 1, 1, 1}         // (3, 4, 5, 1)
        l := linalg.length(linalg.Vector3f32{3, 4, 0})        // 5
        ok := abs(s - 0.5) < 0.0001 && v == {3, 4, 5, 1} && abs(l - 5) < 0.0001
        report("math/linalg", ok, "sin=%.4f v=%v len=%.1f", s, v, l)
    }

    // 11. core:log (look for the line in the log output)
    {
        log.infof("core:log works, %d results so far", len(results))
        report("core:log", context.logger.procedure != nil, "see the log for an INFO line")
    }

    // 12. a second thread: its own context, the shared heap, atomics
    {
        thid := sce.sceKernelCreateThread("worker", worker, sce.THREAD_DEFAULT_PRIORITY_USER,
                                          sce.THREAD_DEFAULT_STACK_SIZE, 0, 0, nil)
        ok := thid >= 0
        if ok {
            sce.sceKernelStartThread(thid, 0, nil)
            // Race the worker on the same counter and the same heap.
            for i in 0 ..< THREAD_LOOPS {
                intrinsics.atomic_add(&shared_counter, 1)
                if i % 64 == 0 {
                    p := new(Enemy)
                    free(p)
                }
            }
            sce.sceKernelWaitThreadEnd(thid, nil, nil)
            sce.sceKernelDeleteThread(thid)
        }
        count := intrinsics.atomic_load(&shared_counter)
        want_sum := i64(THREAD_LOOPS) * i64(THREAD_LOOPS - 1) / 2
        ok = ok && count == 2 * THREAD_LOOPS && worker_sum == want_sum && intrinsics.atomic_load(&worker_done) == 1
        report("thread+atomics", ok, "counter %d (want %d) sum %d", count, 2 * THREAD_LOOPS, worker_sum)
    }
}

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()

    sce.sceCtrlSetSamplingMode(.ANALOG)
    if v2d.Init() < 0 {
        vito.println("vita2d: Init failed")
        return sce.sceKernelExitProcess(1)
    }
    v2d.SetClearColor(v2d.RGBA8(0x10, 0x12, 0x20, 0xFF))

    run_tests()
    passed := 0
    for r in results do passed += int(r.ok)
    log.infof("%d of %d tests passed", passed, len(results))

    pad:    sce.CtrlData
    frames: int
    peak:   uint // most temp memory used in one frame

    for {
        sce.sceCtrlPeekBufferPositive(0, &pad, 1)
        if pad.buttons & sce.CTRL_START != 0 do break
        if pad.buttons & sce.CTRL_TRIANGLE != 0 {
            assert(frames < 0, "Triangle was pressed: this assertion fails on purpose")
        }

        v2d.StartDrawing()
        v2d.ClearScreen()

        v2d.DrawText(24, 40, WHITE, 1.3, "Runtime example")
        v2d.DrawText(24, 66, GREY, 0.8, "lib/vito: allocator, temp allocator, logger, assertion handler")

        y := i32(100)
        for r in results {
            // ctprintf allocates from context.temp_allocator, freed below each frame.
            v2d.DrawText(24, y, GREEN if r.ok else RED, 0.9, "PASS" if r.ok else "FAIL")
            v2d.DrawText(90, y, WHITE, 0.9, fmt.ctprintf("%s", r.name))
            v2d.DrawText(290, y, GREY, 0.8, fmt.ctprintf("%s", r.detail))
            y += 26
        }

        summary_color := GREEN if passed == len(results) else RED
        v2d.DrawText(24, y + 14, summary_color, 1.0, fmt.ctprintf("%d of %d passed", passed, len(results)))
        v2d.DrawText(24, 496, YELLOW, 0.9, fmt.ctprintf("frame %d   temp allocator: free_all every frame", frames))
        v2d.DrawText(24, 522, GREY, 0.8, "Triangle: fail an assertion on purpose   Start: exit")

        v2d.EndDrawing()
        v2d.SwapBuffers()

        free_all(context.temp_allocator)
        frames += 1
    }

    v2d.WaitRenderingDone()
    v2d.FreeSizedFonts()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
