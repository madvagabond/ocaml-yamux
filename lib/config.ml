
type t = {
  max_streams: int;
  keep_alive: bool;
  keep_alive_interval: int64;
  max_window_size: int;
}


let default_window_size = 200 * 1024

let default_capacity = 1024 * 1024

let default_max_streams = 8192

(*remember mirage-time*)


let default_interval = Int64.of_float 6e+9
  
let make
    ?(max_streams= default_max_streams)
    ?keep_alive:(keep_alive = true)
    ?(keep_alive_interval = default_interval)
    ?(max_window_size = default_window_size)
    () =

  {max_streams; keep_alive; keep_alive_interval; max_window_size}

  
