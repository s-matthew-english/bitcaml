let print_hex_string s line_length =
  let hex_iterator index c =
    if (index > 0) && (line_length > 0) && ((index mod line_length) = 0) then print_newline ();
    Printf.printf "%02x " (int_of_char c);
  in
  String.iteri hex_iterator s;
;;

let reverse_string s =
  let rec reverse_string_acc s acc index length =
    if index >= length
    then acc
    else reverse_string_acc s ((String.make 1 s.[index]) ^ acc) (index+1) length
  in
  reverse_string_acc s "" 0 (String.length s)
;;

let bytestring_of_int64 i bytesize =
  let rec bytestring_of_int_ i acc byte_index =
    let shift_distance = 8 * byte_index in
    let mask = Int64.shift_left 0xffL shift_distance in
    let masked_int = Int64.logand i mask in
    let shifted_int = Int64.shift_right_logical masked_int shift_distance in
    let byte_char = Char.chr (Int64.to_int shifted_int) in
    let new_acc = acc ^ (String.make 1 byte_char) in
    match byte_index with
    | 0 -> new_acc
    | byte_index -> bytestring_of_int_ i new_acc (byte_index-1)
  in
  bytestring_of_int_ i "" (bytesize-1)
;;
let le_bytestring_of_int64 i bytesize =
  reverse_string (bytestring_of_int64 i bytesize)
;;


let unix_tm_of_int64 timestamp = 
  Unix.localtime (Int64.to_float timestamp)
;;
let int64_of_unix_tm unix_tm = 
  let timestamp, _ = Unix.mktime unix_tm in
  Int64.of_float timestamp
;;
let string_of_unix_tm time =
  Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d" (time.Unix.tm_year + 1900) (time.Unix.tm_mon + 1) time.Unix.tm_mday time.Unix.tm_hour time.Unix.tm_min time.Unix.tm_sec
;;
let string_of_timestamp timestamp =
  string_of_unix_tm (unix_tm_of_int64 timestamp)
;;

let string_from_zeroterminated_string zts =
  let string_length =
    try
      String.index zts '\x00'
    with Not_found -> 12
  in
  String.sub zts 0 string_length
;;
let zeropad_string_to_length s length =
  s ^ (String.make (length - (String.length s)) '\x00')
;;

let int_of_bool = function
  | false -> 0
  | true -> 1
;;










