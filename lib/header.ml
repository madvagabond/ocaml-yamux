

[%%cenum
   
type type_t = 
  | Data [@id 0x0]
  | Window_Update [@id 0x1]
  | Ping [@id 0x02]
  | Go_Away [@id 0x03]

[@@uint8_t]

]



[%%cenum  


    type flag =

      | NULL [@id 0x0]
      | SYN [@id 0x1]
      | ACK [@id 0x2]
      | FIN [@id 0x4]
      | RST [@id 0x8]

      [@@uint16_t]

]




[%%cstruct 

  type header_t = {
    version: uint8_t;
    mtype: uint8_t;
    flags: uint16_t;
    stream_id: uint32_t;
    len: uint32_t
  } [@@big_endian]

]


type t =  {
  version: int;
  mtype: type_t;
  flag: flag;
  stream_id: int32;
  len: int32;
}


let get_opt o =
  match o with
  | Some x -> x
  | _ -> raise Not_found




let size = sizeof_header_t 


let encode buf t =
  set_header_t_len buf t.len;
  set_header_t_flags buf (flag_to_int t.flag);
  set_header_t_mtype buf (type_t_to_int t.mtype);
  set_header_t_stream_id buf t.stream_id;
  set_header_t_version buf t.version;;


  


let decode buf =

  let len = get_header_t_len buf in
  let flag = get_header_t_flags buf |> int_to_flag |> get_opt in
  let mtype = get_header_t_mtype buf |> int_to_type_t |> get_opt  in

  let stream_id = get_header_t_stream_id buf in
  let version = get_header_t_version buf in
  {len; flag; mtype; version; stream_id}


let flag t = t.flag
let id t = t.stream_id

let len t = t.len
let mtype t = t.mtype

let syn t = {t with flag = SYN}
let ack t = {t with flag = ACK}

let fin t = {t with flag = FIN}
let rst t = {t with flag = RST}


let contains t other =
  let i = flag_to_int t.flag in
  (i land other) = other


module Ping = struct
  let make nonce =
    {version=0; mtype=Ping; flag=NULL; len=nonce; stream_id=0l}

  let nonce t =
    t.len

end




module Data = struct
  let make id len =
    {version=0; mtype=Data; flag=NULL; len; stream_id=id}

  let len t = t.len

end 


module WindowUpdate = struct
  let make id credit =
    {version=0; mtype=Window_Update; flag=NULL; len=credit; stream_id=id}

  let credit t = t.len 
end





module GoAway = struct
  let make code =
    {version=0; mtype=Go_Away; flag=NULL; len=code; stream_id=0l}

  let error_code t = t.len 

end 

