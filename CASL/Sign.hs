
{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

CASL signature
    
-}

module CASL.Sign where

import CASL.AS_Basic_CASL
import CASL.Print_AS_Basic()
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel
import Common.PrettyPrint
import Common.PPUtils
import Common.Lib.Pretty
import Common.Lib.State
import Common.Keywords
import Common.Id
import Common.Result
import Common.AS_Annotation
import Common.GlobalAnnotations

-- constants have empty argument lists 
data OpType = OpType {opKind :: FunKind, opArgs :: [SORT], opRes :: SORT} 
              deriving (Show, Eq, Ord)

data PredType = PredType {predArgs :: [SORT]} deriving (Show, Eq, Ord)

type OpMap = Map.Map Id (Set.Set OpType)

data Sign f e = Sign { sortSet :: Set.Set SORT
               , sortRel :: Rel.Rel SORT         
               , opMap :: OpMap
               , assocOps :: OpMap
               , predMap :: Map.Map Id (Set.Set PredType)
               , varMap :: Map.Map SIMPLE_ID SORT
               , sentences :: [Named (FORMULA f)]        
               , envDiags :: [Diagnosis]
               , extendedInfo :: e
               } deriving Show

-- better ignore assoc flags for equality
instance (Eq f, Eq e) => Eq (Sign f e) where
    e1 == e2 = 
        sortSet e1 == sortSet e2 &&
        sortRel e1 == sortRel e2 &&
        opMap e1 == opMap e2 &&
        predMap e1 == predMap e2 &&
        extendedInfo e1 == extendedInfo e2

emptySign :: e -> Sign f e
emptySign e = Sign { sortSet = Set.empty
               , sortRel = Rel.empty
               , opMap = Map.empty
               , assocOps = Map.empty
               , predMap = Map.empty
               , varMap = Map.empty
               , sentences = []
               , envDiags = []
               , extendedInfo = e }

-- | proper subsorts (possibly excluding input sort)
subsortsOf :: SORT -> Sign f e -> Set.Set SORT
subsortsOf s e = Rel.predecessors (sortRel e) s

-- | proper supersorts (possibly excluding input sort)
supersortsOf :: SORT -> Sign f e -> Set.Set SORT
supersortsOf s e = Rel.succs (sortRel e) s

toOP_TYPE :: OpType -> OP_TYPE
toOP_TYPE OpType { opArgs = args, opRes = res, opKind = k } =
    Op_type k  args res nullRange

toPRED_TYPE :: PredType -> PRED_TYPE
toPRED_TYPE PredType { predArgs = args } = Pred_type args nullRange

toOpType :: OP_TYPE -> OpType
toOpType (Op_type k args r _) = OpType k args r

toPredType :: PRED_TYPE -> PredType
toPredType (Pred_type args _) = PredType args

instance PrettyPrint OpType where
  printText0 ga ot = printText0 ga $ toOP_TYPE ot

instance PrettyPrint PredType where
  printText0 ga pt = printText0 ga $ toPRED_TYPE pt

instance (PrettyPrint f, PrettyPrint e) => PrettyPrint (Sign f e) where
    printText0 ga s = 
        ptext (sortS++sS) <+> commaT_text ga (Set.toList $ sortSet s) 
        $$ 
        (if Rel.null (sortRel s) then empty
            else ptext (sortS++sS) <+> 
             (fsep . punctuate semi $ map printRel $ Map.toList 
                       $ Rel.toMap $ Rel.transpose $ sortRel s))
        $$ printSetMap (ptext opS) empty ga (opMap s)
        $$ printSetMap (ptext predS) space ga (predMap s)
        $$ printText0 ga (extendedInfo s)
     where printRel (supersort, subsorts) =
             printSet ga subsorts <+> ptext lessS <+> printText0 ga supersort

printSetMap :: (PrettyPrint k, PrettyPrint a, Ord k, Ord a) => Doc 
            -> Doc -> GlobalAnnos -> Map.Map k (Set.Set a) -> Doc
printSetMap header sepa ga m = 
    vcat $ map (\ (i, t) -> 
               header <+>
               printText0 ga i <+> colon <> sepa <>
               printText0 ga t) 
             $ concatMap (\ (o, ts) ->
                          map ( \ ty -> (o, ty) ) $ Set.toList ts)
                   $ Map.toList m 

-- working with Sign

diffSig :: Sign f e -> Sign f e -> Sign f e
diffSig a b = 
    a { sortSet = sortSet a `Set.difference` sortSet b
      , sortRel = Rel.transClosure $ Rel.difference (sortRel a) $ sortRel b
      , opMap = opMap a `diffMapSet` opMap b
      , assocOps = assocOps a `diffMapSet` assocOps b   
      , predMap = predMap a `diffMapSet` predMap b      
      }
  -- transClosure needed:  {a < b < c} - {a < c; b} 
  -- is not transitive!

diffMapSet :: (Ord a, Ord b) => Map.Map a (Set.Set b) 
           -> Map.Map a (Set.Set b) -> Map.Map a (Set.Set b)
diffMapSet =
    Map.differenceWith ( \ s t -> let d = Set.difference s t in
                         if Set.null d then Nothing 
                         else Just d )

addMapSet :: (Ord a, Ord b) => Map.Map a (Set.Set b) -> Map.Map a (Set.Set b) 
          -> Map.Map a (Set.Set b)
addMapSet = Map.unionWith Set.union 

addOpMapSet :: OpMap -> OpMap -> OpMap
addOpMapSet m = remPartOpsM . addMapSet m

addSig :: (e -> e -> e) -> Sign f e -> Sign f e -> Sign f e
addSig ad a b = 
    a { sortSet = sortSet a `Set.union` sortSet b
      , sortRel = Rel.transClosure $ Rel.union (sortRel a) $ sortRel b
      , opMap = addOpMapSet (opMap a) $ opMap b
      , assocOps = addOpMapSet (assocOps a) $ assocOps b
      , predMap = addMapSet (predMap a) $ predMap b
      , extendedInfo = ad (extendedInfo a) $ extendedInfo b
      }

isEmptySig :: (e -> Bool) -> Sign f e -> Bool 
isEmptySig ie s = 
    Set.null (sortSet s) && 
    Rel.null (sortRel s) && 
    Map.null (opMap s) &&
    Map.null (predMap s) && ie (extendedInfo s)

isSubMapSet :: (Ord a, Ord b) => Map.Map a (Set.Set b) -> Map.Map a (Set.Set b)
            -> Bool
isSubMapSet = Map.isSubmapOfBy Set.isSubsetOf

isSubOpMap :: OpMap -> OpMap -> Bool
isSubOpMap a b = Map.isSubmapOfBy Set.isSubsetOf a $ addPartOpsM b 

isSubSig :: (PrettyPrint e, PrettyPrint f) => 
            (e -> e -> Bool) -> Sign f e -> Sign f e -> Bool
isSubSig isSubExt a b = 
  Set.isSubsetOf (sortSet a) (sortSet b) 
          && Rel.isSubrelOf (sortRel a) (sortRel b)
          && isSubOpMap (opMap a) (opMap b)
          -- ignore associativity properties! 
          && isSubMapSet (predMap a) (predMap b)
          && isSubExt (extendedInfo a) (extendedInfo b) 

partOps :: Set.Set OpType -> Set.Set OpType
partOps s = Set.fromDistinctAscList $ map ( \ t -> t { opKind = Partial } ) 
         $ Set.toList $ Set.filter ((==Total) . opKind) s

remPartOps :: Set.Set OpType -> Set.Set OpType 
remPartOps s = s Set.\\ partOps s

remPartOpsM :: Ord a => Map.Map a (Set.Set OpType) 
            -> Map.Map a (Set.Set OpType) 
remPartOpsM = Map.map remPartOps

addPartOps :: Set.Set OpType -> Set.Set OpType 
addPartOps s = Set.union s $ partOps s

addPartOpsM :: Ord a => Map.Map a (Set.Set OpType) 
            -> Map.Map a (Set.Set OpType) 
addPartOpsM = Map.map addPartOps

addDiags :: [Diagnosis] -> State (Sign f e) ()
addDiags ds = 
    do e <- get
       put e { envDiags = reverse ds ++ envDiags e }

addSort :: SORT -> State (Sign f e) ()
addSort s = 
    do e <- get
       let m = sortSet e
       if Set.member s m then 
          addDiags [mkDiag Hint "redeclared sort" s] 
          else put e { sortSet = Set.insert s m }

hasSort :: Sign f e -> SORT -> [Diagnosis]
hasSort e s = if Set.member s $ sortSet e then [] 
                else [mkDiag Error "unknown sort" s]

checkSorts :: [SORT] -> State (Sign f e) ()
checkSorts s = 
    do e <- get
       addDiags $ concatMap (hasSort e) s

addSubsort :: SORT -> SORT -> State (Sign f e) ()
addSubsort = addSubsortOrIso True

addSubsortOrIso :: Bool -> SORT -> SORT -> State (Sign f e) ()
addSubsortOrIso b super sub = 
    do if b then checkSorts [super, sub] else return ()
       e <- get
       let r = sortRel e  
       put e { sortRel = (if b then id else 
                         Rel.insert super sub) $ Rel.insert sub super r }
       let p = posOfId sub
           rel = " '" ++ showPretty sub (if b then " < "
                                         else " = ") ++ showPretty super "'"
       if super == sub then 
          addDiags [mkDiag Warning 
                    "void reflexive subsort" sub]
          else if b then 
              if Rel.path super sub r then 
                  if  Rel.path sub super r then
                  addDiags [Diag Warning 
                            ("sorts are isomorphic" ++ rel) p]
                  else addDiags [Diag Warning 
                                 ("added subsort cycle by" ++ rel) p]
              else if Rel.path sub super r then 
                  addDiags [Diag Hint ("redeclared subsort" ++ rel) p]
              else return ()
          else if Rel.path super sub r then 
                  if Rel.path sub super r then
                       addDiags [Diag Hint 
                                 ("redeclared isomoprhic sorts" ++ rel) p]
                  else addDiags [Diag Warning 
                                 ("subsort '" ++ showPretty super 
                                  "' made isomorphic by" ++ rel) 
                                 $ posOfId super]
               else if Rel.path sub super r then
                  addDiags [Diag Warning 
                            ("subsort  '" ++ showPretty sub
                             "' made isomorphic by" ++ rel) p]
                  else return()

closeSubsortRel :: State (Sign f e) ()
closeSubsortRel= 
    do e <- get
       put e { sortRel = Rel.transClosure $ sortRel e }

addVars :: VAR_DECL -> State (Sign f e) ()
addVars (Var_decl vs s _) = mapM_ (addVar s) vs

addVar :: SORT -> SIMPLE_ID -> State (Sign f e) ()
addVar s v = 
    do e <- get
       let m = varMap e
       case Map.lookup v m of
          Just _ -> addDiags [mkDiag Warning "variable shadowed" v] 
          Nothing -> return ()
       put e { varMap = Map.insert v s m }

