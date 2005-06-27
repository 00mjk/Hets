{- |
Module      :  $Header$
Copyright   :  (c) University of Cambridge, Cambridge, England
               adaption (c) Till Mossakowski, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

Printing functions for Isabelle logic.
-}
{-
  todo: brackets in (? x . p x) ==> q
  properly construct docs
-}

module Isabelle.IsaPrint where

import Isabelle.IsaSign 
import Isabelle.IsaConsts
import Common.Lib.Pretty
import Common.PrettyPrint
import Common.PPUtils
import Common.AS_Annotation
import Data.Char
import qualified Common.Lib.Map as Map

------------------- Printing functions -------------------

showBaseSig :: BaseSig -> String
showBaseSig = reverse . drop 4 . reverse . show

instance PrettyPrint BaseSig where
     printText0 _ s = text $ showBaseSig s

instance PrettyPrint IsaClass where
     printText0 _ (IsaClass c) = parens $ text c

instance PrintLaTeX Sentence where
  printLatex0 = printText0

{- test for sentence translation -}
instance PrettyPrint Sentence where
      printText0 _ = text . showTerm . senTerm

showIsaDef :: Named Sentence -> Doc
showIsaDef x = let d = senName x in 
  if d == "" then empty
  else text (d++"_def:"++sp++"\""++(showTerm $ senTerm $ sentence x)++"\"")

instance PrettyPrint Typ where
  printText0 _ = text . showTyp Null 1000 -- Unquoted 1000

showClass :: Sort -> String
showClass s = case s of 
   [] -> ""
   (IsaClass x):(a:as) -> x ++ "," ++ showClass (a:as)
   (IsaClass x) : [] -> x

showSort :: Sort -> String
showSort s = "{"++(showClass s)++"}"

data SynFlag = Unquoted | Quoted | Null 

showTyp :: SynFlag -> Integer -> Typ -> String
showTyp a pri t = case t of 
 (TFree v s) -> case a of
   Unquoted -> lb ++ "\'" ++ v ++ "::" ++ (showSort s) ++ rb
   Quoted -> "\'" ++ v ++ "::\"" ++ (showSort s) ++ "\""
   Null ->  "\'" ++ v
 (TVar (v,_) s) -> case a of
   Unquoted -> lb ++ "?\'" ++ v ++ "::" ++ (showSort s) ++ rb
   Quoted -> "?\'" ++ v ++ "::\"" ++ (showSort s) ++ "\""
   Null ->  "?\'" ++ v
 (Type name _ args) -> case args of 
   [] -> name
   arg:[] ->  showTyp a 10 arg ++ sp ++ name
   [t1,t2] -> let tyst = showTypeOp a pri name t1 t2
      in case a of 
         Quoted -> tyst
         _ -> lb ++ tyst ++ rb
   _  -> let tyst = (rearrangeVarsInType a pri name args) 
       in case a of 
         Quoted -> tyst
         _ -> lb ++ tyst ++ rb
 where rearrangeVarsInType x p n as = 
            let (tyVars,types) = foldl split ([],[]) as
            in (encloseTup x p (concRev tyVars types)) ++ sp ++ n 
       split (tv,ty) k = case k of 
                        TFree _ _ -> (tv++[k],ty)
                        _       -> (tv,ty++[k])
       concRev b c = reverse b ++ reverse c
       encloseTup f g l = if (length l) < 2 then showTypTup f g l else lb++(showTypTup f g l)++rb 
       showTypTup f g l = case l of
          [] -> []
          [c] -> showTyp f g c
          c:b:as -> (showTyp f g c)++","++sp++(showTypTup f g (b:as)) 
       showTypeOp x p n r1 r2
          | n == funS =
             bracketize (p<=10) (showTyp x 10 r1 ++ " => " ++ showTyp x 10 r2)
          | n == "dFun" =
             bracketize (p<=10) (showTyp x 10 r1 ++ " -> " ++ showTyp x 10 r2)
          | n == prodS = 
             lb ++ showTyp x p r1 ++ " * " ++ showTyp x p r2 ++ rb
          | n == "**" = 
             lb ++ showTyp x p r1 ++ " ** " ++ showTyp x p r2 ++ rb
          | True = rearrangeVarsInType x p n [r1,r2]

instance PrettyPrint TypeSig where
  printText0 ga tysig = printText0 ga $ arities tysig

instance PrettyPrint Term where
  printText0 _ = text . showTerm -- outerShowTerm   
  -- back to showTerm, because meta !! causes problems with show ?thesis


typedVars2st :: (a -> String) -> (b -> String) -> [(a,b)] -> String
typedVars2st f g ls = concat [" (" ++ (f x) ++ "::" ++ (g y) ++ ")" | (x,y) <- ls]

showTypedVars :: [(Term,Typ)] -> String
showTypedVars ls = typedVars2st showTerm (showTyp Unquoted 1000) ls

showQuantStr :: String -> String
showQuantStr s | s == allS = "!"
               | s == exS  = "?"
               | s == ex1S = "?!"
               | otherwise = error "IsaPrint.showQuantStr"

showTerm :: Term -> String
showTerm (Const c _) = c
showTerm (Free v _) = v

showTerm (Tuplex ls c) = case c of
   IsCont -> "< " ++ (showTupleArgs ls) ++ ">" -- the extra space takes care of a minor Isabelle bug
   NotCont -> "(" ++ (showTupleArgs ls) ++ ")" 
 where 
   showTupleArgs xs = case xs of 
     [] -> []
     [a] -> showTerm a
     a:as -> case a of
      (Free n t) -> (showTerm a) ++ "::" ++ (showTyp Null 1000 t) ++ "," ++ showTupleArgs as
--    (showTyp Unquoted 1000 t) ++ "," ++ showTupleArgs as
      _ -> (showTerm a) ++ "," ++ showTupleArgs as

showTerm (Abs v y t l) 
  | y == noType = lb ++ (case l of 
    NotCont -> "%"
    IsCont -> "LAM ") ++ showTerm v ++ ". " ++ showTerm t ++ rb
  | True = lb ++ (case l of 
    NotCont -> "%"
    IsCont -> "LAM ") ++ (case v of 
      (Free n y) -> showTerm v ++ "::" 
       ++ showTyp Null 1000 y -- Unquoted 1000 y
      _ -> showTerm v) ++ ". " ++ showTerm t ++ rb

-- showTerm (App (Const q _) (Abs v ty t _) _) | q `elem` [allS, exS, ex1S] =
--   showQuant (showQuantStr q) v ty t
-- showTerm t@(Const c _) = showPTree (toPrecTree t) 
showTerm (Paren t) = showTerm t 
showTerm (Fix t) = lb++"fix"++"$"++(showTerm t)++rb
showTerm t@(App _ _ NotCont) = showPTree (toPrecTree t) 
showTerm (App t1 t2 IsCont) = lb++(showTerm t1)++"$"++(showTerm t2)++rb
showTerm Bottom = "UU"

showTerm (IsaEq t1 t2) = lb ++ (showTerm t1) ++ sp ++ "==" 
                         ++ sp ++ (showTerm t2) ++ rb
showTerm (Case term alts) =
  let sAlts = map showCaseAlt alts
  in 
   lb ++ "case" ++ sp ++ showTerm term ++ sp ++ "of" 
      ++ sp ++ head sAlts
      ++ concat (map ((++) ("\n" ++ sp ++ sp ++ sp ++ "|" ++ sp)) 
                                                    (tail sAlts)) ++ rb
showTerm (If t1 t2 t3 c) = case c of
  NotCont -> 
    lb ++ "if" ++ sp ++ showTerm t1 ++ sp ++ "then" ++ sp 
           ++ showTerm t2 ++ sp ++ "else" ++ sp ++ showTerm t3 ++ rb
  IsCont -> 
    lb ++ "If" ++ sp ++ showTerm t1 ++ sp ++ "then" ++ sp 
           ++ showTerm t2 ++ sp ++ "else" ++ sp ++ showTerm t3 ++ sp ++ "fi" ++ rb

showTerm (Let pts t) = lb ++ "let" ++ sp ++ showPat False (head pts) 
                                ++ concat (map (showPat True) (tail pts))
                                ++ sp ++ "in" ++ sp ++ showTerm t ++ rb

showPat :: Bool -> (Term, Term) -> String
showPat b (pat, term) = 
  let s = sp ++ showTerm pat ++ sp ++ "=" ++ sp ++ showTerm term
  in-- showTerm (Const c _) = c

    if b then ";" ++ s
      else s

showCaseAlt :: (Term, Term) -> String
showCaseAlt (pat, term) =
  showPattern pat ++ sp ++ "=>" ++ sp ++ showTerm term

showPattern :: Term -> String
showPattern (App t t' _) = showPattern t ++ sp ++ showPattern t'
showPattern t = showTerm t

showQuant :: String -> Term -> Typ -> Term -> String
showQuant s var typ term =
   s++sp++ showTerm var ++" :: "++ showTyp Null 1000 typ ++ " . " -- Unquoted 1000 typ ++ " . "
        ++ showTerm term

outerShowTerm :: Term -> String
outerShowTerm (App (Const q _) (Abs v ty t _) _) | q == allS = 
  outerShowQuant "!!" v ty t 
outerShowTerm (App (App (Const o _) t1 _) t2 _) | o == impl =
  showTerm t1 ++ " ==> " ++ outerShowTerm1 t2
outerShowTerm t = showTerm t

outerShowTerm1 :: Term -> String
outerShowTerm1 t@(App (App (Const o _) _ _) _ _) | o == impl =
  outerShowTerm t
outerShowTerm1 t = showTerm t

outerShowQuant :: String -> Term -> Typ -> Term -> String
outerShowQuant s var typ term =
  s++sp++ showTerm var ++" :: "++showTyp Null 1000 typ ++ " . " --  Unquoted 1000 typ++" . "
   ++ outerShowTerm term 


{-   
   For nearly perfect parenthesis - they only appear when needed - 
   a formula/term is broken open in following pieces:
                            (logical) connector
                           /                   \
                          /                     \
                formula's lhs               formula's rhs

   Every connector is annotated with its precedence, every 'unbreakable'
   formula gets the lowest precedence.
-}

-- term annotated with precedence
data PrecTerm = PrecTerm Term Precedence deriving (Show)
type Precedence = Int

{- Precedences (descending): __ __ (Isabelle's term application),
                             application of HasCASL ops, <=>, =, /\, \/, => 
   Associativity:  =  -- left
                   => -- right
                   /\ -- right
                   \/ -- right
-}

data PrecTermTree = Node PrecTerm [PrecTermTree]

isaAppPrec :: Term -> PrecTerm
isaAppPrec t = PrecTerm t 0

appPrec :: Term -> PrecTerm
appPrec t = PrecTerm t 5

eqvPrec :: Term -> PrecTerm
eqvPrec t = PrecTerm t 7

eqPrec :: Term -> PrecTerm
eqPrec t = PrecTerm t 10

andPrec :: Term -> PrecTerm
andPrec t = PrecTerm t 20

orPrec :: Term -> PrecTerm
orPrec t = PrecTerm t 30

implPrec :: Term -> PrecTerm
implPrec t = PrecTerm t 40

capplPrec :: Term -> PrecTerm
capplPrec t = PrecTerm t 999

noPrec :: Term -> PrecTerm
noPrec t = PrecTerm t (-10)

quantS :: String
quantS = "QUANT" 

dummyS :: String
dummyS = "Dummy" 

binFunct :: String -> Term -> PrecTerm
binFunct s | s == eqv  = eqvPrec
           | s == eq   = eqPrec
           | s == conj = andPrec
           | s == disj = orPrec
           | s == impl = implPrec
--           | s == cappl = capplPrec
           | otherwise = appPrec

toPrecTree :: Term -> PrecTermTree
toPrecTree trm =
  case trm of
    App c1@(Const q _) a2@(Abs _ _ _ _) _ | q `elem` [allS, exS, ex1S] -> 
       Node (isaAppPrec $ con quantS) [toPrecTree c1, toPrecTree a2]
--    App t1 t2 IsCont -> Node (capplPrec $ con cappl) 
--                   [toPrecTree t1, toPrecTree t2] 
    App (App t@(Const o _) t3 NotCont) t2 NotCont ->
      Node (binFunct o t) [toPrecTree t3, toPrecTree t2]
    App t1 t2 NotCont -> Node (isaAppPrec $ con dummyS) 
                   [toPrecTree t1, toPrecTree t2] 
    _ -> Node (noPrec trm) []

data Assoc = LeftAs | NoAs | RightAs

showPTree :: PrecTermTree -> String
showPTree (Node (PrecTerm term _) []) = showTerm term
showPTree (Node (PrecTerm term pre) annos) = 
  let leftChild = head annos
      rightChild = last annos
   in
     case term of
          Const c _ | c == eq -> infixP pre "=" LeftAs leftChild rightChild
                    | c == "op +" -> infixP pre "+" LeftAs leftChild rightChild
                    | c == "op -" -> infixP pre "-" LeftAs leftChild rightChild
                    | c == "op *" -> infixP pre "*" LeftAs leftChild rightChild
--                    | c == cappl -> infixP pre "$" LeftAs leftChild rightChild
                    | c `elem` [conj, disj, impl] ->
                        infixP pre (drop 3 c) RightAs leftChild rightChild
                    | c == dummyS  -> simpleInfix pre leftChild rightChild
                    | c == isaPair -> pair leftChild rightChild
                    | c == quantS  -> quant leftChild rightChild
                    | otherwise    -> prefixP pre c leftChild rightChild
          _ -> showTerm term

{- Logical connectors: For readability and by habit they are written 
   at an infix position.
   If the precedence of one side is weaker (here: higher number) than the 
   connector's one it is bracketed. Otherwise not. 
-}
infixP :: Precedence -> String -> Assoc -> PrecTermTree -> PrecTermTree -> String
infixP pAdult stAdult assoc leftChild rightChild 
    | (pAdult < prLeftCld) && (pAdult < prRightCld) = both
    | pAdult < prLeftCld = 
        case assoc of 
          LeftAs  -> if pAdult == prRightCld then both else left
          RightAs -> left
          NoAs    -> left
    | pAdult < prRightCld = 
        case assoc of
          LeftAs  -> right
          RightAs -> if pAdult == prLeftCld then both else right
          NoAs    -> right
    | (pAdult == prLeftCld) && (pAdult == prRightCld) = 
        case assoc of
          LeftAs  -> right
          RightAs -> left
          NoAs    -> no
    | pAdult == prLeftCld = 
        case assoc of
          LeftAs  -> no
          RightAs -> left
          NoAs    -> no
    | pAdult == prRightCld =
        case assoc of
          LeftAs  -> right
          RightAs -> no
          NoAs    -> no
    | otherwise = no
  where prLeftCld = pr leftChild
        prRightCld = pr rightChild
        stLeftCld = showPTree leftChild
        stRightCld = showPTree rightChild
        left = lb++ stLeftCld ++rb++sp++ stAdult ++sp++ stRightCld
        both = lb++ stLeftCld ++rb++sp++ stAdult ++sp++lb++ stRightCld ++rb
        right = stLeftCld ++sp++ stAdult ++sp++lb++ stRightCld ++rb
        no =  stLeftCld ++sp++ stAdult ++sp++ stRightCld


{- Application of (HasCASL-)operations with two arguments. 
   Both arguments are usually bracketed, except single ones.
-}
prefixP :: Precedence -> String -> PrecTermTree -> PrecTermTree -> String
prefixP pAdult stAdult leftChild rightChild 
    | (pAdult <= prLeftCld) && (pAdult <= prRightCld) =
          stAdult ++
              sp++lb++ stLeftCld ++rb++
                  sp++lb++ stRightCld ++rb
    | pAdult <= prLeftCld = 
          stAdult ++
              sp++lb++ stLeftCld ++rb++
                  sp++ stRightCld
    | pAdult <= prRightCld = 
          stAdult ++
              sp++ stLeftCld ++
                  sp++lb++ stRightCld ++rb
    | otherwise =  stAdult ++
                       sp++ stLeftCld ++
                           sp++ stRightCld
  where prLeftCld = pr leftChild
        prRightCld = pr rightChild
        stLeftCld = showPTree leftChild
        stRightCld = showPTree rightChild

{- Isabelle application: An operation/a datatype-constructor is applied 
   to one argument. The whole expression is always bracketed.
-}
simpleInfix :: Precedence -> PrecTermTree -> PrecTermTree -> String
simpleInfix pAdult leftChild rightChild 
    | (pAdult < prLeftCld) && (pAdult < prRightCld) = 
          lbb++ stLeftCld ++rb++
                sp++lb++ stRightCld ++rbb
    | pAdult < prLeftCld = 
          lbb++ stLeftCld ++rb++
                sp++ stRightCld ++rb
    | pAdult < prRightCld = 
          lb++ stLeftCld ++sp++
               lb++ stRightCld ++rbb
    | otherwise = lb++ stLeftCld ++sp++
                       stRightCld ++rb
  where prLeftCld = pr leftChild
        prRightCld = pr rightChild
        stLeftCld = showPTree leftChild
        stRightCld = showPTree rightChild


{- Quantification _in_ Formulas
-}
quant :: PrecTermTree -> PrecTermTree -> String
quant (Node (PrecTerm (Const q _) _) []) 
          (Node (PrecTerm (Abs v ty t _) _) []) = 
              lb++showQuant (showQuantStr q) v ty t++rb
quant _ _ = error "[Isabelle.IsaPrint] Wrong quantification!?"

listEnum :: [a] -> [(a,Int)]
listEnum l = case l of
 [] -> []
 a:as -> (a,length (a:as)):(listEnum as)

pr :: PrecTermTree -> Precedence
pr (Node (PrecTerm _ p) _) = p

-- Prints: (p1, p2)
pair :: PrecTermTree -> PrecTermTree -> String
pair leftChild rightChild = lb++showPTree leftChild++", "++
                                showPTree rightChild++rb


-- instances for Classrel and Arities, in alternative to TSig
instance PrettyPrint Classrel where
 printText0 _ s = if Map.null s then empty
      else text $ Map.foldWithKey showTycon "" s 
   where 
   showTycon t cl rest = case cl of 
     Nothing -> rest
     Just x ->  ("axclass " ++ classId t ++ " < " ++ (if x == [] then "pcpo" 
       else showSort x) ++ "\n") ++ rest

instance PrettyPrint Arities where
 printText0 _ s = if Map.null s then empty  
      else text $ Map.foldWithKey showInstances "" s 
   where 
   showInstances t cl rest =
     (concat $ map (showInstance t) cl) ++ rest
   showInstance t xs = 
     "instance " ++ (show t) ++ " :: " ++ (showInstArgs $ snd xs)  
        ++ (classId $ fst xs) ++ "\n" ++ "by intro_classes \n"
   showInstArgs ys = case ys of 
     [] -> ""
     a:as -> "(" ++ (showInstArgsR ys) ++ ") "
   showInstArgsR ys = case ys of 
      [] -> ""     
      [a] -> "\"" ++ (showSort $ snd a) ++ "\""
      a:as -> "\"" ++ (showSort $ snd a) ++ "\", " ++ (showInstArgsR as)

instance PrettyPrint Sign where
  printText0 ga sig = printText0 ga
    (baseSig sig) <> colon $++$
    printText0 ga (classrel $ tsig sig) $++$
    showDataTypeDefs (dataTypeTab sig) $++$
    showDomainDefs (domainTab sig) $++$
    showsConstTab (constTab sig) $++$ 
    (if showLemmas sig then showCaseLemmata (dataTypeTab sig) else empty) $++$
                                   -- this may prints an "o"
    printText0 ga (tsig sig) 
    where
    showsConstTab tab =
     if Map.null tab then empty
      else text("consts") $$ Map.foldWithKey showConst empty tab $$ text "\n"
    showConst c t rest = 
         text (show c ++ " :: " ++ "\"" ++ showTyp Unquoted 1000 t -- (fst t) 
                                ++ "\"") $$ rest
    showDataTypeDefs dtDefs = vcat $ map (text . showDataTypeDef) dtDefs
    showDataTypeDef [] = ""
    showDataTypeDef (dt:dts) = 
       "datatype " ++ showDataType dt
       ++ (concat $ map ((" and "++) . showDataType) dts) ++ "\n"
    showDataType (_,[]) = error "IsaPrint.showDataType"
    showDataType (t,op:ops) =
       showTyp Quoted 1000 t ++ " = " ++ showOp op 
       ++ (concat $ map ((" | "++) . showOp) ops)
    showDomainDefs dtDefs = vcat $ map (text . showDomainDef) dtDefs
    showDomainDef [] = ""
    showDomainDef (dt:dts) =
       "domain " ++ showDomain dt 
       ++ (concat $ map (("\n and "++) . showDomain) dts) ++ "\n"
    showDomain (_,[]) = error "IsaPrint.showDomain"
    showDomain (t,op:ops) =
       showTyp Quoted 1000 t ++ " = " ++ showDOp op
       ++ (concat $ map ((" | "++) . showDOp) ops)
    showDOp (opname,args) =
       opname ++ (concat $ [sp++lb++opname++"_"++(show n)
           ++"::"++sp++(showOpArg x)++rb | (x,n) <- listEnum args])
    showOp (opname,args) =
       opname ++ (concat $ map ((sp ++) . showOpArg) args)
    showOpArg arg = case arg of
                    TFree _ _ -> showTyp Null 1000 arg
                    _         -> "\"" ++ showTyp Null 1000 arg ++ "\""
    showCaseLemmata dtDefs = text (concat $ map showCaseLemmata1 dtDefs)
    showCaseLemmata1 dts = concat $ map showCaseLemma dts
    showCaseLemma (_, []) = ""
    showCaseLemma (tyCons, (c:cons)) = 
      let cs = "case caseVar of" ++ sp
          sc b = showCons b c ++ (concat $ map (("   | " ++) 
                                                . (showCons b)) cons)
          clSome = sc True
          cl = sc False
          showCons b (cName, args) =
            let pat = cName ++ (concat $ map ((sp ++) . showArg) args) 
                            ++ sp ++ "=>" ++ sp 
                term = showCaseTerm cName args
            in
               if b then pat ++ "Some" ++ sp ++ lb ++ term ++ rb ++ "\n"
                 else pat ++ term ++ "\n"
          showCaseTerm name args = if null name then sa 
                                     else [toLower (head name)] ++ sa
            where sa = (concat $ map ((sp ++) . showArg) args)
          showArg (TFree [] _) = "varName"
          showArg (TFree (n:ns) _) = [toLower n] ++ ns
          showArg (TVar ([], _) _) = "varName"
          showArg (TVar ((n:ns), _) _) = [toLower n] ++ ns
          showArg (Type [] _ _) = "varName"
          showArg (Type m@(n:ns) _ s) = 
            if m == "typeAppl" || m == "fun" || m == "*"  then concat $ map showArg s
              else [toLower n] ++ ns
          showName (TFree v _) = v
          showName (TVar (v, _) _)  = v
          showName (Type n _ _) = n
          proof = "apply (case_tac caseVar)\napply (auto)\ndone\n"
      in
        "lemma" ++ sp ++ "case_" ++ showName tyCons ++ "_SomeProm" ++ sp
                ++ "[simp]:\"" ++ sp ++ lb ++ cs ++ clSome ++ rb ++ sp
                ++ "=\n" ++ "Some" ++ sp ++ lb ++ cs ++ cl ++ rb ++ "\"\n"
                ++ proof

quote_underscores :: String -> String
quote_underscores [] = []
quote_underscores ('_':'_':rest) = '_':quote_underscores rest
quote_underscores ('_':rest) = '\'':'_':quote_underscores rest
quote_underscores (c:rest) = c:quote_underscores rest


instance PrintLaTeX Sign where
    printLatex0 = printText0

sp :: String
sp = " "

rb :: String
rb = ")"

rbb :: String
rbb = rb++rb

lb :: String
lb = "("

lbb :: String
lbb = lb++lb


bracketize :: Bool -> String -> String
bracketize b s = if b then lb++s++rb else s
