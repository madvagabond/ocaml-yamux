type input = Frame.t
type output = Frame.t

open Frame 

type error = Invalid_type


let decode buf =

  let open Type in 
  
  let complete () =
    
    let (header, nxt) = Cstruct.split buf sizeof_header in
    let msg_type =  get_header_mtype header |> Type.of_int in


    
    let len = get_header_len header in

    let len_i = len |> Int32.to_int in
    
    let check_size () =
      Cstruct.len nxt >= len_i
    in



    

    match msg_type with


    
    | Some Data when check_size () ->
      let (body, rest) = Cstruct.split nxt len_i in
      let frame = {header; body} in 
      let state = Mirage_codec.Done (frame, rest) in
      Ok state



    | Some Data ->
      Ok( Mirage_codec.Partial )




    | Some _ ->
      let body = Cstruct.empty in 
      let out = Mirage_codec.Done ({header; body}, nxt) in
      Ok out

    | None -> Error Invalid_type 
  in

  

  if (Cstruct.len buf) >= sizeof_header then
    complete ()
  else
    Ok Mirage_codec.Partial




 




                
let encode t =
  Cstruct.append t.header t.body 






