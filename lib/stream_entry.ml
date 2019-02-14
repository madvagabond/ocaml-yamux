open Util

type state = Open | SendClosed | RecvClosed | Closed

type t = {

  
  buf: AsyncBuf.t;
  mutable window: int;
  mutable credit: int;
  mutable state: state;

}


let make window credit =
  let buf = AsyncBuf.create () in
  let lock = Lwt_mutex.create () in
  let state = Open in
  {buf; window; credit; state;}





let update_state t next =
  let current = t.state in
  let _ =
    match (current, next) with
    | (Closed, _) -> () 
    | (Open, _) -> t.state <- next

    | (RecvClosed, Closed) -> t.state <- Closed

    | (RecvClosed, Open) -> ()
    | (RecvClosed, RecvClosed) -> ()

    | (RecvClosed, SendClosed) -> t.state <- Closed

    | (SendClosed, Open) -> ()
    | (SendClosed, Closed) -> t.state <- Closed
    | (SendClosed, RecvClosed) -> t.state <- Closed
    | (SendClosed, SendClosed) -> ()


  in

  t.state

let state t =
  t.state





