open Lwt.Infix
open Stream 
open Config

type session_type = Server | Client

let src = Logs.Src.create "sessions" ~doc:"Yamux Session Management"
module Log = (val Logs.src_log src : Logs.LOG)









module Make (F: Mirage_flow_lwt.S) = struct

  
  module Transport = Mirage_codec.Make(F)(Codec)

  
      
  type t = {
    transport: Transport.t;
    streams: (int32, Stream.stream) Hashtbl.t;
    config: Config.t;

    
    pings: (int32, unit Lwt.u) Hashtbl.t;

    out: Frame.t Lwt_queue.t;
    incoming: Stream.stream Lwt_queue.t;

    
    pending_streams: (int32, Stream.stream Lwt.u) Hashtbl.t; 
    close_r: unit Lwt.u;
    close_t: unit Lwt.t 
  }






  let incoming_stream t frame = ()
  let process_data t frame = ()  
                             

  let process_window_update t frame = ()

      
  let handle_ping t frame =
    let open Frame.Flags in
    let open Frame in
    
    let flags = Frame.flags frame in

    let wake_ping () =
      let ping_id = Frame.length frame in
      Hashtbl.find_opt t.pings ping_id |> function

      | Some r  -> Lwt.wakeup_later r ()
      | None -> () 
    in 



    let reply () =

      let id = Frame.length frame in
      let flags = Ack |> flag_to_int in
      


      let frame = Frame.ping ~flags id in
      let _ = Lwt_queue.offer t.out frame in

      ()
    in
     

    if has flags Ack then
      wake_ping ()
        
    else if has flags Syn then
      reply ()

    else
      ()










  let incoming_stream t frame =
    let open Frame in
    let open Flags in

    let id = Frame.stream_id frame in



    (* Sends go away and then returns*) 
    let send_go_away () =
      let frame = Frame.go_away 1l in
      let _ = Lwt_queue.offer t.out frame in
      Error frame  
    in



    
    let on_fin stream =
      if has (Frame.flags frame) Fin then
        Stream.update_status stream Stream.RecvClosed
    in
    



    
    if Hashtbl.mem t.streams id then
      send_go_away ()

    else if (Config.max_streams t.config) >= (Hashtbl.length t.streams) then
      send_go_away ()

    else
      

      let stream =
        Stream.make Config.default_recv_window (Frame.length frame)
      in


      let _ = on_fin stream in 
      
      let _ = Lwt_queue.offer t.incoming stream in
      let _ = Hashtbl.add t.streams id stream in
      Ok stream 
      

      







  


  let accept t =
    Lwt_queue.poll t.incoming


  
      

  
end
