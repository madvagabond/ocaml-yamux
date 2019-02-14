open Lwt.Infix
open Util


let src = Logs.Src.create "streams" ~doc:"Yamux Streams"
module Log = (val Logs.src_log src : Logs.LOG)

module Make (F: Mirage_flow_lwt.S) = struct


  
  module Mux = Muxer.Make(F)

  type buffer = F.buffer

  type error = F.error

  type 'a io = 'a F.io


  type write_error = F.write_error

  let (pp_error, pp_write_error) = F.pp_error, F.pp_write_error

  
      
  open Stream_entry
  open Mux
      

  type flow = {
    id: int32;
    mux: Mux.t;
    entry: Stream_entry.t
  }

  type 'a or_eof = [
    | `Data of 'a
    | `Eof
  ]


  let (pp_error, pp_write_error) = F.pp_error, F.pp_write_error
  


  let read_op t f =
    match t.entry.state with
    | Open when flow.entry.window = 0 ->

      let win = flow.mux.config.recv_window in
      flow.entry.window  <- win;  

      let frame = Packet.window_update flow.id (Int32.of_int win) in
      Mux.send flow.mux frame >>= fun _ ->

      f t.entry.buf >|= fun data ->
      Ok (`Data data)


    | _ ->
      f t.entry.buf

   



  
      
  let read_bytes t n =
    AsyncBuf.get_bytes t n >|= fun buf ->
    Ok (`Data buf)



  let close flow =

    let update = Packet.window_update flow.id 0l in
    let _ = update_state flow.entry RecvClosed in
    let _ = PromiseMap.delete flow.mux.streams flow.id in 
    Mux.send flow.mux {update with header = (Packet.header update |> Header.ack) } >>= function


    | Ok () -> Lwt.return_unit
    | _ -> Lwt.return_unit 





  
  let rec write flow buf =
   
    let len = Cstruct.len buf in

  
    match flow.entry.state with
    | Open when flow.entry.credit > len ->
      Mux.send flow.mux (Packet.data flow.id buf)

    | Open when flow.entry.credit > 0 ->
      let body = Cstruct.sub buf 0 flow.entry.credit in
      let remainder = Cstruct.sub buf flow.entry.credit len in

      let packet = Packet.data flow.id body in  
      Mux.send flow.mux packet >>= fun res ->

      begin
        match res with
        | Ok () -> write flow remainder
        | Error e -> Error `Closed |> Lwt.return
      end


    | Open ->
      write flow buf
      



    | _ -> Error `Closed |> Lwt.return

  



  let writev flow structs =
    let buf = Cstruct.concat structs in
    write flow buf
    
end
