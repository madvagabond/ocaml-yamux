
type type_t = 
  | Data
  | Window_Update
  | Ping 
  | Go_Away



type flag =
  | SYN 
  | ACK 
  | FIN
  | RST



type t =  {
  version: int;
  mtype: type_t;
  flags: int;
  stream_id: int32;
  len: int32;
}



val encode: Cstruct.t -> t -> unit
val decode: Cstruct.t -> t

val size: int
val flag: t -> int 
val mtype: t -> type_t


val len: t -> int32
val id: t -> int32

val contains: t -> flag list -> bool

val is_syn: t -> bool
val is_fin: t -> bool
val is_ack: t -> bool

val is_rst: t -> bool




val syn: t -> t
val ack: t -> t

val fin: t -> t
val rst: t -> t


module Ping: sig
  val make: int32 -> t
  val nonce: t -> int32
end


module Data: sig
  val make: int32 -> int32 -> t
  val len: t -> int32
end


module GoAway: sig
  val make: int32 -> t
  val error_code: t -> int32
end


module WindowUpdate: sig
  val make: int32 -> int32 -> t
  val credit: t -> int32
end

