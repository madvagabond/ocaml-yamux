open Lwt.Infix
open Util



let src = Logs.Src.create "muxer" ~doc:"Yamux Multiplexer"
module Log = (val Logs.src_log src : Logs.LOG)









module type S = sig
  type t
  type flow

  module Flow: S.FLOW_EXT

  

  type write_result = (unit, Flow.write_error) result Lwt.t
  
  val create: flow -> Util.Config.t -> t
  val send: t -> Packet.t -> (unit, Flow.write_error) result Lwt.t
      
  val flow: t -> Flow.flow

  val on_window_update: t -> Packet.t -> write_result
  val on_data: t -> Packet.t -> write_result
  val on_ping: t -> Packet.t -> write_result


  val process: t -> Packet.t -> write_result

  
end 





module Make (F: Mirage_flow_lwt.S): S = struct

  open Stream
  open Packet
  open Header


  type flow = F.flow

  
  module Flow = Flow_ext(F)

  type write_result = (unit, Flow.write_error) result Lwt.t
  
  type t = {

    mutable local_closed: bool;
    mutable remote_closed: bool; 
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
      local_closed=false; remote_closed=false;
      flow; config 
    }

  

  let flow t = t.flow


  


  
    
  let send t frame = 
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
      send t packet






  

  let valid_remote t sid =
    let id = Int32.to_int sid in 
    if (Config.is_server t.config) then
      ID.is_client id
    else
      ID.is_server id

  




  

  let process_flags t frame f =
    

    let open Packet in
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


    else if Header.is_syn header && t.local_closed then
     
      let rst = WindowUpdate.make id 0l in
      let header = Header.rst (rst.header) in
      send t {rst with header}

  
    else if
      Header.is_syn header && ( Hashtbl.mem t.streams id )
    then
      
      let _ =
        Log.debug (fun fmt ->
            fmt "Protocol Error, stream %ld already exists" id
          )
      in
      t.local_closed <- true; 

      send t (Packet.GoAway.protocol_error)

    else if
      Header.is_syn header && (Hashtbl.length t.streams >= (Config.max_streams t.config) )
    then
      
      let max = Config.max_streams t.config in
      let _ = Log.debug ( fun fmt ->
          fmt "Protocol Error: maximum number of streams %d reached" max
        ) in


      t.local_closed <- true;
      send t (Packet.GoAway.protocol_error)



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
    send t packet





  

  let on_data t packet =
    let open Entry in 

    let aux t frame =
      let id = Packet.id packet in
      let len = Packet.header packet |> Header.len |> Int32.to_int in
      
      match Hashtbl.find_opt t.streams id with

      | Some stream when len > stream.window ->
        let _ = Log.debug (fun fmt -> fmt "data frame exceeded window size") in
        t.local_closed <- true; 
        send t Packet.GoAway.protocol_error

      | Some stream when (Bstruct.writer_index stream.buf) >= t.config.max_buffer_size ->
        let _ = Log.debug (fun fmt -> fmt "Cannot receive data frame" ) in
        reset t id

      | Some stream ->
        stream.window <- stream.window - len;
        Lwt_mutex.lock stream.lock >|= fun () ->
        Bstruct.write_bytes stream.buf frame.body;
        Ok ()

      | None ->
       Ok () |> Lwt.return

    in

    process_flags t packet aux 



  


  
  let on_goaway t frame =
    let open Packet in
    
    let code = Packet.GoAway.code frame in
    t.remote_closed <- true;

    let _ = match code with
    | 0x0l ->
      Log.debug (fun fmt -> fmt "Received normal go away")

    | 0x1l ->
      Log.debug (fun fmt -> fmt "Received protocol error go away ")

    | 0x2l ->
      Log.debug (fun fmt -> fmt "Recieved internal error go away")

    | x ->
      Log.debug (fun fmt -> fmt "Received go away with error code %ld" x)

    in
    Lwt.return (Ok ())


  

  
  let process t frame =
    match (Packet.msg_type frame) with
    | Data -> on_data t frame
    | Window_Update -> on_window_update t frame
    | Ping -> on_ping t frame
    | Go_Away -> on_goaway t frame
                   

  
  
end 




