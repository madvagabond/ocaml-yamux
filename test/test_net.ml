
open Lwt.Infix

module Transport = struct



  type 'a io = 'a Lwt.t
  type buffer = Cstruct.t
  type peer = string

  type conn = {
    peer: string;
    ic: Cstruct.t Lwt_queue.t;
    oc: Cstruct.t Lwt_queue.t
  }


  let pp_write_error = Mirage_flow_lwt.pp_write_error
  let pp_error = Mirage_flow_lwt.pp_error
                   
  type flow = conn

  type write_error = Mirage_flow_lwt.write_error

  type error = Mirage_flow_lwt.error
  


  let create peer =
    let ic = Lwt_queue.create () in
    let oc = Lwt_queue.create () in 
    {peer; ic; oc}


  let pipe l r =
    let tx = {(create l) with peer = r} in
    let rx = {peer = l; ic = tx.oc; oc = tx.ic} in
    (tx, rx)

  
  let write conn msg =
    Lwt_queue.put conn.oc msg >|= fun () ->
    Ok ()

  let read conn =
    Lwt_queue.poll conn.ic >|= fun buf ->
    Ok (`Data buf)

  let close conn =
    Lwt_queue.close conn.oc


  let dst conn = conn.peer

  let writev conn bufs =
    Cstruct.concat bufs |> write conn
end





module Net = struct
  include Transport


  type conn_t = {src: peer; dst: peer}

  type cb = conn -> unit Lwt.t


  type listeners = (peer, cb) Hashtbl.t



  let create () : (string, cb) Hashtbl.t = Hashtbl.create 1024


  let accept net conn_t =
    let {src; dst} =  conn_t in

    let cb = Hashtbl.find net dst in
    let (tx, rx) = Transport.pipe src dst in
    let _ = cb rx in
    Lwt.return tx




  
  let listen net peer cb =
    let _ = Hashtbl.add net peer cb in
    Lwt.return_unit


  let connect net peer =
    let src = "client:" ^  (Random.int 36000 |> string_of_int) in
    let ct = {src; dst=peer} in
    accept net ct


  

end 


  
