open Cstruct

type error =
  | Too_short of int
  | Invalid_argument of string


[%%cenum  
    type flag =

      | SYN [@id 0x1]
      | ACK [@id 0x2]
      | FIN [@id 0x4]
      | RST [@id 0x8]

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
      | Window_Update [@id 0x01]
      | Ping [@id 0x2]
      | Go_Away [@id 0x3]
      
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
         

let make_header ~message_type ~flags ~id ~len =
  let header = Cstruct.create sizeof_header in
  let _ = set_header_len header len in
  let _ = set_header_flags header flags in
  

  let _ = set_header_mtype header (Type.to_int message_type) in
  let _ = set_header_stream_id header id in 

  let _  = set_header_version header 1 in
  header


let data ?flags:(flags=Flags.empty) ~id ~body =
  let header =
    make_header ~message_type: Data ~flags ~id ~len: (Cstruct.len body |> Int32.of_int)
  in

  {header; body}



let ping ?flags:(flags=Flags.empty) ~ping_id =

  let header = make_header
      ~message_type: Ping
      ~flags
      ~id: 0l
      ~len: ping_id  
  in

  let body = Cstruct.empty in

  {header; body}


let go_away ~code =
  let header = make_header 
      ~message_type: Go_Away
      ~flags: Flags.empty 
      ~id: 0l
      ~len: code

  in

  {header; body=Cstruct.empty}



let window_update ?flags:(flags=Flags.empty) ~id ~credit =
  let header = make_header
      ~message_type: Window_Update
      ~flags
      ~id
      ~len: credit
  in

  let body = Cstruct.empty in
  {header; body}




let packet_type t =
  match (get_header_mtype t.header |> Type.of_int ) with
  | Some(x) -> x
  | None -> raise (Invalid_argument "No such packet type")



let stream_id t =
  get_header_stream_id t.header

let flags t =
  get_header_flags t.header 


let length t =
  get_header_len t.header

let body t =
  t.body



let decode buf =
  let (header, body) = Cstruct.split buf sizeof_header in
  {header; body}


let encode t =
  Cstruct.append t.header t.body 
