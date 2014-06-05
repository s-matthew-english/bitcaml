open Bitcoin_protocol;;

module Sqlexpr = Sqlexpr_sqlite.Make(Sqlexpr_concurrency.Id);;
module S = Sqlexpr;;

let init_db db = 
  S.execute db
    sqlinit"CREATE TABLE IF NOT EXISTS blockchain(
    id INTEGER PRIMARY KEY,
    hash TEXT COLLATE BINARY NOT NULL,
    height INTEGER NOT NULL,
    cumulative_log_difficulty REAL NOT NULL,
    previous_block INTEGER NOT NULL
  );";
  S.execute db
    sqlinit"CREATE TABLE IF NOT EXISTS orphans(
    id INTEGER PRIMARY KEY,
    hash TEXT COLLATE BINARY NOT NULL,
    previous_block_hash TEXT COLLATE BINARY NOT NULL,
    log_difficulty REAL NOT NULL
  );";
  S.execute db
    sqlinit"CREATE INDEX IF NOT EXISTS hash_index ON blockchain (hash);";
  S.execute db
    sqlinit"CREATE INDEX IF NOT EXISTS previous_block_index ON blockchain (previous_block);";
;;

type insertion_result =
| InsertedIntoBlockchain of int64
| InsertedAsOrphan of int64
| InsertionFailed
| NotInsertedExisted
;;

let block_hash header =
  let header_bitstring = Bitcoin_protocol_generator.bitstring_of_block_header header in
  Bitcoin_crypto.double_sha256 (Bitstring.string_of_bitstring header_bitstring)
;;

let difficulty_1_target = {
  bits_base = 0x00ffff;
  bits_exponent = 0x1d;
}
let float_log_difficulty_1_base = log (float_of_int difficulty_1_target.bits_base);;
let float_log_difficulty_scaland = log 256.0;;
let log_difficulty_of_difficulty_bits bits =
  let float_log_base = log (float_of_int bits.bits_base) in
  let float_exponent_difference = float_of_int (difficulty_1_target.bits_exponent - bits.bits_exponent) in
  float_log_difficulty_1_base -. float_log_base +. float_log_difficulty_scaland *. float_exponent_difference
;;
let difficulty_of_difficulty_bits bits = exp (log_difficulty_of_difficulty_bits bits);;

let retrieve_block hash db =
  S.select_one_maybe db
    sqlc"SELECT @L{id}, @s{hash}, @L{height}, @L{previous_block}, @f{cumulative_log_difficulty} FROM blockchain WHERE hash LIKE %s" hash
;;

let block_id hash db =
  match retrieve_block hash db with
  | None -> None
  | Some (id, _, _, _, _) -> Some id
;;
let block_height hash db =
  match retrieve_block hash db with
  | None -> None
  | Some (_, _, height, _, _) -> Some height
;;
let block_cumulative_log_difficulty hash db =
  match retrieve_block hash db with
  | None -> None
  | Some (_, _, _, _, cld) -> Some cld
;;

let block_exists hash db =
  match retrieve_block hash db with
  | None -> false
  | Some x -> true
;;

let retrieve_latest_mainchain_block db =
  S.select_one_maybe db
    sqlc"SELECT @L{id}, @s{hash}, @L{height}, @L{previous_block}, @f{cumulative_log_difficulty} FROM blockchain ORDER BY height DESC, cumulative_log_difficulty DESC"
;;

let retrieve_orphan hash db =
  S.select_one_maybe db
    sqlc"SELECT @L{id}, @s{hash}, @s{previous_block_hash}, @f{log_difficulty} FROM orphans WHERE hash LIKE %s" hash
;;

let orphan_exists hash db =
  match retrieve_orphan hash db with
  | None -> false
  | Some x -> true
;;

let insert_block_into_blockchain hash previous_block_hash log_difficulty db =
  match block_exists hash db with
  | true -> NotInsertedExisted
  | false ->
    match retrieve_block previous_block_hash db with
    | None -> InsertionFailed
    | Some (previous_block_id, _, previous_block_height, _, previous_block_cld) ->
      let record_id = S.insert db
	sqlc"INSERT INTO blockchain(hash, height, previous_block, cumulative_log_difficulty) VALUES(%s, %L, %L, %f)"
	hash
	(Int64.add previous_block_height 1L)
	previous_block_id
	(previous_block_cld +. log_difficulty)
      in
      InsertedIntoBlockchain record_id
;;
let insert_block_as_orphan hash previous_block_hash log_difficulty db =
  match orphan_exists hash db with
  | true -> NotInsertedExisted
  | false ->
    let record_id = S.insert db
      sqlc"INSERT INTO orphans(hash, previous_block_hash, log_difficulty) VALUES(%s, %s, %f)"
      hash
      previous_block_hash
      log_difficulty
    in
    InsertedAsOrphan record_id
;;

let rec resolve_orphans inserted_hash db =
  let resolve_orphan (id, hash, previous_block_hash, log_difficulty) =
    match insert_block_into_blockchain hash previous_block_hash log_difficulty db with
    | InsertedIntoBlockchain _ ->
      S.execute db
	sqlc"DELETE FROM orphans WHERE id = %L"
	id;
      resolve_orphans hash db
    | _ -> ()
  in
  S.iter db
    resolve_orphan
    sqlc"SELECT @L{id}, @s{hash}, @s{previous_block_hash}, @f{log_difficulty} FROM orphans WHERE previous_block_hash LIKE %s" inserted_hash  
;;
    
let insert_block header db =
  let hash = block_hash header in
  let log_difficulty = log_difficulty_of_difficulty_bits header.block_difficulty_target in
  if not (block_exists hash db) then
    if not (block_exists header.previous_block_hash db) then
      (* orphan block *)
      insert_block_as_orphan hash header.previous_block_hash log_difficulty db
    else (
      (* we know the previous block, we can insert this block into the chain *)
      match insert_block_into_blockchain hash header.previous_block_hash log_difficulty db with
      | InsertedIntoBlockchain i as result ->
	(* we inserted a new block into the blockchain, so we should check whether this resolved any dangling orphans *)
	resolve_orphans hash db;
	result
      | result -> result
    )
  else
    NotInsertedExisted
;;

(* we need a special implementation for this, since no previous block exists for the genesis block *)
let insert_genesis_block db =
  let hash = Config.testnet3_genesis_block_hash in
  let log_difficulty = log_difficulty_of_difficulty_bits Config.testnet3_genesis_block_header.block_difficulty_target in
  if not (block_exists hash db) then
    Some (S.insert db
	    sqlc"INSERT INTO blockchain(hash, height, previous_block, cumulative_log_difficulty) VALUES(%s, %L, %L, %f)"
	    hash
	    0L
	    0L
	    log_difficulty
    )
  else
    None
;;
      
let open_db path =
  let db = S.open_db path in
  init_db db;
  ignore (insert_genesis_block db);
  db
;;
