{-# OPTIONS -cpp #-}
{- | 
   
    Module      :  $Header$
    Copyright   :  (c) Mingyi Liu and Till Mossakowski and Uni Bremen 2004
    Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

    Maintainer  :  hets@tzi.de
    Stability   :  provisional
    Portability :  portable

-}

{-  
"free datatypes and recursive equations are consistent"

checkFreeType :: (PrettyPrint f, Eq f) => 
                 (Sign f e,[Named (FORMULA f)]) -> Morphism f e m -> [Named (FORMULA f)] 
                       -> Result (Maybe Bool)
Just (Just True) => Yes, is consistent
Just (Just False) => No, is inconsistent
Just Nothing => don't know
-}

{- todo

Improve warnings: sort s should output the actual sort
                  more informative messages
Document the code

Check CASL-lib/Basic/Numbers.casl

-} 

module CASL.CCC.FreeTypes where

import Debug.Trace
import CASL.Sign                -- Sign, OpType
import CASL.Morphism              
import CASL.AS_Basic_CASL       -- FORMULA, OP_{NAME,SYMB}, TERM, SORT, VAR
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel
import CASL.CCC.SignFuns
import Common.AS_Annotation
import Common.PrettyPrint
import Common.Lib.Pretty
import Common.Result
import Common.Id
#ifdef UNI_PACKAGE
import Isabelle.IsaProve
import ChildProcess
#endif
import Foreign

{-
   function checkFreeType:
   - check if leading symbols are new (not in the image of morphism), if not, return Nothing
   - the leading terms consist of variables and constructors only, if not, return Nothing
     - split function leading_Symb into 
       leading_Term_Predication ::  FORMULA f -> Maybe(Either Term (Formula f))
       and 
       extract_leading_symb :: Either Term (Formula f) -> Either OP_SYMB PRED_SYMB
     - collect all operation symbols from recover_Sort_gen_ax fconstrs (= constructors)
   - no variable occurs twice in a leading term, if not, return Nothing
   - check that patterns do not overlap, if not, return Nothing This means:
       in each group of the grouped axioms:
       all patterns of leading terms/formulas are disjoint
       this means: either leading symbol is a variable, and there is just one axiom
                   otherwise, group axioms according to leading symbol
                              no symbol may be a variable
                              check recursively the arguments of constructor in each group
  - return (Just True)
-}
checkFreeType :: (PosItem f, PrettyPrint f, Eq f) => 
                 (Sign f e,[Named (FORMULA f)]) -> Morphism f e m -> [Named (FORMULA f)] 
                  -> Result (Maybe Bool)
checkFreeType (osig,osens) m fsn      
#ifdef UNI_PACKAGE
       | Set.any (\s->not $ elem s srts) newSorts =
                   let (Id ts _ ps) = head $ filter (\s->not $ elem s srts) newL
                       pos = headPos ps
                       sname = concat $ map tokStr ts 
                   in warning Nothing (sname ++ " is not freely generated") pos
       | Set.any (\s->not $ elem s f_Inhabited) newSorts =
                   let (Id ts _ ps) = head $ filter (\s->not $ elem s f_Inhabited) newL
                       pos = headPos ps
                       sname = concat $ map tokStr ts 
                   in warning (Just False) (sname ++ " is not inhabited") pos
       | elem Nothing l_Syms =
                   let p = snd $ head $ filter (\f'-> (fst f') == Nothing) $ map leadingSymPos _axioms
                       pos = case p of
                               Just p' -> headPos p'
                               Nothing -> nullPos 
                   in warning Nothing "axiom is not definitional" pos
       | not $ null $ p_t_axioms ++ pcheck = 
                   let p = get_pos_l $ head (p_t_axioms ++ pcheck)
                       pos = case p of
                               Just p' -> headPos p'
                               Nothing -> nullPos 
                   in warning Nothing "partial axiom is not definitional" pos
       | any id $ map find_ot id_ots =    
                   let pos = headPos old_op_ps
                   in warning Nothing ("Op: " ++ old_op_id ++ " ist not new") pos
       | any id $ map find_pt id_pts =    
                   let pos = headPos old_pred_ps
                   in warning Nothing ("Pedication: " ++ old_pred_id ++ " ist not new")pos
       | not $ and $ map checkTerm leadingTerms =
                   let (Application os _ ps) = head $ filter (\t->not $ checkTerm t) leadingTerms
                       pos = headPos ps
                   in warning Nothing ("a leading term of " ++ (opSymStr os) ++
                      "consist of not only variables and constructors") pos
       | not $ and $ map checkVar leadingTerms =
                   let (Application os _ ps) = head $ filter (\t->not $ checkVar t) leadingTerms
                       pos = headPos ps
                   in warning Nothing ("a variable occurs twice in a leading term of " ++ opSymStr os) pos
       | not $ and $ map checkPatterns leadingPatterns = 
                   let pos = headPos $ snd $ pattern_Pos leadingSymPatterns
                       symb = fst $ pattern_Pos leadingSymPatterns
                   in warning Nothing ("patterns overlap in " ++ symb) pos
       | (not $ null (axioms ++ old_axioms)) && (not $ proof) = 
                   warning Nothing "not terminating" nullPos 
#endif         
       | otherwise = return (Just True)
#ifdef UNI_PACKAGE
{-
  call the symbols in the image of the signature morphism "new"

- each new sort must be a free type,
  i.e. it must occur in a sort generation constraint that is marked as free
     (Sort_gen_ax constrs True)
     such that the sort is in srts, where (srts,ops,_)=recover_Sort_gen_ax constrs
    if not, output "don't know"
  and there must be one term of that sort (inhabited)
    if not, output "no"
- group the axioms according to their leading operation/predicate symbol,
  i.e. the f resp. the p in
  forall x_1:s_n .... x_n:s_n .                  f(t_1,...,t_m)=t
  forall x_1:s_n .... x_n:s_n .       phi =>      f(t_1,...,t_m)=t
                                  Implication  Application  Strong_equation
  forall x_1:s_n .... x_n:s_n .                  p(t_1,...,t_m)<=>phi
  forall x_1:s_n .... x_n:s_n .    phi1  =>      p(t_1,...,t_m)<=>phi
                                 Implication   Predication    Equivalence
  if there are axioms not being of this form, output "don't know"

-}
   where fs1 = map sentence (filter is_user_or_sort_gen fsn)
     --    fs1 = map sentence fsn
         fs = trace (showPretty fs1 "new formulars") fs1                     -- new formulars
         is_user_or_sort_gen ax = take 12 name == "ga_generated" || take 3 name /= "ga_"
             where name = senName ax
         sig = imageOfMorphism m
         oldSorts1 = sortSet sig
         oldSorts = trace (showPretty oldSorts1 "old sorts") oldSorts1          -- old sorts
         allSorts1 = sortSet $ mtarget m
         allSorts = trace (showPretty allSorts1 "all sorts") allSorts1
         newSorts1 = Set.filter (\s-> not $ Set.member s oldSorts) allSorts     -- new sorts
         newSorts = trace (showPretty newSorts1 "new sorts") newSorts1
         newL = Set.toList newSorts
         oldOpMap = opMap sig
         oldPredMap = predMap sig 
         fconstrs = concat $ map fc fs
         fc f = case f of
                  Sort_gen_ax constrs True -> constrs
                  _ ->[]
         (srts1,constructors1,_) = recover_Sort_gen_ax fconstrs
         srts = trace (showPretty srts1 "srts") srts1      --   srts
         constructors = trace (showPretty constructors1 "constructors") constructors1       -- constructors
         f_Inhabited1 = inhabited (Set.toList oldSorts) fconstrs
         f_Inhabited = trace (showPretty f_Inhabited1 "f_inhabited" ) f_Inhabited1          --  f_inhabited
--         leading_o_p1 = filter isOp_Pred fs
--         leading_o_p = trace (showPretty leading_o_p1 "leading_o_p") leading_o_p1         -- leading_o_p
         axioms1 = filter (\f-> case f of                       
                                    Sort_gen_ax _ _ -> False
                                    _ -> True) fs
         axioms = trace (showPretty axioms1 "axioms") axioms1                               --  axioms
         _axioms = map (\f-> case f of
                               Quantification _ _ f' _ -> f'
                               _ -> f) axioms

         l_Syms1 = map leadingSym axioms                                    
         l_Syms = trace (showPretty l_Syms1 "leading_Symbol") l_Syms1                       -- leading_Symbol
         op_Syms = concat $ map (\s-> case s of
                                        Just (Left op) -> [op]
                                        _ -> []) l_Syms
         pred_Syms = concat $ map (\s-> case s of
                                          Just (Right p) -> [p]
                                          _ -> []) l_Syms  
{-
  check all partial axiom
-}
         p_axioms = filter partialAxiom _axioms                       -- all partial axioms
         t_axioms = filter (not.partialAxiom) _axioms                 -- all total axioms 
         p_t_axioms = filter (\f-> case (opTyp_Axiom f) of            -- exist partial axioms in total axioms?
                                     Just False -> True
                                     _ -> False) t_axioms
         equi_p_axioms = filter (\f-> case f of
                                       Equivalence _ _ _ -> True
                                       _ -> False) p_axioms
         opSyms_p = map (\os-> case os of
                                 (Just (Left opS)) -> opS
                                 _ -> error "partial axiom") $ map leadingSym equi_p_axioms 
         impl_p_axioms = filter (\f-> case f of
                                        Equivalence _ _ _ -> False
                                        Negation _ _ -> False
                                        _ -> True) p_axioms
         pcheck = foldl (\im os-> 
                           filter (\im'-> 
                             case leadingSym im' of
                               (Just (Left opS)) -> opS /= os
                               _ -> False) im) impl_p_axioms opSyms_p         
{- 
  check if leading symbols are new (not in the image of morphism),
        if not, return Nothing
-}
         op_fs = filter (\f-> case leadingSym f of
                                Just (Left _) -> True
                                _ -> False) _axioms 
         pred_fs = filter (\f-> case leadingSym f of
                                  Just (Right _) -> True
                                  _ -> False) _axioms 
         filterOp symb = case symb of
                           Just (Left (Qual_op_name ident (Op_type k as rs _) _))->
                                [(ident, OpType {opKind=k, opArgs=as, opRes=rs})]
                           _ -> []
         filterPred symb = case symb of
                               Just (Right (Qual_pred_name ident (Pred_type s _) _))->
                                    [(ident, PredType {predArgs=s})]
                               _ -> [] 
         id_ots = concat $ map filterOp $ l_Syms 
         id_pts = concat $ map filterPred $ l_Syms
         old_op_id= idStr $ fst $ head $ filter (\ot->find_ot ot) $ id_ots
         old_pred_id = idStr $ fst $ head $ filter (\pt->find_pt pt) $ id_pts
         old_op_ps = case head $ map leading_Term_Predication $       
                          filter (\f->find_ot $ head $ filterOp $ leadingSym f) op_fs of
                       Just (Left (Application _ _ p)) -> p
                       _ -> []
         old_pred_ps = case head $ map leading_Term_Predication $ 
                            filter (\f->find_pt $ head $ filterPred $ leadingSym f) pred_fs of
                         Just (Right (Predication _ _ p)) -> p
                         _ -> []
         find_ot (ident,ot) = case Map.lookup ident oldOpMap of
                                Nothing -> False
                                Just ots -> Set.member ot ots
         find_pt (ident,pt) = case Map.lookup ident oldPredMap of
                                Nothing -> False
                                Just pts -> Set.member pt pts
{-
   the leading terms consist of variables and constructors only, if not, return Nothing
     - split function leading_Symb into 
       leading_Term_Predication ::  FORMULA f -> Maybe(Either Term (Formula f))
       and 
       extract_leading_symb :: Either Term (Formula f) -> Either OP_SYMB PRED_SYMB
     - collect all operation symbols from recover_Sort_gen_ax fconstrs (= constructors)
-}
         ltp1 = map leading_Term_Predication (t_axioms ++ impl_p_axioms)                 
         ltp = trace (showPretty ltp1 "leading_term_pred") ltp1              --  leading_term_pred
         leadingTerms1 = concat $ map (\tp->case tp of
                                              Just (Left t)->[t]
                                              _ -> []) $ ltp
         leadingTerms = trace (showPretty leadingTerms1 "leading Term") leadingTerms1   -- leading Term
         checkTerm (Application _ ts _) = all id $ map (\t-> case (term t) of
                                                               Qual_var _ _ _ -> True
                                                               Application op' _ _ -> elem op' constructors && 
                                                                                      checkTerm (term t) 
                                                               _ -> False) ts
{-
   no variable occurs twice in a leading term, 
      if not, return Nothing
-} 
         checkVar (Application _ ts _) = notOverlap $ concat $ map allVarOfTerm ts
         allVarOfTerm t = case t of
                            Qual_var _ _ _ -> [t]
                            Sorted_term t' _ _ -> allVarOfTerm  t'
                            Application _ ts _ -> if length ts==0 then []
                                                  else concat $ map allVarOfTerm ts
                            _ -> [] 
{-  
   check that patterns do not overlap, if not, return Nothing This means:
       in each group of the grouped axioms:
       all patterns of leading terms/formulas are disjoint
       this means: either leading symbol is a variable, and there is just one axiom
                   otherwise, group axioms according to leading symbol
                              no symbol may be a variable
                              check recursively the arguments of constructor in each group
-}
         leadingSymPatterns = case (groupAxioms (t_axioms ++ impl_p_axioms)) of
                                Just sym_fs -> zip (fst $ unzip sym_fs) $
                                                   (map ((map (\f->case f of
                                                                     Just (Left (Application _ ts _))->ts
                                                                     Just (Right (Predication _ ts _))->ts
                                                                     _ -> [])).
                                                         (map leading_Term_Predication)) $ map snd sym_fs)
                                Nothing -> error "axiom group"
         leadingPatterns1 = snd $ unzip leadingSymPatterns
   --      leadingPatterns = trace (showPretty leadingPatterns1 (tmp ++ "\n" ++ tmp1 ++ "\n" ++ tmp2 ++ "\n")) leadingPatterns1    --leading Patterns
         leadingPatterns = trace (showPretty leadingPatterns1 "leadingPatterns") leadingPatterns1    --leading Patterns
         isApp t = case t of
                     Application _ _ _->True
                     Sorted_term t' _ _ ->isApp t'
                     _ -> False
         isVar t = case t of
                     Qual_var _ _ _ ->True
                     Sorted_term t' _ _ ->isVar t'
                     _ -> False
         allIdentic ts = all (\t-> t== (head ts)) ts
         notOverlap ts = let check [] = True
                             check (p:ps)=if elem p ps then False
                                          else check ps
                         in check ts 
         patternsOfTerm t = case t of
                              Application (Qual_op_name _ _ _) ts _-> ts
                              Sorted_term t' _ _ -> patternsOfTerm t'
                              _ -> []
         sameOps app1 app2 = case (term app1) of
                               Application ops1 _ _ -> case (term app2) of
                                                         Application ops2 _ _ -> ops1==ops2
                                                         _ -> False
                               _ -> False
         group [] = []
         group ps = (filter (\p1-> sameOps (head p1) (head (head ps))) ps):
                      (group $ filter (\p2-> not $ sameOps (head p2) (head (head ps))) ps)
         checkPatterns ps 
                | length ps <=1 = True
                | allIdentic ps = False
                | all isVar $ map head ps = if allIdentic $ map head ps then checkPatterns $ map tail ps
                                            else False
                | all (\p-> sameOps p (head (head ps))) $ map head ps = 
                                            checkPatterns $ map (\p'->(patternsOfTerm $ head p')++(tail p')) ps 
                | all isApp $ map head ps = all id $ map checkPatterns $ group ps
                | otherwise = False

         pattern_Pos [] = error "pattern overlap"
         pattern_Pos sym_ps = if not $ checkPatterns $ snd $ head sym_ps then symPos $ fst $ head sym_ps
                              else pattern_Pos $ tail sym_ps
         symPos sym = case sym of
                        Left (Qual_op_name on _ ps) -> (idStr on,ps)
                        Right (Qual_pred_name pn _ ps) -> (idStr pn,ps)
                        _ -> error "pattern overlap"               
{-
         term_Pos t = case term t of
                        Application _ _ p -> p
                        Qual_var _ _ p -> p
                        _ -> []
         pattern_Pos pas
                | length pas <=1 = []
                | allIdentic pas = term_Pos $ head $ head pas
                | not $ all isApp $ map head pas = term_Pos $ head $ filter (\t-> isVar t) $ map head pas
                | all isVar $ map head pas = if allIdentic $ map head pas then pattern_Pos $ map tail pas
                                            else term_Pos $ head $ map head pas 
                | all (\p-> sameOps p (head (head pas))) $ map head pas =
                                            pattern_Pos $ map (\p'->(patternsOfTerm $ head p')++(tail p')) pas
                | otherwise = concat $ map pattern_Pos $ group pas
-}

{- 
   Automatic termination proof
   using cime, see http://cime.lri.fr/

  interface to cime system, using newChildProcess
  transform CASL signature to Cime signature, CASL formulas to Cime rewrite rules

Example:

spec NatJT2 = {} then
  free type Nat ::= 0 | suc(Nat)
  op __+__ : Nat*Nat->Nat
  forall x,y:Nat
  . 0+x=x
  . suc(x)+y=suc(x+y)
end

theory generated by Hets:

sorts Nat
op 0 : Nat
op __+__ : Nat * Nat -> Nat
op suc : Nat -> Nat


forall X1:Nat; Y1:Nat
    . (op suc : Nat -> Nat)((var X1 : Nat) : Nat) : Nat =
          (op suc : Nat -> Nat)((var Y1 : Nat) : Nat) : Nat <=>
          (var X1 : Nat) : Nat = (var Y1 : Nat) : Nat %(ga_injective_suc)%

forall Y1:Nat
    . not (op 0 : Nat) : Nat =
              (op suc : Nat -> Nat)((var Y1 : Nat) : Nat) : Nat %(ga_disjoint_0_suc)%

generated{sort Nat; op 0 : Nat;
                    op suc : Nat -> Nat} %(ga_generated_Nat)%

forall x, y:Nat
    . (op __+__ : Nat * Nat -> Nat)((op 0 : Nat) : Nat,
                                    (var x : Nat) : Nat) : Nat =
          (var x : Nat) : Nat

forall x, y:Nat
    . (op __+__ : Nat *
                  Nat -> Nat)((op suc : Nat -> Nat)((var x : Nat) : Nat) : Nat,
                              (var y : Nat) : Nat) : Nat =
          (op suc : Nat -> Nat)((op __+__ : Nat *
                                            Nat -> Nat)((var x : Nat) : Nat,
                                                        (var y : Nat) : Nat) : Nat) : Nat

CiME:
let F = signature "when_else : 3; eq : binary; True,False : constant; 0 : constant; suc : unary; __+__ : binary; ";
let X = vars "t1 t2 x y";
let axioms = TRS F X "
eq(t1,t1) -> True; 
eq(t1,t2) -> False; 
when_else(t1,True,t2) -> t1; 
when_else(t1,False,t2) -> t2; 
__+__(0,x) -> x; 
__+__(suc(x),y) -> suc(__+__(x,y)); ";
termcrit "dp";
termination axioms;


spec NatJT1 = 
  sort Elem
  free type Bool ::= True | False
  op __or__ : Bool*Bool->Bool
  . True or True = True
  . True or False = True
  . False or True = True
  . False or False = False
then
  free types Tree ::= Leaf(Elem) | Branch(Forest);
             Forest ::= Nil | Cons(Tree;Forest)
  op elemT : Elem * Tree -> Bool
  op elemF : Elem * Forest -> Bool
  forall x,y:Elem; t:Tree; f:Forest
  . elemT(x,Leaf(y)) = True when x=y else False
  . elemT(x,Branch(f)) = elemF(x,f)
  . elemF(x,Nil) = False
  . elemF(x,Cons(t,f)) = elemT(x,t) or elemF(x,f)
end

CiME:
let F = signature "when_else : 3; eq : binary; True,False : constant; True : constant; False : constant; __or__ : binary; Leaf : unary; Branch : unary; Nil : constant; Cons : binary; elemT : binary; elemF : binary; ";
let X = vars "t1 t2 x y t f";
let axioms = TRS F X "
eq(t1,t1) -> True;
eq(t1,t2) -> False;
when_else(t1,True,t2) -> t1;
when_else(t1,False,t2) -> t2;
__or__(True,True) -> True; 
__or__(True,False) -> True; 
__or__(False,True) -> True; 
__or__(False,False) -> False;
elemT(x,Leaf(y)) -> when_else(True,eq(x,y),False); 
elemT(x,Branch(f)) -> elemF(x,f); 
elemF(x,Nil) -> False; 
elemF(x,Cons(t,f)) -> __or__(elemT(x,t),elemF(x,f)); ";

-}      
         idStrT id = map (\s-> case s of
                                 '[' -> '|'
                                 ']' -> '|'
                                 _ -> s) $ idStr id
         oldfs1 = map sentence (filter is_user_or_sort_gen osens)
         oldfs = trace (showPretty oldfs1 "old formulas") oldfs1               -- old formulas
         old_axioms = filter (\f->case f of                      
                                    Sort_gen_ax _ _ -> False
                                    _ -> True) oldfs
         o_fconstrs = concat $ map fc oldfs
         (_,o_constructors1,_) = recover_Sort_gen_ax o_fconstrs
         o_constructors = trace (showPretty o_constructors1 "o_constructors") o_constructors1       -- olc constructors
         o_l_Syms1 = map leadingSym $ filter isOp_Pred $ oldfs             
         o_l_Syms = trace (showPretty o_l_Syms1 "o_leading_Symbol") o_l_Syms1         --old leading_Symbol
         o_op_Syms = concat $ map (\s-> case s of
                                          Just (Left op) -> [op]
                                          _ -> []) o_l_Syms
         o_pred_Syms = concat $ map (\s-> case s of
                                            Just (Right p) -> [p]
                                            _ -> []) o_l_Syms  
         --  read the result of proof
         rP cp = do
            msg <- readMsg cp
            case msg of
              "Termination proof found." -> return True
              "Quitting." -> return False
              _ -> rP cp
         --  OP_SYMB -> Signature of CiME
         opStr o_s = case o_s of                -- kontext analyse
                       Qual_op_name op_n (Op_type k a_sorts _ _) _ -> case (length a_sorts) of 
                                                                            0 -> (idStrT op_n) ++ " : constant"
                                                                            1 -> (idStrT op_n) ++ " : unary"
                                                                            2 -> (idStrT op_n) ++ " : binary"
                                                                            3 -> (idStrT op_n) ++ " : 3"
                                                                            4 -> (idStrT op_n) ++ " : 4"
                                                                            5 -> (idStrT op_n) ++ " : 5"
                                                                            6 -> (idStrT op_n) ++ " : 6"
                                                                            _ -> error "Termination_Signature_OpS"
                       _ -> error "Termination_Signature_OpS: Op_name"
         --  PRED_SYMB -> Signature of CiME
         predStr p_s = case p_s of
                       Qual_pred_name pred_n (Pred_type sts _) _ -> case (length sts) of
                                                                      0 -> (idStrT pred_n) ++ " : constant"
                                                                      1 -> (idStrT pred_n) ++ " : unary"
                                                                      2 -> (idStrT pred_n) ++ " : binary"
                                                                      3 -> (idStrT pred_n) ++ " : 3"
                                                                      4 -> (idStrT pred_n) ++ " : 4"
                                                                      5 -> (idStrT pred_n) ++ " : 5"
                                                                      6 -> (idStrT pred_n) ++ " : 6"
                                                                      _ -> error "Termination_Signature_PredS"
                       _ -> error "Termination_Signature_PredS"
         noDouble [] = []
         noDouble (x:xs) 
                  | elem x xs = noDouble xs
                  | otherwise = x:(noDouble xs)

{-
         --  collection of signature
         --  operation
         sigComb sig1 sig2 | null sig2 =sig1             
                           | otherwise = case (head sig2) of
                                           Just (Left o_s) -> if elem o_s sig1 then sigComb sig1 (tail sig2)
                                                              else sigComb (o_s:sig1) (tail sig2)
                                           Just (Right p_s) -> p_s:(sigComb sig1 (tail sig2))       --  not Predication
                                           _ -> error "Termination_Signature_Comb"
-}
         --  build signature of operation together 
         opSignStr signs str                      
                 | null signs = str
                 | otherwise =  opSignStr (tail signs) (str ++ (opStr $ head signs) ++ "; ")
         --  build signature of predication together 
         predSignStr signs str                      
                 | null signs = str
                 | otherwise =  predSignStr (tail signs) (str ++ (predStr $ head signs) ++ "; ")

         --  all variable of a axiom
         varOfAxiom f = case f of
                          Quantification Universal v_d _ _ -> concat $  map (\v-> case v of
                                                                                   Var_decl vs _ _ -> vs
                                                                                   _ -> error "Termination_Variable") v_d
                          Quantification Existential v_d _ _ -> concat $  map (\v-> case v of
                                                                                   Var_decl vs _ _ -> vs
                                                                                   _ -> error "Termination_Variable") v_d
                          Quantification Unique_existential v_d _ _ -> concat $  map (\v-> case v of
                                                                                   Var_decl vs _ _ -> vs
                                                                                   _ -> error "Termination_Variable") v_d
                          _ -> [] 
         allVar vs = foldl (\hv tv->hv ++ (filter (\v->not $ elem v hv) tv)) (head vs) (tail vs)
         --  transform variables to string
         varsStr vars str                               
                 | null vars = str
                 | otherwise = if null str then varsStr (tail vars) (tokStr $ head vars)
                               else varsStr (tail vars) (str ++ " " ++ (tokStr $ head vars))
         --  transform a axiom to string
         f_str f = case f of
                     Quantification Universal _ f' _ -> f_str f'
                     Conjunction fs _ -> error "Termination_Axioms_Conjunction"
                     Disjunction fs _ -> error "Termination_Axioms_Disjunction"
                     Implication f1 f2 _ _ -> error "Termination_Axioms_Implication" 
                     Equivalence f1 f2 _ -> error "Termination_Axioms_Equivalence"
                     Negation f' _ -> error "Termination_Axioms_Negation"
                     True_atom _ -> "Termination_Axioms_True"	    
	             False_atom _ -> "Termination_Axioms_False"
                     Predication p_s ts _ -> ((predSymStr p_s) ++ "(" ++ (termsStr ts) ++ ") -> True")
                     Definedness t _ -> "Termination_Axioms_Definedness"
                     Existl_equation t1 t2 _ -> (termStr t1) ++ " -> " ++ (termStr t2)
                     Strong_equation t1 t2 _ -> (termStr t1) ++ " -> " ++ (termStr t2)                   
                     _ -> error "Termination_Axioms"
         --  condition of term
         t_f_str f =case f of
                     Strong_equation t1 t2 _ -> ("eq(" ++ (termStr t1) ++ "," ++ (termStr t2) ++ ")")
                     _ -> error "Termination_Term-Formula"
         termsStr ts = drop 1 $ concat $ map (\s->","++s) $ map termStr ts
         --  transform a term to string
         termStr t = case (term t) of
                       (Qual_var var _ _) -> tokStr var
                       (Application (Qual_op_name opn _ _) ts _) -> if null ts then (idStrT opn)
                                                                    else ((idStrT opn) ++ "(" ++ 
                                                                         (tail $ concat $ map (\s->"," ++ s) $ map termStr ts) ++ ")")
                       (Conditional t1 f t2 _) -> ("when_else(" ++ (termStr t1) ++ "," ++ (t_f_str f) ++  "," ++ (termStr t2)  ++
                                                  ")")
                       _ -> error "Termination_Term"
         --  transform all axioms to string
         axiomStr axioms str
                 | null axioms = str
                 | otherwise = axiomStr (tail axioms) (str ++ (f_str $ (head axioms)) ++ "; ")                    
         proof = unsafePerformIO (do
            --     cim <- newChildProcess "/home/xinga/bin/cime" []
                 cim <- newChildProcess "cime" []
                 sendMsg cim ("let F = signature \"when_else : 3; eq : binary; True,False : constant; " ++ 
                              (opSignStr (noDouble (o_constructors ++ constructors ++ o_op_Syms ++ op_Syms)) "") ++
                              (predSignStr (noDouble (o_pred_Syms ++ pred_Syms)) "") ++ "\";")
                 sendMsg cim ("let X = vars \"t1 t2 " ++ (varsStr (allVar $ map varOfAxiom $ old_axioms ++ axioms) "") ++ "\";")        
                 sendMsg cim ("let axioms = TRS F X \"eq(t1,t1) -> True; " ++ 
                                                     "eq(t1,t2) -> False; " ++ 
                                                     "when_else(t1,True,t2) -> t1; " ++ 
                                                     "when_else(t1,False,t2) -> t2; " ++
                                (axiomStr (old_axioms ++ axioms) "") ++"\";")    
                 sendMsg cim "termcrit \"dp\";"
                 sendMsg cim "termination axioms;"
                 sendMsg cim "#quit;"
                 res <-rP cim
                 return res)
       --  print infomation 
         tmp  = ("let F = signature \"when_else : 3; eq : binary; True,False : constant; " ++ 
                              (opSignStr (noDouble (o_constructors ++ constructors ++ o_op_Syms ++ op_Syms)) "") ++
                              (predSignStr (noDouble (o_pred_Syms ++ pred_Syms)) "") ++ "\";") 
         tmp1 = ("let X = vars \"t1 t2 " ++ (varsStr (allVar $ map varOfAxiom $ old_axioms ++ axioms) "") ++ "\";")        
         tmp2 = ("let axioms = TRS F X \"eq(t1,t1) -> True; " ++ 
                                                     "eq(t1,t2) -> False; " ++ 
                                                     "when_else(t1,True,t2) -> t1; " ++ 
                                                     "when_else(t1,False,t2) -> t2; " ++
                                (axiomStr (old_axioms ++ axioms) "") ++"\";")    
                              
#endif

leadingSym :: FORMULA f -> Maybe (Either OP_SYMB PRED_SYMB)
leadingSym f = do
       tp<-leading_Term_Predication f
       return (extract_leading_symb tp)
 

leadingSymPos ::(PosItem f)=> FORMULA f -> (Maybe (Either OP_SYMB PRED_SYMB),Maybe [Pos])
leadingSymPos f = leading (f,False,False)
  where leading (f,b1,b2)= case (f,b1,b2) of
                             ((Quantification _ _ f' _),b1,b2)  -> leading (f',b1,b2)
                             ((Negation f' _),b1,b2) -> leading (f',b1,b2)
                             ((Implication _ f' _ _),False,False) -> leading (f',True,False)
                             ((Equivalence f' _ _),b,False) -> leading (f',b,True)
                             ((Definedness t _),_,_) -> case (term t) of
                                                          Application opS _ p -> (Just (Left opS),Just p)
                                                          _ -> (Nothing,(get_pos_l f))
                             ((Predication predS _ _),_,_) -> ((Just (Right predS)),(get_pos_l f))
                             ((Strong_equation t _ _),_,_) -> case (term t) of
                                                                Application opS _ p -> (Just (Left opS),Just p)                 
                                                                _ -> (Nothing,(get_pos_l f))
                             ((Existl_equation t _ _),_,_) -> case (term t) of
                                                                Application opS _ p -> (Just (Left opS),Just p)
                                                                _ -> (Nothing,(get_pos_l f))
                             _ -> (Nothing,(get_pos_l f)) 


term :: TERM f -> TERM f
term t = case t of
           Sorted_term t' _ _ ->term t'
           _ -> t 

leading_Term_Predication ::  FORMULA f -> Maybe (Either (TERM f) (FORMULA f))
leading_Term_Predication f = leading (f,False,False)
    where leading (f,b1,b2)= case (f,b1,b2) of
                               ((Quantification _ _ f' _),b1,b2)  -> leading (f',b1,b2)     
                               ((Negation f' _),b1,b2) -> leading (f',b1,b2)
                               ((Implication _ f' _ _),False,False) -> leading (f',True,False)
                               ((Equivalence f' _ _),b,False) -> leading (f',b,True)
                               ((Definedness t _),_,_) -> case (term t) of
                                                            Application _ _ _ -> return (Left (term t))
                                                            _ -> Nothing
                               ((Predication p ts ps),_,_) -> return (Right (Predication p ts ps))
                               ((Strong_equation t _ _),_,_) -> case (term t) of
                                                                  Application _ _ _ -> return (Left (term t))
                                                                  _ -> Nothing
                               ((Existl_equation t _ _),_,_) -> case (term t) of
                                                                  Application _ _ _ -> return (Left (term t))
                                                                  _ -> Nothing
                               _ -> Nothing
 


extract_leading_symb :: Either (TERM f) (FORMULA f) -> Either OP_SYMB PRED_SYMB
extract_leading_symb lead = case lead of
                              Left (Application os _ _) -> Left os
                              Right (Predication p _ _) -> Right p

{- group the axioms according to their leading symbol
   output Nothing if there is some axiom in incorrect form -}
groupAxioms :: [FORMULA f] -> Maybe [(Either OP_SYMB PRED_SYMB,[FORMULA f])]
groupAxioms phis = do
  symbs <- mapM leadingSym phis
  return (filterA (zip symbs phis) [])
    where filterA [] _=[]
          filterA (p:ps) symb=let fp=fst p
                                  p'= if elem fp symb then []
                                      else [(fp,snd $ unzip $ filter (\p'->(fst p')==fp) (p:ps))]
                                  symb'= if not $ (elem fp symb) then fp:symb
                                         else symb
                              in p'++(filterA ps symb')


isOp_Pred :: FORMULA f -> Bool
isOp_Pred f = case f of
               Quantification _ _ f' _ -> isOp_Pred f'
               Negation f' _ -> isOp_Pred f'
               Implication _ f' _ _ -> isOp_Pred f'
               Equivalence f' _ _ -> isOp_Pred f'
               Definedness t _ -> case (term t) of
                                    (Application _ _ _) -> True
                                    _ -> False
               Predication _ _ _ -> True
               Existl_equation t _ _ -> case (term t) of 
                                          (Application _ _ _) -> True
                                          _ -> False
               Strong_equation t _ _ -> case (term t) of
                                          (Application _ _ _) -> True
                                          _-> False 
               _ -> False

partialAxiom :: FORMULA f -> Bool
partialAxiom f = case f of
                    Quantification _ _ f' _ -> partialAxiom f'
                    Negation f' _ ->
                               case f' of
                                 Definedness t _ -> 
                                            case (term t) of
                                              Application opS _ _ -> case (partial_OpSymb opS) of
                                                                       Just True -> True
                                                                       _ -> False
                                              _ -> False
                                 _ -> False
                    Implication f' _ _ _ -> 
                               case f' of
                                 Definedness t _ -> 
                                            case (term t) of
                                              Application opS _ _ -> case (partial_OpSymb opS) of
                                                                       Just True -> True
                                                                       _ -> False
                                              _ -> False
                                 _ -> False
                    Equivalence f' _ _ -> 
                               case f' of
                                 Definedness t _ -> 
                                   case (term t) of
                                     Application opS _ _ -> case (partial_OpSymb opS) of
                                                              Just True -> True
                                                              _ -> False
                                     _ -> False
                                 _ -> False
                    _ -> False                    

-- leadingTerm is total operation : Just True
-- leadingTerm is partial operation : Just False
-- others : Nothing
opTyp_Axiom :: FORMULA f -> Maybe Bool
opTyp_Axiom f = case (leadingSym f) of
                  Just (Left (Op_name _)) -> Nothing
                  Just (Left (Qual_op_name _ (Op_type Total _ _ _) _)) -> Just True 
                  Just (Left (Qual_op_name _ (Op_type Partial _ _ _) _)) -> Just False  
                  _ -> Nothing 

idStr :: Id -> String
idStr (Id ts _ _) = concat $ map tokStr ts 

opSymStr :: OP_SYMB -> String 
opSymStr os = case os of
                Op_name on -> idStr on
	        Qual_op_name on _ _ -> idStr on

predSymStr :: PRED_SYMB -> String
predSymStr ps = case ps of 
                  Pred_name pn -> idStr pn 
	          Qual_pred_name pn _ _ -> idStr pn
{-
noDouble :: (Eq a) => [a] -> [a]
noDouble [] = []
noDouble (x:xs) 
    | elem x xs = noDouble xs
    | otherwise = x:(noDouble xs)
-}
