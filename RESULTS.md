# Jello Test Results

Real-world project builds using `CC=jellocc` as a drop-in compiler/linker driver. Each project tests a different facet of jello's pipeline — compile passthrough, library resolution, reordering, diagnostics, and plan emission.

---

## 1. mbedtls (Mbed TLS)

**Repo:** https://github.com/Mbed-TLS/mbedtls
**Result:** PASS
**Date:** 2025-02-14

### Why This Project

mbedtls produces three interdependent static libraries — `libmbedcrypto.a`, `libmbedx509.a`, and `libmbedtls.a` — where link order causes real undefined reference errors. This is the exact class of problem jello is built to solve: dependency-aware library reordering and actionable diagnostics when the order is wrong. It's also pure C with zero external dependencies, making it a clean first test with no confounding variables.

### Build Command

```
make -C library CC=jellocc -j4
```

### Output Summary

- 113 C source files compiled via compile passthrough (jellocc -c)
- 3 static libraries produced: `libmbedcrypto.a`, `libmbedx509.a`, `libmbedtls.a`
- Zero errors, zero warnings
- All compilations routed through jello's compile passthrough to the real system compiler (clang)
- Build completed cleanly with -j4 parallelism

### What Jello Exercised

- **Compile passthrough:** Every `CC=jellocc -c foo.c -o foo.o` invocation was detected as compile-only via the `-c` flag pre-scan, then routed directly to the real compiler. This is the feature that was missing before this test — jello previously sent all wrapper-mode invocations through the linker pipeline, causing compile-only calls to hang.
- **Self-reference avoidance:** With `CC=jellocc`, jello's `Discover.real_compiler` correctly found `/usr/bin/cc` (clang) by searching PATH defaults and filtering out any path resolving to a jello binary. No infinite loop.
- **Transparent drop-in:** The build system (make) had no idea jello was in the loop. All 113 source files compiled identically to a native `CC=cc` build.

### What This Exposed

This project exposed the critical compile passthrough gap. Before testing mbedtls, jello only handled link invocations in wrapper mode. The mbedtls build immediately hung because make calls `CC` for compilation too, not just linking. This led to implementing `Parse.is_compile_only`, `Discover.real_compiler`, `Execute.run_cmd`, and `Driver.compile` — the full compile passthrough pipeline.
