open Header

module type FLOW_EXT = sig
  include Mirage_flow_lwt.S

  val read_bytes: flow -> int -> (buffer Mirage_flow.or_eof, error) Pervasives.result io
end



module type MUXER = sig

  type conn
  type t
  
  module Flow: Mirage_flow_lwt.S


  val flow: t -> Flow.flow

  
  val on_ping: t -> Packet.t -> unit Lwt.t
  val on_data: t -> Packet.t -> unit Lwt.t

  val on_window_update: t -> Packet.t -> unit Lwt.t
  val on_go_away: t -> Packet.t -> unit Lwt.t

  val process: t -> unit Lwt.t
  val send_data: t -> Cstruct.t -> (unit, Flow.write_error) result Lwt.t
  
end

