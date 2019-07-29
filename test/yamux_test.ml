

open Alcotest
open Lwt.Infix

module Session = Yamux.Session.Make(Mirage_flow_unix.Fd)

module Stream = Yamux.Stream
module Config = Yamux.Config
                  




let (tx, rx) =
  let (x, y) = Lwt_unix.(socketpair PF_UNIX SOCK_STREAM) 0 in
  Session.make x (Config.client ()), Session.make y (Config.server ())




let handle_echo () =
  Session.accept rx >>= fun stream ->
  Yamux.Stream.read stream >>= fun buf ->
  let _ = print_string "stream accepted" in
  Stream.write stream buf



let test_echo _s () =
  Session.open_stream tx >>= fun stream ->
  Stream.write stream (Cstruct.of_string "echo") >>= fun _ ->
  handle_echo () >>= fun _ ->
  Stream.read stream >|= fun buf ->

  let got = Cstruct.to_string buf in
  let exp = "echo" in
  Alcotest.(check string) "checking echo" got exp



  




let test_ping _s () =
  Session.ping tx >>= fun () ->
  Lwt.return_unit 




let _ = 


  let suite = [
    Alcotest_lwt.test_case "test_echo" `Quick test_echo;
    Alcotest_lwt.test_case "test ping" `Quick test_ping;
  ]

  in





  Logs.set_level (Some Logs.Debug);
  Logs.set_reporter (Logs_fmt.reporter ());

  Alcotest.run "Testing Yamux" [
    "yamux suite", suite
  ]
