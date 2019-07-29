open Lwt.Infix
open Stream 
open Config


let src = Logs.Src.create "sessions" ~doc:"Yamux Session Management"
module Log = (val Logs.src_log src : Logs.LOG)









module Make (F: Mirage_flow_lwt.S) = struct

  
  module Transport = Mirage_codec.Make(F)(Codec)


  type transition = Close  | Continue | Go_away


  
  

  type t = {

    mutable closed: bool; 
    transport: Transport.t;
    
    streams: (int32, Stream.stream) Hashtbl.t;
    
    mutable ping_id: int32;
    mutable stream_id: int32;

    
    config: Config.t;

    
    pings: (int32, unit Lwt.u) Hashtbl.t;

    out: Frame.t Lwt_queue.t;
    incoming: Stream.stream Lwt_queue.t;
  }







  
  let handle_ping t frame =
    let open Frame.Flags in
    let open Frame in
    
    let flags = Frame.flags frame in

    let wake_ping () =
      let ping_id = Frame.length frame in
      
      let _ = Hashtbl.find_opt t.pings ping_id |> function
        | Some r  -> Lwt.wakeup_later r ()
        | None -> ()
      in

      Continue 
    in 



    let reply () =

      let id = Frame.length frame in
      let flags = Ack |> flag_to_int in
      


      let frame = Frame.ping ~flags id in
      let _ = Lwt_queue.offer t.out frame in

      Continue 
    in
     

    if has flags Ack then
      wake_ping ()
        
    else
      reply ()


  







  let on_fin frame stream =

    let open Frame in 
    if Flags.has (Frame.flags frame) Fin then
      Stream.update_status stream Stream.RecvClosed
              



  let on_syn t frame f =
    let open Frame in
    let open Stream in

    let id = Frame.stream_id frame in




    if Hashtbl.mem t.streams id then
      
      let _ = Logs.err ~src (fun m ->
          m "Cannot create stream %ld because it already exists, shutting down transport" id
        )
      in
      Go_away

    else if (Config.max_streams t.config) <= (Hashtbl.length t.streams) then
      
      let _ = Logs.err ~src (fun m -> m "Maximum stream capacity met, cannot allocate more, shutting down transport.") in 
      Go_away

    else

      let _ = Logs.info ~src (fun m -> m "Creating new stream %ld" id) in

      let stream =
        f () 
      in


      let _ = on_fin frame stream in 

      let _ = Lwt_queue.offer t.incoming stream in
      let _ = Hashtbl.add t.streams id stream in
      Continue




    




  (**
    flag behavior:  
      
      syn: 
      if the stream frame.id doesn't exist create the stream with window sizes as frame.length
      if the stream id exists send a go_away with the protocol error code and shutdown 
     
      fin: 
       close the stream  

      
      
    operations 
      syn flag -> check fin -> done     
    

      standard behavior if a go_away has not been sent then shutdown 
       
  *)

  
  let handle_window_update t frame =

    let open Frame in
    let open Flags in
    let open Stream in 

    
    let id = Frame.stream_id frame in

    let make_stream () =
      Stream.make Config.default_recv_window (Frame.length frame) id t.out
    in
    


    if has (Frame.flags frame) Syn then
      on_syn t frame make_stream
  
    else
      Hashtbl.find_opt t.streams id  |> function
      | Some s ->
        let _ = Stream.update_window s (Frame.length frame) in
        Continue 

      | None ->
        Continue


  
  


  
        




  let handle_data t frame =
    
    let open Frame in
    let open Flags in
    let open Stream in 



    let _ = Logs.info ~src (fun m -> m "receiving data packet") in

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


        Continue 
      in
      

        
      match (Hashtbl.find_opt t.streams id) with
      | Some s ->
        f s    

      | None ->
        Continue 
    in
  

    if has (Frame.flags frame) Syn then
      let init_stream () =
        Stream.make Config.default_recv_window Config.default_recv_window id t.out
      in
      
      on_syn t frame init_stream |> function
      | Continue -> notify_substream ()                  
      | state -> state

  
    else
      notify_substream () 


  







  
  

  let shutdown t =
    let _ = t.closed <- true in
    Lwt.return_unit 


  
  


  let accept t =
    Lwt_queue.poll t.incoming



 


  let ping t =
    let (p, u) = Lwt.task () in
    let ping_id = Int32.add t.ping_id 1l in
    let _ = t.ping_id <- ping_id in
    
    let frame = Frame.ping ping_id in
    let _ = Hashtbl.add t.pings ping_id u in
    let _ = Lwt_queue.offer t.out frame in
    
    p
  



  
  
  let open_stream t =
    let open Frame in
    let open Flags in
    
    let id = Int32.add t.stream_id 2l in
    let flags = flag_to_int Syn in
    let frame = Frame.window_update ~flags id (Config.recv_window t.config) in

    let size = Config.recv_window t.config in
    let stream = Stream.make size size id t.out in
    let _ = Hashtbl.add t.streams id stream in
    

    let _= t.stream_id <- id in 
    let _ = Lwt_queue.offer t.out frame in
    Lwt.return stream





  
    



  let handle_frame t frame =
    let open Frame in
    match (Frame.frame_type frame) with
    | Data -> handle_data t frame
    | Window_update -> handle_window_update t frame
    | Ping -> handle_ping t frame
    | Go_away -> Close
  



  
  let read_loop t =
      

    let handle_message =
      let open Transport in 
      function
      | Ok (Data msg) -> handle_frame t msg
      | Ok Eof -> Close
      | Error e -> Go_away
  in 

  

  let rec aux () =

    let send_go_away () =
      let frame = Frame.go_away 1l in 
      let _ = Lwt_queue.offer t.out frame in
      let _ = Lwt_queue.close t.out in
      Lwt.return_unit 
    in

    

    
    
    let handle_transition out =

      match out with
      | Close -> shutdown t 
      | Continue -> aux ()
      | Go_away ->  send_go_away () 

    in

    let step res = handle_message res |> handle_transition in
    

      if t.closed then Lwt.return_unit
      else
        Transport.read t.transport >>= step 
    in

    
    aux ()






  
  let write_loop t =



    let on_goaway frame =
      Transport.write t.transport frame >>= fun _ ->
      shutdown t
    in
    


  
  
        
    let rec aux () =


      let send frame =
        Transport.write t.transport frame >>= function 
        | Ok () -> aux ()
        | Error _ -> shutdown t
      in

      
      let step frame =
        let open Frame in 
        match Frame.frame_type frame with

        | Go_away -> on_goaway frame
        | _ -> send frame

      in
      
      if t.closed then
        Lwt.return_unit
      else
        Lwt_queue.poll t.out >>= fun frame -> 
        step frame 


    in


    
    aux ()




 

  

  let make flow config =
    let open Config in
    
    let stream_id =
      match config.mode with
      | Client -> 1l
      | Server -> 2l
    in

    let transport = Transport.make flow in
    let streams = Hashtbl.create config.max_streams in
    let ping_id = 0l in

    let out = Lwt_queue.unbounded () in
    let incoming = Lwt_queue.unbounded () in
    let pings = Hashtbl.create 65000 in
    let closed = false in 

    let t = {closed; transport; streams; ping_id; stream_id; config; pings; out; incoming;} in

    let _ = Lwt.async (fun () -> read_loop t) in
    let _ = Lwt.async (fun () -> write_loop t) in

    t 
    
    
  
      

  
end
