open Lwt.Infix

module Flags = Frame.Flags


module Entry = struct

  type status =
    | Init | SynSent | SynReceived
    | Established | LocalClosed
    | RemoteClosed | Reset |  Closed 


  type errors = [
      `Unexpected_Flag |
      `Window_Exceeded |
      `Closed |
      `Stream_Reset
  ]

  
  type write_error = [
    `Closed |
    `Window_Exceeded
  ]


  type or_eof = [
    | `Data of Cstruct.t
    | `Eof
  ]


  type read = (or_eof, errors) result 
  
  type t = {
    id: int32;
    
    tx: Frame.t Lwt_queue.t;
    rx: Frame.t Lwt_queue.t;

    max_recv_window: int;

    mutable read_buf: Cstruct.t; 
    mutable write_buf: Cstruct.t;
    shutdown: (unit Lwt.u * unit Lwt.t) ; 
    mutable send_window: int;
    mutable recv_window: int;
    
    mutable status: status;
    waiters: read Lwt.u Queue.t
  }


  let insert_frame t frame =
    Lwt_queue.put t.rx frame


  let send_frame t frame =
    Lwt_queue.put t.tx frame 


  let send_close t =
    let flags = Flags.add Flags.empty Frame.FIN in 

    let frame = Frame.window_update
        ~flags
        ~id: t.id
        ~credit: 0l
    in
    
    send_frame t frame


  let get_flags t =
    match t.status with
    | Init ->
      let _ = t.status <- SynSent in
      Frame.flag_to_int Frame.SYN

    | SynReceived ->
      let _ = t.status <- Established in 
      Frame.flag_to_int Frame.ACK

    | _ -> Flags.empty
  

    

 


  let notify_shutdown t =
    let (p, _) = t.shutdown in
    Lwt.wakeup_later p ()

  


  
  let close t =

    match t.status with
    | Established | SynSent | SynReceived  ->
      let _ = t.status <- LocalClosed in
      send_close t >>= fun () ->
      Lwt_queue.close t.tx 
        
    | RemoteClosed->
      let _ = t.status <- Closed in
      send_close t >>= fun () ->
      Lwt_queue.close t.tx >>= fun () ->
      Lwt_queue.close t.rx >|= fun () ->
      notify_shutdown t

    | Reset | Closed ->
      let _ = notify_shutdown t in
      Lwt.return_unit
        
    | _ -> Lwt.return_unit



  

  let process_flags t flags=
    match t.status with
    | SynReceived |  SynSent | Established when (Flags.has flags FIN) ->
      let _ = t.status <- RemoteClosed in
      Lwt.return (
        Ok ()
      )
        
    | LocalClosed when Flags.has flags FIN ->
      close t >|= fun () ->
      Ok () 


    | _ when Flags.has flags RST ->
      close t >|= fun () ->
      Ok ()
        
    | _ when Flags.has flags FIN ->
      Lwt.return (Error `Unexpected_Flag )

    | _ -> Lwt.return (
        Ok ()
      )






  let send_data t buf =
    let flags = get_flags t in 
    let data = Frame.data ~flags ~id: t.id ~body: buf in
    send_frame t data 



  

  let send_window_update t =
    let read_len = Cstruct.len t.read_buf in
    let delta = t.max_recv_window - read_len - t.recv_window in
    let flags = get_flags t in

    if delta < (t.max_recv_window / 2) && (flags = 0) then
      Lwt.return_unit           
    else

      let _ =
        t.recv_window <- t.recv_window + delta
      in

      let frame = Frame.window_update ~flags ~id: t.id ~credit: (Int32.of_int delta) in
      send_frame t frame







  let write t buf =

    match t.status with
    | LocalClosed | Closed | Reset  -> 
      Lwt.return ( Error `Closed )

    | _ when t.send_window = 0 ->
      let _ = t.write_buf <- Cstruct.append t.write_buf buf in
      Lwt.return (Ok ())

    | _  when Cstruct.len t.write_buf > 0 ->
      
      let n = min (Cstruct.len t.write_buf) t.send_window in
      let (hd, tl) = Cstruct.split t.write_buf n in

      let _ = t.write_buf <- Cstruct.append tl buf in 

      send_data t hd >|= fun () ->
      Ok ()

    | _ ->
        
      let n = min (Cstruct.len buf) t.send_window in
      let (hd, tl) = Cstruct.split buf n in
      let _ = t.write_buf <- Cstruct.append t.write_buf tl in

      send_data t hd >|= fun _ ->
      Ok ()


  
      
  let broadcast_waiters t result =
    let rec aux q =
      if Queue.is_empty q = false then
        let _ = Lwt.wakeup_later (Queue.pop q) result in
        aux q
      else
        Lwt.return result 
    in

    aux t.waiters
  


  let read t =
    let len = Cstruct.len t.read_buf in





    match t.status with
    | LocalClosed | RemoteClosed | Closed when len = 0 ->
      if Queue.is_empty t.waiters = false then
        broadcast_waiters t (Ok `Eof) 
      else
        Lwt.return (Ok `Eof)

    | Reset ->
      broadcast_waiters t (Error `Stream_Reset)
        


    | _ when len > 0 ->

      let n_bytes = min len 1024 in 

      let (out, rcv_buf) = Cstruct.split t.read_buf n_bytes in
      let _ = t.read_buf <- rcv_buf in

      send_window_update t >>= fun _ -> 

      Lwt.return (
        Ok (`Data out)
      )

    | _ ->
      let p, r = Lwt.wait () in 
      let _ = Queue.push r t.waiters in
      p





  let handle_window_update t frame =
    process_flags t (Frame.flags frame) >>= fun res ->
    match res with
    | Ok () ->

      let _ =
        t.recv_window <- t.recv_window + (Frame.length frame |> Int32.to_int)
      in

      let n_pending = Cstruct.len t.write_buf in

      if n_pending > 0 then
        let n = min n_pending t.send_window in
        let (out, pending) = Cstruct.split t.write_buf n in
        let _ = t.write_buf <- pending in
        write t out
          
      else
        Lwt.return (
          Ok ()
        )
      
    | Error e ->
      Lwt.return (Error e)


      

    


  let handle_data t frame =
    let len = Frame.length frame |> Int32.to_int in
    let flags = Frame.flags frame in

    let complete () =

      let _ = t.recv_window - len in
 
      Lwt.return (
        Ok ()
      )
    in

    
    process_flags t flags >>= function
    | Ok () when len > t.recv_window ->
      Lwt.return (
        Error `Window_Exceeded
      )

    | Ok () when (Queue.length t.waiters) > 0 ->
      let p = Queue.pop t.waiters in
      let body = Frame.body frame in 

      let _ = Lwt.wakeup_later p (
          Ok ( `Data body)
        )
      in

      complete () 

    | Ok () ->
      let body = Frame.body frame in
      let _ = t.read_buf <- Cstruct.append t.read_buf body in
      complete ()
        
    | Error e ->
      Lwt.return (Error `Unexpected_Flag)



  


    
    

end 



