
open Lwt.Infix
       
[@@@ocaml.warning "-3"]
module Lwt_sequence = Lwt_sequence
[@@@ocaml.warning "+3"]




module AsyncBuf = struct

  type t = {
    writes: Cstruct.t Lwt_sequence.t;
    reads:  (Cstruct.t Lwt.u) Lwt_sequence.t
  }



  let bufs t = Lwt_sequence.length t.writes
  
  let len buf =
    Lwt_sequence.fold_l (fun b acc -> acc + (Cstruct.len b) ) buf.writes 0 

  let create () =
    let reads = Lwt_sequence.create () in
    let writes = Lwt_sequence.create () in
    {reads; writes}



  let put t buf =
    match Lwt_sequence.take_opt_l t.reads with
    | Some r ->
      Lwt.wakeup r buf

    | None ->
      Lwt_sequence.add_l buf t.writes ;
      ()



  let get t =
    match Lwt_sequence.take_opt_l t.writes with

    | Some x ->
      Lwt.return x
                  
    | None ->
      let (p, r) = Lwt.task () in 
      Lwt_sequence.add_r r t.reads;
      p 



  let get_bytes t ct =
    

    let rec aux bufs =
      get t >>= fun buf ->
      let bufs1 = bufs @ [buf] in
      let size = Cstruct.lenv bufs1 in
      
      if size < ct then
        aux bufs1 

      else if size = ct then
        Cstruct.concat bufs1 |> Lwt.return 
      else
        
        let diff = size - ct in
        let (head, rem) = Cstruct.split buf diff in
        let data = Cstruct.concat (bufs @ [head]) in
        put t rem;
        Lwt.return data

    in


    aux []
        

  

      
  

  
end





module Flow_ext (F: Mirage_flow_lwt.S) = struct

  type buffer = F.buffer

  type error = F.error

  type 'a io = 'a F.io

  
  type write_error = F.write_error

  
  type flow = {
    flow: F.flow;
    bufs: Cstruct.t Lwt_sequence.t; 
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

    let rec aux bufs =

      Lwt_sequence.take_opt_l t.bufs |> function

      | Some x when Cstruct.lenv (bufs @ [x]) >= len ->
        let diff = (Cstruct.lenv bufs) - len in
        let (head, rem) = Cstruct.split x diff in
        let _ = Lwt_sequence.add_l rem t.bufs in
        let data = Cstruct.concat (bufs @ [head]) in
        Ok (`Data data) |> Lwt.return 

      | Some x when Cstruct.lenv (bufs @ [x]) < len ->
        aux (bufs @ [x])

      | None ->
        F.read t.flow >>= fun data ->

        begin

          match data with
          | Ok (`Data buf) ->
            let _ = Lwt_sequence.add_r buf t.bufs in
            aux bufs 

          | Ok `Eof -> Lwt.return (Ok `Eof)

          | Error e -> Error e |> Lwt.return 
        end



    in
    aux []



  let create flow =
    let bufs = Lwt_sequence.create () in
    let lock = Lwt_mutex.create () in
    {flow; bufs; lock}



  let read t =
    match (Lwt_sequence.take_opt_l t.bufs) with
    | Some buf -> Ok (`Data buf) |> Lwt.return
    | None -> F.read t.flow 


  
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





