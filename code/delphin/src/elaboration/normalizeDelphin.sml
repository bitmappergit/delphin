(* Delphin Normalize *)
(* Author: Adam Poswolsky *)

structure NormalizeDelphin = 

  struct
    structure D = DelphinIntSyntax
    structure I = IntSyn


    fun normalizeIsParam (D.PVar (ref (SOME P))) = normalizeIsParam P
      | normalizeIsParam P = P

    fun normalizeFor F = normalizeForN (D.whnfF F)
    and normalizeForN (F as D.Top) = F
      | normalizeForN (D.All(Ds, F)) = D.All(map (fn (vis, D) => (vis, normalizeNormalDec D)) Ds, 
					     normalizeFor F)
      | normalizeForN (D.Exists(D, F)) = D.Exists(normalizeNormalDec D, normalizeFor F)
      | normalizeForN (D.Nabla(D, F)) = D.Nabla(normalizeNewDec D, normalizeFor F)
      | normalizeForN (D.FormList Flist) = D.FormList(map normalizeFor Flist)
      | normalizeForN (D.FVar ((_, ref (SOME F), cnstrs), t)) = raise Domain (* not in whnf *)
      | normalizeForN (F as D.FClo _) = raise Domain (* not in whnf *)
      | normalizeForN (F as D.FVar ((G, r, cnstrs), t)) = D.FVar((Whnf.normalizeCtx G, r, cnstrs), Whnf.normalizeSub t) 
                                         (* WARNING: we do NOT normalize the constraints..
					  * but NEITHER does Twelf in whnf.fun
					  * ideally, normalize is called on "evar free" terms
					  * or at least "evar free" with respect to any evars we care about.
					  * !! It appears that if we unify E with V and V contains no epsilons,
					  * then E may still contain EVars.. but I suspect non meaningful ones.
					  *)
														   

    and normalizeCtx (I.Decl (G, D.InstantiableDec D)) = I.Decl(normalizeCtx G, D.InstantiableDec (normalizeNormalDec D))
      | normalizeCtx (I.Decl (G, D.NonInstantiableDec D)) = I.Decl(normalizeCtx G, D.NonInstantiableDec (normalizeNewDec D))
      | normalizeCtx (I.Null) = I.Null

    and normalizeNormalDec (D.NormalDec (sLO, T)) = D.NormalDec (sLO, normalizeTypes T)
    and normalizeNewDec (D.NewDecLF (sO, A)) = D.NewDecLF(sO, Whnf.normalize (A, I.id))
      | normalizeNewDec (D.NewDecWorld (sO, W)) = D.NewDecWorld(sO, W)

    and normalizeTypes (D.LF (isP, A)) = D.LF(normalizeIsParam isP, Whnf.normalize(A, I.id))
      | normalizeTypes (D.Meta(F)) = D.Meta(normalizeFor F)

    fun normalizeExp (E) = (normalizeExpW (D.whnfE E) handle D.SubstFailed => raise Domain)
    and normalizeExpW (E as D.Var (D.Fixed _, _)) = E 
      (* removed BVarMeta
      | normalizeExpW (E as D.Var (D.BVarMeta ((r, F), s), fileInfo)) = D.Var (D.BVarMeta ((r, normalizeFor F), normalizeSub s), fileInfo)
       *)
      | normalizeExpW (E as D.Var (D.BVarLF ((r, A, list, cnstrs), s), fileInfo)) = D.Var (D.BVarLF ((r, Whnf.normalize(A, I.id), list, cnstrs), Whnf.normalizeSub s), fileInfo)
      | normalizeExpW (D.Quote U) = D.Quote (Whnf.normalize(U, I.id))
      | normalizeExpW (E as D.Unit) = D.Unit
      | normalizeExpW (D.Lam (Clist, F, fileInfo)) = D.Lam(map normalizeCase Clist, normalizeFor F, fileInfo)
      | normalizeExpW (D.New (D, E, fileInfo)) = D.New(normalizeNewDec D, normalizeExp E, fileInfo)
      | normalizeExpW (D.App (E1, args)) = D.App (normalizeExp E1, 
						  map (fn (vis, fileInfo, E2) => (vis, fileInfo, normalizeExp E2)) args)
      | normalizeExpW (D.Pair (E1, E2, F)) = D.Pair (normalizeExp E1, normalizeExp E2, normalizeFor F)
      | normalizeExpW (D.ExpList Elist) = D.ExpList (map normalizeExp Elist)
      | normalizeExpW (D.Proj (E, i)) = D.Proj (normalizeExp E, i)
      | normalizeExpW (D.Pop (i, E, fileInfo)) = D.Pop (i, normalizeExp E, fileInfo)
      | normalizeExpW (D.Fix (D, E)) = D.Fix (normalizeNormalDec D, normalizeExp E)
      | normalizeExpW (D.EVar (r, t)) = D.EVar (r, normalizeSub t)
      | normalizeExpW (D.EClo _) = raise Domain (* not in whnf *)

    and normalizeCase (D.Eps (D, C, fileInfo)) = D.Eps(normalizeNormalDec D, normalizeCase C, fileInfo)
      | normalizeCase (D.NewC (D, C, fileInfo)) = D.NewC(normalizeNewDec D, normalizeCase C, fileInfo)
      | normalizeCase (D.PopC (i, C)) = D.PopC(i, normalizeCase C)
      | normalizeCase (D.Match(pats, E2)) = D.Match(map (fn (vis, E1) => (vis, normalizeExp E1)) pats, 
						    normalizeExp E2)
      (*
      | normalizeCase (D.MatchAnd (visible, E1, C)) = D.MatchAnd(visible, normalizeExp E1, normalizeCase C)
	*)

    and normalizeSub (D.Shift t) = D.Shift (normalizeSub t)
      | normalizeSub (D.Dot(Ft, t)) = D.Dot(normalizeFront Ft, normalizeSub t)
      | normalizeSub (D.id) = D.id

    and normalizeFront (D.Prg E) = D.Prg (normalizeExp E)
      | normalizeFront (D.Undef) = D.Undef
      
      

    (* ***************************************************************************** *)

    (* Check if an expression has any uninstantiated Variables
     * This is used in opsem to see if the unification was successful.
     * Additionally, it is used in convert to check if there are any leftover Vars
     *)     
    (* **************************************************************************** *)

    fun LFhasVarsSub (s as I.Shift _) = false
      | LFhasVarsSub (I.Dot (I.Exp U, s)) = (LFhasVarsExp U) orelse (LFhasVarsSub s)
      | LFhasVarsSub (I.Dot (I.Block B, s)) = (LFhasVarsBlock B) orelse (LFhasVarsSub s)
      | LFhasVarsSub (I.Dot (_, s)) = LFhasVarsSub s

    and LFhasVarsExp (E as I.Uni _) = false
      | LFhasVarsExp (I.Pi ((D,P), U)) = (LFhasVarsDec D) orelse (LFhasVarsExp U)
      | LFhasVarsExp (I.Root (H, S)) = (LFhasVarsHead H) orelse (LFhasVarsSpine S)
      | LFhasVarsExp (I.Redex (E, S)) = (LFhasVarsExp E) orelse (LFhasVarsSpine S)
      | LFhasVarsExp (I.Lam (D, E)) = (LFhasVarsDec D) orelse (LFhasVarsExp E)
      | LFhasVarsExp (I.EVar (ref (SOME E), _, _, _)) = (LFhasVarsExp E) (* We don't bother checking the type. even if there are EVars there it doesn't matter... *)
      | LFhasVarsExp (I.EVar X) = true
      | LFhasVarsExp (I.EClo (E, s)) = (LFhasVarsExp E) orelse (LFhasVarsSub s)
      | LFhasVarsExp (I.AVar (ref (SOME E))) = LFhasVarsExp E
      | LFhasVarsExp (I.AVar _) = true
      | LFhasVarsExp (I.FgnExp csfe) = false 

    and LFhasVarsHead (I.Proj (B, i)) = LFhasVarsBlock B
      | LFhasVarsHead (I.FVar (name, isP, E, s)) = false (* FVars are ok *)
      | LFhasVarsHead (I.FgnConst (c, condec)) = false 
      | LFhasVarsHead H = false

    and LFhasVarsSpine (I.Nil) = false
      | LFhasVarsSpine (I.App (E, S)) = (LFhasVarsExp E) orelse (LFhasVarsSpine S)
      | LFhasVarsSpine (I.SClo (S, t)) = (LFhasVarsSpine S) orelse (LFhasVarsSub t)

    and LFhasVarsBlock (B as I.Bidx _) = false
      | LFhasVarsBlock (I.LVar (ref (SOME L), sk, (l, t))) = false
      | LFhasVarsBlock (I.LVar _) = true
      | LFhasVarsBlock (I.Inst Elist) = foldr (fn (E,b) => b orelse (LFhasVarsExp E)) false Elist


    and LFhasVarsDec (I.Dec (sO, E)) = LFhasVarsExp E
      | LFhasVarsDec (I.BDec (sO, (c, t))) = LFhasVarsSub t
      | LFhasVarsDec D = false


    fun hasVarsIsP (D.Existential) = false
      | hasVarsIsP (D.Param) = false
      | hasVarsIsP (D.PVar (ref (SOME P))) = hasVarsIsP P
      | hasVarsIsP (D.PVar r) = true

    fun hasVarsFor F = hasVarsForN (D.whnfF F)
    and hasVarsForN (D.Top) = false
      | hasVarsForN (D.All([], F)) = (hasVarsFor F)
      | hasVarsForN (D.All(((vis,D)::Ds), F)) = (hasVarsNormalDec D) orelse (hasVarsFor (D.All(Ds, F)))
      | hasVarsForN (D.Exists(D, F)) = (hasVarsNormalDec D) orelse (hasVarsFor F)
      | hasVarsForN (D.Nabla(D, F)) = (hasVarsNewDec D) orelse (hasVarsFor F)
      | hasVarsForN (D.FormList Flist) = foldr (fn (F,b) => b orelse (hasVarsFor F)) false Flist
      | hasVarsForN (D.FVar ((_, ref (SOME F), cnstrs), t)) = raise Domain (* not in whnf *)
      | hasVarsForN (D.FClo _) = raise Domain (* not in whnf *)
      | hasVarsForN (D.FVar ((G, r, cnstrs), t)) = true

    and hasVarsCtx (I.Decl (G, D.InstantiableDec D)) = (hasVarsCtx G) orelse (hasVarsNormalDec D)
      | hasVarsCtx (I.Decl (G, D.NonInstantiableDec D)) = (hasVarsCtx G) orelse (hasVarsNewDec D)
      | hasVarsCtx (I.Null) = false

    and hasVarsNormalDec (D.NormalDec (sLO, T)) = hasVarsTypes T
    and hasVarsNewDec (D.NewDecLF (sO, A)) = LFhasVarsExp A
      | hasVarsNewDec (D.NewDecWorld (sO, W)) = false

    and hasVarsTypes (D.LF (isP, A)) = (hasVarsIsP isP) orelse (LFhasVarsExp A)
      | hasVarsTypes (D.Meta(F)) = (hasVarsFor F)

    fun hasVarsExp E = (hasVarsExpW (D.whnfE E) handle D.SubstFailed => raise Domain )
    and hasVarsExpW (D.Var (D.Fixed _, _)) = false
      | hasVarsExpW (D.Var _) = true
      | hasVarsExpW (D.Quote U) = (LFhasVarsExp U)
      | hasVarsExpW (E as D.Unit) = false
      | hasVarsExpW (D.Lam (Clist, F, fileInfo)) = foldr (fn (C,b) => b orelse (hasVarsCase C)) (hasVarsFor F) Clist
      | hasVarsExpW (D.New (D, E, fileInfo)) = (hasVarsNewDec D) orelse (hasVarsExp E)
      | hasVarsExpW (D.App (E1, [])) = (hasVarsExp E1)
      | hasVarsExpW (D.App (E1, ((vis,fileInfo,E2)::args))) = (hasVarsExp E2) orelse (hasVarsExp (D.App (E1, args)))
      | hasVarsExpW (D.Pair (E1, E2, F)) = (hasVarsExp E1) orelse (hasVarsExp E2) orelse (hasVarsFor F)
      | hasVarsExpW (D.ExpList Elist) = foldr (fn (E,b) => b orelse (hasVarsExp E)) false Elist
      | hasVarsExpW (D.Proj (E, i)) = hasVarsExp E
      | hasVarsExpW (D.Pop (i, E, fileInfo)) = hasVarsExp E
      | hasVarsExpW (D.Fix (D, E)) = (hasVarsNormalDec D) orelse (hasVarsExp E)
      | hasVarsExpW (D.EVar (r, t)) = true
      | hasVarsExpW (D.EClo _) = raise Domain (* not in whnf *)

    and hasVarsCase (D.Eps (D, C, fileInfo)) = (hasVarsNormalDec D) orelse (hasVarsCase C)
      | hasVarsCase (D.NewC (D, C, fileInfo)) = (hasVarsNewDec D) orelse (hasVarsCase C)
      | hasVarsCase (D.PopC (i, C)) = (hasVarsCase C)
      | hasVarsCase (D.Match([], E2)) = (hasVarsExp E2)
      | hasVarsCase (D.Match((vis,E1)::pats, E2)) = (hasVarsExp E1) orelse (hasVarsCase (D.Match(pats, E2)))
      (*
      | hasVarsCase (D.MatchAnd (visible, E1, C)) = (hasVarsExp E1) orelse (hasVarsCase C)
	*)


    and hasVarsSub (D.Shift t) = (hasVarsSub t)
      | hasVarsSub (D.Dot(Ft, t)) = (hasVarsFront Ft) orelse (hasVarsSub t)
      | hasVarsSub (D.id) = false

    and hasVarsFront (D.Prg E) = (hasVarsExp E)
      | hasVarsFront (D.Undef) = false



   (* Check only for FVars *)
    fun hasFVarsFor F = hasFVarsForN (D.whnfF F)
    and hasFVarsForN (D.Top) = false
      | hasFVarsForN (D.All([], F)) = (hasFVarsFor F)
      | hasFVarsForN (D.All((vis,D)::Ds, F)) = (hasFVarsNormalDec D) orelse (hasFVarsFor (D.All(Ds, F)))
      | hasFVarsForN (D.Exists(D, F)) = (hasFVarsNormalDec D) orelse (hasFVarsFor F)
      | hasFVarsForN (D.Nabla(D, F)) = (hasFVarsNewDec D) orelse (hasFVarsFor F)
      | hasFVarsForN (D.FormList Flist) = foldr (fn (F,b) => b orelse (hasFVarsFor F)) false Flist
      | hasFVarsForN (D.FVar ((_, ref (SOME F), cnstrs), t)) = raise Domain (* not in whnf *)
      | hasFVarsForN (D.FClo _) = raise Domain (* not in whnf *)
      | hasFVarsForN (D.FVar ((G, r, cnstrs), t)) = true

    and hasFVarsCtx (I.Decl (G, D.InstantiableDec D)) = (hasFVarsCtx G) orelse (hasFVarsNormalDec D)
      | hasFVarsCtx (I.Decl (G, D.NonInstantiableDec D)) = (hasFVarsCtx G) orelse (hasFVarsNewDec D)
      | hasFVarsCtx (I.Null) = false

    and hasFVarsNormalDec (D.NormalDec (sLO, T)) = hasFVarsTypes T
    and hasFVarsNewDec (D.NewDecLF (sO, A)) = false
      | hasFVarsNewDec (D.NewDecWorld (sO, W)) = false

    and hasFVarsTypes (D.LF (isP, A)) = false
      | hasFVarsTypes (D.Meta(F)) = (hasFVarsFor F)

    fun hasFVarsExp E = (hasFVarsExpW (D.whnfE E) handle D.SubstFailed => raise Domain )
    and hasFVarsExpW (D.Var (D.Fixed _, _)) = false
      | hasFVarsExpW (D.Var _) = false (* BoundVars vars.. *)
      | hasFVarsExpW (D.Quote U) = false
      | hasFVarsExpW (E as D.Unit) = false
      | hasFVarsExpW (D.Lam (Clist, F, fileInfo)) = foldr (fn (C,b) => b orelse (hasFVarsCase C)) (hasFVarsFor F) Clist
      | hasFVarsExpW (D.New (D, E, fileInfo)) = (hasFVarsNewDec D) orelse (hasFVarsExp E)
      | hasFVarsExpW (D.App (E1, [])) = (hasFVarsExp E1)
      | hasFVarsExpW (D.App (E1, ((vis,fileInfo,E2)::args))) = (hasFVarsExp E2) orelse (hasFVarsExp (D.App (E1, args)))
      | hasFVarsExpW (D.Pair (E1, E2, F)) = (hasFVarsExp E1) orelse (hasFVarsExp E2) orelse (hasFVarsFor F)
      | hasFVarsExpW (D.ExpList Elist) = foldr (fn (E,b) => b orelse (hasFVarsExp E)) false Elist
      | hasFVarsExpW (D.Proj (E, i)) = hasFVarsExp E
      | hasFVarsExpW (D.Pop (i, E, fileInfo)) = hasFVarsExp E
      | hasFVarsExpW (D.Fix (D, E)) = (hasFVarsNormalDec D) orelse (hasFVarsExp E)
      | hasFVarsExpW (D.EVar (r, t)) = false
      | hasFVarsExpW (D.EClo _) = raise Domain (* not in whnf *)

    and hasFVarsCase (D.Eps (D, C, fileInfo)) = (hasFVarsNormalDec D) orelse (hasFVarsCase C)
      | hasFVarsCase (D.NewC (D, C, fileInfo)) = (hasFVarsNewDec D) orelse (hasFVarsCase C)
      | hasFVarsCase (D.PopC (i, C)) = (hasFVarsCase C)
      | hasFVarsCase (D.Match([], E2)) = (hasFVarsExp E2)
      | hasFVarsCase (D.Match((vis,E1)::pats, E2)) = (hasFVarsExp E1) orelse (hasFVarsCase (D.Match(pats, E2)))
      (*
      | hasFVarsCase (D.MatchAnd (_, E1, C)) = (hasFVarsExp E1) orelse (hasFVarsCase C)
	*)

    and hasFVarsSub (D.Shift t) = (hasFVarsSub t)
      | hasFVarsSub (D.Dot(Ft, t)) = (hasFVarsFront Ft) orelse (hasFVarsSub t)
      | hasFVarsSub (D.id) = false

    and hasFVarsFront (D.Prg E) = (hasFVarsExp E)
      | hasFVarsFront (D.Undef) = false
      


  end 