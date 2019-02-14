
open Alcotest

open Test_net
open Lwt.Infix
open Yamux

module AsyncBuf = Yamux.Util.AsyncBuf
module Session = Yamux.Session.Make(Net)(Time)
module Stream = Session.Stream

module Flow = Util.Flow_ext(Transport)

let src = Logs.Src.create "yamux testing" ~doc:"Yamux Tests"
module Log = (val Logs.src_log src : Logs.LOG)
             
let net = Net.create ()



let server addr =
  let callback stream =

    print_endline "running server callback";
    Stream.read stream >>= function
    | Ok `Eof ->
      print_endline "closed";
      Stream.close stream

    | Ok (`Data buf) ->
      Log.info (fun fmt -> fmt "%s\n" (Cstruct.to_string buf) );
      Stream.write stream buf >|= fun _ ->
      ()
      
    | Error e ->  Stream.close stream

  in
   
  Net.listen net addr (fun flow ->
      let server = Session.server flow in
      Session.listen server callback
  )






let conn () =
  Net.connect net "peer1" >|= fun conn ->
  Session.client conn







let smoke_test s () =
  let _ =  Lwt.async (fun () -> server "peer1") in
  conn () >>= fun conn -> 
  Session.create_stream conn >>= fun stream ->
  let _ = Log.info (fun fmt -> fmt "stream created" ) in

  let buf = Cstruct.of_string "hello" in 
  Stream.write stream buf >>= fun _ ->

  let _ = Log.info (fun fmt -> fmt "message sent" ) in
  
  Stream.read stream >|= function
  | Ok (`Data body) ->
    let exp = "hello" in
    let got = Cstruct.to_string body in

    check string "echo works" exp got

  | _ ->
    raise (Failure "connection error: smoke test failed")
    
  


let gen_string length () =
  let gen() =
    match Random.int(26+26+10) with
      n when n < 26 -> int_of_char 'a' + n
    | n when n < 26 + 26 -> int_of_char 'A' + n - 26
    | n -> int_of_char '0' + n - 26 - 26 in
  let gen _ = String.make 1 (char_of_int(gen())) in

  let g () = String.concat "" (Array.to_list (Array.init length gen)) in

  g ()

    


let gen_cstruct size () =
  gen_string size () |> Cstruct.of_string 




let buf_test s () =
  let buf = Util.AsyncBuf.create 4096 in
  let r = AsyncBuf.get buf 1024 in
  print_endline "got pushed";

  let bytes = gen_cstruct 1024 () in 
  let _ = AsyncBuf.put buf bytes in

  r >|= fun got_b ->
  let exp = Cstruct.to_string bytes in
  let got = Cstruct.to_string got_b in
  check string "Contents are equal" exp got




let gen_chunks size n () =
  let csize = size /. n |> ceil |> int_of_float in
  
  
  let rec aux bufs =
    if Cstruct.lenv bufs < (size |> int_of_float) then
      let b = gen_cstruct csize () in
      bufs @ [b] |> aux

    else
      bufs
  in

  aux []
  
      

let test_flow_ext s () =
  
  let (cli, srv) =
    let (c, s) = Transport.pipe "client" "server" in
    Flow.create c, Flow.create s

  in

  let x = Flow.read_bytes srv 4096 in

  
  let bufs = gen_chunks 4096.0 10.0 () in
  Log.info (fun fmt -> fmt "%d chunks" (List.length bufs) );
  
  Lwt_list.iter_s ( fun x -> Flow.write cli x >|= fun _ -> ()) bufs >>= fun _ ->
  x >|= function
  | Ok (`Data _) -> ()

  | _ -> raise (Failure "flow_ext failed")
  
  
  

let suite = [
  Alcotest_lwt.test_case "testing async buffer" `Quick buf_test;
  Alcotest_lwt.test_case "testing flow_ext" `Quick test_flow_ext;
  (* Alcotest_lwt.test_case "smoke test" `Quick smoke_test; *)
]



let _ =
  Logs.set_level (Some Logs.Info);
  Logs.set_reporter (Logs_fmt.reporter ());
  Alcotest.run "Testing Yamux" [
    "yamux suite", suite
  ]
  
