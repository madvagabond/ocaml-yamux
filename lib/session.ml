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
    close_p: unit Lwt.t 
  }







  
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












    



  let handle_window_update t frame =

    let open Frame in
    let open Flags in
    let open Stream in 


    let send_go_away () =
      let frame = Frame.go_away 1l in
      let _ = Lwt_queue.offer t.out frame in
      Error frame  
    in


    let on_fin stream =
      if has (Frame.flags frame) Fin then
        Stream.update_status stream Stream.RecvClosed
    in

    
    let id = Frame.stream_id frame in
    

    let on_syn () =

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
        Ok ()


    in





    if has (Frame.flags frame) Syn then
      on_syn ()
  
    else
      Hashtbl.find_opt t.streams id  |> function
      | Some s ->
        let _ = s.send_window <- Int32.add s.send_window (Frame.length frame) in
        Ok ()

      | None ->
        Ok ()


  
        




  let handle_data t frame =
    
    let open Frame in
    let open Flags in
    let open Stream in 


    let send_go_away () =
      let frame = Frame.go_away 1l in
      let _ = Lwt_queue.offer t.out frame in
      Error frame  
    in


    let on_fin stream =
      if has (Frame.flags frame) Fin then
        Stream.update_status stream Stream.RecvClosed
    in



    let id = Frame.stream_id frame in
    

    let notify_substream () =

      let f stream =

        let _ = stream.recv_window <- Stream.saturating_sub stream.recv_window (Frame.length frame) in
        let _ = Lwt_queue.offer stream.rx (Frame.body frame) in
        let _ = on_fin stream in

        Ok ()
      in
      

        
      match (Hashtbl.find_opt t.streams id) with
      | Some s -> f s    

      | None -> Ok ()

    in
    


    

    

    let on_syn () =

      if Hashtbl.mem t.streams id then
        send_go_away ()

      else if (Config.max_streams t.config) >= (Hashtbl.length t.streams) then
        send_go_away ()

      else


        let stream =
          Stream.make Config.default_recv_window Config.default_recv_window
        in


        let _ = on_fin stream in 

        let _ = Lwt_queue.offer t.incoming stream in
        let _ = Hashtbl.add t.streams id stream in
        notify_substream () 
    in



    if has (Frame.flags frame) Syn then
      on_syn ()
    else
      notify_substream () 
      







  
  

  let shutdown t =
    let _ = Lwt.wakeup_later t.close_r () in
    t.close_p


  


  let accept t =
    Lwt_queue.poll t.incoming



  

  
      

  
end
