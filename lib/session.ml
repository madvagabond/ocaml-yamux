open Lwt.Infix
open Util

open Stream_entry
open Packet

module type S = sig
  
  type t

  type conn
  
  module Stream: S.FLOW_EXT 

  val ping: t -> unit Lwt.t 

  val create_stream: t -> Stream.flow Lwt.t 
  val listen: t -> (Stream.flow -> unit Lwt.t) -> unit Lwt.t

  val close: t -> (Stream.flow -> unit Lwt.t) -> unit Lwt.t

  
  val server: ?max_streams: int -> ?max_buffer: int -> ?window_size: int  -> unit -> t
  val client: ?max_streams: int -> ?max_buffer: int -> ?window_size: int -> unit -> t
  
end 





module Make (F: Mirage_flow_lwt.S) = struct
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

    let buf = Bstruct.create 1024 in
    let lock = Lwt_mutex.create () in
    let window = Config.window t.config in
    let credit = window in

    let state = Open in
    let entry = {buf; lock; window; credit; state} in


    let msg =
      Packet.window_update id (Int32.of_int window) |>
      (fun packet -> {packet with header = Header.ack packet.header} )
    in

    let stream = {id=id; mux=t; entry} in
    

    Mux.send t msg >>= function
    | Ok () ->  Lwt.return stream
    | Error `Closed -> Lwt.fail (Failure "connection is closed")







  


  

  
end

