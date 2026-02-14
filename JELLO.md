

Product definition

What it is

A linker driver that sits where cc/c++/ld sit, ingests a compiler/linker invocation (or compile database), and produces a deterministic LinkPlan:
  • chosen backend (mold/lld/bfd/link.exe)
  • normalized args
  • resolved library deps
  • resolved search paths
  • chosen sysroot/toolchain
  • chosen runtime libs / stdlib
  • fixes applied (ordering, missing flags, etc.)
  • emitted as a readable artifact for debugging/repro

Then it executes the backend and captures structured diagnostics.

What it is not

It is not a new ELF/Mach-O/COFF linker backend.

⸻

Core goals (what it must realistically solve)

G0. “Drop-in” integration
  • Must be usable as CC=gelcc CXX=gelc++ or as a wrapper around clang/gcc.
  • Must support common build systems without patches: CMake, Meson, Bazel-ish wrappers, Makefiles.

G1. Invocation normalization

Take chaos like:
  • gcc vs clang differences
  • redundant flags
  • conflicting flags
  • platform-specific defaults

…and normalize to an internal canonical model.

G2. Toolchain and target inference

Correctly infer/resolve:
  • target triple
  • sysroot
  • libc variant (glibc vs musl)
  • arch mismatches (x86_64 vs aarch64) early
  • “you’re cross-compiling and don’t know it” cases

G3. Library discovery + dependency closure

Given -lfoo (and/or foo.a, libfoo.so) it should:
  • locate the actual artifacts
  • understand pkg-config and/or *-config helpers where relevant
  • optionally close deps (e.g., foo implies bar on this distro/toolchain) via rules
  • choose static vs dynamic based on policy and availability

G4. Order and grouping fixes (the #1 “why the hell” failure)

Common recoverable stuff:
  • static library ordering problems
  • “needs –start-group/–end-group” loops
  • missing -Wl,--as-needed / --no-as-needed interactions
  • adding --whole-archive in a targeted way (rare, but real)

G5. Root-cause diagnostics + auto-fix when safe

Translate garbage like:
  • undefined reference to ...
  • cannot find -lX
  • relocation R_X86_64_32S against ...
  • file format not recognized
  • DSO missing from command line
  • ld: error: unable to find library -lc++

Into:
  • “you are linking C++ objects with a C linker driver; you need CXX or add stdlib”
  • “you mixed architectures; these .o are aarch64 but target is x86_64”
  • “you are building PIE but linked non-PIC static lib; rebuild with -fPIC or use shared”
  • “libX is installed but not in search path; add -L… or install dev package Y”

…and apply fixes only when confidence is high.

G6. Reproducibility artifact

Every run emits:
  • linkplan.json (or .toml) with the full resolved plan
  • linkplan.sh replay script
  • diagnostics.json structured errors/warnings
This turns “it fails on CI” into “here is the exact plan.”

⸻

“Silently works” definition (so it doesn’t become dangerous)

You want a policy with three modes:

Mode A: Auto-fix

Only for fixes that are:
  • deterministic
  • reversible
  • extremely likely correct

Examples:
  • add missing -lstdc++ when detecting C++ symbols
  • reorder static libs based on dependency graph
  • switch backend to mold if installed and compatible

Mode B: Explain + Suggest

When multiple fixes could be correct:
  • don’t guess; present top 1–3 fixes with confidence scores
  • show why (actual evidence from symbols/objects/targets)

Mode C: Hard fail with pinpoint reason

When it’s genuinely not solvable automatically (ABI mismatch across third-party binaries, corrupt objects, etc.)

This preserves correctness while still removing sharp corners.

⸻

Explicit scope boundaries (out of scope for v1)

This is what keeps the project “feature rich but targeted.”

OOS1. Writing final binaries yourself

No custom relocation/section layout. You delegate to mold/lld/ld.

OOS2. LTO implementation

You can pass through LTO flags and detect incompatibilities, but you’re not implementing LTO or plugin protocols.

OOS3. Full package manager behavior

You can suggest packages (“install libssl-dev”), but you’re not building apt/yum integration as a hard dependency.

OOS4. Being smarter than the compiler

You’re not doing whole-program compilation decisions—just link-stage resolution and diagnostics.

OOS5. Solving runtime loader issues (beyond basic)

You can help with rpath/runpath sanity, but you’re not building a dynamic loader debugger in v1.

⸻

Feature set that hits “usable v1” without exploding

V1 must-have features
  1.  Intercept + parse link commands
  • support gcc/clang style
  • support response files (@file.rsp)
  • support -Wl, forwarding parsing
  2.  Backend selection
  • prefer mold if available and compatible
  • else lld
  • else system ld
  • output which was chosen and why
  3.  Target inference
  • detect target triple (from compiler, env, objects)
  • detect sysroot and default search paths
  • early arch mismatch detection
  4.  Library resolution
  • resolve -lX to concrete paths
  • print the resolution chain
  • detect “found wrong arch” libs
  5.  Static lib ordering repair
  • build a symbol dependency graph:
  • undefined -> defined providers across libs
  • reorder libs or apply --start-group if cycles
  6.  DX error translation
  • a curated set of 20–30 high-value linker failure patterns
  • each with:
  • detection heuristic
  • suggested fix(es)
  • evidence snippet
  7.  Emit LinkPlan + Replay
  • reproducible linkplan.sh
  • linkplan.json
  • “diff” between input args and normalized args

V1 nice-to-have (still reasonable)
  • caching by hash of LinkPlan inputs
  • “doctor” command: gel doctor to inspect environment (toolchains, search paths)
  • --explain mode: prints reasoning tree

⸻

V2 expansions (where it becomes “gel”)

Once v1 is solid, these are the obvious “wow” upgrades:

V2.1 Profiles

Named profiles like:
  • linux-gnu-x86_64
  • linux-musl-x86_64
  • linux-gnu-aarch64-cross
  • macos-arm64
Each profile defines:
  • default sysroot behavior
  • stdlib selection rules
  • allowed backends
  • fallback strategies

V2.2 pkg-config integration
  • auto-consume pkg-config --libs --cflags for known libs
  • detect mismatched pkg-config target

V2.3 ABI mismatch detection (C++ pain)

Heuristics to detect:
  • libstdc++ vs libc++ mismatch
  • _GLIBCXX_USE_CXX11_ABI mismatch indicators
  • mixing clang++ and g++ runtime libs in the same binary

V2.4 RPATH/RUNPATH sanity
  • automatically add safe rpath for bundled deps
  • warn on insecure patterns

⸻

Architecture sketch (tight and buildable)

Components
  1.  Frontend
  • CLI + wrapper mode (gelcc, gelc++, geld)
  • parses raw args
  2.  Normalizer
  • transforms raw args into canonical LinkRequest
  • resolves response files
  • standardizes semantics across GCC/Clang
  3.  Resolver
  • discovers toolchain + target + sysroot
  • builds search path set
  • resolves -l + file inputs
  4.  Planner
  • builds symbol tables from libs/objs (using nm, llvm-nm, or direct parsing later)
  • decides ordering / grouping strategy
  • chooses backend + produces LinkPlan
  5.  Executor
  • runs backend
  • captures stdout/stderr + exit code
  6.  Diagnoser
  • pattern matches error output
  • consults LinkPlan evidence
  • emits structured root cause + suggested remediations

Key artifact

LinkPlan is your “gel membrane.” Everything is explainable from it.

⸻

Definition of Done for “targeted and usable”

A v1 is real when:
  • you can set CC=gelcc CXX=gelc++ on a typical Linux dev box
  • build 3–5 moderately gnarly OSS C/C++ projects successfully
  • and when it fails, the output is actually actionable (not vibes)
