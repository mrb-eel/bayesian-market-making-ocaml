let rec ensure_directory path =
  if path = "" || path = "." || Sys.file_exists path then ()
  else (
    ensure_directory (Filename.dirname path);
    Unix.mkdir path 0o755)

let escape cell =
  let needs_quotes =
    String.exists (fun character -> character = ',' || character = '"' || character = '\n') cell
  in
  if not needs_quotes then cell
  else
    let buffer = Buffer.create (String.length cell + 8) in
    Buffer.add_char buffer '"';
    String.iter
      (fun character ->
        if character = '"' then Buffer.add_string buffer "\"\""
        else Buffer.add_char buffer character)
      cell;
    Buffer.add_char buffer '"';
    Buffer.contents buffer

let write path rows =
  ensure_directory (Filename.dirname path);
  let channel = open_out path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () ->
      List.iter
        (fun row ->
          output_string channel (String.concat "," (List.map escape row));
          output_char channel '\n')
        rows)

let float_cell value = Printf.sprintf "%.17g" value
let int_cell = string_of_int
