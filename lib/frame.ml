open Cstruct


type error =
  | Too_short of int
  | Invalid_argument of string


[%%cenum  
    type flag =

      | Syn [@id 0x1]
      | Ack [@id 0x2]
      | Fin [@id 0x4]
      | Rst [@id 0x8]

      [@@uint16_t]
  ]


let flag_of_int = int_to_flag


module Flags = struct
  type t = int

  let empty = 0

  let add t flag =
    t lor (flag_to_int flag)
  
  let has t flag =
    let i = flag_to_int flag in
    (t land i) = i 
  
  let intersects l r =
    (l land r) = r  

  let of_list l =
    List.fold_left (fun acc x -> add acc x) empty l
      
  let union l r =
    l lor r


  
  
end 


module Type = struct
  [%%cenum 
    type t =
      | Data [@id 0x0]
      | Window_update [@id 0x01]
      | Ping [@id 0x2]
      | Go_away [@id 0x3]
      
    [@@uint8_t]
  ]


  let to_int = t_to_int
  let of_int = int_to_t
    
end




[%%cstruct 

  type header = {
    version: uint8_t;
    mtype: uint8_t;
    flags: uint16_t;
    stream_id: uint32_t;
    len: uint32_t
  } [@@big_endian]

]


type header = Cstruct.t
                
type t = {header: header; body: Cstruct.t}




let encode_header dst msg_type flags stream_id len =
  let _ = set_header_mtype dst msg_type in 
  let _ = set_header_version dst 1 in
  let _ = set_header_len dst len in
  let _ = set_header_flags dst flags in
  set_header_stream_id dst stream_id




let decode_header src =
  Cstruct.sub src 0 sizeof_header


let body src =
  Cstruct.sub src sizeof_header (Cstruct.len src)


let len src =
  get_header_len src.header


let stream_id src =
  get_header_stream_id src

let flags src =
  get_header_flags src







let make_header msg_type flags id len =
  let dst = Cstruct.create sizeof_header in
  let _ = encode_header dst (Type.to_int msg_type) flags id len in
  dst



let data ?flags:(flags=Flags.empty) id body =
  let header = make_header Type.Data flags id (Cstruct.len body |> Int32.of_int) in
  {header; body}



  


let ping ?flags:(flags=Flags.empty) id =

  let open Type in 
  let header = make_header
      Ping
      flags
      0l 
      id  
  in

  let body = Cstruct.empty in

  {header; body}


let go_away code =
  let open Type in 
  let header = make_header 
      Go_away
      Flags.empty 
      0l
      code

  in

  {header; body=Cstruct.empty}



let window_update ?flags:(flags=Flags.empty) id credit =
  let header = make_header
      Window_update
      flags
      id
      credit
  in

  let body = Cstruct.empty in
  {header; body}




let frame_type t =
  match (get_header_mtype t.header |> Type.of_int ) with
  | Some x  -> x
  | None -> raise (Invalid_argument "No such packet type")



let stream_id t =
  get_header_stream_id t.header

let flags t =
  get_header_flags t.header 


let length t =
  get_header_len t.header

let body t =
  t.body

let header t = t.header


