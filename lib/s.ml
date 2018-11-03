open Header





module type FLOW_EXT = sig
  include Mirage_flow_lwt.S

  val read_bytes: flow -> int -> (buffer Mirage_flow.or_eof, error) Pervasives.result io
end


