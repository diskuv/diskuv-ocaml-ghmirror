open Configurator.V1
open Flags

type platformtype =
  | Android_arm64v8a
  | Android_arm32v7a
  | Android_x86
  | Android_x86_64
  | Darwin_arm64
  | Darwin_x86_64
  | Linux_arm64
  | Linux_arm32v6
  | Linux_arm32v7
  | Linux_x86_64
  | Windows_x86_64
  | Windows_x86

type osinfo = {
  ostypename : (string, string) Result.t;
  platformtypename : (string, string) Result.t;
  platformname : (string, string) Result.t;
}

let get_osinfo t =
  let header =
    let file = Filename.temp_file "discover" "os.h" in
    let fd = open_out file in
    output_string fd Dkml_compiler_probe_c_header.contents;
    close_out fd;
    file
  in
  let os_define =
    C_define.import t ~includes:[ header ] [ ("DKML_OS_NAME", String) ]
  in
  let platform_define =
    C_define.import t ~includes:[ header ] [ ("DKML_ABI", String) ]
  in

  let ostypename =
    match os_define with
    | [ (_, String ("Android" as x)) ] -> Result.ok x
    | [ (_, String ("IOS" as x)) ] -> Result.ok x
    | [ (_, String ("Linux" as x)) ] -> Result.ok x
    | [ (_, String ("OSX" as x)) ] -> Result.ok x
    | [ (_, String ("Windows" as x)) ] -> Result.ok x
    | _ ->
      failwith ("Unknown operating system: no detection found in " ^ Dkml_compiler_probe_c_header.filename)
  in

  let platformtypename, platformname =
    match platform_define with
    | [ (_, String ("android_arm64v8a" as x)) ] -> (Result.ok "Android_arm64v8a", Result.ok x)
    | [ (_, String ("android_arm32v7a" as x)) ] -> (Result.ok "Android_arm32v7a", Result.ok x)
    | [ (_, String ("android_x86" as x)) ] -> (Result.ok "Android_x86", Result.ok x)
    | [ (_, String ("android_x86_64" as x)) ] -> (Result.ok "Android_x86_64", Result.ok x)
    | [ (_, String ("darwin_arm64" as x)) ] -> (Result.ok "Darwin_arm64", Result.ok x)
    | [ (_, String ("darwin_x86_64" as x)) ] -> (Result.ok "Darwin_x86_64", Result.ok x)
    | [ (_, String ("linux_arm64" as x)) ] -> (Result.ok "Linux_arm64", Result.ok x)
    | [ (_, String ("linux_arm32v6" as x)) ] -> (Result.ok "Linux_arm32v6", Result.ok x)
    | [ (_, String ("linux_arm32v7" as x)) ] -> (Result.ok "Linux_arm32v7", Result.ok x)
    | [ (_, String ("linux_x86_64" as x)) ] -> (Result.ok "Linux_x86_64", Result.ok x)
    | [ (_, String ("windows_x86_64" as x)) ] -> (Result.ok "Windows_x86_64", Result.ok x)
    | [ (_, String ("windows_x86" as x)) ] -> (Result.ok "Windows_x86", Result.ok x)
    | [ (_, String ("windows_arm64" as x)) ] -> (Result.ok "Windows_arm64", Result.ok x)
    | [ (_, String ("windows_arm32" as x)) ] -> (Result.ok "Windows_arm32", Result.ok x)
    | _ ->
      failwith ("Unknown platform: no detection found in " ^ Dkml_compiler_probe_c_header.filename)
  in

  { ostypename; platformtypename; platformname }

let () =
  main ~name:"discover" (fun t ->
      let { ostypename; platformtypename; platformname } = get_osinfo t in
      let result_to_string = function
        | Result.Ok v -> "Result.ok (" ^ v ^ ")"
        | Result.Error e -> "Result.error (`Msg \"" ^ (String.escaped e) ^ "\")"
      in
      let quote_string s = "\"" ^ s ^ "\"" in
      let to_lazy s = "lazy (" ^ s ^ ")" in

      write_lines "target_context.ml"
        [
          (* As you expand the list of platforms and OSes make new versions! Make sure the new platforms and OS give back Result.error in older versions. *)
          {|module V1 = struct|};
          {|  type ostype = Android | IOS | Linux | OSX | Windows|};
          {|  type platformtype =
              | Android_arm64v8a
              | Android_arm32v7a
              | Android_x86
              | Android_x86_64
              | Darwin_arm64
              | Darwin_x86_64
              | Linux_arm64
              | Linux_arm32v6
              | Linux_arm32v7
              | Linux_x86_64
              | Windows_x86_64
              | Windows_x86
              | Windows_arm64
              | Windows_arm32
          |};
          {|  let get_os = |} ^ (result_to_string ostypename |> to_lazy);
          {|  let get_platform = |} ^ (result_to_string platformtypename |> to_lazy);
          {|  let get_platform_name = |} ^ (Result.map quote_string platformname |> result_to_string |> to_lazy);
          {|end (* module V1 *) |};
        ])
