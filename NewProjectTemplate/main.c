// C entry point — forwards to Odin game_main.

// newlib's heap (what vito's allocator, and so Odin's new / make / append, use)
// is one block taken at start-up. It is 128 MiB unless this variable is
// defined. Uncomment and change it if the game needs a different amount, for
// example to leave more room for textures (CDRAM is separate, but the main
// memory budget is shared with sceKernelAllocMemBlock).
//
// unsigned int _newlib_heap_size_user = 64 * 1024 * 1024;

extern int odin_main(int argc, char* argv[]);

int main(int argc, char* argv[]) {
    return odin_main(argc, argv);
}
