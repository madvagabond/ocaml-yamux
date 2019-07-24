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


type status = Open | SendClosed | RecvClosed | Closed


type stream =  {

  mutable status: status;

  id: int32; 
  mutable send_window: int32;
  mutable recv_window: int32;

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

  {
    status; 
    send_window;
    recv_window;
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



(*make non naive*)
let write t buf =
  let len = Cstruct.len buf |> Int32.of_int in 
  let frame  = Frame.data t.id buf in 
  let window = saturating_sub t.send_window len in

  let _ = t.send_window <- window in 
  let _ = Lwt_queue.offer t.tx frame in

  
  Lwt.return_unit




(*make non naive*)
  
let read t buf =
  let open Lwt.Infix in 
  Lwt_queue.poll t.rx >|= fun buf ->

  let len = Cstruct.len buf |> Int32.of_int in
  let window = Int32.add t.recv_window len in
  let _ = t.recv_window <- window in
  
  let frame = Frame.window_update t.id len in
  let _ = Lwt_queue.offer t.tx frame in

  buf
  
