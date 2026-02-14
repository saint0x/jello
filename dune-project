(lang dune 3.17)

(name jello)

(generate_opam_files true)

(license ISC)

(package
 (name jello)
 (synopsis "An intelligent linker driver")
 (description
  "A linker driver that normalizes invocations, resolves dependencies, reorders libraries, selects backends, and produces actionable diagnostics.")
 (depends
  (ocaml (>= 5.1))
  (cmdliner (>= 1.3.0))
  (yojson (>= 2.1))
  (bos (>= 0.2))
  (fpath (>= 0.7))
  (logs (>= 0.7))
  (fmt (>= 0.9))
  (re (>= 1.11))
  (alcotest :with-test)))
