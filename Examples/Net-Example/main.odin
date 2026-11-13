package net_example

// Networking through lib/net: connection info, name lookup, HTTP and HTTPS,
// and TCP and UDP sockets in both directions.
//
//   left    the connection: state, IP address, Wi-Fi name and signal
//   right   a log of what each test did
//
//   Cross      look example.com up, then GET http://example.com/
//   Circle     GET https://example.com/ with the certificate check on, and
//              again with it off if that fails
//   Square     TCP: send a line to the PC and expect it back
//   Triangle   UDP: the same with one packet
//   R          TCP server: wait 20 s for the PC to connect to this console
//   Up         type the PC's address (kept in ux0:data/vito_net_ip.txt)
//
// Square, Triangle and R need tools/net_test_server.py running on a PC on
// the same network; run it and it prints the address to type in.
//
// Network calls wait for the other side, so they run on a second thread and
// the screen keeps drawing: the square in the corner keeps moving.
//
// Hold Start + Select for a second to exit.

import "base:intrinsics"
import "core:fmt"

import net  "../../lib/net"
import sce  "../../lib/sce"
import v2d  "../../lib/vita2d"
import vito "../../lib/vito"

WHITE  :: u32(0xFFFFFFFF)
GREEN  :: u32(0xFF40E040)
RED    :: u32(0xFF4040FF)
YELLOW :: u32(0xFF00DCFF)
CYAN   :: u32(0xFFE0D030)
GREY   :: u32(0xFF909090)
PANEL  :: u32(0xFF2A2420)

ECHO_PORT   :: 9999
SERVER_PORT :: 9998
IP_FILE     :: "ux0:data/vito_net_ip.txt"

Job :: enum i32 {
    None,
    Http,
    Https,
    Tcp,
    Udp,
    Server,
}

// ---- messages from the worker thread to the screen ------------------------
// One writer (the worker) and one reader (the main thread): the worker fills
// an entry and then raises the count, so no lock is needed.
Line_Kind :: enum {
    Info,
    Good,
    Bad,
}
Line :: struct {
    kind: Line_Kind,
    len:  int,
    text: [110]u8,
}
MAX_MESSAGES :: 256
messages:      [MAX_MESSAGES]Line
message_count: int // raised by the worker, atomically

emit :: proc(kind: Line_Kind, format: string, args: ..any) {
    index := intrinsics.atomic_load(&message_count)
    if index >= MAX_MESSAGES do return
    line := &messages[index]
    line.kind = kind
    line.len  = len(fmt.bprintf(line.text[:], format, ..args))
    intrinsics.atomic_store(&message_count, index + 1)
}

job_request: i32 // set by the main thread, cleared by the worker when done
worker_run:  i32 = 1
pc_ip:       [16]u8
send_number: int

pc_address :: proc(port: u16) -> (address: net.Address, ok: bool) {
    address, ok = net.parse_ip(cstring(&pc_ip[0]), port)
    if !ok do emit(.Bad, "no PC address yet: press Up and type the one the PC script prints")
    return
}

show_failure :: proc(what: string) {
    emit(.Bad, "%s failed: 0x%08X", what, u32(net.last_error))
}

// A short, one-line preview of a response body.
preview :: proc(body: []u8, buf: []u8) -> string {
    n := 0
    for b in body {
        if n >= len(buf) do break
        buf[n] = b if b >= 32 && b < 127 else ' '
        n += 1
    }
    return string(buf[:n])
}

run_http :: proc() {
    ip_text: [16]u8
    address, ok := net.resolve("example.com", 80)
    if !ok {
        show_failure("looking up example.com")
        return
    }
    emit(.Good, "example.com is %s", net.ip_string(address, ip_text[:]))

    response, got := net.http_get("http://example.com/")
    if !got {
        emit(.Bad, "GET failed at step %v: 0x%08X", net.last_http_step, u32(net.last_error))
        return
    }
    defer net.http_free(&response)
    text: [70]u8
    emit(.Good if response.status == 200 else .Bad, "GET http://example.com/ -> %d, %d bytes", response.status, len(response.body))
    emit(.Info, "  %s", preview(response.body, text[:]))
}

run_https :: proc() {
    // Three things can stop HTTPS on a Vita: the certificate check (the
    // console's list of authorities is old), the TLS handshake itself (its
    // TLS versions and ciphers are old too), or the network. The error name
    // says which.
    net.https_set_verify(true)
    response, ok := net.http_get("https://example.com/")
    if ok {
        emit(.Good if response.status == 200 else .Bad, "HTTPS with certificate check -> %d, %d bytes", response.status, len(response.body))
        net.http_free(&response)
        return
    }
    emit(.Bad, "HTTPS with check failed at %v: 0x%08X", net.last_http_step, u32(net.last_error))
    emit(.Info, "  %s  ssl 0x%X detail 0x%X", net.http_error_name(net.last_error), u32(net.last_ssl_error), net.last_ssl_detail)

    option := net.https_set_verify(false)
    calls_before := net.https_callback_calls
    response, ok = net.http_get("https://example.com/")
    net.https_set_verify(true)
    if !ok {
        emit(.Bad, "HTTPS without check failed at %v: 0x%08X", net.last_http_step, u32(net.last_error))
        emit(.Info, "  %s  ssl 0x%X detail 0x%X", net.http_error_name(net.last_error), u32(net.last_ssl_error), net.last_ssl_detail)
        emit(.Info, "  option 0x%X  callback set 0x%X, called %d times, saw 0x%X", u32(option), u32(net.https_callback_result),
            net.https_callback_calls - calls_before, net.https_callback_error)
        return
    }
    emit(.Good if response.status == 200 else .Bad, "HTTPS without check -> %d, %d bytes", response.status, len(response.body))
    net.http_free(&response)
}

run_tcp :: proc() {
    address, has_address := pc_address(ECHO_PORT)
    if !has_address do return
    started := vito.time_us()
    socket, ok := net.tcp_connect(address, 5)
    if !ok {
        show_failure("TCP connect (is the PC script running? firewall?)")
        return
    }
    defer net.close(socket)

    send_number += 1
    out, back: [64]u8
    message := fmt.bprintf(out[:], "hello from the Vita %d", send_number)
    if !net.send_all(socket, transmute([]u8)message) {
        show_failure("TCP send")
        return
    }
    n := net.receive(socket, back[:])
    if n <= 0 {
        show_failure("TCP receive")
        return
    }
    same := string(back[:n]) == message
    emit(.Good if same else .Bad, "TCP echo %s in %d ms: \"%s\"", "ok" if same else "DIFFERENT",
        (vito.time_us() - started) / 1000, string(back[:n]))
}

run_udp :: proc() {
    address, has_address := pc_address(ECHO_PORT)
    if !has_address do return
    socket, ok := net.udp_open()
    if !ok {
        show_failure("UDP open")
        return
    }
    defer net.close(socket)
    net.set_timeout(socket, 3)

    send_number += 1
    out, back: [64]u8
    message := fmt.bprintf(out[:], "packet from the Vita %d", send_number)
    started := vito.time_us()
    if net.udp_send(socket, address, transmute([]u8)message) < 0 {
        show_failure("UDP send")
        return
    }
    n, from := net.udp_receive(socket, back[:])
    if n < 0 {
        if net.timed_out(n) {
            emit(.Bad, "UDP: nothing came back in 3 s (PC script running? firewall?)")
        } else {
            show_failure("UDP receive")
        }
        return
    }
    ip_text: [16]u8
    same := string(back[:n]) == message
    emit(.Good if same else .Bad, "UDP echo %s in %d ms from %s:%d", "ok" if same else "DIFFERENT",
        (vito.time_us() - started) / 1000, net.ip_string(from, ip_text[:]), net.port_number(from))
}

run_server :: proc() {
    listener, ok := net.tcp_listen(SERVER_PORT)
    if !ok {
        show_failure("TCP listen")
        return
    }
    defer net.close(listener)
    net.set_timeout(listener, 20)
    emit(.Info, "listening on port %d for 20 s. On the PC:", SERVER_PORT)
    emit(.Info, "  python tools/net_test_server.py --connect <this console's IP>")

    socket, from, accepted := net.tcp_accept(listener)
    if !accepted {
        emit(.Bad, "nobody connected: 0x%08X", u32(net.last_error))
        return
    }
    defer net.close(socket)
    net.set_timeout(socket, 5)
    ip_text: [16]u8
    back: [64]u8
    n := net.receive(socket, back[:])
    reply := "hello from the Vita\n"
    net.send_all(socket, transmute([]u8)reply)
    text: [64]u8
    emit(.Good if n > 0 else .Bad, "connection from %s said: \"%s\"", net.ip_string(from, ip_text[:]),
        preview(back[:max(n, 0)], text[:]))
}

worker :: proc "c" (args: sce.Size, argp: rawptr) -> i32 {
    context = vito.thread_context()
    for intrinsics.atomic_load(&worker_run) != 0 {
        job := Job(intrinsics.atomic_load(&job_request))
        if job == .None {
            sce.sceKernelDelayThread(20_000)
            continue
        }
        switch job {
        case .Http:   run_http()
        case .Https:  run_https()
        case .Tcp:    run_tcp()
        case .Udp:    run_udp()
        case .Server: run_server()
        case .None:
        }
        intrinsics.atomic_store(&job_request, 0)
    }
    return 0
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
    vito.dialog_init()

    net_ok := net.init()
    results := net.init_results

    // The PC's address from last time.
    if saved, ok := vito.read_entire_file(IP_FILE); ok {
        n := 0
        for b in saved {
            if n >= 15 || !((b >= '0' && b <= '9') || b == '.') do break
            pc_ip[n] = b
            n += 1
        }
        delete(saved)
    }

    thread := sce.sceKernelCreateThread("net_worker", worker, sce.THREAD_DEFAULT_PRIORITY_USER, 0x20000, 0, 0, nil)
    thread_ok := thread >= 0 && sce.sceKernelStartThread(thread, 0, nil) >= 0

    LOG_LINES :: 16
    shown := 0 // messages already seen
    info: net.Info
    info_age: f32 = 10
    typing := false
    typed: [64]u8

    input: vito.Input
    timer: vito.Frame_Timer
    exit_hold := 0
    frames := 0

    for {
        dt := vito.frame_tick(&timer)
        vito.input_update(&input)
        busy := intrinsics.atomic_load(&job_request) != 0

        info_age += dt
        if info_age > 1 {
            info = net.info()
            info_age = 0
        }

        if vito.held(input, vito.BUTTON_START) && vito.held(input, vito.BUTTON_SELECT) {
            exit_hold += 1
            if exit_hold > 60 && !vito.dialog_active() do break
        } else {
            exit_hold = 0
        }

        if typing {
            if text, accepted, done := vito.text_input_poll(typed[:]); done {
                typing = false
                if accepted {
                    pc_ip = {}
                    copy(pc_ip[:15], text)
                    vito.write_entire_file(IP_FILE, transmute([]u8)text)
                }
            }
        } else if !busy && !vito.dialog_active() {
            job := Job.None
            switch {
            case vito.pressed(input, vito.BUTTON_CROSS):    job = .Http
            case vito.pressed(input, vito.BUTTON_CIRCLE):   job = .Https
            case vito.pressed(input, vito.BUTTON_SQUARE):   job = .Tcp
            case vito.pressed(input, vito.BUTTON_TRIANGLE): job = .Udp
            case vito.pressed(input, vito.BUTTON_R):        job = .Server
            case vito.pressed(input, vito.BUTTON_UP):
                typing = vito.text_input_open("The PC's IP address", string(cstring(&pc_ip[0])), 15, .Basic_Latin, {.No_Assistance})
            }
            if job != .None do intrinsics.atomic_store(&job_request, i32(job))
        }

        // ---- draw -------------------------------------------------------
        v2d.StartDrawing()
        v2d.ClearScreen()
        v2d.DrawText(24, 40, WHITE, 1.3, "Net example")
        v2d.DrawRectangle(700 + f32(frames % 120) * 2, 24, 16, 16, YELLOW if busy else GREY)

        // connection
        y := i32(84)
        v2d.DrawText(24, y, CYAN, 1.0, "Connection"); y += 26
        if info.connected {
            v2d.DrawText(24, y, GREEN, 0.8, "connected"); y += 22
            v2d.DrawText(24, y, WHITE, 0.8, fmt.ctprintf("IP       %s", cstring(&info.ip[0]))); y += 22
            v2d.DrawText(24, y, GREY, 0.75, fmt.ctprintf("mask     %s", cstring(&info.netmask[0]))); y += 20
            v2d.DrawText(24, y, GREY, 0.75, fmt.ctprintf("gateway  %s", cstring(&info.gateway[0]))); y += 20
            v2d.DrawText(24, y, GREY, 0.75, fmt.ctprintf("DNS      %s", cstring(&info.dns[0]))); y += 20
            v2d.DrawText(24, y, GREY, 0.75, fmt.ctprintf("Wi-Fi    %s  %d%%", cstring(&info.ssid[0]), info.signal)); y += 20
            v2d.DrawText(24, y, GREY, 0.75, fmt.ctprintf("MAC      %02X:%02X:%02X:%02X:%02X:%02X",
                info.mac[0], info.mac[1], info.mac[2], info.mac[3], info.mac[4], info.mac[5])); y += 20
        } else {
            v2d.DrawText(24, y, RED, 0.8, fmt.ctprintf("not connected (state %d)", info.state)); y += 22
            v2d.DrawText(24, y, GREY, 0.7, "turn Wi-Fi on in Settings"); y += 20
        }
        y += 14
        v2d.DrawText(24, y, CYAN, 1.0, "Start-up"); y += 24
        v2d.DrawText(24, y, GREEN if net_ok && results.netctl >= 0 else RED, 0.7,
            fmt.ctprintf("net 0x%X  netctl 0x%X", u32(results.net), u32(results.netctl))); y += 20
        v2d.DrawText(24, y, GREEN if results.ssl >= 0 && results.http >= 0 else RED, 0.7,
            fmt.ctprintf("ssl 0x%X  http 0x%X", u32(results.ssl), u32(results.http))); y += 20
        v2d.DrawText(24, y, GREY, 0.7,
            fmt.ctprintf("modules %X %X %X %X  thread %v", u32(results.load_net), u32(results.load_ssl), u32(results.load_http), u32(results.load_https), thread_ok)); y += 30
        v2d.DrawText(24, y, CYAN, 1.0, "PC"); y += 24
        has_ip := pc_ip[0] != 0
        v2d.DrawText(24, y, WHITE if has_ip else YELLOW, 0.8, fmt.ctprintf("%s", cstring(&pc_ip[0]) if has_ip else "not set: press Up")); y += 22
        v2d.DrawText(24, y, GREY, 0.65, "python tools/net_test_server.py")

        // log
        LX :: 380
        v2d.DrawRectangle(LX - 12, 64, 960 - LX, 400, PANEL)
        v2d.DrawText(LX, 88, CYAN, 1.0, "Log")
        count := intrinsics.atomic_load(&message_count)
        shown = count
        ly := i32(112)
        for i in max(0, count - LOG_LINES) ..< count {
            line := &messages[i]
            color := WHITE
            switch line.kind {
            case .Good: color = GREEN
            case .Bad:  color = RED
            case .Info: color = GREY
            }
            v2d.DrawText(LX, ly, color, 0.65, fmt.ctprintf("%s", string(line.text[:line.len])))
            ly += 21
        }
        if count == 0 do v2d.DrawText(LX, ly, GREY, 0.7, "nothing yet: press a button below")
        if busy do v2d.DrawText(LX + 60, 88, YELLOW, 0.8, "working...")

        v2d.DrawText(24, 492, WHITE, 0.75, "Cross  HTTP    Circle  HTTPS    Square  TCP to PC    Triangle  UDP to PC")
        v2d.DrawText(24, 514, WHITE, 0.75, "R  wait for the PC to connect    Up  type the PC's address")
        v2d.DrawText(24, 536, YELLOW if exit_hold > 0 else GREY, 0.7, "Hold Start + Select to exit")

        v2d.EndDrawing()
        v2d.CommonDialogUpdate()
        v2d.SwapBuffers()
        free_all(context.temp_allocator)
        frames += 1
    }

    // The worker may be in the middle of a wait of up to 20 seconds; give it
    // a moment, and leave it to the process exit if it does not come back.
    intrinsics.atomic_store(&worker_run, 0)
    if thread_ok {
        timeout: u32 = 2_000_000
        if sce.sceKernelWaitThreadEnd(thread, nil, &timeout) >= 0 {
            sce.sceKernelDeleteThread(thread)
            net.shutdown()
        }
    }

    v2d.WaitRenderingDone()
    v2d.FreeSizedFonts()
    vito.input_shutdown()
    sce.sceAppUtilShutdown()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
