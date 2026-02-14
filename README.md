# jello

> The compiler IR for linkers.

**jello** is a deterministic linker driver that turns messy, folklore-heavy linking into a clean, explainable **LinkPlan**. It sits where `cc`/`c++`/`ld` sit, normalizes the invocation, resolves the environment, produces a deterministic plan, and runs the best backend linker.

It does **not** replace your linker. It makes linking **understandable and reliable**.

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

* Acts as a drop-in driver: `CC=jellocc CXX=jelloc++`
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
