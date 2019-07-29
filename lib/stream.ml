(** Update writes to be like this
     let credit be an alias for send_window
     let w be a tuple of (len, cstruct, promise) 
     let pending be a set of w 
      
     let defer payload be a function that pushes onto pending

     if pending  
      credit gtr body.len AND credit gtr 0 ->
        (payload, rest) = body[0:credit], body[credit:]
        add rest to pending 
        send (data_frame payload) 

      credit eq 0 ->  defer body
  



     let flush_deferred stream = if pending is non_empty recursively resolve pending writes pushing them to out. 

     let update_window stream frame =
       add frame.len to credit 
       flush_deferred stream 
     
*)

let src = Logs.Src.create "stream" ~doc:"Yamux Streams"
module Log = (val Logs.src_log src : Logs.LOG)



type write_error = [`Closed]

type status = Open | SendClosed | RecvClosed | Closed

type waiter = (int32 * Cstruct.t * (unit, write_error) result Lwt.u)



type stream =  {

  mutable status: status;

  id: int32; 
  mutable send_window: int32;
  mutable recv_window: int32;
  mutable waiters: waiter list;
  rx: Cstruct.t Lwt_queue.t;
  tx: Frame.t Lwt_queue.t;
}






let update_status t status =
  match (t.status, status) with
  | (Closed, _) -> ()
  | (Open, _) -> t.status <- status
  | (RecvClosed, Closed) -> t.status <- Closed
  | (RecvClosed, SendClosed) -> t.status <- Closed
  | (RecvClosed, Open) -> ()
  | (RecvClosed, RecvClosed) -> ()

  | (SendClosed, Closed) -> t.status <- Closed
  | (SendClosed, Open) -> ()

  | (SendClosed, RecvClosed) -> t.status <- Closed
  | (SendClosed, SendClosed) -> ()

 









let make send_window recv_window id tx =
  let status = Open in

  let rx = Lwt_queue.unbounded () in
  let waiters = [] in
  {
    status; 
    send_window;
    recv_window;
    waiters;
    id;
    rx;
    tx;
  }



let saturating_sub l r =
  let i = Int32.sub l r in

  if i >= 0l then i
  else 0l









let close t =
  let _ = update_status t SendClosed in
  let flags = Frame.flag_to_int Frame.Fin in
  let frame = Frame.window_update ~flags t.id 0l in
  let _ = Lwt_queue.offer t.tx frame in
  Lwt.return_unit

(*

(*make non naive*)
let write t buf =
  let len = Cstruct.len buf |> Int32.of_int in 
  let frame  = Frame.data t.id buf in 
  let window = saturating_sub t.send_window len in

  let _ = t.send_window <- window in 
  let _ = Lwt_queue.offer t.tx frame in

  
  Lwt.return_unit
*)

(*make non naive*)
  
let read t =
  let open Lwt.Infix in

  let _ = Logs.debug ~src (fun m -> m "Reading stream") in
  Lwt_queue.poll t.rx >|= fun buf ->

  let len = Cstruct.len buf |> Int32.of_int in
  let window = Int32.add t.recv_window len in
  let _ = t.recv_window <- window in
  
  let frame = Frame.window_update t.id len in
  let _ = Lwt_queue.offer t.tx frame in

  buf
  




let send_data t buf =

  let len = Cstruct.len buf |> Int32.of_int in 
  let frame  = Frame.data t.id buf in 
  let window = saturating_sub t.send_window len in

  let _ = t.send_window <- window in 
  let _ = Lwt_queue.offer t.tx frame in

  ()





let resolve_waiters t =


  let rec step waiters credit = 
    match waiters with
    | hd :: tl ->
      let (size, buf, p) = hd in

      if credit >= size then
        let _ = send_data t buf in 
        let _ = Lwt.wakeup_later p in
        step waiters t.send_window

      else

        let (payload, rest) = Cstruct.split buf (Int32.to_int t.send_window)  in
        let _ = send_data t payload in
        let w2 = (Cstruct.len rest |> Int32.of_int, rest, p) in
        [w2] @ tl
       



    | [] ->
      []
      
  in

  let waiters = step t.waiters t.send_window in
  t.waiters <- waiters










let write t buf =
  let size = Cstruct.len buf |> Int32.of_int in

  let step () = 
    match (t.waiters, size) with
    | ([], size) when size <= t.send_window ->
      let _ = send_data t buf in
      Lwt.return (Ok () )

    | ([], _) ->


      let (payload, rest) = Cstruct.split buf (Int32.to_int t.send_window)  in
      let _ = send_data t payload in

      let (p, r) = Lwt.task () in
      
      let w  = (Cstruct.len rest |> Int32.of_int, rest, r) in
      let _ = t.waiters <- t.waiters @ [w] in
      p
      
   

    | (_::_, size) ->
      let (p, u) = Lwt.task () in 
      let w  = (size, buf, u) in
      let _ = t.waiters <- t.waiters @ [w] in
      p

  in


  match t.status with
  | Open -> step ()
  | RecvClosed -> step ()
  | _ -> Lwt.return (Error `Closed)

  


 
    


let update_window t credit =
  let credit = Int32.add t.send_window credit in
  let _ = t.send_window <- credit in
  resolve_waiters t 
