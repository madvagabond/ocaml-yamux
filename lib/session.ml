open Lwt.Infix
open Util



let src = Logs.Src.create "muxer" ~doc:"Yamux Multiplexer"
module Log = (val Logs.src_log src : Logs.LOG)





module ID = struct
  let is_server id =
    (id mod 2) = 0

  let is_client id =
    is_server id <> true

  let is_session id =
    id = 0l
end 



module Muxer (F: Mirage_flow_lwt.S) = struct

  open Stream
  open Packet
  open Header



  module Flow = Flow_ext(F)
 

  
  type t = {

    lock: Lwt_mutex.t;
    flow: Flow.flow; 
    streams: (int32, Stream.Entry.t) Hashtbl.t;
  
    next_id: int32;
    config: Config.t;
    
    pending_streams: (int32, Stream.Entry.t Lwt.u) Hashtbl.t;
    pending_pings: (int32, unit Lwt.u) Hashtbl.t;
  }

  


  let create conn config =
    let open Config in
    

    let flow = Flow.create conn in  
    let streams = Hashtbl.create config.max_streams in

    let pending_pings = Hashtbl.create 1000 in
    let pending_streams = Hashtbl.create config.max_streams in
    let lock = Lwt_mutex.create () in
    let next_id = 1l in 


    {
      streams; pending_streams;
      pending_pings; lock; next_id;
      flow; config 
    }

  
    
    
  let send_packet t frame = 
    let buf = Packet.encode frame in
    Lwt_mutex.lock t.lock >>= fun () ->
    Flow.write t.flow buf >|= fun res ->

    Lwt_mutex.unlock t.lock;
    res




  let on_ping t frame =
    let open Header in 
    let header  = Packet.header frame in

    if Header.is_ack header then
      let nonce = header.len in 
      let pings = t.pending_pings in
      PromiseMap.wake_up pings nonce ();
      Ok () |> Lwt.return 


    else
      let packet = {frame with header = Header.ack header} in
      send_packet t packet




  let valid_remote t sid =
    let id = Int32.to_int sid in 
    if (Config.is_server t.config) then
      ID.is_client id
    else
      ID.is_server id

  



  let process_flags t frame f =
    

    let open Entry in
    let open Option.Infix in

    let id = Packet.id frame in
    let header = Packet.header frame in

    if Header.is_rst header then
      
      let _ =
        Hashtbl.find_opt t.streams id >>> fun entry ->
        let _ = Entry.update_state entry Closed in 
        PromiseMap.delete t.streams id
      in

      Lwt.return ( Ok () )

    else if Header.is_fin header then
      
      let _ =
        Hashtbl.find_opt t.streams id >>> fun entry ->
        Entry.update_state entry RecvClosed;
      in

      Lwt.return ( Ok () )

    else if
      Header.is_syn header && ( Hashtbl.mem t.streams id )
    then
      
      let _ =
        Log.debug (fun fmt ->
            fmt "Protocol Error, stream %ld already exists" id
          )
      in


      send_packet t (Packet.GoAway.protocol_error)

    else if
      Header.is_syn header && (Hashtbl.length t.streams >= (Config.max_streams t.config) )
    then
      
      let max = Config.max_streams t.config in
      let _ = Log.debug ( fun fmt ->
          fmt "Protocol Error: maximum number of streams %d reached" max
        ) in
      send_packet t (Packet.GoAway.protocol_error)



    else
      f t frame

  

  let on_window_update t frame =


    let handle t frame =
      let id = Packet.id frame in
      let credit = Packet.WindowUpdate.credit frame in
      let s = Hashtbl.find t.streams id in
      s.credit <- Int32.add s.credit credit;
      Ok () |> Lwt.return

    in process_flags t frame handle
      


  let reset t id =
    let packet = Packet.data id Cstruct.empty in
    send_packet t packet



  let on_data t packet =
    let open Entry in 

    let aux t frame =
      let id = Packet.id packet in
      let len = Packet.header packet |> Header.len |> Int32.to_int in
      
      match Hashtbl.find_opt t.streams id with

      | Some stream when len > stream.window ->
        let _ = Log.debug (fun fmt -> fmt "data frame exceeded window size") in
        send_packet t Packet.GoAway.protocol_error

      | Some stream when (Bstruct.writer_index stream.buf) >= t.config.max_buffer_size ->
        let _ = Log.debug (fun fmt -> fmt "Cannot receive data frame" ) in
        reset t id

      | Some stream ->
        stream.window <- stream.window - len;
        Lwt_mutex.lock stream.lock >|= fun () ->
        Bstruct.write_bytes stream.buf frame.body;
        Ok ()

      | None ->
        let _ = Log.debug (fun fmt -> fmt "No such stream") in
        send_packet t Packet.GoAway.protocol_error

    in

    process_flags t packet  aux 


  
end 




