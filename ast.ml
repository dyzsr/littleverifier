type pure = True | False

let show_pure = function True -> "True" | False -> "False"

type instants =
  | Bottom
  | Empty
  | Instant  of Signals.t
  | Sequence of instants * instants
  | Union    of instants * instants
  | Kleene   of instants

let rec show_instants = function
  | Bottom -> "⏊ "
  | Empty -> "𝝐"
  | Instant i -> Signals.show i
  | Sequence (es1, es2) ->
      Printf.sprintf "(%s · %s)" (show_instants es1) (show_instants es2)
  | Union (es1, es2) ->
      Printf.sprintf "(%s ⋁ %s)" (show_instants es1) (show_instants es2)
  | Kleene es -> Printf.sprintf "(%s)^*" (show_instants es)
;;

type effects = pure * instants

let show_effects (pure, instants) =
  show_pure pure ^ " ⋀ " ^ show_instants instants
;;

type entailment = Entailment of { lhs : effects; rhs : effects }

let show_entailment (Entailment { lhs; rhs }) =
  "\027[36m" ^ show_effects lhs ^ "  ⊑  " ^ show_effects rhs ^ "\027[0m"
;;

type spec = Spec of entailment * bool

let show_spec (Spec (entailment, assertion)) =
  show_entailment entailment ^ " \027[35m: " ^ string_of_bool assertion ^ "\027[0m"
;;
