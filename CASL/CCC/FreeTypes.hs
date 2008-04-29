{- |
Module      :  $Header$
Description :  consistency checking of free types
Copyright   :  (c) Mingyi Liu and Till Mossakowski and Uni Bremen 2004-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  xinga@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

Consistency checking of free types
-}

module CASL.CCC.FreeTypes where

import CASL.Sign                -- Sign, OpType
import CASL.Morphism
import CASL.AS_Basic_CASL       -- FORMULA, OP_{NAME,SYMB}, TERM, SORT, VAR
import qualified Data.Map as Map
import qualified Data.Set as Set
-- import qualified Common.Lib.Rel as Rel
import CASL.CCC.SignFuns
import CASL.CCC.TermFormula
import CASL.CCC.TerminationProof
import Common.AS_Annotation
import Common.DocUtils
import Common.Result
import Common.Id
import Maybe
import Debug.Trace
import Data.List (nub,intersect,delete)


{------------------------------------------------------------------------
   function checkFreeType:
   - check if leading symbols are new (not in the image of morphism),
           if not, return Nothing
   - the leading terms consist of variables and constructors only,
           if not, return Nothing
     - split function leading_Symb into
       leading_Term_Predication
       and
       extract_leading_symb
     - collect all operation symbols from recover_Sort_gen_ax fconstrs
                                                       (= constructors)
   - no variable occurs twice in a leading term, if not, return Nothing
   - check that patterns do not overlap, if not, return Nothing This means:
       in each group of the grouped axioms:
       all patterns of leading terms/formulas are disjoint
       this means: either leading symbol is a variable,
                           and there is just one axiom
                   otherwise, group axioms according to leading symbol
                              no symbol may be a variable
                              check recursively the arguments of
                              constructor in each group
  - termination proof
  - return (Just True)
-------------------------------------------------------------------------}
-- | free datatypes and recursive equations are consistent
checkFreeType :: (Sign () (),[Named (FORMULA ())]) -> Morphism () () ()
                 -> [Named (FORMULA ())] -> Result (Maybe (Bool,[FORMULA ()]))
checkFreeType (osig,osens) m fsn
    | not $ null notFreeSorts =
        let (Id ts _ pos) = head notFreeSorts
            sname = concat $ map tokStr ts
        in warning Nothing (sname ++ " is not freely generated") pos
    | not $ null nefsorts =
        let (Id ts _ pos) = head nefsorts
            sname = concat $ map tokStr ts
        in warning (Just (False,[])) (sname ++ " is not inhabited") pos
    | elem Nothing l_Syms =
        let pos = snd $ head $ filter (\f'-> (fst f') == Nothing) $
                  map leadingSymPos _axioms
        in warning Nothing "axiom is not definitional" pos
    | not $ null $ un_p_axioms =
        let pos = posOf $ (take 1 un_p_axioms)
        in warning Nothing "partial axiom is not definitional" pos
    | (length dom_l) /= (length $ nub $ dom_l) =
        let pos = posOf $ (take 1 dualDom)
            dualOS = head $ filter (\o-> elem o $ delete o dom_l) dom_l
            dualDom = filter (\f-> domain_os f dualOS) p_axioms
        in warning Nothing "partial axiom is not definitional" pos
    | not $ null $ pcheck =
        let pos = posOf $ (take 1 pcheck)
        in warning Nothing "partial axiom is not definitional" pos
    | any id $ map find_ot id_ots =
        let pos = old_op_ps
        in warning Nothing ("Operation: " ++ old_op_id ++ " is not new") pos
    | any id $ map find_pt id_pts =
        let pos = old_pred_ps
        in warning Nothing ("Predicate: " ++old_pred_id++ " is not new") pos
    | not $ and $ map (checkTerms tsig constructors) $
      map arguOfTerm leadingTerms=
        let (Application os _ _) = tt
            tt= head $ filter (\t->not $ checkTerms tsig constructors $
                                   arguOfTerm t) $ leadingTerms
            pos = axiomRangeforTerm _axioms tt
        in warning Nothing ("a leading term of " ++ (opSymName os) ++
           " consists of not only variables and constructors") pos
    | not $ and $ map (checkTerms tsig constructors) $
      map arguOfPred leadingPreds=
        let (Predication ps _ pos) = quanti pf
            pf= head $ filter (\p->not $ checkTerms tsig constructors $
                                   arguOfPred p) $ leadingPreds
        in warning Nothing ("a leading predicate of " ++ (predSymName ps) ++
           " consists of not only variables and constructors") pos
    | not $ and $ map checkVar_App leadingTerms =
        let (Application os _ _) = tt
            tt = head $ filter (\t->not $ checkVar_App t) leadingTerms
            pos = axiomRangeforTerm _axioms tt
        in warning Nothing ("a variable occurs twice in a leading term of " ++
                            opSymName os) pos
    | not $ and $ map checkVar_Pred leadingPreds =
        let (Predication ps _ pos) = quanti pf
            pf = head $ filter (\p->not $ checkVar_Pred p) leadingPreds
        in warning Nothing ("a variable occurs twice in a leading " ++
                            "predicate of " ++ predSymName ps) pos
    | (not $ null fs_terminalProof) && (proof /= Just True)=
         if proof == Just False
         then warning Nothing "not terminating" nullRange
         else warning Nothing "cannot prove termination" nullRange
    | not $ ((null (info_subsort ++ overlap_query ++ ex_axioms))) =
        return (Just (True,(overlap_query ++
                            ex_axioms ++
                            info_subsort)))
    | otherwise = return (Just (True,[]))
{-
  call the symbols in the image of the signature morphism "new"

- each new sort must be a free type,
  i.e. it must occur in a sort generation constraint that is marked as free
    (Sort_gen_ax constrs True)
    such that the sort is in srts,
        where (srts,ops,_)=recover_Sort_gen_ax constrs
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
    where
    fs = map sentence (filter is_user_or_sort_gen fsn)
    fs_terminalProof = filter (\f->(not $ isSortGen f) &&
                                   (not $ is_Membership f) &&
                                   (not $ is_ex_quanti f) &&
                                   (not $ isDomain f)) fs
    ofs = map sentence (filter is_user_or_sort_gen osens)
    sig = imageOfMorphism m
    tsig = mtarget m
    oldSorts = (sortSet osig)
    oSorts = Set.toList oldSorts
    allSorts = sortSet $ tsig
    esorts = Set.toList $ emptySortSet tsig
    newSorts = Set.filter (\s-> not $ Set.member s oldSorts) allSorts                                             
    nSorts = Set.toList newSorts
    axOfS = filter (\f-> (isSortGen f) ||
                         (is_Membership f)) fs
    notFreeSorts = filter (\s->(is_free_gen_sort s axOfS) == Just False) nSorts
    oldOpMap = opMap sig
    oldPredMap = predMap sig
    fconstrs = concat $ map constraintOfAxiom (ofs ++ fs)
    (srts,constructors_o,_) = recover_Sort_gen_ax fconstrs
    constructors = constructorOverload tsig op_map constructors_o
    f_Inhabited = inhabited oSorts fconstrs
    fsorts = filter (\s-> not $ elem s esorts) $ intersect nSorts srts
    nefsorts = filter (\s->not $ elem s f_Inhabited) fsorts
    op_map = opMap $ tsig
    axioms = filter (\f-> (not $ isSortGen f) &&
                           (not $ is_Membership f)) fs
    memberships = filter (\f-> is_Membership f) fs
    info_subsort1 = concat $ map (infoSubsort esorts) memberships
    info_subsort = trace (showDoc info_subsort1 "infoSubsort") info_subsort1
    _axioms = map quanti axioms
    l_Syms = map leadingSym axioms        -- leading_Symbol 
{-
   check all partial axiom
-}
    p_axioms = filter partialAxiom _axioms           -- all partial axioms
    pax_with_def = filter containDef p_axioms
    ax_without_dom = filter (not.isDomain) _axioms
    pax_without_def = filter (not.containDef) p_axioms
    un_p_axioms = filter (not.correctDef) pax_with_def
    dom_l = domainOpSymbs p_axioms
    pcheck = filter (\f-> case leadingSym f of
                            Just (Left opS) ->
                              elem opS dom_l
                            _ -> False) pax_without_def
    domains = domainList fs
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
    id_ots = concat $ map filterOp $ l_Syms
    id_pts = concat $ map filterPred $ l_Syms
    old_op_id= idStr $ fst $ head $ filter (\ot->find_ot ot) $ id_ots
    old_pred_id = idStr $ fst $ head $ filter (\pt->find_pt pt) $ id_pts
    old_op_ps = case head $ map leading_Term_Predication $
                     filter (\f-> find_ot $ head $ filterOp $
                                  leadingSym f) op_fs of
                  Just (Left (Application _ _ p)) -> p
                  _ -> nullRange
    old_pred_ps = case head $ map leading_Term_Predication $
                       filter (\f->find_pt $ head $ filterPred $
                                   leadingSym f) pred_fs of
                    Just (Right (Predication _ _ p)) -> p
                    _ -> nullRange
    find_ot (ident,ot) = case Map.lookup ident oldOpMap of
                           Nothing -> False
                           Just ots -> Set.member ot ots
    find_pt (ident,pt) = case Map.lookup ident oldPredMap of
                           Nothing -> False
                           Just pts -> Set.member pt pts
{-
   the leading terms consist of variables and constructors only,
   if not, return Nothing
   - split function leading_Symb into
      leading_Term_Predication::FORMULA f -> Maybe(Either Term (Formula f))
       and
      extract_leading_symb::Either Term (Formula f) -> Either OP_SYMB PRED_SYMB
   - collect all operation symbols from
        recover_Sort_gen_ax fconstrs (= constructors)
  the leading predication consist of only variables and constructors too
-}
    ltp = map leading_Term_Predication _axioms       --  leading_term_pred
    leadingTerms = concat $ map (\tp->case tp of
                                         Just (Left t)->[t]
                                         _ -> []) $ ltp      -- leading Term
    leadingPreds = concat $ map (\tp->case tp of
                                        Just (Right f)->[f]
                                        _ -> []) $ ltp
{-
   check that patterns do not overlap, if not, return Nothing This means:
       in each group of the grouped axioms:
       all patterns of leading terms/formulas are disjoint
       this means: either leading symbol is a variable,
                           and there is just one axiom
                   otherwise, group axioms according to leading symbol
                              no symbol may be a variable
                              check recursively the arguments of constructor
                              in each group
-}
    axPairs =
        case (groupAxioms ax_without_dom) of
          Just sym_fs -> concat $ map pairs $ map snd sym_fs
          Nothing -> error "CASL.CCC.FreeTypes.<axPairs>"
    olPairs = filter (\a-> checkPatterns $
                       (patternsOfAxiom $ fst a,
                        patternsOfAxiom $ snd a)) axPairs
    subst (f1,f2) = ((f1,sb1),(f2,sb2))
      where p1= patternsOfAxiom f1
            p2= patternsOfAxiom f2
            (sb1,sb2) = st ((p1,[]),(p2,[]))
            st ((pa1,s1),(pa2,s2))
              | null pa1 =(s1,s2)
              | head pa1 == head pa2 = st ((tail pa1,s1),(tail pa2,s2))
              | isVar $ head pa1 = st ((tail pa1,s1++[(head pa2,head pa1)]),
                                       (tail pa2,s2))
              | isVar $ head pa2 = st ((tail pa1,s1),
                                       (tail pa2,s2++[(head pa1,head pa2)]))
              | otherwise = st (((patternsOfTerm $ head pa1)++(tail pa1),s1),
                                ((patternsOfTerm $ head pa2)++(tail pa2),s2))
    olPairsWithS = map subst olPairs
    overlap_qu = map overlapQuery olPairsWithS
    overlap_query = map (\f-> Quantification Universal
                                              (varDeclOfF f)
                                              f
                                              nullRange) overlap_qu
    ex_axioms = filter is_ex_quanti $ fs
    proof = terminationProof fs_terminalProof domains


data ConsistencyStatus = Inconsistent | Conservative |
                         Monomorphic | Definitional deriving (Show, Eq, Ord)

-- | group the axioms according to their leading symbol,
--   output Nothing if there is some axiom in incorrect form
groupAxioms :: [FORMULA f] -> Maybe [(Either OP_SYMB PRED_SYMB,[FORMULA f])]
groupAxioms phis = do
  symbs <- mapM leadingSym phis
  return (filterA (zip symbs phis) [])
  where filterA [] _=[]
        filterA (p:ps) symb=
            let fp=fst p
                p'= if elem fp symb then []
                    else [(fp,snd $ unzip $ filter (\x->(fst x)==fp) (p:ps))]
                symb'= if not $ (elem fp symb) then fp:symb
                       else symb
            in p'++(filterA ps symb')


filterOp :: Maybe (Either OP_SYMB PRED_SYMB) -> [(OP_NAME,OpType)]
filterOp symb = case symb of
                  Just (Left (Qual_op_name ident (Op_type k ags rs _) _))->
                      [(ident, OpType {opKind=k, opArgs=ags, opRes=rs})]
                  _ -> []


filterPred :: Maybe (Either OP_SYMB PRED_SYMB) -> [(OP_NAME,PredType)]
filterPred symb = case symb of
                    Just (Right (Qual_pred_name ident (Pred_type s _) _)) ->
                        [(ident, PredType {predArgs=s})]
                    _ -> []


-- | a leading term and a predication consist of
-- | variables and constructors only
checkTerms :: Sign f e -> [OP_SYMB] -> [TERM f] -> Bool
checkTerms sig cons ts = all checkT ts
  where checkT (Sorted_term tt _ _) = checkT tt
        checkT (Qual_var _ _ _) = True
        checkT (Application subop subts _) =
            (isCons sig cons subop) &&
            (all checkT subts)
        checkT _ = False



-- |  no variable occurs twice in a leading term
checkVar_App :: (Eq f) => TERM f -> Bool
checkVar_App (Application _ ts _) = noDuplation $ concat $ map varOfTerm ts
checkVar_App _ = error "CASL.CCC.FreeTypes<checkVar_App>"


-- |  no variable occurs twice in a leading predication
checkVar_Pred :: (Eq f) => FORMULA f -> Bool
checkVar_Pred (Predication _ ts _) = noDuplation $ concat $ map varOfTerm ts
checkVar_Pred _ = error "CASL.CCC.FreeTypes<checkVar_Pred>"


-- check whether all element are identic
allIdentic :: (Eq a) => [a] -> Bool
allIdentic ts = if (length $ nub ts) <= 1 then True
                else False


-- | there are no duplicate items in a list
noDuplation :: (Eq a) => [a] -> Bool
noDuplation l = if (length $ nub l) == (length l) then True
                else False

-- | create all possible pairs from a list
pairs :: [a] -> [(a,a)]
pairs ps= if length ps <=1 then []
          else (map (\x'->((head ps),x')) $ tail ps) ++
               (pairs $ tail ps)


-- | get the patterns of a term
patternsOfTerm :: TERM f -> [TERM f]
patternsOfTerm t = case t of
                     Qual_var _ _ _ -> [t]
                     Application (Qual_op_name _ _ _) ts _-> ts
                     Sorted_term t' _ _ -> patternsOfTerm t'
                     Cast t' _ _ -> patternsOfTerm t'
                     _ -> []


-- | get the patterns of a axiom
patternsOfAxiom :: FORMULA f -> [TERM f]
patternsOfAxiom f = case f of
                      Quantification _ _ f' _ -> patternsOfAxiom f'
                      Negation f' _ -> patternsOfAxiom f'
                      Implication _ f' _ _ -> patternsOfAxiom f'
                      Equivalence f' _ _ -> patternsOfAxiom f'
                      Predication _ ts _ -> ts
                      Existl_equation t _ _ -> patternsOfTerm t
                      Strong_equation t _ _ -> patternsOfTerm t
                      _ -> []


-- | check whether two patterns are overlapped
checkPatterns :: (Eq f) => ([TERM f],[TERM f]) -> Bool
checkPatterns (ps1,ps2)
        | ps1 == ps2 = True
        | (isVar $ head ps1) ||
          (isVar $ head ps2) = checkPatterns (tail ps1,tail ps2)
        | otherwise = if sameOps_App (head ps1) (head ps2)
                      then checkPatterns $
                           ((patternsOfTerm $ head ps1)++(tail ps1),
                            (patternsOfTerm $ head ps2)++(tail ps2))
                      else False


-- | get the axiom from left hand side of a implication,
-- | if there is no implication, then return atomic formula true
conditionAxiom ::  FORMULA f -> [FORMULA f]
conditionAxiom f = case f of
                     Quantification _ _ f' _ -> conditionAxiom f'
                     Implication f' _ _ _ -> [f']
                     _ -> [True_atom nullRange]


-- | get the axiom from right hand side of a equivalence,
-- | if there is no equivalence, then return atomic formula true
resultAxiom ::  FORMULA f -> [FORMULA f]
resultAxiom f = case f of
                  Quantification _ _ f' _ -> resultAxiom f'
                  Implication _ f' _ _ -> resultAxiom f'
                  Equivalence _ f' _ -> [f']
                  _ -> [True_atom nullRange]


-- | get the term from left hand side of a equation in a formula,
-- | if there is no equation, then return a simple id
resultTerm :: FORMULA f -> [TERM f]
resultTerm f = case f of
                 Quantification _ _ f' _ -> resultTerm f'
                 Implication _ f' _ _ -> resultTerm f'
                 Negation (Definedness _ _) _ ->
                   [Simple_id (mkSimpleId "undefined")]
                 Strong_equation _ t _ -> [t]
                 Existl_equation _ t _ -> [t]
                 _ -> [Simple_id (mkSimpleId "unknown")]


-- | create the proof obligation for a pair of overlapped formulas
overlapQuery :: Eq f => ((FORMULA f,[(TERM f,TERM f)]),
                         (FORMULA f,[(TERM f,TERM f)])) -> FORMULA f
overlapQuery ((a1,s1),(a2,s2)) =
        case leadingSym a1 of
          Just (Left _)
            | (containNeg a1) &&
              (not $ containNeg a2) ->
                Implication (Conjunction [con1,con2] nullRange)
                            (Negation (Definedness resT2 nullRange)
                                      nullRange)
                            True
                            nullRange
            | (containNeg a2) &&
              (not $ containNeg a1)->
                Implication (Conjunction [con1,con2] nullRange)
                            (Negation (Definedness resT1 nullRange)
                                      nullRange)
                            True
                            nullRange
            | (containNeg a1) &&
              (containNeg a2) ->
                True_atom nullRange
            | otherwise ->
                Implication (Conjunction [con1,con2] nullRange)
                            (Strong_equation resT1 resT2 nullRange)
                            True
                            nullRange
          Just (Right _)
            | (containNeg a1) &&
              (not $ containNeg a2) ->
                Implication (Conjunction [con1,con2] nullRange)
                            (Negation resA2 nullRange)
                            True
                            nullRange
            | (containNeg a2) &&
              (not $ containNeg a1) ->
                Implication (Conjunction [con1,con2] nullRange)
                            (Negation resA1 nullRange)
                            True
                            nullRange
            | (containNeg a1) &&
              (containNeg a2) ->
                True_atom nullRange
            | otherwise ->
                Implication (Conjunction [con1,con2] nullRange)
                            (Conjunction [resA1,resA2] nullRange)
                            True
                            nullRange
          _ -> error "CASL.CCC.FreeTypes.<overlapQuery>"
      where cond = concat $ map conditionAxiom [a1,a2]
            resT = concat $ map resultTerm [a1,a2]
            resA = concat $ map resultAxiom [a1,a2]
            con1 = substiF s1 $ head cond
            con2 = substiF s2 $ last cond
            resT1 = substitute s1 $ head resT
            resT2 = substitute s2 $ last resT
            resA1 = substiF s1 $ head resA
            resA2 = substiF s2 $ last resA

