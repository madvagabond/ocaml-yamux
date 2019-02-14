open Cstruct


type flag =
  | SYN 
  | ACK 
  | FIN
  | RST


val flag_to_int: flag -> int
val flag_of_int: t -> flag option


module Flags: sig

  type t = int 

  val empty: t
  
  val add: t -> flag -> t 
  val has: t -> flag -> bool  
  val contains: t -> flag list -> bool 

end




module Type: sig

  type t =
    | Data
    | Window_Update
    | Ping
    | Go_Away 
  
  val to_int: t -> int
  val of_int: int -> t option 
end


type header
type t = {header: header; body: Cstruct.t option}

val data: ?flags: Flags.t -> id: uint32 -> body: Cstruct.t -> t
val ping: ?flags: Flags.t-> ping_id: int -> t


val window_update: ?flags: Flags.t -> id: uint32 -> credit: uint32 -> t 
val go_away: code: uint32 -> id: uint32 -> t



val packet_type: t -> Type.t 
val stream_id: t -> int32
val flags: t -> Flags.t 

(** Reads length field in packet header, it isn't the total size of packet*)
val length: t -> int32

(** Total size of packet*)
val size: t -> int



type error =
  | Too_short of int
  | Invalid_argument of string
    
val encode: t -> Cstruct.t
val decode: Cstruct.t -> (t, error) result

