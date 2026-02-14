(* execute.ml — Backend execution.
   Runs the selected linker backend, captures output. *)

open Types

let src = Logs.Src.create "jello.execute" ~doc:"Backend executor"

module Log = (val Logs.src_log src : Logs.LOG)

(* Build the command from a plan *)
let build_cmd plan =
  let cmd = Bos.Cmd.v plan.backend_path in
  List.fold_left (fun c a -> Bos.Cmd.(c % a)) cmd plan.backend_args

(* Run the backend and capture everything *)
let run plan =
  let cmd = build_cmd plan in
  Log.info (fun m ->
      m "Executing: %s %s" plan.backend_path
        (String.concat " " plan.backend_args));
  let open Bos in
  (* Run and capture stdout, stderr, and exit code *)
  match
    OS.Cmd.(
      run_out ~err:err_run_out cmd |> out_string)
  with
  | Ok (combined, (_, `Exited code)) ->
      (* Split combined output — stderr goes to combined when using err_run_out *)
      let result =
        {
          plan;
          exit_code = code;
          stdout = "";
          stderr = combined;
          post_diagnostics = [];
        }
      in
      if code = 0 then
        Log.info (fun m -> m "Link succeeded: %s" plan.output)
      else
        Log.err (fun m -> m "Link failed with exit code %d" code);
      Ok result
  | Ok (combined, (_, `Signaled sig_num)) ->
      let result =
        {
          plan;
          exit_code = 128 + sig_num;
          stdout = "";
          stderr = combined;
          post_diagnostics = [];
        }
      in
      Log.err (fun m -> m "Linker killed by signal %d" sig_num);
      Ok result
  | Error (`Msg msg) ->
      Error (Exec_error { exit_code = 1; stderr = msg })

(* Dry-run: just return what would be executed *)
let dry_run plan =
  let cmd = build_cmd plan in
  Bos.Cmd.to_string cmd

(* Run an arbitrary command, capturing exit code + combined output.
   Used for compile passthrough where we don't have a link_plan. *)
let run_cmd cmd =
  Log.info (fun m -> m "Executing: %s" (Bos.Cmd.to_string cmd));
  let open Bos in
  match OS.Cmd.(run_out ~err:err_run_out cmd |> out_string) with
  | Ok (combined, (_, `Exited code)) -> Ok (code, "", combined)
  | Ok (combined, (_, `Signaled sig_num)) -> Ok (128 + sig_num, "", combined)
  | Error (`Msg msg) -> Error (`Msg msg)
