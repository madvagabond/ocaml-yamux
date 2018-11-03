open Lwt.Infix
open Util


module Make (F: Mirage_flow_lwt.S) = struct


  
  module Mux = Muxer.Make(F)

  type buffer = F.buffer

  type error = F.error

  type 'a io = 'a F.io


  type write_error = F.write_error

  let (pp_error, pp_write_error) = F.pp_error, F.pp_write_error

  
      
  open Stream_entry
  open Mux
      

  type flow = {id: int32; mux: Mux.t; entry: Stream_entry.t}

  type 'a or_eof = [
    | `Data of 'a
    | `Eof
  ]


  let (pp_error, pp_write_error) = F.pp_error, F.pp_write_error
  



  
  let rec read_bytes flow n =
    let len = Bstruct.readable flow.entry.buf in
    
    
    match flow.entry.state with


    | Open when flow.entry.window = 0 ->
      let win = flow.mux.config.recv_window in
      flow.entry.window  <- win;  
      let frame = Packet.window_update flow.id (Int32.of_int win) in
      Mux.send flow.mux frame >>= fun _ -> read_bytes flow n

    | Open ->
      read_bytes flow n

    
    | _ when len >= n -> 
      Lwt_mutex.lock flow.entry.lock >>= fun () ->  
      let bytes = Bstruct.read_bytes flow.entry.buf n in
      let _ = Lwt_mutex.unlock flow.entry.lock in
      
      Ok (`Data bytes) |> Lwt.return


    | _ ->
      Ok `Eof |> Lwt.return



    

  

  let read flow =
    read_bytes flow 1024



  

  let rec write flow buf =
   
    let len = Cstruct.len buf in

  
    match flow.entry.state with
    | Open when len < flow.entry.credit ->
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

  
  




  let close flow =
  
    let update = Packet.window_update flow.id 0l in
    let _ = update_state flow.entry RecvClosed in
    let _ = PromiseMap.delete flow.mux.streams flow.id in 
    Mux.send flow.mux {update with header = (Packet.header update |> Header.ack) } >>= function


    | Ok () -> Lwt.return_unit
    | _ -> Lwt.return_unit 


  


  let writev flow structs =
    let buf = Cstruct.concat structs in
    write flow buf
    
end
