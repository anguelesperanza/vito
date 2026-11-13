# Notes on the `.gxp` shader format

`SceGxm` runs shader programs in a binary format called GXP. Today they come from
Sony's `psp2cgc.exe` (see "Shaders" in [getting-started.md](getting-started.md)).
The long-term plan, on the Matchbox side, is a shader language of its own with a
compiler that writes each platform's format directly, which for the Vita means
writing `.gxp` files. These notes collect what is known about the format so that
work does not start from zero.

**Status: a starting point, not a specification.** Only the container (header and
parameter table) is described. The instruction encoding, which is most of the work,
is not.

Everything under "Checked here" was read out of the 18 `.gxp` files in this
repository with [tools/gxp_info.py](../tools/gxp_info.py) and is consistent across
all of them. Run that tool on any `.gxp` to see these fields. All the files were
produced by one compiler version (SDK 3.50), so other versions may differ.

## Checked here

All values are little-endian. A file is one program: either a vertex program or a
fragment program.

### Header

| Offset | Size | Meaning |
|---|---|---|
| 0x00 | 4 | Magic: `GXP\0` |
| 0x04 | 1 | Format major version (1) |
| 0x05 | 1 | Format minor version (5) |
| 0x06 | 2 | SDK version (0x0350) |
| 0x08 | 4 | Size of the program in bytes. The file is this rounded up to a multiple of 4. |
| 0x0C | 4 | A hash. Identical for identical source text. |
| 0x10 | 4 | A second hash. It differed between two compiles of the same source text from different folders, so it covers more than the text (probably the path). |
| 0x14 | 4 | Flags. Bit 0 is set for a fragment program and clear for a vertex program. The other bits vary and are not understood. |
| 0x1C | 4 | Bit mask of the texture units the program samples (1 for one sampler on unit 0). |
| 0x24 | 4 | Number of parameters |
| 0x28 | 4 | Offset of the parameter table, **relative to this field's own position** (table = 0x28 + value) |
| 0x30 | 2 | Size of the primary register bank in floats. For a vertex program this is the attributes, 4 per attribute. |
| 0x32 | 2 | Size of the secondary register bank in floats: the default uniform buffer, plus (in one file) 2 more that are probably constants. |
| 0x3C | 4 | Number of instructions |
| 0x40 | 4 | Offset of the instructions, relative to this field's own position |
| 0x64 | 4 | Size of the default uniform buffer in floats (16 for one `float4x4`) |

Offsets inside the file are generally stored this way, relative to the position of
the field that holds them. Several more header words (0x2C, 0x48, 0x4C, 0x68, 0x74,
0x7C, ...) look like offsets of the same kind to tables this document does not
describe.

### Parameter table

One 16-byte entry per attribute, uniform and sampler, in declaration order.
Parameters the shader does not use are absent: the compiler removes them.

| Offset | Size | Meaning |
|---|---|---|
| 0 | 4 | Offset of the name (zero-terminated ASCII), relative to the start of this entry |
| 4 | 2 | Bit field: bits 0-3 category (0 attribute, 1 uniform, 2 sampler), bits 4-7 type (0 in every file here, all floats), bits 8-11 component count, bits 12-15 container index (14 for uniforms in the default uniform buffer, 0 otherwise) |
| 6 | 1 | Semantic (0 for attributes and uniforms here, 1 for samplers) |
| 7 | 1 | Semantic index |
| 8 | 4 | Array size. A `float4x4` is 4 (four rows of 4 components). |
| 12 | 4 | Resource index: for an attribute, its register (0, 4, 8, ...); for a uniform, its offset in the default uniform buffer in floats; for a sampler, the texture unit |

Two things to note:

- Uniforms are padded to 4 floats each: three `float3` uniforms sit at 0, 4 and 8.
- The component count is 4 for every attribute, including `float2` and `float3`
  ones, so for attributes it is not the declared width. For uniforms it is (3 for
  `float3`, 4 for `float4`).

These fields are what `sceGxmProgramFindParameterByName`,
`sceGxmProgramParameterGetResourceIndex` and the other `sceGxmProgramParameter*`
functions return, which is a second way to check them on a console.

### Instructions

Instructions are 8 bytes each. Every program here starts with the same instruction
(words `00000000 FA440700`) and every vertex program ends with the same one
(`A0200000 FB275000`). `gxp_info.py` prints them as hex; nothing more is decoded.

## Not known

- The instruction encoding. The GPU is a PowerVR SGX543 and the instruction set is
  Imagination's "USSE"; that is the search term.
- The tables between the header and the code: vertex outputs and fragment inputs
  (which link a vertex program to a fragment program), constants, the sampler and
  uniform buffer descriptions, and the fields the shader patcher uses to apply blend
  modes and output formats.
- Which header fields `sceGxmProgramCheck` and the shader patcher validate. A
  hand-written file has to pass both.

## Where to look next

- **Vita3K** (the open-source emulator) reads `.gxp` files and translates their
  instructions, so its source contains a full description of the header structure
  and an instruction decoder. I have not checked these notes against it; the field
  names above are mine.
- **`psp2spvc`** is an open-source tool that writes `.gxp` from SPIR-V. It is the
  closest existing thing to the planned compiler, and is described by its authors as
  experimental.
- **Differential testing with `psp2cgc`.** With the compiler at hand, the cheapest
  way to learn an instruction is to compile two shaders that differ in one operation
  and compare the output with `gxp_info.py`.

## What a compiler of our own would need

A tool in the style of `psp2cgc` has four parts. Three are ordinary compiler work;
one depends on knowledge that was never published.

| Part | What it does | How hard |
|---|---|---|
| Front end | Parses the shader language, checks types, produces an intermediate form | Ordinary. Needed for the Matchbox shader language anyway. For Cg input it also needs Cg's built-in functions (`mul`, `dot`, `normalize`, `tex2D`, ...) |
| Lowering | Turns that into operations the GPU has and assigns every value to one of its register banks (attributes, uniforms, temporaries, outputs) | Ordinary, but shaped by the hardware's rules |
| Instruction encoder | Writes each operation as an 8-byte USSE instruction | **The hard part.** Not documented by Sony or Imagination |
| Container writer | Wraps the code in a `.gxp`: header, parameter table, vertex-output and fragment-input tables, constants, metadata | Moderate. This file covers the header and parameters; the other tables are not mapped yet |

What makes the encoder hard:

- **The opcodes and their bit layouts.** Each instruction packs an operation, source
  and destination registers, component swizzles and write masks into 64 bits.
- **Fragment programs are split into phases.** Texture lookups whose coordinates
  come straight from the vertex shader are done by the hardware before the shader
  runs. The compiler describes those lookups in a table instead of emitting code for
  them, and splits the program around any lookup that depends on computed values.
- **Metadata the system checks.** `sceGxmProgramCheck` and the shader patcher both
  validate the file, and the patcher rewrites part of it to apply blend modes and
  output formats. Correct code with wrong metadata is rejected or drawn wrong.

The three sources of that knowledge are listed under "Where to look next" above:
Vita3K (the reading direction), `psp2spvc` (the writing direction), and differential
testing with `psp2cgc`. The first two are described here from memory; their current
state and licences have not been checked, which matters if code is to be reused and
not only learned from.

### A staged way to get there

1. **Emit Cg and call `psp2cgc`.** This is what `tools/build_shaders.py` does today.
   The shader language works on the Vita at once, with a known-good back end, and
   the later stages can replace it without changing the language.
2. **Write a disassembler.** Extend `tools/gxp_info.py` until it prints every
   instruction and every table of the 18 shaders in this repository.
3. **Write an assembler.** Take that printed form and rebuild the identical bytes.
   When all 18 round-trip exactly, the format is understood for everything those
   shaders use. Stages 2 and 3 need no compiler design at all, and are where the
   real learning happens.
4. **Generate code for a small subset:** straight-line shaders with multiply, add,
   dot product and one texture lookup. That covers the colour, texture and sprite
   shaders in this repository.
5. **Widen it:** lighting maths, branches, dependent texture reads, more output
   formats.

Each stage should end the way every phase of the bindings did: the output loaded and
drawn on a real Vita, and compared with what `psp2cgc` produces for the same source.

### Rough size

No reliable estimate is possible, because the encoding work is discovery and not
only construction. As an order of magnitude: the subset in stage 4 is weeks of
focused work if Vita3K's decoder is a good guide, and matching `psp2cgc` across
everything a game might write is months. The front end for the Matchbox language is
separate from both, and is needed for the PC and 3DS targets regardless.

### What is not an alternative

A compiler cannot be built from a header. VitaSDK has no `psp2cgc.h`; its
`psp2/shacccg.h` is the interface to the compiler that runs on the console
(`libshacccg.suprx`, a Sony binary). Using it would move the dependency from a PC
executable to a file on the console, not remove it. That was considered and declined
on 2026-11-13; see "Shader notes" in [roadmap.md](roadmap.md).
