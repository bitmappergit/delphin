(* Lexer for Delphin *)
(* Author:  Adam Poswolsky *)

structure Tokens = Tokens
structure Interface = Interface

type pos = Interface.pos

type svalue = Tokens.svalue
type ('a, 'b) token = ('a, 'b) Tokens.token
type lexresult = (svalue, pos) token

val numOpeningComments = ref 0 
val toPos = Interface.intToPos

(* The twelf printer for Regions will add 1 since it counts from 0
 * so this is to just adjust 
 *)
fun toReg(a,b) = Paths.Reg(a-1,b-1)

(*
 * This function is called when we hit EOF
 *)
  fun eof () = 
    let 
        val pos = Interface.noPos
    in 
    (
     if (!numOpeningComments > 0) then
        Interface.error (("unclosed comment at eof."), pos, pos)
      else ()
      ;
      numOpeningComments := 0;
     (* If we reset, then the parser errors are messed up, it
        must be reset before not after.
      Interface.reset();
       *)
     Tokens.EOF(pos,pos))
    end

  (* Below, we will not allow the following characters (besides whitespace) in uiden
   , ; : {  } (  )  [  ]  <  > # @ *
   and the following strings cannot be used as uiden
   _ * , -> <- = | . => 
     and type fun unit case of pop let in end val fn eps
  *)

%% 

%s COMMENT LF;
%reject
%header (functor DelphinLexFun(structure Tokens : Delphin_TOKENS
                               structure Interface : INTERFACE));

ws = [\t\ ];
uidenchar  = [\033-\034\036-\039\043-\043\045-\047\048-\057\061-\061\063-\063\065-\090\094-\122\124-\124\126-\126];
uiden      = {uidenchar}+;
digits     = [0-9]+;
lfchar     = [\033-\034\036-\039\042-\045\047-\057\060-\061\063-\090\092-\092\094-\122\124-\124\126-\126];
lfarrowID1  = "->";
lfarrowID2  = "=>";
lfarrowID3  = "~>";
lfiden   = ({lfchar} | {lfarrowID1}| {lfarrowID2} | {lfarrowID3})+;
filechar = [\033-\033\035-\126];
filename = {filechar}+;
%%
<INITIAL,COMMENT,LF>{ws}+          
                                => (continue());
<INITIAL,COMMENT,LF>\n             
                                => (Paths.newLine(yypos) ; Interface.incLineNum(yypos); continue());
<INITIAL>("use")(" "+)("\"")({filename})("\"")
                                 => (Tokens.USE(substring(yytext, 4, size(yytext)-4), 
                                  toPos yypos, toPos(yypos + size(yytext)-1)));
<INITIAL>"(*"                   => (numOpeningComments := 1 ; 
                                    YYBEGIN COMMENT; 
                                    continue());
<COMMENT>"(*"                   => (numOpeningComments := !numOpeningComments + 1;
                                    continue());
<COMMENT>"*)"                   => (
                                    numOpeningComments := !numOpeningComments - 1;
                                    if (!numOpeningComments = 0) then 
                                      ( YYBEGIN INITIAL ; continue() )
                                    else
                                      continue()
                                   );
<COMMENT>.                      => (continue());

<INITIAL>"%abbrev"              => (Tokens.ABBREV(toReg(yypos,yypos+6), toPos yypos, toPos (yypos+6)));
<INITIAL>"%infix"               => (Tokens.INFIX(toReg(yypos,yypos+5), toPos yypos, toPos (yypos+5)));
<INITIAL>"%postfix"             => (Tokens.POSTFIX(toReg(yypos,yypos+7), toPos yypos, toPos (yypos+7)));
<INITIAL>"%prefix"              => (Tokens.PREFIX(toReg(yypos,yypos+6), toPos yypos, toPos (yypos+6)));
<INITIAL>"%name"                => (Tokens.NAME(toReg(yypos,yypos+4), toPos yypos, toPos (yypos+4)));
<INITIAL>"right"                => (Tokens.RIGHT(toReg(yypos,yypos+5), toPos yypos, toPos (yypos+4)));
<INITIAL>"left"                 => (Tokens.LEFT(toReg(yypos,yypos+4), toPos yypos, toPos (yypos+3)));
<INITIAL>{digits}               => (Tokens.DIGITS((toReg(yypos, yypos + size(yytext)-1), valOf (Int.fromString(yytext))),
                                     toPos yypos,toPos (yypos + size(yytext)-1)));
<INITIAL,LF>"_"                    => (Tokens.UNDERSCORE(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL>"*"                    => (Tokens.STAR(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL>","                    => (Tokens.COMMA(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL,LF>"#"                    => (Tokens.POUND(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL>"."                    => (Tokens.DOT(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL,LF>"->"                   => (Tokens.RTARROW(toReg(yypos, yypos + 1), toPos yypos, toPos(yypos+1)));
<INITIAL>"=>"                   => (Tokens.EQARROW(toReg(yypos, yypos + 1), toPos yypos, toPos(yypos+1)));
<INITIAL,LF>"<-"                => (Tokens.LTARROW(toReg(yypos, yypos + 1), toPos yypos, toPos(yypos+1)));
<INITIAL,LF>"="                 => (Tokens.EQUAL(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL>"|"                    => (Tokens.BAR(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL>"\\"                   => (Tokens.BACKSLASH(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL>"and"                  => (Tokens.AND(toReg(yypos, yypos+2), toPos yypos,toPos (yypos+2)));
<INITIAL>"params"               => (Tokens.PARAMS(toReg(yypos, yypos+5), toPos yypos,toPos (yypos+5)));
<INITIAL>"with"                 => (Tokens.WITH(toReg(yypos, yypos + 3), toPos yypos, toPos (yypos+3)));
<INITIAL,LF>"type"              => (Tokens.TYPE(toReg(yypos, yypos + 3), toPos yypos, toPos(yypos +3)));
<INITIAL>"fun"                  => (Tokens.FUN(toReg(yypos, yypos + 2), toPos yypos,toPos (yypos+2)));
<INITIAL>"unit"                 => (Tokens.UNIT(toReg(yypos, yypos + 3), toPos yypos, toPos (yypos+3)));
<INITIAL>"case"                 => (Tokens.CASE(toReg(yypos, yypos + 3), toPos yypos,toPos (yypos+3)));
<INITIAL>"sig"                  => (Tokens.SIG(toReg(yypos, yypos + 2), toPos yypos,toPos (yypos+2)));
<INITIAL>"of"                   => (Tokens.OF(toReg(yypos, yypos + 1), toPos yypos,toPos (yypos+1)));
<INITIAL>"pop"                  => (Tokens.POP(toReg(yypos, yypos + 2), toPos yypos,toPos (yypos +2)));
<INITIAL>"end"                  => (Tokens.END(toReg(yypos, yypos + 2), toPos yypos,toPos (yypos +2)));
<INITIAL>"val"                  => (Tokens.VAL(toReg(yypos, yypos + 2), toPos yypos,toPos (yypos +2)));
<INITIAL>"let"                  => (Tokens.LET(toReg(yypos, yypos + 2), toPos yypos,toPos (yypos+2)));
<INITIAL>"in"                   => (Tokens.IN(toReg(yypos, yypos + 1), toPos yypos,toPos (yypos+1)));
<INITIAL>"fn"                   => (Tokens.FN(toReg(yypos, yypos + 1), toPos yypos,toPos (yypos+1)));
<INITIAL>";"                    => (Tokens.SEMICOLON(toReg(yypos, yypos), toPos yypos, toPos(yypos )));
<INITIAL>"<<"                   => (YYBEGIN LF;
				    Tokens.DBL_LTANGLE(toReg(yypos, yypos+1), toPos yypos,toPos (yypos+1)));
<INITIAL>"<"                    => (YYBEGIN LF;
				    Tokens.LTANGLE(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<LF>     ">>"                   => (YYBEGIN INITIAL ;
				    Tokens.DBL_RTANGLE(toReg(yypos, yypos+1), toPos yypos,toPos (yypos+1)));
<LF>     ">"                    => (YYBEGIN INITIAL ;
				    Tokens.RTANGLE(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL,LF>"("                 => (Tokens.LTPAREN(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL,LF>")"                 => (Tokens.RTPAREN(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL,LF>"["                 => (Tokens.LTBRACKET(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL,LF>"]"                 => (Tokens.RTBRACKET(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL,LF>"{"                 => (Tokens.LTBRACE(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL,LF>"}"                 => (Tokens.RTBRACE(toReg(yypos, yypos), toPos yypos,toPos (yypos)));
<INITIAL,LF>":"                 => (Tokens.COLON(toReg(yypos, yypos), toPos yypos,toPos(yypos)));
<INITIAL>"@"                    => (Tokens.AT(toReg(yypos, yypos), toPos yypos,toPos(yypos)));


<INITIAL>{uiden}                => (Tokens.ID((toReg(yypos, yypos + size(yytext)-1), yytext),toPos yypos,toPos (yypos+size(yytext)-1)));
<LF>{lfiden}                    => (Tokens.ID((toReg(yypos, yypos + size(yytext)-1), yytext),toPos yypos,toPos (yypos+size(yytext)-1)));
<INITIAL,LF>.                   => (Interface.error ("ignoring bad character " ^ yytext,
                                    toPos yypos, toPos (yypos)); continue());
