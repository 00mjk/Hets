{- |
    Module      :  $Header$
    Copyright   :  (c) Martin Kuehl, T. Mossakowski, C. Maeder, Uni Bremen 2004-2005
    Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

    Maintainer  :  hets@tzi.de
    Stability   :  provisional
    Portability :  portable

    Overload resolution (injections are inserted separately)
    Follows Sect. III:3.3 of the CASL Reference Manual.
    The algorthim is from:
      Till Mossakowski, Kolyang, Bernd Krieg-Brueckner:
      Static semantic analysis and theorem proving for CASL.
      12th Workshop on Algebraic Development Techniques, Tarquinia 1997,
      LNCS 1376, p. 333-348
-}

module CASL.Overload(minExpFORMULA, oneExpTerm, Min,
                     is_unambiguous, term_sort, leqF, leqP,
                     minimalSupers, maximalSubs,
                     keepMinimals, keepMaximals,
                     common_supersorts, common_subsorts)  where

import CASL.Sign
import CASL.AS_Basic_CASL

import qualified Common.Lib.Map         as Map
import qualified Common.Lib.Set         as Set
import Common.Lib.State

import Common.Id
import Common.GlobalAnnotations
import Common.ListUtils
import Common.PrettyPrint
import Common.Result

import Data.Maybe

{-  
      TODO
      - equivalent candidates should be sorted in a suitable way
      - move functions from ListUtils to the (single) module of use
-}

-- | the type of the type checking function of extensions
type Min f e = GlobalAnnos -> Sign f e -> f -> Result f

{-----------------------------------------------------------
    - Minimal expansion of a formula -
  Expand a given formula by typing information.
  * For non-atomic formulae, recurse through subsentences.
  * For trival atomic formulae, no expansion is neccessary.
  * For atomic formulae, the following cases are implemented:
    + Predication is handled by the dedicated expansion function
      'minExpFORMULA_pred'.
    + Existl_equation and Strong_equation are handled by the dedicated
      expansion function 'minExpFORMULA_eq'.
    + Definedness is handled by expanding the subterm.
    + Membership is handled like Cast
-----------------------------------------------------------}
minExpFORMULA :: PrettyPrint f =>
                 Min f e               ->
                 GlobalAnnos           ->
                 Sign f e              ->
                 (FORMULA f)           ->
                 Result (FORMULA f)
minExpFORMULA mef ga sign formula = case formula of
    Quantification q vars f pos -> do
        -- add 'vars' to signature
        let (_, sign') = runState (mapM_ addVars vars) sign
        -- expand subformula
        f' <- minExpFORMULA mef ga sign' f
        return (Quantification q vars f' pos)
    Conjunction fs pos -> do
        fs' <- mapR (minExpFORMULA mef ga sign) fs
        return (Conjunction fs' pos)
    Disjunction fs pos -> do
        fs' <- mapR (minExpFORMULA mef ga sign) fs
        return (Disjunction fs' pos)
    Implication f1 f2 b pos -> 
        joinResultWith (\ f1' f2' -> Implication f1' f2' b pos)
              (minExpFORMULA mef ga sign f1) $ minExpFORMULA mef ga sign f2
    Equivalence f1 f2 pos -> 
        joinResultWith (\ f1' f2' -> Equivalence f1' f2' pos)
              (minExpFORMULA mef ga sign f1) $ minExpFORMULA mef ga sign f2
    Negation f pos -> do
        f' <- minExpFORMULA mef ga sign f
        return (Negation f' pos)
    Predication (Pred_name ide) terms pos
        -> minExpFORMULA_pred mef ga sign ide Nothing terms pos
    Predication (Qual_pred_name ide ty pos1) terms pos2
        -> minExpFORMULA_pred mef ga sign ide (Just $ toPredType ty) 
           terms (pos1 ++ pos2)
    Existl_equation term1 term2 pos
        -> minExpFORMULA_eq mef ga sign Existl_equation term1 term2 pos
    Strong_equation term1 term2 pos
        -> minExpFORMULA_eq mef ga sign Strong_equation term1 term2 pos
    Definedness term pos -> do
        t <- oneExpTerm mef ga sign term
        return (Definedness t pos)
    Membership term sort pos -> do
        ts   <- minExpTerm mef ga sign term
        let fs = map (concatMap ( \ t -> 
                    let s = term_sort t in
                    if leq_SORT sign sort s then
                    [Membership t sort pos] else
                    map ( \ c -> 
                        Membership (Sorted_term t c pos) sort pos)
                    $ minimalSupers sign s sort)) ts 
        is_unambiguous ga formula fs pos
    ExtFORMULA f -> fmap ExtFORMULA $ mef ga sign f
    _ -> return formula -- do not fail even for unresolved cases

-- | test if a term can be uniquely resolved
oneExpTerm :: PrettyPrint f => Min f e -> GlobalAnnos -> Sign f e 
           -> TERM f -> Result (TERM f)
oneExpTerm minF ga sign term = do 
    ts <- minExpTerm minF ga sign term
    is_unambiguous ga term ts []

{-----------------------------------------------------------
    - Minimal expansion of an equation formula -
  see minExpTerm_cond
-----------------------------------------------------------}
minExpFORMULA_eq :: PrettyPrint f =>
                    Min f e               ->
                    GlobalAnnos           ->
                    Sign f e              ->
                    (TERM f -> TERM f -> [Pos] -> FORMULA f) -> 
                    TERM f                ->
                    TERM f                ->
                    [Pos]              ->
                    Result (FORMULA f)
minExpFORMULA_eq mef ga sign eq term1 term2 pos = do
    ps <- minExpTerm_cond mef ga sign ( \ t1 t2 -> eq t1 t2 pos) 
          term1 term2 pos
    is_unambiguous ga (eq term1 term2 pos) ps pos

-- | check if there is at least one solution
hasSolutions :: PrettyPrint f => GlobalAnnos -> f -> [[f]] -> [Pos] 
             -> Result [[f]]
hasSolutions ga topterm ts pos = let terms = filter (not . null) ts in
   if null terms then Result
    [Diag Error ("no typing for: " ++ show (printText0 ga topterm))
          $ headPos pos] Nothing
    else return terms

-- | check if there is a unique equivalence class
is_unambiguous :: PrettyPrint f => GlobalAnnos -> f -> [[f]] -> [Pos] 
               -> Result f
is_unambiguous ga topterm ts pos = do 
    terms <- hasSolutions ga topterm ts pos
    case terms of 
        [ term : _ ] -> return term
        _ -> Result [Diag Error ("ambiguous term\n  " ++ 
                showSepList (showString "\n  ") (shows . printText0 ga) 
                (take 5 $ map head terms) "") $ headPos pos] Nothing

checkIdAndArgs :: Id -> [a] -> [Pos] -> Result (Pos, Int)
checkIdAndArgs ide args poss =     
    let nargs = length args
        pargs = placeCount ide
        pos = headPos (poss ++ [posOfId ide])
    in if isMixfix ide && pargs /= nargs then 
    Result [Diag Error
       ("expected " ++ shows pargs " argument(s) of mixfix identifier '" 
         ++ showPretty ide "' but found " ++ shows nargs " argument(s)")
       pos] Nothing
    else return (pos, nargs)


noOpOrPred :: PrettyPrint t =>
              [a] -> String -> Maybe t -> Id -> (Pos, Int) -> Result ()
noOpOrPred ops str mty ide (pos, nargs) =
    if null ops then case mty of 
           Nothing -> Result [Diag Error 
             ("no " ++ str ++ " with " ++ shows nargs " argument"
              ++ (if nargs == 1 then "" else "s") ++ " found for '" 
              ++ showPretty ide "'") pos] Nothing
           Just ty -> Result [Diag Error
             ("no " ++ str ++ " with profile '" 
              ++ showPretty ty "' found for '"
              ++ showPretty ide "'") pos] Nothing
       else return ()

{-----------------------------------------------------------
    - Minimal expansion of a predication formula -
    see minExpTerm_appl
-----------------------------------------------------------}
minExpFORMULA_pred :: PrettyPrint f =>
                      Min f e               ->
                      GlobalAnnos           ->
                      Sign f e              ->
                      Id                    ->
                      Maybe PredType        ->
                      [TERM f]              ->
                      [Pos]                 ->
                      Result (FORMULA f)
minExpFORMULA_pred mef ga sign ide mty args poss = do
    pos@(_, nargs) <- checkIdAndArgs ide args poss
    let -- predicates matching that name in the current environment
        preds' = Set.filter ( \ p -> length (predArgs p) == nargs) $ 
              Map.findWithDefault Set.empty ide $ predMap sign
        preds =  case mty of 
                   Nothing -> Set.toList preds'
                   Just ty -> if Set.member ty preds' 
                              then [ty] else []
    noOpOrPred preds "predicate" mty ide pos
    expansions <- mapM (minExpTerm mef ga sign) args
    let get_profile :: [[TERM f]] -> [(PredType, [TERM f])]
        get_profile cs = [ (pred', ts) |
                             pred' <- preds,
                             ts    <- permute cs,
                             zipped_all (leq_SORT sign)
                             (map term_sort ts)
                             (predArgs pred') ]
        qualForms = qualifyPreds ide poss
                       $ concatMap (equivalence_Classes $ 
                                    args_eq sign leqP)
                       $ map get_profile 
                       $ permute expansions
    is_unambiguous ga (Predication (Pred_name ide) args poss) qualForms poss

qualifyPreds :: Id -> [Pos] -> [[(PredType, [TERM f])]] -> [[FORMULA f]]
qualifyPreds ide pos = map $ map $ qualify_pred ide pos 

-- | qualify a single pred, given by its signature and its arguments
qualify_pred :: Id -> [Pos] -> (PredType, [TERM f]) -> FORMULA f
qualify_pred ide pos (pred', terms') = 
    Predication (Qual_pred_name ide (toPRED_TYPE pred') pos) terms' pos

-- | expansions of an equation formula or a conditional
minExpTerm_eq :: PrettyPrint f =>
                    Min f e               ->
                    GlobalAnnos           ->
                    Sign f e              ->
                    TERM f                ->
                    TERM f                ->
                    Result [[(TERM f, TERM f)]]
minExpTerm_eq mef ga sign term1 term2 = do
    exps1 <- minExpTerm mef ga sign term1
    exps2 <- minExpTerm mef ga sign term2
    return $ map (minimize_eq sign)
           $ map getPairs $ permute [exps1, exps2]

getPairs :: [[TERM f]] -> [(TERM f, TERM f)]
getPairs cs = [ (t1, t2) | [t1,t2] <- permute cs ]

minimize_eq :: Sign f e -> [(TERM f, TERM f)] -> [(TERM f, TERM f)]
minimize_eq s l = keepMinimals s (term_sort . snd) $ 
                  keepMinimals s (term_sort . fst) l

{-----------------------------------------------------------
    - Minimal expansion of a term -
  Expand a given term by typing information.
  * 'Simple_id' do not exist!
  * 'Qual_var' terms are handled by 'minExpTerm_var'
  * 'Application' terms are handled by 'minExpTerm_op'.
  * 'Conditional' terms are handled by 'minExpTerm_cond'.
-----------------------------------------------------------}
minExpTerm :: PrettyPrint f =>
              Min f e               ->
              GlobalAnnos           ->
              Sign f e              ->
              TERM f                ->
              Result [[TERM f]]
minExpTerm _ _ sign (Qual_var var sort _)
    = let ts = minExpTerm_var sign var (Just sort)
      in if null ts then mkError "no matching qualified variable found" var
         else return ts
minExpTerm mef ga sign (Application op terms pos)
    = minExpTerm_op mef ga sign op terms pos
minExpTerm mef ga sign top@(Sorted_term term sort pos) = do
    expandedTerm <- minExpTerm mef ga sign term
    -- choose expansions that fit the given signature, then qualify
    let validExps = map (filter ( \ t -> leq_SORT sign (term_sort t) sort)) 
                          expandedTerm
    hasSolutions ga top (map (map (\ t -> 
                 Sorted_term t sort pos)) validExps) pos 
minExpTerm mef ga sign top@(Cast term sort pos) = do
    expandedTerm <- minExpTerm mef ga sign term
    -- find a unique minimal common supersort
    let ts = map (concatMap (\ t -> 
                    let s = term_sort t in
                    if leq_SORT sign sort s then
                    [Cast t sort pos] else
                    map ( \ c -> 
                        Cast (Sorted_term t c pos) sort pos)
                    $ minimalSupers sign s sort)) expandedTerm
    hasSolutions ga top ts pos
minExpTerm mef ga sign (Conditional term1 formula term2 pos) = do
    f <- minExpFORMULA mef ga sign formula
    ts <- minExpTerm_cond mef ga sign ( \ t1 t2 -> Conditional t1 f t2 pos) 
                    term1 term2 pos
    hasSolutions ga (Conditional term1 formula term2 pos) ts pos
minExpTerm _ _ _n _
    = error "minExpTerm"

-- | Minimal expansion of a possibly qualified variable identifier
minExpTerm_var :: Sign f e -> Token -> Maybe SORT -> [[TERM f]]
minExpTerm_var sign tok ms = case Map.lookup tok $ varMap sign of 
    Nothing -> []
    Just s -> let qv = [[Qual_var tok s []]] in
              case ms of 
              Nothing -> qv
              Just s2 -> if s == s2 then qv else []

-- | all minimal common supersorts of the two input sorts
minimalSupers :: Sign f e -> SORT -> SORT -> [SORT]
minimalSupers s s1 s2 = 
    keepMinimals s id $ Set.toList $ common_supersorts s s1 s2

keepMinimals :: Sign f e -> (a -> SORT) -> [a] -> [a]
keepMinimals s' f' l = keepMinimals2 s' f' l l
    where keepMinimals2 s f l1 l2 = case l1 of
              [] -> l2
              x : r -> keepMinimals2 s f r $ filter 
                   ( \ y -> let v = f x 
                                w = f y 
                            in geq_SORT s v w ||
                            not (leq_SORT s v w)) l2

-- | all maximal common subsorts of the two input sorts
maximalSubs :: Sign f e -> SORT -> SORT -> [SORT]
maximalSubs s s1 s2 = 
    keepMaximals s id $ Set.toList $ common_subsorts s s1 s2

keepMaximals :: Sign f e -> (a -> SORT) -> [a] -> [a]
keepMaximals s' f' l = keepMaximals2 s' f' l l
    where keepMaximals2 s f l1 l2 = case l1 of
              [] -> l2
              x : r -> keepMaximals2 s f r $ filter 
                   ( \ y -> let v = f x 
                                w = f y 
                            in leq_SORT s v w ||
                            not (geq_SORT s v w)) l2
 
-- | minimal expansion of an (possibly qualified) operator application
minExpTerm_appl :: PrettyPrint f => Min f e -> GlobalAnnos 
                -> Sign f e -> Id -> Maybe OpType -> [TERM f] 
                -> [Pos] -> Result [[TERM f]]
minExpTerm_appl mef ga sign ide mty args poss = do
    pos@(_, nargs) <- checkIdAndArgs ide args poss
    let -- functions matching that name in the current environment
        ops' = Set.filter ( \ o -> length (opArgs o) == nargs) $ 
              Map.findWithDefault Set.empty ide $ opMap sign
        ops =  case mty of 
                   Nothing -> Set.toList ops'
                   Just ty -> if Set.member ty ops' || 
                                  -- might be known to be total
                                 Set.member ty {opKind = Total} ops' 
                              then [ty] else []
    noOpOrPred ops "operation" mty ide pos
    expansions <- mapM (minExpTerm mef ga sign) args
    let  -- generate profiles as descr. on p. 339 (Step 3)
        get_profile :: [[TERM f]] -> [(OpType, [TERM f])]
        get_profile cs = [ (op', ts) |
                             op' <- ops,
                             ts  <- permute cs,
                             zipped_all (leq_SORT sign)
                             (map term_sort ts)
                             (opArgs op') ]
        qualTerms = qualifyOps ide poss
                       $ map (minimize_op sign) 
                       $ concatMap (equivalence_Classes 
                                    $ args_eq sign leqF)
                       $ map get_profile 
                       $ permute expansions
    hasSolutions ga (Application (Op_name ide) args poss) qualTerms poss

qualifyOps :: Id -> [Pos] -> [[(OpType, [TERM f])]] -> [[TERM f]]
qualifyOps ide pos = map $ map $ qualify_op ide pos

    -- qualify a single op, given by its signature and its arguments
qualify_op :: Id -> [Pos] -> (OpType, [TERM f]) -> TERM f
qualify_op ide pos (op', terms') = 
    Application (Qual_op_name ide (toOP_TYPE op') pos) terms' pos

-- the equivalence relation as descr. on p. 339 (Step 4)
args_eq :: Sign f e -> (Sign f e -> a -> a -> Bool) 
        -> (a, [TERM f]) -> (a, [TERM f]) -> Bool
args_eq sign g (op1, _) (op2, _) =
    g sign op1 op2

{-----------------------------------------------------------
    - Minimal expansion of a function application or a variable -
  Expand a function application by typing information.
  1. First expand all argument subterms.
  2. Permute these expansions so we compute the set of tuples
    { (C_1, ..., C_n) | (C_1, ..., C_n) \in
                        minExpTerm(t_1) x ... x minExpTerm(t_n) }
    where t_1, ..., t_n are the given argument terms.
  3. For each element of this set compute the set of possible profiles
    (as described on p. 339).
  4. Define an equivalence relation ~ on these profiles
    (as described on p. 339).
  5. Separate each profile into equivalence classes by the relation ~
    and take the unification of these sets.
  6. Minimize each element of this unified set (as described on p. 339).
  7. Transform each term in the minimized set into a qualified function
    application term.
-----------------------------------------------------------}
minExpTerm_op :: PrettyPrint f =>
                 Min f e               ->
                 GlobalAnnos           ->
                 Sign f e              ->
                 OP_SYMB               ->
                 [TERM f] -> [Pos]     ->
                 Result [[TERM f]]
minExpTerm_op mef ga sign (Op_name ide@(Id (tok:_) _ _)) args pos =
    let res = minExpTerm_appl mef ga sign ide Nothing args pos in
      if null args && isSimpleId ide then 
          let vars = minExpTerm_var sign tok Nothing
          in if null vars then res else 
             case maybeResult res of 
             Nothing -> return vars 
             Just ops -> return (ops ++ vars)
      else res 
minExpTerm_op mef ga sign (Qual_op_name ide ty pos1) args pos2 = 
   if length args /= length (args_OP_TYPE ty) then 
      mkError "type qualification does not match number of arguments" ide
   else minExpTerm_appl mef ga sign ide (Just $ toOpType ty) args
        (pos1 ++ pos2)
minExpTerm_op _ _ _ _ _ _ = error "minExpTerm_op"

{-----------------------------------------------------------
    - Minimal expansion of a conditional -
  Expand a conditional by typing information (see minExpTerm_eq)
  First expand the subterms and subformula. Then calculate a profile
  P(C_1, C_2) for each (C_1, C_2) \in minExpTerm(t1) x minExpTerm(t_2).
  Separate these profiles into equivalence classes and take the
  unification of all these classes. Minimize each equivalence class.
  Finally transform the eq. classes into lists of 
  conditionals with equally sorted terms.
-----------------------------------------------------------}
minExpTerm_cond :: PrettyPrint f =>
                   Min f e               ->
                   GlobalAnnos           ->
                   Sign f e              ->
                   (TERM f -> TERM f -> a) -> 
                   TERM f                ->
                   TERM f                ->
                   [Pos]                 ->
                   Result [[a]]
minExpTerm_cond  mef ga sign f term1 term2 pos = do
    pairs <- minExpTerm_eq mef ga sign term1 term2
    return $ map (concatMap ( \ (t1, t2) -> 
              let s1 = term_sort t1 
                  s2 = term_sort t2
              in if s1 == s2 then [f t1 t2]
              else if leq_SORT sign s2 s1 then
                   [f t1 (Sorted_term t2 s1 pos)]
              else if leq_SORT sign s1 s2 then
                   [f (Sorted_term t1 s2 pos) t2]
              else map ( \ s -> f (Sorted_term t1 s pos)
                                (Sorted_term t2 s pos))
                   $ minimalSupers sign s1 s2)) pairs

{-----------------------------------------------------------
    Let P be a set of equivalence classes of qualified terms.
    For each C \in P, let C' choose _one_
    t:s \in C for each s minimal such that t:s \in C.
    That is, discard all terms whose sort is a supersort of
    any other term in the same equivalence class.
-----------------------------------------------------------}
minimize_op :: Sign f e -> [(OpType, [TERM f])] -> [(OpType, [TERM f])]
minimize_op sign = keepMinimals sign (opRes . fst)

{-----------------------------------------------------------
    - Extract the sort from a given term -
  If the given term contains information about its sort, return that,
  otherwise signal an error.
-----------------------------------------------------------}
term_sort :: TERM f -> SORT
term_sort term' = case term' of
    Sorted_term _ sort _                  -> sort
    Qual_var _ sort _                     -> sort
    Cast _ sort _                         -> sort
    Application (Qual_op_name _ ty _) _ _ -> res_OP_TYPE ty
    Conditional t1 _ _ _                  -> term_sort t1 
    Simple_id tok ->  error ("term_sort: no sort for a simple id '" 
                             ++ shows tok "'")
    _ -> error "term_sort: unsorted TERM after expansion"


-- | the set of subsorts common to both sorts
common_subsorts :: Sign f e -> SORT -> SORT -> Set.Set SORT
common_subsorts sign s1 s2 = Set.intersection (subsortsOf s1 sign) 
                             $ subsortsOf s2 sign

-- | the set of supersorts common to both sorts
common_supersorts :: Sign f e -> SORT -> SORT -> Set.Set SORT
common_supersorts sign s1 s2 = Set.intersection (supersortsOf s1 sign) 
                             $ supersortsOf s2 sign

-- True if both sorts have a common subsort
have_common_subsorts :: Sign f e -> SORT -> SORT -> Bool
have_common_subsorts s s1 s2 = not $ Set.isEmpty $ common_subsorts s s1 s2

-- True if both sorts have a common supersort
have_common_supersorts :: Sign f e -> SORT -> SORT -> Bool
have_common_supersorts s s1 s2 = not $ Set.isEmpty $ common_supersorts s s1 s2

-- | True if s1 is subsort of s2
leq_SORT :: Sign f e -> SORT -> SORT -> Bool
leq_SORT sign s1 s2 = Set.member s2 (supersortsOf s1 sign)

-- | True if s1 is supersort of s2
geq_SORT :: Sign f e -> SORT -> SORT -> Bool
geq_SORT sign s1 s2 = Set.member s2 (subsortsOf s1 sign)

-- | True if both ops are in the overloading relation 
leqF :: Sign f e -> OpType -> OpType -> Bool
leqF sign o1 o2 = have_common_supersorts sign (opRes o1) (opRes o2) &&
    zipped_all (have_common_subsorts sign) (opArgs o1) (opArgs o2)

-- | True if both preds are in the overloading relation 
leqP :: Sign f e -> PredType -> PredType -> Bool
leqP sign p1 p2 = 
    zipped_all (have_common_subsorts sign) (predArgs p1) (predArgs p2)
