(* test.ml — Core tests for jello. *)

open Jello

(* --- Parse tests --- *)

let test_parse_basic () =
  let args = [ "foo.o"; "-o"; "out"; "-lfoo"; "-L/usr/lib" ] in
  match Parse.args args with
  | Ok inv ->
      Alcotest.(check int) "one input" 1 (List.length inv.inputs);
      Alcotest.(check (option string)) "output" (Some "out") inv.output;
      Alcotest.(check int) "search paths" 1
        (List.length inv.search_paths)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_parse_wl () =
  let args = [ "foo.o"; "-Wl,--as-needed,-rpath,/opt/lib" ] in
  match Parse.args args with
  | Ok inv ->
      let has_as_needed =
        List.exists
          (fun f -> f = Types.As_needed)
          inv.flags
      in
      Alcotest.(check bool) "has as-needed" true has_as_needed
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_parse_link_mode () =
  let args = [ "-shared"; "foo.o" ] in
  match Parse.args args with
  | Ok inv ->
      Alcotest.(check string) "shared mode" "shared"
        (Types.link_mode_to_string inv.link_mode)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_parse_static () =
  let args = [ "-static"; "foo.o"; "-lfoo" ] in
  match Parse.args args with
  | Ok inv ->
      Alcotest.(check string) "static mode" "static"
        (Types.link_mode_to_string inv.link_mode)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

(* --- Triple tests --- *)

let test_triple_parse () =
  match Triple.parse "x86_64-unknown-linux-gnu" with
  | Ok t ->
      Alcotest.(check string) "arch" "x86_64"
        (Types.arch_to_string t.arch);
      Alcotest.(check string) "os" "linux"
        (Types.os_to_string t.os)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_triple_parse_short () =
  match Triple.parse "aarch64-linux-gnu" with
  | Ok t ->
      Alcotest.(check string) "arch" "aarch64"
        (Types.arch_to_string t.arch);
      Alcotest.(check string) "os" "linux"
        (Types.os_to_string t.os)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_triple_parse_darwin () =
  match Triple.parse "aarch64-apple-darwin" with
  | Ok t ->
      Alcotest.(check string) "arch" "aarch64"
        (Types.arch_to_string t.arch);
      Alcotest.(check string) "os" "darwin"
        (Types.os_to_string t.os);
      Alcotest.(check (option string)) "vendor" (Some "apple")
        t.vendor
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

(* --- Normalize tests --- *)

let test_normalize_default_output () =
  let inv =
    {
      Types.empty_invocation with
      flags = [];
      inputs = [ Types.Object "foo.o" ];
    }
  in
  match Normalize.invocation inv with
  | Ok inv ->
      Alcotest.(check (option string)) "default output" (Some "a.out")
        inv.output
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

(* --- Type tests --- *)

let test_arch_roundtrip () =
  let arches =
    [
      Types.X86_64; I686; Aarch64; Armv7; Riscv64; Riscv32; Mips;
      Powerpc64; S390x; Wasm32;
    ]
  in
  List.iter
    (fun a ->
      let s = Types.arch_to_string a in
      match Types.arch_of_string s with
      | Some a' ->
          Alcotest.(check string) "roundtrip" s (Types.arch_to_string a')
      | None ->
          Alcotest.fail (Printf.sprintf "failed to parse arch: %s" s))
    arches

let test_triple_to_string () =
  let t =
    {
      Types.arch = X86_64;
      vendor = Some "unknown";
      os = Linux;
      env = Some Gnu;
    }
  in
  Alcotest.(check string) "triple string" "x86_64-unknown-linux-gnu"
    (Types.triple_to_string t)

(* --- Test suite --- *)

let () =
  Alcotest.run "jello"
    [
      ( "parse",
        [
          Alcotest.test_case "basic" `Quick test_parse_basic;
          Alcotest.test_case "wl-forwarding" `Quick test_parse_wl;
          Alcotest.test_case "link-mode-shared" `Quick test_parse_link_mode;
          Alcotest.test_case "link-mode-static" `Quick test_parse_static;
        ] );
      ( "triple",
        [
          Alcotest.test_case "parse-full" `Quick test_triple_parse;
          Alcotest.test_case "parse-short" `Quick test_triple_parse_short;
          Alcotest.test_case "parse-darwin" `Quick test_triple_parse_darwin;
        ] );
      ( "normalize",
        [
          Alcotest.test_case "default-output" `Quick
            test_normalize_default_output;
        ] );
      ( "types",
        [
          Alcotest.test_case "arch-roundtrip" `Quick test_arch_roundtrip;
          Alcotest.test_case "triple-to-string" `Quick
            test_triple_to_string;
        ] );
    ]
