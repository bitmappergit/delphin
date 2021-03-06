(* Copying lambda expressions *)
(* Author: Adam Poswolsky, Carsten Schuermann *)

sig 	<exp  : type>
	<app  : exp -> exp -> exp>
	<lam  : (exp -> exp) -> exp>;

(* Structural Identity *)
sig <eq : exp -> exp -> type> 
    <eq_app : eq E1 F1 -> eq E2 F2 -> eq (app E1 E2) (app F1 F2)>
    <eq_lam : ({x}eq x x -> eq (E x) (F x)) -> eq (lam E) (lam F)>;

params = <exp>, <eq e e> ;

fun cp : <exp> -> <exp> =
   fn <p#> => <p>
   | <app E1 E2> => <app> @ (cp <E1>) @ (cp <E2>)
   | <lam E> => case ({<p:exp#>} (cp <E p>)) of
                     ({<p>} <F p> => <lam F>)  ;

val cp'1  = cp <lam [x] x>;
val cp'2  = cp <lam [x] app x x>;
val cp'3  = cp <app (lam [x] x) (lam [x] x)>;
val cp'4  = cp <lam [x] lam [y] x>;


fun eqfun : (<x:exp #> -> <eq x x>) -> <e:exp> -> <eq e e> = 
  fn W => 

  (fn <app E1 E2> => (case ((eqfun W <E1>), (eqfun W <E2>))
                                of (<D1>, <D2>) => <eq_app D1 D2>)
   | <lam E> => (case ({<x:exp>}{<u:eq x x>} eqfun (W with <x> => <u>) <E x>)
                            of ({<x>}{<u>} <D x u>) => <eq_lam D>)

   | <x#> => W <x>) ;

val eq'1  = eqfun (fn .) <lam [x] x>;
val eq'2  = eqfun (fn .) <lam [x] app x x>;
val eq'3  = eqfun (fn .) <app (lam [x] x) (lam [x] x)>;
val eq'4  = eqfun (fn .) <lam [x] lam [y] x>;
