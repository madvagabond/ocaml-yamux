
open Lwt.Infix


module Flow_ext (F: Mirage_flow_lwt.S) = struct

  type buffer = F.buffer

  type error = F.error

  type 'a io = 'a F.io

  
  type write_error = F.write_error

  
  type flow = {
    flow: F.flow;
    buf: Bstruct.t;
    lock: Lwt_mutex.t 
  }

  let src = Logs.Src.create "flow_ext" ~doc:"Additional functionality to mirage flows"
  module Log = (val Logs.src_log src : Logs.LOG)



  let (pp_error, pp_write_error) = F.pp_error, F.pp_write_error



  let fmap_read rd f =
    rd >>= function
    | Ok (`Data b) -> f b
    | Error e -> Lwt.return (Error e)
    | Ok `Eof -> Lwt.return (Ok `Eof)


  
  
  let map_read rd f =
    rd >|= function
    | Ok (`Data b) -> Ok (`Data (f b) )
    | Error e -> Error e
    | Ok `Eof -> Ok `Eof
  
  
  
  let read_bytes t len =
    let present = Bstruct.readable t.buf in

    let rec aux () =
      F.read t.flow >>= function

      | Ok (`Data cs) ->
        let _ = Bstruct.write_bytes t.buf cs in

        if (Bstruct.readable t.buf) >= len then
          let data = `Data (Bstruct.read_bytes t.buf len) in
          Ok data |> Lwt.return

        else
          aux ()

      | Ok `Eof ->
        let _ = Log.debug (fun fmt ->
            fmt "remote peer closed connection before we could read %d bytes from flow" len  
          )
        in

        Ok `Eof |> Lwt.return


      | Error e ->
        Error e |> Lwt.return

    in


    if present >= len then
      let data = `Data (Bstruct.read_bytes t.buf len) in
      Ok data |> Lwt.return 

    else
      Lwt_mutex.lock t.lock >>= fun () ->

      let res = aux () in
      let _ = Lwt_mutex.unlock t.lock in
      res



  let create flow =
    let buf = Bstruct.create 4096 in
    let lock = Lwt_mutex.create () in
    {flow; buf; lock}



  let read t =
    read_bytes t 1024

  let write t buf =
    Lwt_mutex.lock t.lock >>= fun () ->
    F.write t.flow buf >|= fun res ->
    let _ = Lwt_mutex.unlock t.lock in 
    res


  let writev t buf =
    Lwt_mutex.lock t.lock >>= fun () ->
    F.writev t.flow buf >|= fun res ->
    let _ = Lwt_mutex.unlock t.lock in 
    res


  let close t =
    Lwt_mutex.lock t.lock >>= fun () ->
    F.close t.flow >|= fun res ->

    let _ = Lwt_mutex.unlock t.lock in
    res


  
  
end







module Config = struct

  type t = {
    max_streams: int;
    is_client: bool;
    max_buffer_size: int;
    recv_window: int;
  }


  let default_recv_window = 200 * 1024

  let default_capacity = 1024 * 1024

  let default_streams = 8192


  let max_streams t = t.max_streams

  let window t = t.recv_window

  
  let is_server t =
    t.is_client <> true

  let is_client t =
    t.is_client


  let recv_window t = t.recv_window

  let client ?(max_streams=default_streams) ?(max_buffer_size=default_capacity) ?(recv_window=default_recv_window) () =
    {max_streams; max_buffer_size; is_client=true; recv_window}


  let server ?(max_streams=default_streams) ?(max_buffer_size=default_capacity)  ?(recv_window=default_recv_window) () =
    {max_streams; max_buffer_size; is_client=false; recv_window}
  
  
    
  
end



module Option = struct


  let map o f =
    match o with
    | Some x -> Some (f x)
    | None -> None



  let bind o f =
    match o with
    | Some x -> f x
    | None -> None


  let get = function
    | Some x -> x
    | None -> raise Not_found



  let is_some = function
    | Some _ -> true
    | None -> false


  let is_none = function
    | Some _-> false
    | None -> true


  let on_some o f =
    match o with
    | Some x ->
      f x;
      () 
    | None -> () 


  let on_none o f =
    match o with
    | None ->
      let _ = f () in
      ()
    | _ -> ()
    
  module Infix = struct
    let (>>=) = bind
    let (>|=) = map

    let (>>>) = on_some
  end
  
  

end


module PromiseMap = struct
  type 'a t = (int32, 'a Lwt.u) Hashtbl.t


  let rec delete tbl i =
    if Hashtbl.mem tbl i  then 
      let _ = Hashtbl.remove tbl i in
      delete tbl i
      
    else
      ()

     
          

  
  let wake_up t i a =
    Hashtbl.find_opt t i |> function
    | Some x ->
      Lwt.wakeup x a;
      delete t i

    | None -> ()




  

  let map_key tbl f id =
    match (Hashtbl.find_opt tbl id) with
    | Some x -> Some (f x)
    | None -> None
    

  let use_and_discard tbl f id =
    match (Hashtbl.find_opt tbl id) with
    | Some x ->
      let res = f x in
      delete tbl id; 
      Some res
      
    | None -> None
end






module ID = struct
  let is_server id =
    (id mod 2) = 0

  let is_client id =
    is_server id <> true

  let is_session id =
    id = 0l
end 





