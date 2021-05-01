type subhistory = {
  first : Inference.Set.elem option;
  mutable iterations : (string * Ast.simple_entailment) list;
  mutable unfoldings : subhistory list;
  mutable constraints : Ast.pi option;
  mutable verdict : bool option;
}

let add_iteration (label, es) hist =
  (* Printf.printf "%s :: %s\n" label (Ast.show_entailment es); *)
  hist.iterations <- (label, es) :: hist.iterations


let add_unfolding sub hist = hist.unfoldings <- sub :: hist.unfoldings

let set_constraints constrnt hist = hist.constraints <- Some constrnt

let set_verdict verdict hist = hist.verdict <- Some verdict

let show_subhistory hist ~verbose =
  let rec aux spaces prefix hist =
    let first = ref true in
    let get_prefix () =
      if !first then (
        first := false;
        prefix)
      else
        spaces
    in
    let print name message =
      Printf.sprintf "%s%10s %s│%s  %s%s%s" Colors.yellow name Colors.magenta Colors.reset
        (get_prefix ()) message Colors.reset
    in
    let show_first =
      match hist.first with
      | None        -> fun x -> x
      | Some (i, t) ->
          let first =
            Printf.sprintf "%s%s, %s%s" Colors.magenta (Signals.show i) Colors.yellow
              (match t with
              | None   -> "_"
              | Some t -> Ast.show_term t)
          in
          List.cons (print "-" first)
    in
    let show_iterations =
      if verbose then
        List.fold_right
          (fun (name, entailment) acc -> print name (Ast.show_simple_entailment entailment) :: acc)
          hist.iterations
      else
        List.cons
          (let name, entailment = List.hd hist.iterations in
           print name (Ast.show_simple_entailment entailment))
    in
    let show_unfoldings =
      List.fold_right List.cons
        (List.mapi
           (fun i x ->
             let prefix' = get_prefix () in
             if i = 0 then
               aux (prefix' ^ "   ") (prefix' ^ "└──") x
             else
               aux (prefix' ^ "│  ") (prefix' ^ "├──") x)
           hist.unfoldings)
    in
    let show_constraints =
      match hist.constraints with
      | None      -> fun x -> x
      | Some True -> fun x -> x
      | Some con  -> List.cons (print "CHECK" (Ast.show_pi con))
    in
    let show_verdict =
      match hist.verdict with
      | None         -> fun x -> x
      | Some verdict ->
          List.cons
            (print "VERDICT"
               (Colors.blue ^ Colors.italic
               ^ (if verdict then "SUCCESS" else "FAILURE")
               ^ Colors.reset))
    in
    [] |> show_first |> show_iterations |> show_unfoldings |> show_constraints |> show_verdict
    |> List.rev |> String.concat "\n"
  in
  aux "" "" hist


type history = subhistory list list

let show_history hist ~verbose =
  let _, output =
    List.fold_left
      (fun (i, acc) l ->
        ( i + 1,
          let _, subh =
            List.fold_left
              (fun (j, acc2) sub ->
                ( j + 1,
                  let sub = show_subhistory sub ~verbose in
                  let label =
                    Printf.sprintf "%s%sSub-case %d-%d%s" Colors.cyan Colors.italic i j Colors.reset
                  in
                  sub :: label :: acc2 ))
              (1, []) l
          in
          List.rev subh :: acc ))
      (1, []) hist
  in
  String.concat "\n" (List.concat (List.rev output))


let show_verification ~case ~no ~verdict ~verbose ~history =
  Colors.reset
  ^ Printf.sprintf "%sCase %-5d :%s  %s\n" Colors.bold no Colors.reset (Ast.show_specification case)
  ^ Printf.sprintf "%sVerify     :%s\n%s\n" Colors.bold Colors.reset (show_history history ~verbose)
  ^ Printf.sprintf "%sVerdict    :%s  %s\n" Colors.bold Colors.reset verdict


let verify_simple_entailment (Ast.SimpleEntail { lhs; rhs }) =
  let rec aux ctx first_opt (lhs : Ast.simple_effects) rhs =
    let hist =
      {
        first =
          (match first_opt with
          | None        -> None
          | Some (i, t) -> Some (i, t));
        iterations = [];
        unfoldings = [];
        constraints = None;
        verdict = None;
      }
    in
    let bot_lhs (_, es1) = es1 = Ast.Bottom
    and bot_rhs (_, es2) = es2 = Ast.Bottom
    and disprove (_, es1) (_, es2) = Inference.nullable es1 && not (Inference.nullable es2)
    and reoccur ctx (_, es1) (_, es2) = es1 = es2 || Proofctx.exists_entail es1 es2 ctx
    and unfold ctx (pi1, es1) (pi2, es2) =
      ctx |> Proofctx.add_entail es1 es2;
      let firsts = Inference.first ctx es1 in
      let empty = Inference.Set.is_empty firsts in
      let verdict =
        firsts
        |> Inference.Set.for_all (fun x ->
               let es1 = Inference.partial_deriv ctx x es1 in
               let es2 = Inference.partial_deriv ctx x es2 in
               let verdict, sub_hist = aux (ctx |> Proofctx.clone) (Some x) (pi1, es1) (pi2, es2) in
               hist |> add_unfolding sub_hist;
               verdict)
      in
      (verdict, empty)
    and normal lhs rhs =
      let lhs =
        Utils.fixpoint ~f:Ast_utils.normalize
          ~fn_iter:(fun es -> hist |> add_iteration ("NORM-LHS", SimpleEntail { lhs = es; rhs }))
          lhs
      in
      let rhs =
        Utils.fixpoint ~f:Ast_utils.normalize
          ~fn_iter:(fun es -> hist |> add_iteration ("NORM-RHS", SimpleEntail { lhs; rhs = es }))
          rhs
      in
      (lhs, rhs)
    in
    let check () =
      let verdict, constrnt = ctx |> Proofctx.check_imply in
      hist |> set_constraints constrnt;
      hist |> set_verdict verdict;
      verdict
    in
    (* Verify *)
    let lhs, rhs = normal lhs rhs in
    let verdict =
      if bot_lhs lhs then (
        hist |> add_iteration ("Bot-LHS", SimpleEntail { lhs; rhs });
        check ())
      else if bot_rhs rhs then (
        hist |> add_iteration ("Bot-RHS", SimpleEntail { lhs; rhs });
        false)
      else if disprove lhs rhs then (
        hist |> add_iteration ("DISPROVE", SimpleEntail { lhs; rhs });
        false)
      else if reoccur ctx lhs rhs then (
        hist |> add_iteration ("REOCCUR", SimpleEntail { lhs; rhs });
        check ())
      else (
        hist |> add_iteration ("UNFOLD", SimpleEntail { lhs; rhs });
        let verdict, empty = unfold ctx lhs rhs in
        if verdict && empty then
          check ()
        else
          verdict)
    in
    (verdict, hist)
  in
  let ctx = Proofctx.make () in
  (* let lhs = Ast_utils.trim_irrelevant_pi lhs in
     let rhs = Ast_utils.trim_irrelevant_pi rhs in *)
  let rhs = Ast_utils.disambiguate_simple_effects rhs in
  let () =
    let pre, _ = lhs in
    let post, _ = rhs in
    ctx |> Proofctx.add_precond pre;
    ctx |> Proofctx.add_postcond post
  in
  aux ctx None lhs rhs


let verify_entailment (Ast.Entail { lhs; rhs }) =
  let verdict, history =
    List.fold_left
      (fun (acc_verdict, acc_history) lhs ->
        if not acc_verdict then
          (false, acc_history)
        else
          let verdict, history =
            List.fold_left
              (fun (acc2_verdict, acc2_history) rhs ->
                if acc2_verdict then
                  (true, acc2_history)
                else
                  let verdict, history = verify_simple_entailment (Ast.SimpleEntail { lhs; rhs }) in
                  (verdict, history :: acc2_history))
              (false, []) rhs
          in
          (verdict, List.rev history :: acc_history))
      (true, []) lhs
  in
  (verdict, List.rev history)


let verify_specification (Ast.Spec (entailment, assertion)) =
  let verdict, history = verify_entailment entailment in
  if verdict == assertion then
    (true, Colors.green ^ "Correct" ^ Colors.reset, history)
  else
    ( false,
      Printf.sprintf "%sIncorrect%s  got: %s%B%s  expect: %s%B%s" Colors.red Colors.reset
        Colors.blue verdict Colors.reset Colors.blue assertion Colors.reset,
      history )
