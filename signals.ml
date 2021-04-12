type event = Present of string

let show_event = function
  | Present name -> name

let compare_event ev1 ev2 : bool = 
  match (ev1, ev2) with 
  | (Present e1, Present e2) -> String.compare e1 e2 == 0


(* To test if the event ev present in instant ins *)
let rec isSigOne ev ins: bool  =
  match ins with 
    [] -> false
  | x :: xs -> if compare_event x ev then true else isSigOne ev xs 
  ;;

let present name = Present name

let is_present = function
  | Present _ -> true


(* Type of signals *)
type t = event list

let show = function
  | [] -> "{}"
  | l  -> "{" ^ String.concat ", " (List.map show_event l) ^ "}"


(* Empty signal *)
let empty = []

let is_empty = function
  | [] -> true
  | _  -> false


let from name = [ present name ]

(* Make new signal from name list *)
let make lst = List.sort_uniq compare lst

(* Merge signals `a` and `b` into a new one *)
let merge a b = List.sort_uniq compare (a @ b)

(* Is `b` included in `a`? *)
let ( |- ) a b = b |> List.fold_left (fun res y -> res && a |> List.exists (( = ) y)) true

(* tests *)
let () =
  assert ([] |- []);
  assert ([ present "A" ] |- []);
  assert ([ present "A" ] |- [ present "A" ]);
  assert ([ present "A"; present "B" ] |- [ present "A" ])
