(* Type Checking *)
(* Author: Carsten Schuermann *)

functor TypeCheckLF ((*! structure IntSyn' : INTSYN !*)
		   structure Conv : CONV
		   (*! sharing Conv.IntSyn = IntSyn' !*)
		   structure Whnf : WHNF
		   (*! sharing Whnf.IntSyn = IntSyn'  !*)
                   structure Names : NAMES
		   (*! sharing Names.IntSyn = IntSyn' !*)
		   structure Print : PRINT
		   (*! sharing Print.IntSyn = IntSyn' !*)
		       )
  : TYPECHECKLF =
struct
  (*! structure IntSyn = IntSyn' !*)
  exception Error of string

  local 
    structure I = IntSyn

    (* for debugging purposes *)
    fun subToString (G, I.Dot (I.Idx (n), s)) =
          Int.toString (n) ^ "." ^ subToString (G, s)
      | subToString (G, I.Dot (I.Exp (U), s)) =
	  "(" ^ Print.expToString (G, U) ^ ")." ^ subToString (G, s)
      | subToString (G, I.Dot (I.Block (L as I.LVar _), s)) =
	  LVarToString (G, L) ^ "." ^ subToString (G, s)
      | subToString (G, I.Shift(n)) = "^" ^ Int.toString (n)
      | subToString _ = raise Domain

    and LVarToString (G, I.LVar (ref (SOME B), sk, (l, t))) =
          LVarToString (G, I.blockSub (B, sk))
					(* whnf for Blocks ? Sun Dec  1 11:38:17 2002 -cs *)
      | LVarToString (G, I.LVar (ref NONE, sk, (cid, t))) =
	  "#" ^ I.conDecName (I.sgnLookup cid) ^ "["
	  ^ subToString (G, t) ^ "]"

      | LVarToString _ = raise Domain
	  
    (* some well-formedness conditions are assumed for input expressions *)
    (* e.g. don't contain "Kind", Evar's are consistently instantiated, ... *)

    (* checkExp (G, (U, s1), (V2, s2)) = ()

       Invariant: 
       If   G |- s1 : G1   
       and  G |- s2 : G2    G2 |- V2 : L
       returns () if there is a V1 s.t.
	    G1 |- U : V1
       and  G  |- V1 [s1] = V2 [s2] : L
       otherwise exception Error is raised
    *)
    fun checkExp (G, Us, Vs) =
	let 
	  val Us' = inferExp (G, Us)
	in
	  (* Changed by ABP -- 8/5/04 *)
	  (* if Conv.conv (Us', Vs) then () *)
	  (* Think it should be NoTrail, 
	   * never need to go back.. *)
	  if UnifyNoTrail.unifiable(G, Us', Vs) then ()
	  (* End of changes by ABP -- 8/5/04 *)

	  (* ABP -- 12/13/04 -- comment to CS: Since it now 
             constructs all the type information for the
             entire program at once, can we be safe
             that there is no EVar here?  If so, we can change
             it back to the Twelf way of doing it!  
	   *)
	  else raise Error ("Type mismatch")
	end

    and inferUni (I.Type) = I.Kind
        (* impossible: Kind *)
      | inferUni _ = raise Domain

    (* inferExp (G, (U, s)) = (V', s')

       Invariant: 
       If   G  |- s : G1
       then if G1 |- U : V   (U doesn't contain EVAR's, FVAR's) 
	    then  G  |- s' : G'     G' |- V' : L
	    and   G  |- V [s] = V'[s'] : L
	    else exception Error is raised. 
     *)
    and inferExpW (G, (I.Uni (L), _)) = (I.Uni (inferUni L), I.id)
      | inferExpW (G, (I.Pi ((D, _) , V), s)) = 
	  (checkDec (G, (D, s));
	   inferExp (I.Decl (G, I.decSub (D, s)), (V, I.dot1 s)))
      | inferExpW (G, (I.Root (C, S), s)) = 
	  inferSpine (G, (S, s), Whnf.whnf (inferCon (G, C), I.id))
      | inferExpW (G, (I.Lam (D, U), s)) =
	  (checkDec (G, (D, s)); 
	   (I.Pi ((I.decSub (D, s), I.Maybe),
		  I.EClo (inferExp (I.Decl (G, I.decSub (D, s)), (U, I.dot1 s)))), I.id))
      (* no cases for Redex, EVars and EClo's *)
      | inferExpW (G, (I.FgnExp csfe, s)) =
          inferExp (G, (I.FgnExpStd.ToInternal.apply csfe (), s))    (* AK: typecheck a representative -- presumably if one rep checks, they all do *)

      (* ABP -- added case for EVar -- 12/13/04 *)
      | inferExpW (G, (I.EVar (_, _, U, _), s)) = raise Domain (* Whnf.whnf(U,s) *)


      | inferExpW (G, (I.Redex _, _)) = raise Domain
      | inferExpW (G, (I.EClo _, _)) = raise Domain
      | inferExpW _ = raise Domain

    (* inferExp (G, Us) = (V', s')

       Invariant: same as inferExp, argument is not in whnf 
    *)
    and inferExp (G, Us) = inferExpW (G, Whnf.whnf Us)

    (* inferSpine (G, (S, s1), (V, s2)) = (V', s')

       Invariant: 
       If   G |- s1 : G1  
       and  G |- s2 : G2  and  G2 |- V : L ,   (V, s2) in whnf  
       and  (S,V  don't contain EVAR's, FVAR's) 
       then if   there ex V1, V1'  G1 |- S : V1 > V1'
	    then G |- s' : G'    and  G' |- V' : L
	    and  G |- V1 [s1]   = V [s2] : L
            and  G |- V1'[s1]   = V' [s'] : L
    *)
    and inferSpine (G, (I.Nil, _), Vs) = Vs
      | inferSpine (G, (I.SClo (S, s'), s), Vs) = 
	  inferSpine (G, (S, I.comp (s', s)), Vs)
      | inferSpine (G, (I.App (U, S), s1), (I.Pi ((I.Dec (_, V1), _), V2), s2)) =
	  (checkExp(G, (U, s1), (V1, s2));
	   inferSpine (G, (S, s1), Whnf.whnf (V2, I.Dot (I.Exp (I.EClo (U, s1)), s2))))
	  (* G |- Pi (x:V1, V2) [s2] = Pi (x: V1 [s2], V2 [1.s2 o ^1] : L
	     G |- U [s1] : V1 [s2]
	     Hence
	     G |- S [s1] : V2 [1. s2 o ^1] [U [s1], id] > V' [s']
	     which is equal to
	     G |- S [s1] : V2 [U[s1], s2] > V' [s']

	     Note that G |- U[s1] : V1 [s2]
	     and hence V2 must be under the substitution    U[s1]: V1, s2
	  *)
      | inferSpine (G, Ss as (I.App _, _), Vs as (I.Root (I.Def _, _), _)) =
	  inferSpine (G, Ss, Whnf.expandDef Vs)

      (* Carsten, it appears that this case doesn't come up.
       * I had added it when encountering a bug, but may no longer be an issue.
      (* ABP -- 12/13/04 *)
      | inferSpine (G, (I.App (U, S), s1), (I.Pi ((I.NDec, _), V2), s2)) =
	   inferSpine (G, (S, s1), Whnf.whnf (V2, I.Dot (I.Exp (I.EClo (U, s1)), s2)))
	   *)
	  
      | inferSpine (G, (I.App (U , S), _), (V, s)) = (* V <> (Pi x:V1. V2, s) *)
	  raise  Error ("Expression is applied, but not a function")

    (* inferCon (G, C) = V'

       Invariant: 
       If    G |- C : V  
       and  (C  doesn't contain FVars)
       then  G' |- V' : L      (for some level L) 
       and   G |- V = V' : L
       else exception Error is raised. 
    *)
    and inferCon (G, I.BVar (k')) = 
        let 
	  val V = case I.ctxDec (G, k')
	          of I.Dec (_, V) => V
		   | _ => raise Domain
	in
	  V
	end
      | inferCon (G, I.Proj (B,  i)) = 
        let 
	  val V = case I.blockDec (G, B, i)
	          of I.Dec (_, V) => V
		   | _ => raise Domain
	in
	  V
	end
      | inferCon (G, I.Const(c)) = I.constType (c)
      | inferCon (G, I.Def(d))  = I.constType (d)
      | inferCon (G, I.Skonst(c)) = I.constType (c) (* this is just a hack. --cs 
						       must be extended to handle arbitrary 
						       Skolem constants in the right way *)
      (* no case for FVar *)
      (* ABP -- 8/12//04 -- Added case for FVar *)
      | inferCon (G, I.FVar (_, U, t)) = I.EClo(U, t)

      | inferCon (G, I.FgnConst(cs, conDec)) = I.conDecType(conDec)

      | inferCon _ = raise Domain


    and typeCheck (G, (U, V)) = 
          (checkCtx G; checkExp (G, (U, I.id), (V, I.id)))


    (* checkSub (G1, s, G2) = ()

       Invariant:
       The function terminates 
       iff  G1 |- s : G2
    *)
    and checkSub (I.Null, I.Shift 0, I.Null) = ()
      | checkSub (I.Decl (G, D), I.Shift k, I.Null) = 
        if k>0 then checkSub (G, I.Shift (k-1), I.Null)
	else raise Error "Substitution not well-typed"
      | checkSub (G', I.Shift k, G) =
	  checkSub (G', I.Dot (I.Idx (k+1), I.Shift (k+1)), G)
      | checkSub (G', I.Dot (I.Idx k, s'), I.Decl (G, (I.Dec (_, V2)))) =
        (* changed order of subgoals here Sun Dec  2 12:14:27 2001 -fp *)
	let 
	  val _ = checkSub (G', s', G) 
	  val V1 = case I.ctxDec (G', k)
	           of I.Dec (_, V1) => V1
		    | _ => raise Domain
	in
	  if Conv.conv ((V1, I.id), (V2, s')) then ()
	  else raise Error ("Substitution not well-typed \n  found: " ^
			    Print.expToString (G', V1) ^ "\n  expected: " ^
			    Print.expToString (G', I.EClo (V2, s')))
	end
      | checkSub (G', I.Dot (I.Exp (U), s'), I.Decl (G, (I.Dec (_, V2)))) =
	(* changed order of subgoals here Sun Dec  2 12:15:53 2001 -fp *)
	let 
	  val _ = checkSub (G', s', G)
	  val _ = typeCheck (G', (U, I.EClo (V2, s')))
	in
	  ()
	end
      | checkSub (G', I.Dot (I.Idx w, t), I.Decl (G, (I.BDec (_, (l, s))))) =
	(* Front of the substitution cannot be a I.Bidx or LVar *)
	(* changed order of subgoals here Sun Dec  2 12:15:53 2001 -fp *)
	let
	  val _ = checkSub (G', t, G)
	  val (l', s') = case I.ctxDec (G', w)
	                 of I.BDec (_, (l', s')) => (l', s')
			  | _ => raise Domain

	  (* G' |- s' : GSOME *)
	  (* G  |- s  : GSOME *)
	  (* G' |- t  : G       (verified below) *) 
	in
	  if (l <> l') 
	    then raise Error "Incompatible block labels found"
	  else 
	    if Conv.convSub (I.comp (s, t), s')
	      then ()
	    else raise Error "Substitution in block declaration not well-typed"
	end
      | checkSub (G', I.Dot (I.Block (I.Inst I), t), I.Decl (G, (I.BDec (_, (l, s))))) =
	let
	  val _ = checkSub (G', t, G)
	  val (G, L) = I.constBlock l
	  val _ = checkBlock (G', I, (I.comp (s, t), L))
	in
	  ()
	end
      | checkSub (G', s as I.Dot (_, _), I.Null) =
	raise Error ("Long substitution" ^ "\n" ^ subToString (G', s)) 
      (*
      | checkSub (G', I.Dot (I.Block (I.Bidx _), t), G) =
	raise Error "Unexpected block index in substitution"
      | checkSub (G', I.Dot (I.Block (I.LVar _), t), G) =
	raise Error "Unexpected LVar in substitution after abstraction"
      *)
      | checkSub _ = raise Domain

    and checkBlock (G, nil, (_, nil)) = ()
      | checkBlock (G, U :: I, (t, I.Dec (_, V) :: L)) =
        (checkExp (G, (U, I.id), (V, t)); checkBlock (G, I, (I.Dot (I.Exp U, t), L)))
      | checkBlock _ = raise Domain

    (* checkDec (G, (x:V, s)) = B

       Invariant: 
       If G |- s : G1 
       then B iff G |- V[s] : type
    *)
    and checkDec (G, (I.Dec (_, V) ,s)) =
          checkExp (G, (V, s), (I.Uni (I.Type), I.id))
      | checkDec (G, (I.BDec (_, (c, t)), s)) =
	  let 
	    (* G1 |- t : GSOME *)
	    (* G  |- s : G1 *)
	    val (Gsome, piDecs) = I.constBlock c
	  in
	    checkSub (G, I.comp (t, s), Gsome)
	  end
      | checkDec (G, (NDec, _)) = () 

    and checkCtx (I.Null) =  ()
      | checkCtx (I.Decl (G, D)) = 
          (checkCtx G; checkDec (G, (D, I.id)))


    fun check (U, V) = checkExp (I.Null, (U, I.id), (V, I.id))
    fun infer U = I.EClo (inferExp (I.Null, (U, I.id)))
    fun infer' (G, U) =  I.EClo (inferExp (G, (U, I.id)))



    fun checkConv (U1, U2) =
          if Conv.conv ((U1, I.id), (U2, I.id)) then ()
          else raise Error ("Terms not equal\n  left: " ^
                            Print.expToString (I.Null, U1) ^ "\n  right:" ^
                            Print.expToString (I.Null, U2))


  in
      val check = check
      val checkDec = checkDec
      val checkConv = checkConv

      val infer = infer
      val infer' = infer'
      val typeCheck = typeCheck
      val typeCheckCtx = checkCtx			   
      val typeCheckSub = checkSub
  end  (* local ... *)
end; (* functor TypeCheck *)
