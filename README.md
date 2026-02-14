# jello

> The compiler IR for linkers.

**jello** is a deterministic linker driver that turns messy, folklore-heavy linking into a clean, explainable **LinkPlan**. It normalizes linker invocations, resolves the environment, produces a deterministic plan, and runs the best backend linker.

It does **not** replace your linker. It makes linking **understandable and reliable**.

jello ships as three binaries:

* **`jellocc` / `jelloc++`** — transparent compiler wrappers. Drop in as `CC=jellocc` and they passthrough all invocations to the real compiler. Your build system doesn't know they're there.
* **`jellod`** — the intelligent linker driver. This is where the LinkPlan pipeline lives: normalization, resolution, reordering, diagnostics, and backend selection.

---

## Why jello exists

Linking is still one of the most opaque parts of modern development:

* cryptic errors
* environment-dependent behavior
* fragile flag ordering
* tribal knowledge fixes

jello makes linking **deterministic and explainable** by introducing a first-class artifact: the **LinkPlan**.

---

## What jello does

* Acts as a transparent drop-in: `CC=jellocc CXX=jelloc++` — handles compile, link, preprocess, and introspection seamlessly
* Normalizes chaotic linker invocations into a structured model
* Resolves target, sysroot, search paths, and libraries
* Computes a deterministic **LinkPlan**
* Selects the best backend (`mold` → `lld` → system linker)
* Executes the backend and emits structured diagnostics

---

## The LinkPlan (the core idea)

A **LinkPlan** is the compiler IR for linking — a deterministic snapshot of intent.

It includes:

* target triple
* ordered inputs
* resolved library paths
* chosen backend linker
* applied fixes and assumptions

jello emits:

* `linkplan.json` — machine-readable plan
* `replay.sh` — deterministic reproduction

This turns linker behavior from folklore into data.

---

## DX benefits (developer perspective)

* **Fewer "what the hell" linker failures**
* **Actionable errors instead of cryptic symbols**
* **Reproducible link steps** across machines and CI
* **Less cargo-cult flag tweaking**

Example:

Instead of:

```
undefined reference to _ZSt4cout@@GLIBCXX_3.4
```

jello says:

> You're linking C++ objects with a C driver. Use CXX or add the C++ standard library.

---

## DX benefits (technical perspective)

* Deterministic linking via immutable plans
* Structured diagnostics with root-cause evidence
* Environment introspection (target, sysroot, ABI mismatches)
* Stable artifacts for debugging and caching

jello turns linking into a **modeled system** instead of a side-effect of toolchains.

---

## Configuration

jello works out of the box with zero config. For per-project customization, drop a `.jello.json` at your project root:

```bash
jello init
```

```json
{
  "fix_mode": "auto",
  "emit_plan": true,
  "plan_dir": ".jello",
  "silent": true
}
```

Config hierarchy (highest priority wins):

1. Environment variables (`JELLO_BACKEND`, `JELLO_FIX_MODE`, etc.)
2. Project config (`.jello.json`, found by walking up from CWD)
3. User config (`~/.config/jello/config.json`)
4. Defaults

All fields are optional. Missing fields fall through to the next layer. Run `jello doctor` to see active config and detected environment.

---

## Validated

jello has been tested as a drop-in `CC=jellocc` across 5 real-world C projects covering Makefile, autotools, and CMake build systems:

| Project | Files | Artifacts | Build System |
|---------|-------|-----------|-------------|
| [mbedtls](https://github.com/Mbed-TLS/mbedtls) | 113 | 3 static libs | Makefile |
| [lz4](https://github.com/lz4/lz4) | 22 | static + shared + CLI | Makefile |
| [libsodium](https://github.com/jedisct1/libsodium) | 146 | 9 link targets, static + shared | autotools + libtool |
| [zstd](https://github.com/facebook/zstd) | 101 | static + shared + CLI | Makefile |
| [mimalloc](https://github.com/microsoft/mimalloc) | 39 | static + shared + 4 test binaries | CMake |

All builds produce identical outputs to native `CC=cc`. See [RESULTS.md](RESULTS.md) for details.

---

## What jello is not

* Not a new ELF/Mach-O/COFF linker
* Not a package manager
* Not a full build system

jello is a **semantic linker driver**: orchestration, normalization, and diagnostics.

---

## Philosophy

Linking should not require folklore.

If compilers have IRs, linking should too.

**jello makes linking legible.**
