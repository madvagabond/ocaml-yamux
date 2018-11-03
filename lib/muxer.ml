open Lwt.Infix
open Util



let src = Logs.Src.create "muxer" ~doc:"Yamux Multiplexer"
module Log = (val Logs.src_log src : Logs.LOG)









module type S = sig
  type t
  type flow

  module Flow: S.FLOW_EXT

  type res = (Packet.t option, Flow.write_error) result

  type write_result =  (unit, Flow.write_error) result

 
  
  val create: flow -> Util.Config.t -> t
  val send: t -> Packet.t -> write_result Lwt.t
      
  val flow: t -> Flow.flow

  val on_window_update: t -> Packet.t -> res Lwt.t
  val on_data: t -> Packet.t -> res Lwt.t
  val on_ping: t -> Packet.t -> write_result Lwt.t


  val process: t -> Packet.t -> res Lwt.t

  (*val next_id: t -> int32*)
  

  
end 














module Make (F: Mirage_flow_lwt.S) = struct

  open Packet
  open Header
  open Stream_entry
      


  type flow = F.flow

  
  module Flow = Flow_ext(F)

  type error = [`Msg of string | `Eof ]
  type res =  (Packet.t option, Flow.write_error) result
  type write_result = (unit, Flow.write_error) result Lwt.t
  
  type t = {

    mutable local_closed: bool;
    mutable remote_closed: bool; 
    lock: Lwt_mutex.t;
    flow: Flow.flow; 
    streams: (int32, Stream_entry.t) Hashtbl.t;
  
    mutable next_id: int32;
    config: Config.t;
    
    pending_streams: (int32, Stream_entry.t Lwt.u) Hashtbl.t;
    pending_pings: (int32, unit Lwt.u) Hashtbl.t;

    close: unit Lwt.t * unit Lwt.u; 
    mutable ping_id: int32
  }


  let create conn config =
    let open Config in
    

    let flow = Flow.create conn in  
    let streams = Hashtbl.create config.max_streams in

    let pending_pings = Hashtbl.create 1000 in
    let pending_streams = Hashtbl.create config.max_streams in
    let lock = Lwt_mutex.create () in


    let next_id =
      if config.is_client = true then 1l
      else 2l
    in
    

    let (p, r) = Lwt.wait () in
    

    {
      streams; pending_streams;
      pending_pings; lock; next_id;
      local_closed=false; remote_closed=false;
      close=(p, r);
      ping_id=0l; flow; config 
    }



  
  

  let flow t = t.flow


  let next_id t =
    let id = Int32.add t.next_id 2l in
    let _ = t.next_id <- id in
    id



  
    
  let send t frame = 
    let buf = Packet.encode frame in
    Lwt_mutex.lock t.lock >>= fun () ->
    Flow.write t.flow buf >|= fun res ->

    Lwt_mutex.unlock t.lock;
    res 
    










  

  let valid_remote t sid =
    let id = Int32.to_int sid in 
    if (Config.is_server t.config) then
      ID.is_client id
    else
      ID.is_server id

  


  
  let read t =
    
    let read_data hdr =
      match Header.mtype hdr with
      | Data -> 
        let len = Header.len hdr |> Int32.to_int in
        let rd = Flow.read_bytes t.flow len in 
        Flow.map_read rd (fun body -> Packet.make hdr ~body)

      | _ ->
        let packet = Packet.make hdr in 
        Ok (`Data packet ) |> Lwt.return 
    in
    

    let rd1 = Flow.map_read (Flow.read_bytes t.flow 16) Header.decode in
    Flow.fmap_read rd1 read_data



  

  let check_close t =
    if (t.local_closed || t.remote_closed) && (Hashtbl.length t.streams = 0)  then
      let (_, p) = t.close in
      Lwt.wakeup p ()



  let notify_close t =
    let (_, p) = t.close in 
    Lwt.wakeup p () 

  
  let proto_error t =
    t.local_closed <- true;
    let msg = Packet.GoAway.protocol_error in 
    send t msg >|= function
    | Ok () -> Ok (Some msg) 

    | Error e ->
      let _ = notify_close t in
      Error e


  
  let process_flags t frame f =
    

    let open Packet in
    let open Stream_entry in
    let open Option.Infix in

    let id = Packet.id frame in
    let header = Packet.header frame in

    if Header.is_rst header then
      
      let _ =
        Hashtbl.find_opt t.streams id >>> fun entry ->
        let _ = Stream_entry.update_state entry Closed in 
        PromiseMap.delete t.streams id
      in

      let _ = check_close t in


      Ok None |> Lwt.return

    else if Header.is_fin header then
      
      let _ =
        Hashtbl.find_opt t.streams id >>> fun entry ->
        Stream_entry.update_state entry RecvClosed;
      in

      let _ = check_close t in

       Ok None |> Lwt.return

    else if Header.is_syn header && t.local_closed then
      proto_error t

  
    else if
      Header.is_syn header && ( Hashtbl.mem t.streams id )
    then
      
      let _ =
        Log.debug (fun fmt ->
            fmt "Protocol Error, stream %ld already exists" id
          )
      in
      
      proto_error t 

    else if
      Header.is_syn header && (Hashtbl.length t.streams >= (Config.max_streams t.config) )
    then
      
      let max = Config.max_streams t.config in
      let _ = Log.debug ( fun fmt ->
          fmt "Protocol Error: maximum number of streams %d reached" max
        ) in


      t.local_closed <- true;
      proto_error t 



    else
      f t frame






  

  let on_window_update t frame =


    let handle t frame =
      let id = Packet.id frame in
      let credit = Packet.WindowUpdate.credit frame |> Int32.to_int in
      let s = Hashtbl.find t.streams id in
      s.credit <- s.credit + credit;
      Ok None |> Lwt.return

    in process_flags t frame handle
      





  

  let reset t id =
    let packet =
      Packet.data id Cstruct.empty |>
      (fun p -> {p with header = Header.ack p.header} )
    in

    
    send t packet




  
  let as_res t r =
    match r with
    | Ok () -> Ok None |> Lwt.return
    | Error e ->
      let _ = notify_close t in
      Lwt.return (Error e)
  

  

  let on_data t packet =
    let open Stream_entry in 

    let aux t frame =
      let id = Packet.id packet in
      let len = Packet.header packet |> Header.len |> Int32.to_int in
      
      match Hashtbl.find_opt t.streams id with

      | Some stream when len > stream.window ->
        let _ = Log.debug (fun fmt -> fmt "data frame exceeded window size") in
        proto_error t

      | Some stream when (Bstruct.writer_index stream.buf) >= t.config.max_buffer_size ->
        let _ = Log.debug (fun fmt -> fmt "Cannot receive data frame" ) in
        reset t id >>= as_res t

  
      | Some stream ->
        stream.window <- stream.window - len;
        Lwt_mutex.lock stream.lock >|= fun () ->
        Bstruct.write_bytes stream.buf frame.body;
        Ok None

      | None ->
       Ok None |> Lwt.return

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
    Lwt.return (Ok (Some frame) )





  let on_ping t frame =
    let open Header in 
    let header  = Packet.header frame in

    if Header.is_ack header then
      let nonce = header.len in 
      let pings = t.pending_pings in
      PromiseMap.wake_up pings nonce ();
      Ok None |> Lwt.return 


    else
      let packet = {frame with header = Header.ack header} in
      send t packet >>= as_res t


  
  let process t frame =
    match (Packet.msg_type frame) with
    | Data -> on_data t frame
    | Window_Update -> on_window_update t frame
    | Ping -> on_ping t frame
    | Go_Away -> on_goaway t frame
                   

  
  
end 





