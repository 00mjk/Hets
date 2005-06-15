{- | 
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luettich@tzi.de
Stability   :  provisional
Portability :  portable

   Coding out subsorting into unary predicates.
   New concept for proving Ontologies.
-}

module Comorphisms.CASL2TopSort where

import Control.Exception (assert)

import Data.Maybe
import Data.List

import Logic.Logic
import Logic.Comorphism

import Common.Id
import Common.Result
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel
import Common.AS_Annotation

-- CASL
import CASL.Logic_CASL 
import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.Morphism 
import CASL.Sublogic
import CASL.Inject (injName)

-- | The identity of the comorphism
data CASL2TopSort = CASL2TopSort deriving (Show)

instance Language CASL2TopSort -- default definition is okay

instance Comorphism CASL2TopSort
               CASL CASL_Sublogics
               CASLBasicSpec CASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CASLSign 
               CASLMor
               Symbol RawSymbol ()
               CASL CASL_Sublogics
               CASLBasicSpec CASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CASLSign 
               CASLMor
               Symbol RawSymbol () where
    sourceLogic CASL2TopSort = CASL
    sourceSublogic CASL2TopSort = CASL_SL
                      { has_sub = True,
                        has_part = True,
                        has_cons = True,
                        has_eq = True,
                        has_pred = True,
                        which_logic = FOL
                      }
    targetLogic CASL2TopSort = CASL
    targetSublogic CASL2TopSort = CASL_SL
                      { has_sub = False, -- subsorting is coded out
                        has_part = True,
                        has_cons = True,
                        has_eq = True,
                        has_pred = True,
                        which_logic = FOL
                      }
    mapSublogic CASL2TopSort sub = 
        sublogics_max (sublogics_max need_horn need_pred) sub
                      { has_sub = False } -- subsorting is coded out
    map_theory CASL2TopSort = mkTheoryMapping transSig transSen
    map_morphism CASL2TopSort mor = 
        let rsigSour = trSig $ msource mor
            rsigTarg = trSig $ mtarget mor
        in case rsigSour of
           Result diags1 mrs ->
               case rsigTarg of
               Result diags2 mrt 
                  | isJust mrs && isJust mrt ->
                      Result (diags1++diags2) (Just 
                               (mor { msource = fromJust mrs
                                    , mtarget = fromJust mrt }))
                      
                  | otherwise -> 
                     (Result (diags1++diags2) Nothing)
      where trSig sig = case transSig sig of
                        Result dias mr -> 
                            Result dias (maybe Nothing
                                                (Just . fst)
                                                mr)
    map_sentence CASL2TopSort = transSen
    map_symbol CASL2TopSort = Set.singleton . id


data PredInfo = PredInfo { topSort_PI    :: SORT
                         , directSuperSorts_PI :: Set.Set SORT
                         , predicate_PI  :: PRED_NAME
                         } deriving (Show, Ord, Eq)

type SubSortMap = Map.Map SORT PredInfo

generateSubSortMap :: Rel.Rel SORT 
                   -> Map.Map Id (Set.Set PredType) 
                   -> Result SubSortMap
generateSubSortMap sortRels pMap = 
    let disAmbMap m  = Map.map disAmbPred m
        disAmbPred v = if (predicate_PI v) `Map.member` pMap
                       then disAmbPred' (1::Int) v'
                       else v
            where v' = add "_s" v
                  disAmbPred' x v1 = 
                      if (predicate_PI v1) `Map.member` pMap
                      then disAmbPred' (x+1) (add (show x) v')
                      else v1
                  add s v1 = v1 {predicate_PI = 
                                   case predicate_PI v1 of
                                   Id ts is ps -> 
                                      assert (not $ null ts) $
                                          Id (init ts ++ 
                                              [(last ts) {tokStr = 
                                                          tokStr (last ts)++s}
                                              ]) is ps
                                }
        mR = Rel.mostRight sortRels
        toPredInfo k e = 
            let ts = case Set.filter (\pts -> Rel.member k pts sortRels) mR of
                     s | Set.size s == 1 -> 
                           head $ Set.toList s
                       | otherwise ->
                           error ("Something went wrong with: "++
                                  show k++';':show e++';':show s) 
            in PredInfo { topSort_PI = ts
                        , directSuperSorts_PI = Set.difference e mR
                        , predicate_PI = k }
        initMap = Map.filterWithKey (\k _ -> not (Set.member k mR))
            (Map.mapWithKey toPredInfo 
                   (Rel.toMap (Rel.intransKernel sortRels)))
    in return (disAmbMap initMap)

-- | Finds Top-sort(s) and transforms for each top-sort all subsorts
-- into unary predicates. All predicates typed with subsorts are now
-- typed with the top-sort and axioms reflecting the typing are
-- generated. The operations are treated analogous. Axioms are
-- generated that each generated unary predicate must hold on at least
-- one element of the top-sort.

transSig :: Sign f e -> Result (Sign f e, [Named (FORMULA f)])
transSig sig 
    | Rel.null (sortRel sig) = 
        Result [Diag Hint (
        "CASL2TopSort.transSig: Signature is unchanged (no subsorting present)"
                             ) nullPos] (Just (sig,[]))
    | otherwise = 
    case generateSubSortMap (sortRel sig) (predMap sig) of
    Result dias m_subSortMap ->
      maybe (Result dias Nothing)
            (\ subSortMap -> -- trace (show subSortMap) $
               let (dias2,newPredMap) = 
                       Map.mapAccum (\ds (un,ds1) -> (ds++ds1,un)) [] $
                       Map.unionWithKey repError 
                              (transPredMap subSortMap (predMap sig)) 
                              (newPreds subSortMap)
                   (Result dias3 maxioms) =
                       generateAxioms subSortMap (predMap sig) (opMap sig)
                   dias' = dias ++ dias2 ++ dias3
               in maybe (Result dias' Nothing)
                        (\axs -> Result dias' $ Just $
                   (sig { sortSet = 
                              Set.fromList (map topSort_PI 
                                                (Map.elems subSortMap))
                              `Set.union`
                              (sortSet sig `Set.difference`
                               Rel.keysSet subSortMap) 
                        , sortRel = Rel.empty
                        , opMap   = transOpMap subSortMap (opMap sig)
                        , assocOps= transOpMap subSortMap (assocOps sig)
                        , predMap = newPredMap
                        },axs ++ symmetryAxioms subSortMap (sortRel sig)))
                   maxioms)
          m_subSortMap          
    where 
          repError k (v1,d1) (v2,d2) = 
              (Set.union v1 v2, 
               (Diag Warning
                     ("CASL2TopSort.transSig: generating "++
                      "overloading: Predicate "++show k++
                      " gets additional type(s): "++show v2) nullPos)
               :d1++d2 )   
          newPreds mp = 
              foldr (\ pI nm -> Map.insert (predicate_PI pI) 
                                           (Set.singleton  
                                            (PredType [topSort_PI pI]),[]) nm)
                    Map.empty (Map.elems mp)

transPredMap :: SubSortMap -> Map.Map PRED_NAME (Set.Set PredType) 
             -> Map.Map PRED_NAME (Set.Set PredType, [Diagnosis])
transPredMap subSortMap = Map.map (\s -> (Set.map transType s,[]))
    where transType t = t { predArgs = map (\s -> maybe s topSort_PI 
                                                  (Map.lookup s subSortMap))
                                           (predArgs t)}

transOpMap :: SubSortMap -> Map.Map OP_NAME (Set.Set OpType) 
           -> Map.Map OP_NAME (Set.Set OpType)
transOpMap subSortMap = Map.map (tidySet . Set.map transType)
    where tidySet s = Set.fold joinPartial s s
            where joinPartial t@(OpType {opKind = Partial})  
                      | t {opKind = Total} `Set.member` s = Set.delete t
                      | otherwise                         = id
                  joinPartial _ = id
          transType t = 
              t { opArgs = map lkp (opArgs t)
                , opRes = lkp (opRes t)}
          lkp = (\s -> maybe s topSort_PI (Map.lookup s subSortMap))

procOpMapping :: SubSortMap 
              -> OP_NAME -> Set.Set OpType 
              -> Result [Named (FORMULA f)] -> Result [Named (FORMULA f)]
procOpMapping subSortMap opName set r@(Result ds1 mal) =
    case mkProfMapOp opName subSortMap set of
    Result ds2 (Just profMap) ->
        -- trace (show profMap) 
        (maybe r 
               (\al -> 
                    Result (ds1++ds2)
                           (Just (al ++ Map.foldWithKey 
                                      procProfMapOpMapping
                                    [] profMap))) mal)
    Result ds2 Nothing -> Result (ds1++ds2) Nothing
  where 
     procProfMapOpMapping :: [SORT] -> (FunKind,Set.Set [Maybe PRED_NAME])
                             -> [Named (FORMULA f)] -> [Named (FORMULA f)]
     procProfMapOpMapping sl (kind,spl) =  
            genArgRest 
                 (genSenName "o" opName (length sl))
                 (genOpEquation kind opName)
                 sl spl

symmetryAxioms :: SubSortMap -> Rel.Rel SORT -> [Named (FORMULA f)]
symmetryAxioms ssMap sortRels =
    let symSets = Rel.sccOfClosure sortRels
        mR = Rel.mostRight sortRels
        symTopSorts symSet = not (Set.null (Set.intersection mR symSet))
        xVar = mkSimpleId "x"
        updateLabel ts symS [sen] = 
            sen { senName = show ts++senName sen++show symS }
        updateLabel _ _ _ = error "CASL2TopSort.symmetryAxioms"
        toAxioms symSet = 
            [updateLabel ts symS (inlineAxioms CASL
                    "sort ts pred symS:ts\n\
                    \forall xVar : ts\n\
                    \. symS(xVar) %(_symmetric_with_)%")
                        | s<-(Set.toList(Set.difference symSet mR)),
                          let ts = lkupTop ssMap s,
                          let symS = fromJust (lkupPRED_NAME ssMap s)] 
                          
    in concatMap toAxioms (filter symTopSorts symSets)

generateAxioms :: SubSortMap -> Map.Map PRED_NAME (Set.Set PredType) 
               -> Map.Map OP_NAME (Set.Set OpType) 
               -> Result [Named (FORMULA f)]
generateAxioms subSortMap pMap oMap = 
    -- generate argument restrictions for operations
    case Map.foldWithKey (procOpMapping subSortMap) (return []) oMap of 
    Result dias m_opAxs -> maybe (Result dias Nothing) 
                                 (\axs -> -- trace (show dias) $
                                          Result dias 
                                     (Just (reverse hi_axs ++ 
                                            reverse p_axs ++ 
                                            reverse axs)))
                                 m_opAxs                                 
    where p_axs =
          -- generate argument restrictions for predicates
           Map.foldWithKey (\ pName set al ->
              case mkProfMapPred subSortMap set of
              profMap ->
                    -- trace (show profMap) 
                          (al ++ Map.foldWithKey 
                             (\sl -> genArgRest 
                                      (genSenName "p" pName (length sl))
                                      (genPredication pName) 
                                      sl) 
                                    [] profMap)) 
                   [] pMap
          hi_axs =
          -- generate subclass_of axioms derived from subsorts
          -- and non-emptyness axioms
              Map.fold (\ (PredInfo { topSort_PI = ts
                         , predicate_PI = subS
                         , directSuperSorts_PI = set
                         }) al -> 
               let supPreds = 
                     map (\ s -> 
                            maybe (error ("CASL2TopSort: genAxioms:"++
                                   " impossible happend: "++show s)) 
                                  predicate_PI (Map.lookup s subSortMap))  
                         (Set.toList set)
                   x = mkSimpleId "x" 
                in al ++ zipWith (\sen supS -> sen { senName = show subS++
                                                               senName sen++
                                                               show supS })
                         (concat [inlineAxioms CASL 
                                  "sort ts\n\
                                  \pred subS,supS: ts\n\
                                  \ forall x : ts . subS(x) =>\n\
                                  \ supS(x) %(_subclassOf_)%"|supS<-supPreds] 
                         ) supPreds ++
                         map (\sen -> sen { senName = show subS ++ 
                                                      senName sen}) 
                                 (concat [inlineAxioms CASL
                                  "sort ts\n\
                                  \pred subS: ts \n\
                                  \. exists x:ts . \n\
                                  \ subS(x) %(_non_empty)%"])
             ) [] subSortMap
 
mkProfMapPred :: SubSortMap -> Set.Set PredType 
              -> Map.Map [SORT] (Set.Set [Maybe PRED_NAME])
mkProfMapPred ssm = Set.fold seperate Map.empty
    where seperate pt = Rel.setInsert (pt2topSorts pt) (pt2preds pt) 
          pt2topSorts = map (lkupTop ssm) . predArgs
          pt2preds = map (lkupPRED_NAME ssm) . predArgs

mkProfMapOp :: OP_NAME -> SubSortMap -> Set.Set OpType 
              -> Result (Map.Map [SORT] (FunKind, Set.Set [Maybe PRED_NAME]))
mkProfMapOp opName ssm = Set.fold seperate (return Map.empty)
    where seperate ot r@(Result dias mmap) =
              maybe r  
                (\ mp -> Result dias' 
                              (Just 
                                (Map.insertWith (\ (k1,s1) (k2,s2) ->
                                           (min k1 k2,Set.union s1 s2)) 
                                        (pt2topSorts joinedList) 
                                        (fKind,
                                         Set.singleton (pt2preds joinedList)) 
                                        mp)))
                 mmap
              where joinedList = opArgs ot ++ [opRes ot]
                    fKind = opKind ot
                    dias' = if fKind == Partial 
                             then dias ++ 
                                  [Diag Warning 
                                        ("Please, check if operation \""++
                                         show opName ++ 
                                         "\" is still partial as intended,\
                                          \ since a joining of types could\
                                         \ have made it total!!")
                                        nullPos]
                             else dias
          pt2topSorts = map (lkupTop ssm) 
          pt2preds = map (lkupPRED_NAME ssm) 

lkupTop :: SubSortMap -> SORT -> SORT
lkupTop ssm s = maybe s topSort_PI (Map.lookup s ssm)

lkupPRED_NAME :: SubSortMap -> SORT -> Maybe PRED_NAME
lkupPRED_NAME ssm s = 
    maybe Nothing (Just . predicate_PI) (Map.lookup s ssm)

genArgRest :: String               
           -> ([SORT] -> [TERM f] -> FORMULA f) 
               -- ^ generates from a list of variables 
               -- either the predication or function equation
           -> [SORT] -> (Set.Set [Maybe PRED_NAME]) 
           -> [Named (FORMULA f)] -> [Named (FORMULA f)]
genArgRest sen_name genProp sl spl fs = 
    let vars = genVars sl 
        mquant = genQuantification (genProp sl (map toSortTerm vars))
                                   vars spl 
    in
    maybe fs ( \ quant -> mapNamed (const quant) (emptyName sen_name)
               : fs) mquant

-- | generate a predication with qualified pred name
genPredication :: PRED_NAME -> [SORT] -> [TERM f] -> FORMULA f
genPredication pName sl ts =
    Predication (Qual_pred_name pName 
                                (Pred_type sl []) [])
                ts
                []

genOpEquation :: FunKind -> OP_NAME -> [SORT] -> [TERM f] -> FORMULA f
genOpEquation kind opName sl terms = 
    Strong_equation sortedFunTerm resTerm []
    where sortedFunTerm = 
             Sorted_term (Application 
                            (Qual_op_name opName 
                                          opType [])
                            argTerms
                            []) 
                         resSort       
                         []
          opType = case kind of 
                   Partial -> Op_type Partial argSorts resSort []
                   Total   -> Op_type Total   argSorts resSort []
          argTerms = init terms
          resTerm  = last terms
          argSorts = init sl
          resSort  = last sl


toSortTerm :: TERM f -> TERM f
toSortTerm t@(Qual_var _ s _) = Sorted_term t s []
toSortTerm _ = error "CASL2TopSort.toSortTerm: can only handle Qual_var" 

genVars :: [SORT] -> [TERM f]
genVars = zipWith toVarTerm varSymbs
    where varSymbs = map mkSimpleId 
                         (map (:[]) "xyzuwv"++
                          map (\i -> 'v':show i) [(1::Int)..])
          toVarTerm vs s = (Qual_var vs s [])

genSenName :: Show a => String -> a -> Int -> String
genSenName suff symbName arity =
    "arg_rest_"++ show symbName++'_':suff++'_':show arity

genQuantification :: FORMULA f -- ^ either the predication or 
                               -- function equation
                  -> [TERM f] -- ^ Qual_vars
                  -> (Set.Set [Maybe PRED_NAME]) 
                  -> Maybe (FORMULA f)
genQuantification prop vars spl =
    -- trace (show vds) $
     maybe Nothing  (\dis -> 
        Just (Quantification Universal vds
                             (Implication prop
                                          dis
                                          True []) []))
           (genDisjunction vars spl)
   where vds = reverse (foldl toVarDecl [] vars)
         -- toVarDecl :: [VAR_DECL] -> TERM f -> [VAR_DECL]
         toVarDecl [] (Qual_var n s _) = [Var_decl [n] s []]
         toVarDecl xxs@((Var_decl l s1 []):xs) (Qual_var n s _) 
             | s1 == s   = Var_decl (l++[n]) s1 []:xs
             | otherwise = Var_decl [n] s []:xxs
         toVarDecl _ _ = 
             error "CASL2TopSort.toVarDecl: can only handle Qual_var"
         

genDisjunction :: [TERM f] -- ^ Qual_vars
                  -> (Set.Set [Maybe PRED_NAME])
                  -> Maybe (FORMULA f)
genDisjunction vars spn  
    | Set.size spn == 1 = 
        case genConjunction [] (head (Set.toList spn)) of
        []  -> Nothing
        [x] -> Just x
        _   -> error "CASL2TopSort.genDisjunction: this cannot happen"
    | null disjs        = Nothing
    | otherwise         = Just (Disjunction disjs [])
      where disjs = foldl genConjunction [] (Set.toList spn)
            genConjunction acc pns 
                | null conjs = acc
                | otherwise  = (Conjunction (reverse conjs) []):acc
                where conjs = foldl genPred [] (zip vars pns)
            -- genPred :: TERM f -> PRED_NAME -> FORMULA f
            genPred acc (v@(Qual_var _ s _),mpn) = 
                maybe acc (\pn -> genPredication pn [s] [v]:acc) mpn
            genPred _ _ = 
                error "CASL2TopSort.genPred: can only handle Qual_var"

partitionArity :: Int -> Set.Set PredType -> Map.Map Int [PredType]
partitionArity arity set
    | arity == 1 = Map.insert arity (Set.toList set) Map.empty
    | otherwise = case Set.partition 
                             (\ x -> length (predArgs x) == arity) set of
                  (tt,ff) -> Map.insert arity (Set.toList tt) 
                                        (partitionArity (arity-1) ff)

combineTypes :: SubSortMap -> Map.Map Int [PredType] 
             -> Map.Map Int [Map.Map SORT (Set.Set SORT)]
combineTypes subSortMap = 
    Map.mapWithKey (\ arity types -> 
                       foldr (\ t sl -> zipWith ins (predArgs t) sl) 
                                          (replicate arity Map.empty) types)
    where ins so mp = maybe mp 
                            (\v -> Rel.setInsert (topSort_PI v) so mp)
                            (Map.lookup so subSortMap)

-- | Each membership test of a subsort is transformed to a predication
-- of the corresponding unary predicate. Variables quantified over a
-- subsort yield a premise to the quantified formula that the
-- corresponding predicate holds. All typings are adjusted according
-- to the subsortmap and sort generation constraints are translated to
-- disjointness axioms.


transSen :: (Show f) => Sign f e -> FORMULA f -> Result (FORMULA f)
transSen sig f 
    | Rel.null (sortRel sig) = 
        Result [Diag Hint (
        "CASL2TopSort.transSen: Sentence is unchanged (no subsorting present)"
                             ) nullPos] (Just f)
    | otherwise = 
    case (generateSubSortMap (sortRel sig) 
                             (predMap sig)) of
    Result d Nothing -> Result d Nothing 
    Result d (Just ssm)  -> 
        case mapSen ssm f of
        Result d2 jf -> Result (d++d2) jf

mapSen :: SubSortMap -> FORMULA f -> Result (FORMULA f)
mapSen ssMap f =
    case f of
    Sort_gen_ax cs _ ->
        genEitherAxiom ssMap cs
    _ -> return $ mapSen1 ssMap f

mapSen1 :: SubSortMap -> FORMULA f -> FORMULA f
mapSen1 subSortMap f = 
    case f of
    Conjunction fl pl -> Conjunction (map (mapSen1 subSortMap) fl) pl
    Disjunction fl pl -> Disjunction (map (mapSen1 subSortMap) fl) pl
    Implication f1 f2 b pl -> 
        Implication (mapSen1 subSortMap f1) (mapSen1 subSortMap f2) b pl
    Equivalence f1 f2 pl -> 
        Equivalence (mapSen1 subSortMap f1) (mapSen1 subSortMap f2) pl
    Negation f1 pl -> Negation (mapSen1 subSortMap f1) pl
    tr@(True_atom _)  -> tr
    fa@(False_atom _) -> fa
    Quantification q vdl f1 pl -> 
        Quantification q (map updateVarDecls vdl) (mapSen1 subSortMap f1) pl
    Membership t s pl ->
        let t' = mapTerm subSortMap t
        in maybe (Membership t' s pl)
                 (\pn -> genPredication pn [lkupTop subSortMap s]
                                           [t'])
                 (lkupPRED_NAME subSortMap s)
    Existl_equation t1 t2 pl ->
        Existl_equation (mapTerm subSortMap t1) (mapTerm subSortMap t2) pl
    Strong_equation t1 t2 pl ->
        Strong_equation (mapTerm subSortMap t1) (mapTerm subSortMap t2) pl
    Definedness t pl ->
        Definedness (mapTerm subSortMap t) pl
    Predication psy tl pl -> 
        Predication (updatePRED_SYMB psy) (map (mapTerm subSortMap) tl) pl
    ExtFORMULA f1 -> ExtFORMULA f1 -- ExtFORMULA stays as it is
    _ -> 
        error "CASL2TopSort.mapSen1"
    where updateVarDecls (Var_decl vl s pl) = 
              Var_decl vl (lkupTop subSortMap s) pl
          updatePRED_SYMB (Pred_name _) = 
              error "CASL2TopSort.mapSen: got untyped predication"
          updatePRED_SYMB (Qual_pred_name pn (Pred_type sl pl') pl) =
              Qual_pred_name pn 
                 (Pred_type (map (lkupTop subSortMap) sl) pl') pl

mapTerm :: SubSortMap -> TERM f -> TERM f
mapTerm ssMap t = 
    case t of
    Qual_var v s pl -> Qual_var v (lTop s) pl
    Application osy tl pl ->
        Application (updateOP_SYMB osy) (map (mapTerm ssMap) tl) pl
    Sorted_term t1 s pl ->
        Sorted_term (mapTerm ssMap t1) (lTop s) pl
    -- casts are discarded due to missing subsorting
    Cast t1 _ _ -> mapTerm ssMap t1
    Conditional t1 f t2 pl ->
        Conditional (mapTerm ssMap t1) (mapSen1 ssMap f) (mapTerm ssMap t2) pl
    _ -> 
        error "CASL2TopSort.mapTerm"
    where lTop = lkupTop ssMap
          updateOP_SYMB (Op_name _) =
              error "CASL2TopSort.mapTerm: got untyped application"
          updateOP_SYMB (Qual_op_name on ot pl) =
              Qual_op_name on (updateOP_TYPE ot) pl
          updateOP_TYPE (Op_type fk sl s pl) =  
              Op_type fk (map lTop sl) (lTop s) pl

genEitherAxiom :: SubSortMap -> [Constraint] -> Result (FORMULA f)
genEitherAxiom ssMap =  
    genConjunction . (\ (_,osl,_) -> osl) . recover_Sort_gen_ax
    where genConjunction osl = 
            let (injOps,constrs) = partition isInjOp osl
                groupedInjOps = groupBy sameTarget $ sortBy compTarget injOps
            in if null constrs
               then case groupedInjOps of
                    [] -> Result [Diag Error 
                                  "No injective operation found" nullPos] 
                                 Nothing
                    [xs@(x:_)] -> Result [] (Just (genQuant x (genImpl xs)))
                    xs@((x:_):_)  -> 
                           Result [] (Just (genQuant x (Conjunction 
                                                        (map genImpl xs) [])))
                    _ -> error "CASL2TopSort.genEitherAxiom.groupedInjOps"
               else Result [Diag Error
                                 ("CASL2TopSort: Cannot handle \
                                  \datatype constructors; only subsort \
                                  \embeddings are allowed with free and \
                                  \generated types!") nullPos] Nothing
          isInjOp ops = 
              case ops of
              Op_name _ -> error "CASL2TopSort.genEitherAxiom.isInjObj"
              Qual_op_name on _ _ -> on == injName
          resultSort (Qual_op_name _ (Op_type _ _ t _) _) = t 
          resultSort _ = error "CASL2TopSort.genEitherAxiom.resultSort"
          argSort (Qual_op_name _ (Op_type _ [x] _ _) _) = x 
          argSort _ = error "CASL2TopSort.genEitherAxiom.argSort"
          compTarget x1 x2 = compare (resultSort x1) (resultSort x2)
          sameTarget x1 x2 = compTarget x1 x2 == EQ
          lTop = lkupTop ssMap
          varName = mkSimpleId "x"
          mkVarTerm qon =
              Sorted_term (Qual_var varName s []) s []
              where s = lTop (resultSort qon)
          mkVarDecl qon =
              Var_decl [varName] (lTop (resultSort qon)) []
          genQuant qon f = Quantification Universal [mkVarDecl qon] f []
          genImpl []       = error "No OP_SYMB found"
          genImpl xs@(x:_) = 
              assert (lTop (resultSort x) == lTop (argSort x)) 
              (if (resultSort x) == lTop (resultSort x)
               then genDisj xs
               else Implication (genProp x) (genDisj xs) True [])
          genProp qon = genPredication (lPredName (resultSort qon)) 
                                       [lTop (resultSort qon)]
                                       [mkVarTerm qon]
          lPredName s = maybe (error ("CASL2TopSort.genEitherAxiom: \
                                      \No PRED_NAME for \""++show s
                                      ++"\" found!"))
                              id
                              (lkupPRED_NAME ssMap s)
          genDisj qons = Disjunction (map genPred qons) []
          genPred qon = genPredication (lPredName (argSort qon)) 
                                       [lTop (resultSort qon)]
                                       [mkVarTerm qon]

