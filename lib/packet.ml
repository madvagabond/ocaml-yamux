
type t = {header: Header.t; body: Cstruct.t}
         
let make header = {header; body = Cstruct.empty}

let header t = t.header
let body t = t.body 




let data id body =
  let len = Cstruct.len body |> Int32.of_int in 
  let header = Header.Data.make id len in
  {header; body}



let ping nonce =
  Header.Ping.make nonce |> make


let window_update id credit =
    Header.WindowUpdate.make id credit |> make


let go_away code =
  Header.GoAway.make code |> make


let flag t = Header.flag t.header
let id t = Header.id t.header


let encode t =
  let buf = Cstruct.create Header.size in 
  Header.encode buf t.header;
  Cstruct.append buf t.body 
  


let decode buf =
  let open Header in 
  try
    let header = Header.decode buf in
    match (Header.mtype header) with
    | Data ->
      let buf1 = Cstruct.shift buf size in
      let body = Cstruct.sub buf1 0 (Int32.to_int header.len) in
      Ok {header; body}

    | _ ->
      Ok (make header)

  with _ ->
    Error "unable to decode"






module Data = struct
  let make id body = data id body
  let len frame = frame.header.len
 
end


module WindowUpdate = struct
  let make id credit = window_update id credit
  let credit t = t.header.len
end


module GoAway = struct
  let make code = go_away code

  let normal = go_away 0x0l 
  let protocol_error = go_away 0x1l
  let internal_error = go_away 0x02l
    
  let code t = t.header.len 
end


