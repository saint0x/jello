# CLAUDE.md — Elite OCaml Engineering Standard

This document defines the engineering bar for an elite OCaml engineer building production-grade tooling (e.g., compilers, linkers, static analyzers, symbolic engines). It encodes principles for writing **elegant, idiomatic, modern OCaml** that maximizes:

* Determinism
* Reliability
* Safety (OCaml-equivalent of full memory safety)
* Performance
* Clarity and algebraic correctness

The goal is not "OCaml that feels like Rust" — it is **OCaml at its highest form**: algebraically clean, predictable, fast, and deeply maintainable.

---

# Core Philosophy

## 1. Determinism First

All core logic must be:

* Referentially transparent where possible
* Free of hidden side effects
* Explicit about time, randomness, and I/O boundaries

Pure logic must be isolated from effectful edges.

**Rule:** If it can be pure, it must be pure.

---

## 2. Algebra Over Cleverness

Programs should read like transformations over algebraic data, not procedural scripts.

Prefer:

* Sum types (variants)
* Product types (records)
* Pattern matching
* Small composable functions

Avoid:

* Implicit mutation
* Opaque control flow
* Overly clever abstractions

---

## 3. Make Invalid States Unrepresentable

Use the type system aggressively.

* Model invariants in types
* Use variants instead of flags
* Encode phases in types
* Separate validated vs unvalidated data

Example:

```ocaml
type unvalidated
type validated

type 'phase config = {
  path : string;
  parsed : ast option;
}
```

---

## 4. OCaml Safety Model (Rust-Grade Discipline, OCaml Style)

OCaml already provides memory safety via GC. The elite bar adds:

* No unsafe mutation in core logic
* No global hidden state
* Deterministic effect boundaries
* No reliance on GC timing

Treat GC as an implementation detail, not a semantic crutch.

---

# Architecture Principles

## 5. Pure Core, Effectful Shell

Structure systems as:

```
Pure Domain Core
        ↓
Planning Layer (pure)
        ↓
Execution Layer (effects)
```

* Parsing, planning, validation → pure
* I/O, subprocess, filesystem → edge modules

This maximizes testability and determinism.

---

## 6. The LinkPlan Pattern (Generalized)

All complex orchestration systems should emit a **plan artifact**:

* Immutable
* Serializable
* Replayable
* Diffable

This enables:

* Deterministic builds
* Debuggability
* Reproducibility

Always prefer computing a plan before executing side effects.

---

## 7. Explicit Phases

Large systems must have typed phases:

* Parsed
* Normalized
* Resolved
* Validated
* Planned
* Executed

Each phase has its own types. Avoid "giant mutable context" designs.

---

# Type System Mastery

## 8. Variants Over Booleans

Never use booleans where a sum type conveys intent.

Bad:

```ocaml
{ static : bool }
```

Good:

```ocaml
type link_mode = Static | Dynamic
```

---

## 9. Closed Worlds by Default

Prefer closed variants unless extensibility is required.
Closed worlds give:

* Exhaustive matching
* Compiler-enforced correctness

---

## 10. Records for Data, Modules for Meaning

Use records for:

* Plain data containers

Use modules for:

* Invariants
* Construction APIs
* Encapsulation

---

## 11. Smart Constructors

Enforce invariants at construction time.

```ocaml
module Non_empty_list : sig
  type 'a t
  val create : 'a -> 'a list -> 'a t
end
```

---

## 12. Phantom Types for Phase Safety

Use phantom types to encode lifecycle states without runtime cost.

This gives Rust-like phase safety in OCaml.

---

# Module System Excellence

## 13. Prefer Small, Sharp Modules

Modules should be:

* Focused
* Algebraically meaningful
* Cohesive

Avoid giant utility modules.

---

## 14. Signatures First Design

Design the `.mli` before `.ml` when building critical components.

A strong signature:

* Encodes invariants
* Prevents misuse
* Improves readability

---

## 15. Functors When Algebraically Justified

Use functors for:

* Parametric architectures
* Swappable policies
* Testable backends

Avoid functors as glorified generics.

---

# Performance Discipline

## 16. Allocation Awareness (Without Obsession)

Write allocation-aware code in hot paths:

* Prefer records over nested tuples
* Avoid intermediate lists in tight loops
* Use `Array` for indexed hot paths
* Use `Buffer` for incremental building

Measure before optimizing.

---

## 17. Structural Sharing by Default

Leverage immutability for cheap persistence.

Prefer persistent structures unless profiling proves otherwise.

---

## 18. Tail Recursion Everywhere It Matters

All recursive traversals over large structures must be tail-recursive or use accumulators.

---

## 19. Avoid Accidental Quadratic Behavior

Watch for:

* List append in loops
* Repeated traversals
* Naive map/filter chains

Fuse passes when necessary.

---

## 20. Choose the Right Container

Guidelines:

| Use     | When                        |
| ------- | --------------------------- |
| list    | small, linear traversal     |
| array   | indexed, hot loops          |
| map/set | ordered logic               |
| hashtbl | performance-critical lookup |

---

# Determinism and Reliability

## 21. No Hidden Global State

Avoid mutable globals unless explicitly modeled.
If needed, isolate in a clearly named module.

---

## 22. Deterministic Iteration

Avoid nondeterministic iteration over hash tables in core logic.
If ordering matters, sort explicitly.

---

## 23. Explicit Time and Randomness

Never call:

* `Unix.time`
* RNGs

Inside core logic. Inject via interfaces.

---

## 24. Reproducible Outputs

All build artifacts must be:

* Stable ordering
* Canonical serialization
* Versioned formats

---

# Error Handling Excellence

## 25. Typed Errors Over Exceptions (Core Logic)

Use result types in core layers:

```ocaml
('a, error) result
```

Exceptions are allowed at boundaries.

---

## 26. Rich Error Domains

Define structured error types, not strings.

```ocaml
type error =
  | Missing_library of string
  | Arch_mismatch of { expected : arch; found : arch }
```

---

## 27. Diagnostics as Data

Errors should carry:

* Evidence
* Context
* Suggested fixes

Make diagnostics serializable.

---

# Modern OCaml Patterns

## 28. Use Let Operators (Result/Option)

Adopt monadic bind operators for clarity:

```ocaml
let* x = parse input in
let* y = resolve x in
Ok (plan y)
```

---

## 29. Prefer Pattern Matching Over If-Chains

Pattern matching is the primary control structure.

---

## 30. Explicit Naming Over Clever Point-Free Style

Clarity > brevity.

Avoid overly point-free code unless it improves readability.

---

## 31. Use Records with Labels for Readability

Favor named fields over positional tuples in public APIs.

---

# Testing Strategy

## 32. Property-Based Testing for Core Logic

Use QCheck or similar for:

* planners
* graph transforms
* normalizers

These systems are algebraic — test them algebraically.

---

## 33. Golden Tests for Plans

Snapshot serialized plan artifacts.
Ensure stability across versions.

---

## 34. Deterministic Test Environments

No reliance on:

* system time
* host randomness
* filesystem ordering

---

# Observability Without Chaos

## 35. Structured Logging Only

Logs should be:

* machine-readable
* levelled
* deterministic

Avoid printf debugging in core layers.

---

## 36. Explainability as a Feature

All planners should support:

* explain mode
* decision traces
* reasoning trees

This is a first-class feature, not a debug hack.

---

# Interop and Systems Boundaries

## 37. Rust/C Interop Philosophy

When crossing language boundaries:

* OCaml owns planning and semantics
* Native code owns raw execution and bit-level work

Keep boundaries narrow and well-typed.

---

## 38. Minimize FFI Surface Area

Prefer:

* coarse-grained FFI calls
* serialized inputs/outputs

Avoid chatty FFI.

---

# Code Quality Bar

## 39. Readability > Cleverness

Elite OCaml is:

* calm
* explicit
* composable

Future readers must understand intent quickly.

---

## 40. No Accidental Complexity

Continuously ask:

* Can this be simpler algebraically?
* Is this type pulling its weight?
* Is this abstraction justified?

---

# Anti-Patterns to Avoid

* Mutable global registries
* Boolean flag explosions
* Stringly-typed errors
* Hidden side effects in helpers
* Deep functor stacks without need
* Premature micro-optimization
* Overusing objects when variants suffice

---

# Performance + Elegance Balance

The elite bar is not:
"Write the fastest code possible."

It is:

> Write the simplest algebraic code that is predictably fast, then optimize surgically with evidence.

Elegance and performance are not enemies in OCaml when designed correctly.

---

# Final Standard

An elite OCaml implementation should feel like:

* Algebraically inevitable
* Deterministic in behavior
* Easy to reason about locally
* Globally composable
* Fast enough by design, fast where it matters

It should give the **confidence of Rust** with the **clarity of functional algebra**.

That is the bar.
