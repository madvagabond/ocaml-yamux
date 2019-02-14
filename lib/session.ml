open Lwt.Infix
open Util

open Stream_entry
open Packet


let src = Logs.Src.create "sessions" ~doc:"Yamux Session Management"
module Log = (val Logs.src_log src : Logs.LOG)



module type S = sig
  
  type t

  type conn
  
  module Stream: S.FLOW_EXT

 

  val ping: t -> unit Lwt.t 

  val create_stream: t -> Stream.flow Lwt.t 
  val listen: t -> (Stream.flow -> unit Lwt.t) -> unit Lwt.t

  val close: t -> unit Lwt.t

  
  val server: ?config: Config.t -> conn -> t
  val client: ?config: Config.t -> conn -> t
  
end 





module Make (F: Mirage_flow_lwt.S) (T: Mirage_time_lwt.S) = struct


  module Mux = Muxer.Make(F)
  module Stream = Stream.Make(F) 

  open Mux

  type t = Mux.t
  

  let ping t =
    let _ = t.ping_id <- Int32.add t.ping_id 1l in
    let (p, r) = Lwt.wait () in
    let id = t.ping_id in
    
    let _ = Hashtbl.add t.pending_pings id r in

    Mux.send t (Packet.ping id) >>= fun res ->
    match res with

    | Ok () -> p >|= fun () -> Ok () 

    | Error `Closed ->
      let _ = Lwt.cancel p in
      Lwt.fail (Failure "connection is closed")



  let create_stream t =

    let open Stream in
    
    let id = Mux.next_id t in

    let buf = AsyncBuf.create () in
    let window = Config.window t.config in
    let credit = window in

    let state = Open in
    let entry = {buf; window; credit; state} in

    let stream = {id; mux=t; entry} in

    
    let msg =
      Packet.window_update id (Int32.of_int window) |>
      (fun packet -> {packet with header = Header.syn packet.header} )
    in
    
    Mux.send t msg >>= function
    | Ok () ->  Lwt.return stream
    | Error `Closed -> Lwt.fail (Failure "connection is closed")


    

  
  let close ?timeout t =

    let shutdown () =
      Mux.Flow.close t.flow
    in

  
    match timeout with 
    | Some tout ->

      let dur = tout * 1000 |> Int64.of_int in
      let packet = Packet.GoAway.normal in
      Mux.send t packet >>= fun packet ->

      let forced =
        T.sleep_ns dur >>= fun x ->
        shutdown ()

      in


      let (c, _) = t.close in
      let drained = c  >>= fun () -> shutdown () in
      Lwt.pick [forced; drained]


    | _ ->
      let (c, _) = t.close in
      c >>= fun () -> shutdown ()
  

 

  

  

  let server ?(config=Config.server ()) conn =
    let open Config in 
    let conf = {config with is_client = false} in
    Mux.create conn conf


  
  let client ?(config=Config.client ()) conn =
    let conf = {config with is_client = true} in
    let t = Mux.create conn conf in
    
    let rec loop () =
      Log.info (fun fmt -> fmt "client loop running"); 
      let (p, _) = t.close in 
      Mux.read t >>= function
        
      | Ok (`Data msg) when Lwt.is_sleeping p ->
        process t msg >>= fun _ ->
        loop () 

      | Ok (`Data msg) ->
        process t msg >>= fun _ ->
        Mux.Flow.close t.flow

  
      | Error e ->
        Mux.Flow.close t.flow

      | Ok `Eof -> Mux.Flow.close t.flow

    in

    let _ = loop () in
    t





  let listen t cb =
    let open Header in
    let (p, _) = t.close in


    let accept id res =
      let open Stream in 
      res >|= function 

      | Ok None ->
        
        let entry = Hashtbl.find t.streams id in
        let _ = cb {entry; id; mux = t} in
        Ok ()
  
      | Ok (Some packet) -> Ok ()

      | Error e -> Error e 
    in

    
    
    
    let handler packet =
      match (Packet.msg_type packet) with
      | Data when Header.is_syn packet.header ->
        let id = Packet.id packet in
        accept id (Mux.process t packet)
          
      | Window_Update when Header.is_syn packet.header ->
        let id = Packet.id packet in
        accept id (Mux.process t packet)

      | _ ->
        process t packet >|= fun _ -> Ok ()
    in



    let rec aux () =
      let _ = Log.info (fun fmt -> fmt "listening") in
      Mux.read t >>= function 


      | Ok (`Data pkt) ->

        begin 
          handler pkt >>= function 
          | Error e ->
            Mux.Flow.close t.flow
          | Ok () -> aux () 
        end

      | Ok `Eof ->
        Mux.Flow.close t.flow


      | Error e ->
        Mux.Flow.close t.flow


    in


    aux ()


  



end

