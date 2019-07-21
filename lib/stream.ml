type status = Open | SendClosed | RecvClosed | Closed


type stream =  {

  mutable status: status;
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

 









let make send_window recv_window =
  let status = Open in

  let rx = Lwt_queue.unbounded () in 
  let tx = Lwt_queue.unbounded () in

  {
    status; 
    send_window;
    recv_window;
    rx;
    tx;
  }
