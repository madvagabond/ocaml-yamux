
type mode = Client | Server
type t = {

  mode: mode;
  max_streams: int;
  keep_alive: bool;
  keep_alive_interval: int64;
  recv_window: int32;
  
}


let default_recv_window = 256 * 1024 |> Int32.of_int

let default_max_streams = 8192

(*remember mirage-time*)


let default_interval = Int64.of_float 6e+9


let make
    ?(max_streams= default_max_streams)
    ?keep_alive:(keep_alive = true)
    ?(keep_alive_interval = default_interval)
    ?(max_window_size = default_recv_window)
    mode =

  {mode; max_streams; keep_alive; keep_alive_interval; recv_window=default_recv_window}


let client ?(max_streams= default_max_streams)
    ?keep_alive:(keep_alive = true)
    ?(keep_alive_interval = default_interval)
    ?(max_window_size = default_recv_window) () =
  let mode = Client in
  {mode; max_streams; keep_alive; keep_alive_interval; recv_window=default_recv_window}



let server ?(max_streams= default_max_streams)
    ?keep_alive:(keep_alive = true)
    ?(keep_alive_interval = default_interval)
    ?(max_window_size = default_recv_window) () =
  let mode = Server in
  {mode; max_streams; keep_alive; keep_alive_interval; recv_window=default_recv_window}





let max_streams t =
  t.max_streams





let recv_window t = t.recv_window
