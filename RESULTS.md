# Jello Test Results

Real-world project builds using `CC=jellocc` as a drop-in compiler/linker driver. Each project tests a different facet of jello's pipeline — compile passthrough, library resolution, reordering, diagnostics, and plan emission.

## Platform Matrix

| Platform | Arch | Compiler | Backends | Date |
|----------|------|----------|----------|------|
| macOS (Darwin) | aarch64 | AppleClang 17.0.0 | system ld | 2026-02-14 |
| Linux (Ubuntu 24.04) | aarch64 | GCC 13.3.0 | gold 1.16, system ld (GNU ld 2.42) | 2026-02-16 |

| Project | Build System | macOS arm64 | Linux arm64 |
|---------|-------------|-------------|-------------|
| mbedtls | Makefile | PASS | PASS |
| lz4 | Makefile | PASS | PASS |
| libsodium | autotools + libtool | PASS | PASS |
| zstd | Makefile | PASS | PASS |
| mimalloc | CMake | PASS | PASS |

---

## 1. mbedtls (Mbed TLS)

**Repo:** https://github.com/Mbed-TLS/mbedtls

| | macOS arm64 | Linux arm64 |
|---|---|---|
| **Result** | PASS | PASS |
| **Date** | 2026-02-14 | 2026-02-16 |

### Why This Project

mbedtls produces three interdependent static libraries — `libmbedcrypto.a`, `libmbedx509.a`, and `libmbedtls.a` — where link order causes real undefined reference errors. This is the exact class of problem jello is built to solve: dependency-aware library reordering and actionable diagnostics when the order is wrong. It's also pure C with zero external dependencies, making it a clean first test with no confounding variables.

### Build Command

```
make -C library CC=jellocc -j4
```

### Output Summary

**macOS arm64:**
- 113 C source files compiled via passthrough
- 3 static libraries produced: `libmbedcrypto.a`, `libmbedx509.a`, `libmbedtls.a`
- Zero errors, zero warnings
- Build completed cleanly with -j4 parallelism

**Linux arm64:**
- 113 C source files compiled via passthrough
- 3 static libraries produced: `libmbedcrypto.a` (883 KB), `libmbedx509.a` (158 KB), `libmbedtls.a` (533 KB)
- Zero errors, zero warnings
- Build completed cleanly with -j4 parallelism

### What Jello Provided

- **Full passthrough:** All compiler driver invocations — compile, link, preprocess — routed transparently to the real system compiler. Completely invisible to the build system.
- **Self-reference avoidance:** With `CC=jellocc`, jello correctly resolved the real compiler by searching PATH defaults and filtering out any path resolving to a jello binary. No infinite loops, no env var conflicts.
- **Transparent drop-in:** The build system had no idea jello was in the loop. All 113 source files compiled identically to a native `CC=cc` build. Zero behavioral difference.
- **Cross-platform consistency:** Identical behavior on both macOS (AppleClang) and Linux (GCC). No platform-specific adjustments needed.

---

## 2. lz4

**Repo:** https://github.com/lz4/lz4

| | macOS arm64 | Linux arm64 |
|---|---|---|
| **Result** | PASS | PASS |
| **Date** | 2026-02-14 | 2026-02-16 |

### Why This Project

lz4 is a minimal smoke test that confirms jello works as a transparent drop-in across all compiler driver modes — not just compilation, but also shared library linking and executable linking. Its Makefile calls `CC` for everything: compiling object files, linking a shared library, archiving a `.a`, and linking the final CLI binary with multithreading support. This exercises the full spectrum of what a build system expects from `CC`.

### Build Command

```
make CC=jellocc
```

### Output Summary

**macOS arm64:**
- 22 C source files compiled via passthrough
- 3 artifacts produced: `liblz4.a` (static), `liblz4.1.10.0.dylib` (shared), `lz4` (CLI binary)
- Shared library linked with macOS-specific flags (`-dynamiclib`, `-install_name`, `-compatibility_version`, `-current_version`)
- CLI binary linked with multithreading support
- Zero errors, zero warnings

**Linux arm64:**
- 22 C source files compiled via passthrough
- 3 artifacts produced: `liblz4.a` (static), `liblz4.so.1.10.0` (shared), `lz4` (CLI binary)
- Shared library linked with `-shared` and `-soname` (ELF-style versioned `.so`)
- CLI binary linked with multithreading support (`-lpthread`)
- Zero errors, zero warnings

### What Jello Provided

- **Full passthrough for all modes:** Compilation (`-c`), shared library linking, and executable linking all routed transparently to the real compiler driver. jello didn't interfere with any of them.
- **Platform-native shared library flags:** On macOS, flags like `-dynamiclib`, `-install_name`, `-compatibility_version`, `-current_version`, `-arch arm64` were passed through verbatim. On Linux, `-shared`, `-Wl,-soname`, and ELF versioning flags were passed through equally cleanly. jello correctly deferred to the compiler driver on both platforms.
- **Multi-target build:** lz4's Makefile builds three separate targets (static lib, shared lib, CLI) in a single `make` invocation. jello handled all of them seamlessly.

---

## 3. libsodium

**Repo:** https://github.com/jedisct1/libsodium

| | macOS arm64 | Linux arm64 |
|---|---|---|
| **Result** | PASS | PASS |
| **Date** | 2026-02-14 | 2026-02-16 |

### Why This Project

libsodium is a widely-used crypto library with an autotools build system (`./configure && make`). It exercises jello against a more complex build pipeline: autoconf probes the compiler with dozens of feature-detection invocations during `./configure`, then `make` compiles into multiple internal convenience libraries before linking the final `libsodium` as both static and shared. This tests jello's ability to survive autoconf's compiler introspection (flag probing, feature tests, `-Werror` trials) and libtool's multi-stage link orchestration.

### Build Command

```
CC=jellocc ./configure && make -j4
```

### Output Summary

**macOS arm64:**
- 146 C source files compiled via passthrough
- 9 link steps: 8 internal convenience libraries (`libsse41`, `libavx2`, `libavx512f`, `libaesni`, `libsse2`, `libarmcrypto`, `libssse3`, `librdrand`) + final `libsodium.la`
- Both static (`libsodium.a`, 939 KB) and shared (`libsodium.30.dylib`, 741 KB) outputs produced
- Zero errors, zero warnings (ranlib warnings about empty archives are expected on macOS for x86-only SIMD libs)

**Linux arm64:**
- 146 C source files compiled via passthrough
- 9 link steps: 8 internal convenience libraries + final `libsodium.la`
- Both static (`libsodium.a`, 756 KB) and shared (`libsodium.so.30.0.0`, 525 KB) outputs produced
- Zero errors, zero warnings

### What Jello Provided

- **Autoconf compatibility:** `./configure` runs dozens of compiler probes — feature tests, flag checks, `conftest.c` compilations, `-Werror` trials. All of them passed through jello transparently. The configure script had no idea it wasn't talking to the real compiler — on either macOS or Linux.
- **Libtool orchestration:** libtool wraps `CC` with its own flags (`-fPIC`, `-DPIC`, version info, install names on macOS / `-soname` on Linux) and calls it for both compilation and linking. jello handled all of libtool's invocation patterns without interference on both platforms.
- **Multi-library builds:** 8 internal convenience libraries for different CPU instruction sets (SSE2, SSE4.1, AVX2, AVX-512, AES-NI, ARM Crypto, SSSE3, RDRAND) all compiled and linked independently before being merged into the final `libsodium`. jello handled the full DAG.

---

## 4. zstd (Zstandard)

**Repo:** https://github.com/facebook/zstd

| | macOS arm64 | Linux arm64 |
|---|---|---|
| **Result** | PASS | PASS |
| **Date** | 2026-02-14 | 2026-02-16 |

### Why This Project

zstd is Facebook's production compression library with a complex multi-target Makefile. A single `make` invocation builds three separate configurations: the core library as both static (`libzstd.a`) and shared (`libzstd.so`/`.dylib`), then the CLI tool which statically links all internal components plus external dependencies. The Makefile compiles the same source files multiple times with different flags for each configuration (static vs dynamic vs program), testing jello's ability to handle a multi-pass build with distinct compilation contexts.

### Build Command

```
make CC=jellocc HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 -j4
```

### Output Summary

**macOS arm64:**
- 101 C source files compiled via passthrough across 3 build configurations (static lib, shared lib, CLI)
- 3 artifacts produced: `libzstd.a` (2.0 MB static), `libzstd.1.6.0.dylib` (1.8 MB shared), `zstd` (2.0 MB CLI binary)
- Final CLI binary linked with threading support (`-pthread`) and 41 object files in a single link invocation
- Zero errors, zero warnings

**Linux arm64:**
- ~101 C source files compiled via passthrough across 3 build configurations (static lib, shared lib, CLI)
- 3 artifacts produced: `libzstd.a` (881 KB static), `libzstd.so.1.6.0` (746 KB shared), `zstd` (958 KB CLI binary)
- Final CLI binary linked with threading support (`-pthread`) and multi-config object files
- Zero errors, zero warnings

### What Jello Provided

- **Multi-configuration builds:** The same source files were compiled three times with different flags (`-fPIC` for shared, without for static, with program-specific defines for CLI). jello passed through all three configurations without interference.
- **Complex link invocation:** The final `zstd` binary link command included dozens of object files, `-pthread`, architecture-specific flags, and warning flags — all passed through verbatim to the real compiler driver on both platforms.
- **Build system flag soup:** zstd's Makefile passes aggressive warning flags (`-Wcast-qual`, `-Wstrict-aliasing=1`, `-Wc++-compat`), architecture flags, and GNU-style assembler options (`-Wa,--noexecstack`). jello handled all of them transparently on both macOS and Linux.

---

## 5. mimalloc

**Repo:** https://github.com/microsoft/mimalloc

| | macOS arm64 | Linux arm64 |
|---|---|---|
| **Result** | PASS | PASS |
| **Date** | 2026-02-14 | 2026-02-16 |

### Why This Project

mimalloc is Microsoft's production memory allocator — a small, clean C project with a CMake build system. It tests jello against CMake's compiler detection and probing pipeline, which is more sophisticated than autotools: CMake runs ABI detection, feature probes, and `try_compile` tests before any real compilation begins. mimalloc also links against `pthread` and builds platform-specific code, testing jello's ability to handle platform-aware linking through CMake.

### Build Command

```
cmake -S . -B build -DCMAKE_C_COMPILER=jellocc && cmake --build build -j4
```

### Output Summary

**macOS arm64:**
- 39 C source files compiled via passthrough across 4 build targets (shared, static, object, tests)
- 6 link targets: `libmimalloc.a` (static), `libmimalloc.dylib` (shared), `mimalloc-test-api`, `mimalloc-test-api-fill`, `mimalloc-test-stress`, `mimalloc-test-stress-dynamic`
- CMake correctly identified jellocc as AppleClang 17.0.0
- All test binaries built and linked against `pthread`
- Zero errors, zero warnings

**Linux arm64:**
- 39 C source files compiled via passthrough across 4 build targets (shared, static, object, tests)
- 6 link targets: `libmimalloc.a` (313 KB static), `libmimalloc.so.2.2` (236 KB shared), `mimalloc-test-api`, `mimalloc-test-api-fill`, `mimalloc-test-stress`, `mimalloc-test-stress-dynamic`
- CMake correctly identified jellocc as GCC 13.3.0
- Linked against `pthread`, `rt`, and `atomic` (Linux-specific runtime deps)
- Compiler flags included `-march=armv8.1-a` for LSE atomics
- Zero errors, zero warnings

### What Jello Provided

- **CMake compiler detection:** CMake ran ABI detection, feature probing, and `try_compile` checks through jellocc. All probes passed — CMake correctly identified the underlying compiler (AppleClang on macOS, GCC on Linux) and detected all platform capabilities.
- **Platform-specific compilation:** On macOS, mimalloc builds allocation zone overrides and interposition code. On Linux, it links against `rt` and `atomic` and uses `armv8.1-a` architecture features. Platform-specific compiler flags (`-ftls-model=initial-exec`, `-fno-builtin-malloc`, `-fvisibility=hidden`) were all passed through verbatim.
- **Test binary linking:** 4 test executables linked against the shared and static libraries plus platform-specific runtime libraries. All link invocations succeeded through jello's passthrough to the real compiler driver.
