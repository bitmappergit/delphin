(* The delphin programming language operational semantics *)
(* Author: Adam Poswolsky *)

structure DelphinOpsem : DELPHIN_OPSEM = 
  struct
    exception NoSolution
    structure I = IntSyn
    structure D = DelphinIntSyntax


   fun getElement(1, E::xs) = SOME E
     | getElement(i, _::xs) = if (i > 1) then getElement(i-1, xs) else raise Domain
     | getElement _ = NONE

    fun getParamList' (I.Null, k) = []
      | getParamList' (I.Decl(G, D.NonInstantiableDec _), k) = k:: (getParamList' (G, k+1))
      | getParamList' (I.Decl(G, _), k) = getParamList' (G, k+1)

    fun getParamList  G = getParamList' (G, 1)

    (* For application, we fill in all pattern variables with logic variables *)
    fun reduceCase G (Ctotal as D.Eps (D.NormalDec(_, D.LF(isP, A)), C)) =
            (case (D.whnfP isP)
	      of D.Existential =>  	     
		      let
			val X = I.EVar(ref NONE, D.coerceCtx G, A, ref nil)
			(* val X' = Whnf.lowerEVar X (* X' is the lowered version *) *)
			val t = D.Dot (D.Prg (D.Quote X), D.id)
		      in
			reduceCase G (D.substCase(C, t))
		      end
	      | D.Param =>                   
		      let 
			val Glf = D.coerceCtx G
			  
			(* Rather than weakening away incompatible parameters, we could also
			 * save the type in "I.BVarVar"..  However, for now, we choose to do it this way.
			 *)
			fun weaken (I.Null, n) = I.id

			  | weaken (I.Decl(G', D.NonInstantiableDec (D.NewDecLF (_, A'))), n) = 
			         let
				   val _ = UnifyTrail.mark ()
				   val b = UnifyTrail.unifiable (Glf, (A, I.id), (A', I.Shift n))
				   val _ = UnifyTrail.unwind ()
				   val t' = weaken(G', n+1)
				 in
				   if b then I.dot1 t' else I.comp(t', I.shift)
				 end

			  | weaken (I.Decl(G', _), n) = I.comp (weaken (G',n+1), I.shift)

			val w = weaken (G,1)       (* G |- w   : G' *)
			val X = D.Var (D.BVarLF (ref NONE, w))  

			val t = D.Dot (D.Prg X, D.id)
		      in
			reduceCase G (D.substCase(C, t))
		      end
              | D.PVar _ => raise Domain (* should not get to opsem with any PVars *)
            )

      | reduceCase G (Ctotal as D.Eps (D.NormalDec(_, D.Meta(isP, F)), C)) =
            (case (D.whnfP isP)
	      of D.Existential =>  	     
		      let
			val X = D.EVar (ref NONE, D.id)
			val t = D.Dot (D.Prg X, D.id)
		      in
			reduceCase G (D.substCase(C, t))
		      end
	      | D.Param =>                   
		      let 
			val X = D.Var (D.BVarMeta (ref NONE, D.id))
			val t = D.Dot (D.Prg X, D.id)
		      in
			reduceCase G (D.substCase(C, t))
		      end
              | D.PVar _ => raise Domain (* should not get to opsem with any PVars *)
            )

      | reduceCase G (D.NewC (D, C)) = D.NewC (D, reduceCase (I.Decl(G, D.NonInstantiableDec D)) C)
      | reduceCase G (D.PopC (i, C)) = 
	         (case (reduceCase (D.popCtx(i, G)) C)
		    of (D.NewC (_, C')) => D.substCase(C', D.shiftTo(i-1, D.id))
		     | _ => raise Domain (* not type correct *)
                 )

      | reduceCase G (C as D.Match _) = C
      | reduceCase G (C as D.MatchAnd _) = C
                                      

    fun eval G E = evalW G (D.whnfE E)
    and evalW G (E as D.Var (D.Fixed _)) = E (* Will only occur if i is parameter *)
      | evalW G (E as D.Var _) = E (* will occur in evaluation of patterns in cases *)
      | evalW G (E as D.Quote _) = E (* LF Terms are values *)
      | evalW G (E as D.Unit) = E (* Unit is a value *)
      | evalW G (E as D.Lam (Clist, F)) =  E (* Lam is a value *)

      | evalW G (D.New(D, E)) = D.New(D, eval (I.Decl(G, D.NonInstantiableDec D)) E)

      | evalW G (Etotal as D.App _) =  
             let
	       (* It would be slow to do many partial evaluations as
		* if the result is a MatchAnd it will need to partially reduce ALL the cases.
		* Therefore, we convert it into a head/spine(list) so we can perform applications faster
		*)
	       fun getHeadSpine (D.App(vis, Ea, Eb)) = 
		         let 
			   val (H, S) = getHeadSpine Ea
			 in
			   (H, (S @ [(vis,Eb)]))
			 end
		 | getHeadSpine (E) = (E, [])

	       val (H, S) = getHeadSpine Etotal

	       val funVal = eval G H
	       val (cList, F) = (case funVal
				   of (D.Lam (cList, F)) => (cList, F)
				    | _ => raise Domain (* evaluated to a non-lambda *)
				 )

               (* evaluate the spine to values *)
	       val Sval = map (fn (vis, S') => (vis, eval G S')) S

	       fun applyF (F, []) = F
		 | applyF (F, (_,S)::Spine) = (case (D.whnfF F)
		                            of (D.All(_, _, F')) => applyF(D.FClo(F', D.coerceSub (D.Dot(D.Prg S, D.id))), Spine)
					     | _ => raise Domain (* bad type (or is FVar) *)
					   )
	       (* result type of all the applications *)
	       val resultF = applyF (F, Sval)


               (* matchCase(C, Spine) = SOME(isDone, E, Spine') or NONE
		* where it matches all MatchAnds in C and is left with E applied to Spine' 
		* precondition is that C is reduced (no epsilons)
		*)

	       fun matchCase (C, Spine) = matchCaseR (reduceCase G C, Spine)
	       and matchCaseR (D.Match (E1, E2), (_,S)::Spine) =
		             (let
			       val E1 = eval G E1 (* evaluate the pattern.
						   * needed for patterns that use "pop"
						   *)
			       val _ = UnifyDelphinOpsemTrail.unifyE(D.coerceCtx G, E1, S)
			     in
			       SOME (true, E2, Spine) (* true is to indicate between match and matchand *)
			     end
			   handle UnifyDelphinOpsemTrail.Error _ => NONE
				| NoSolution => NONE)

		 | matchCaseR (D.MatchAnd (_, E1, C), [(_,S)]) =
		             (let
			       val E1 = eval G E1 (* evaluate the pattern.
						   * needed for patterns that use "pop"
						   *)

			       val _ = UnifyDelphinOpsemTrail.unifyE(D.coerceCtx G, E1, S)
			     in
			       SOME (false, D.Lam([C], resultF), [])
			     end
			   handle UnifyDelphinOpsemTrail.Error _ => NONE
				| NoSolution => NONE)


		 | matchCaseR (D.MatchAnd (_, E1, C), (_,S)::Spine (* Spine is nonempty *)) =
		             (let
			       val E1 = eval G E1 (* evaluate the pattern.
						   * needed for patterns that use "pop"
						   *)

			       val _ = UnifyDelphinOpsemTrail.unifyE(D.coerceCtx G, E1, S)
			     in
			       matchCase(C, Spine)
			     end
			   handle UnifyDelphinOpsemTrail.Error _ => NONE
				| NoSolution => NONE)

		 | matchCaseR _ = raise Domain (* precondition violated *)

	       fun buildApp (E, []) = E
		 | buildApp (E, (vis,S)::Spine) = buildApp(D.App(vis, E, S), Spine)

	       fun matchCases ([], Spine) = raise NoSolution
		 | matchCases (C::cs, Spine) = 
		           let
			     val _ = UnifyDelphinOpsemTrail.mark ()

			    (* normalization slows things down too much! instead we
                               will only unwind when it fails
			     val resultNormalized =  (case (matchCase(C, Spine))
							of NONE => NONE
						         | SOME(b, E, Spine') => SOME(b, NormalizeDelphin.normalizeExp E, Spine')
							                         (* normalize makes it safe to unwind *)
                                                      )

			     val _ = UnifyDelphinOpsemTrail.unwind()

                             *)
			     val resultNotNormalized = (case (matchCase(C, Spine))
							  of NONE => (UnifyDelphinOpsemTrail.unwind() ; NONE)
							   | X => X
							)

			   in
			     case resultNotNormalized
			       of NONE => matchCases (cs, Spine)
				| SOME(true, E, Spine') => buildApp(E, Spine')
			        | SOME(false, D.Lam([C],_), []) =>
				                    (* Final match was attached with an "MatchAnd", so we continue evaluating other cases.*)
				                    let
						      val Eopt = SOME(matchCases (cs, Spine))
							handle NoSolution => NONE
						    in
						      case Eopt 
							of NONE => D.Lam([C], resultF)
							 | SOME(D.Lam(Clist',_)) => D.Lam(C::Clist', resultF)
							 | SOME E => let 
								       val D = case (D.whnfF(resultF))
									          of D.All(_, D, _) => D
										   | _ => raise Domain
								       val Cnew = D.Eps(D, D.Match(D.Var (D.Fixed 1), E))
								     in
								       D.Lam([C,Cnew], resultF)
								     end
						    end
						  
				| _ => raise Domain (* broken invariant *)
			   end
			 
	     in
	       eval G (matchCases (cList, Sval))
	     end

      | evalW G (D.Pair (E1, E2, F)) = D.Pair (eval G E1, eval G E2, F)

      | evalW G (D.ExpList Elist) = D.ExpList (map (fn E => eval G E) Elist)
	                           (* Although we typically only proj one of these out
				    * we do extra work by evaluating all of them first
				    * These will typically all be functions
				    * which means it will create many logic variables which
				    * it never uses.
				    *)

      | evalW G (D.Proj (E, i)) = (case (eval G E)
	                         of (D.ExpList Elist) => (case (getElement(i, Elist))
				                         of NONE => raise Domain (* not type correct *)
							  | SOME V => V)
				   | _ => raise Domain (* not type correct *))

      | evalW G (D.Pop (i, E)) = (case (eval (D.popCtx(i, G)) E)
				   of (D.New(_, V)) => D.substE'(V, D.shiftTo(i-1, D.id))
				     | (D.EVar (r (* ref NONE *), t)) => 
                                              (* This case can occur when evaluating patterns *)
                                              let
						val newBody = D.EVar (ref NONE, D.dot1 t)
						val newDec = let
						               fun getDec(I.Decl(G, D.NonInstantiableDec D), 1) = D
								 | getDec(I.Decl(G, _), n) = getDec(G, n-1)
								 | getDec _ = raise Domain
							     in
							       getDec(G, i)
							     end
						val _ = r := SOME(D.New(newDec, newBody))
					      in
						D.substE'(newBody, D.shiftTo(i-1, D.id))
					      end
                                                 
				     | (D.Lam(Clist, F)) => 
					      let
						val shifts = D.shiftTo(i-1, D.id)
						fun addPop C = D.PopC(i, C)

						(* precondition:  in whnf *)
						fun removeNewF (D.Nabla(_, F)) = D.FClo(F, I.Shift (i-1))
						  | removeNewF (F as D.FVar _) = raise Domain (* should be filled in 
											       * before executing
											       * opsem
											       *)
						  | removeNewF _ = raise Domain
					      in
						D.Lam (map addPop Clist, removeNewF (D.whnfF F))
					      end
				     | _ => raise Domain
				  )

      | evalW G (E as D.Fix(D, E')) = let
				       val t = D.Dot(D.Prg E, D.id)
				       val E'' = D.substE'(E', t)
				     in
				       eval G E''
				     end

      | evalW G (E as D.EVar _) = E (* uninstantiated EVar... can occur in
				     * the evaluation of patterns 
				     *) 

      | evalW G (D.EClo _) = raise Domain (* not in whnf *)



    (* OLD way (normalization/unwind really slowed things down..)
    fun eval0 E = let 
                    val _ = UnifyDelphinOpsemTrail.mark ()
		      (* We do mark here so the "pattern variables" marked as parameters can be cleaned up *)
		    val V = SOME(NormalizeDelphin.normalizeExp(eval (I.Null) E))
		              handle NoSolution => NONE
		    val _ = UnifyDelphinOpsemTrail.unwind() 
		  in
		    case V of
		      SOME V => V
		     | _ => raise NoSolution
		  end
    *)

    fun eval0 E = let 
                   (* ABP:  It may be safe to remove "unwind" and change the Unify structure
		    *       so it doesn't use trailing.  This is
		    *       really only necessary for cases which are badly specified anyway..
		    *       i.e. when pattern variable declared much earlier than when it is needed 
		    *
		    *)
                    val _ = UnifyDelphinOpsemTrail.mark ()
		    val V = SOME(eval (I.Null) E)
		              handle NoSolution => (UnifyDelphinOpsemTrail.unwind() ; NONE)
		    val _ = UnifyDelphinOpsemTrail.reset() (* clears the lists to unwind and such... *)
		  in
		    case V of
		      SOME V => V
		     | _ => raise NoSolution
		  end

end
