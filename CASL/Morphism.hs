
{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Till Mossakowski and Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable
    
Symbols and signature morphisms for the CASL logic
-}

{-
todo:
issue warning for symbols lists like __ * __, __ + __: Elem * Elem -> Elem
the qualification only applies to __+__ !
-}

module CASL.Morphism where

import CASL.Sign
import CASL.AS_Basic_CASL
import Common.Id
import Common.Result
import Common.Keywords
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel
import Control.Monad
import Common.PrettyPrint
import Common.Lib.Pretty

data SymbType = OpAsItemType OpType
                -- since symbols do not speak about totality, the totality
                -- information in OpType has to be ignored
              | PredAsItemType PredType
              | SortAsItemType 
                deriving (Show)
-- Ordering and equality of symbol types has to ingore totality information
instance Ord SymbType where
  compare (OpAsItemType ot1) (OpAsItemType ot2) =
    compare (opArgs ot1,opRes ot1) (opArgs ot2,opRes ot2)
  compare (OpAsItemType _)  _ = LT
  compare (PredAsItemType pt1) (PredAsItemType pt2) =
    compare pt1 pt2
  compare (PredAsItemType _) (OpAsItemType _) = GT
  compare (PredAsItemType _) SortAsItemType = LT
  compare SortAsItemType SortAsItemType  = EQ
  compare SortAsItemType _  = GT

instance Eq SymbType where
  t1 == t2 = compare t1 t2 == EQ

data Symbol = Symbol {symName :: Id, symbType :: SymbType} 
              deriving (Show, Eq, Ord)

type SymbolSet = Set.Set Symbol 
type SymbolMap = Map.Map Symbol Symbol 

data RawSymbol = ASymbol Symbol | AnID Id | AKindedId Kind Id
                 deriving (Show, Eq, Ord)

type RawSymbolSet = Set.Set RawSymbol 
type RawSymbolMap = Map.Map RawSymbol RawSymbol 

data Kind = SortKind | FunKind | PredKind
            deriving (Show, Eq, Ord)

type Sort_map = Map.Map SORT SORT
-- allways use the partial profile as key! 
type Fun_map =  Map.Map (Id,OpType) (Id, FunKind)
type Pred_map = Map.Map (Id,PredType) Id

data Morphism f e m = Morphism {msource :: Sign f e,
                          mtarget :: Sign f e,
                          sort_map :: Sort_map, 
                          fun_map :: Fun_map, 
                          pred_map :: Pred_map,
                          extended_map :: m}
                         deriving (Eq, Show)

mapSort :: Sort_map -> SORT -> SORT
mapSort sorts s = Map.findWithDefault s s sorts

mapOpType :: Sort_map -> OpType -> OpType
mapOpType sorts t = t { opArgs = map (mapSort sorts) $ opArgs t
                      , opRes = mapSort sorts $ opRes t }

mapOpTypeK :: Sort_map -> FunKind -> OpType -> OpType
mapOpTypeK sorts k t = makeTotal k $ mapOpType sorts t

makeTotal :: FunKind -> OpType -> OpType
makeTotal Total t = t { opKind = Total }
makeTotal _ t = t

mapOpSym :: Sort_map -> Fun_map -> (Id, OpType) -> (Id, OpType)
mapOpSym sMap fMap (i, ot) = 
    let mot = mapOpType sMap ot in
    case Map.lookup (i, mot {opKind = Partial} ) fMap of 
    Nothing -> (i, mot)
    Just (j, k) -> (j, makeTotal k mot)

-- | Check if two OpTypes are equal except from totality or partiality
compatibleOpTypes :: OpType -> OpType -> Bool
compatibleOpTypes ot1 ot2 = opArgs ot1 == opArgs ot2 && opRes ot1 == opRes ot2

mapPredType :: Sort_map -> PredType -> PredType
mapPredType sorts t = t { predArgs = map (mapSort sorts) $ predArgs t }

mapPredSym :: Sort_map -> Pred_map -> (Id, PredType) -> (Id, PredType)
mapPredSym sMap fMap (i, pt) = let mpt = mapPredType sMap pt in
    (Map.findWithDefault i (i, mpt) fMap, mpt)

type Ext f e m = Sign f e -> Sign f e -> m

embedMorphism :: Ext f e m -> Sign f e -> Sign f e -> Morphism f e m
embedMorphism extEm a b =
    Morphism 
    { msource = a 
    , mtarget = b
    , sort_map = Map.empty
    , fun_map = Map.empty
    , pred_map = Map.empty
    , extended_map = extEm a b
    }

idToSortSymbol :: Id -> Symbol
idToSortSymbol idt = Symbol idt SortAsItemType

idToOpSymbol :: Id -> OpType -> Symbol
idToOpSymbol idt typ = Symbol idt (OpAsItemType typ)

idToPredSymbol :: Id -> PredType -> Symbol
idToPredSymbol idt typ = Symbol idt (PredAsItemType typ)

symbTypeToKind :: SymbType -> Kind
symbTypeToKind (OpAsItemType _) = FunKind
symbTypeToKind (PredAsItemType _)     = PredKind
symbTypeToKind SortAsItemType      = SortKind

symbolToRaw :: Symbol -> RawSymbol
symbolToRaw sym = ASymbol sym

idToRaw :: Id -> RawSymbol
idToRaw x = AnID x

rawSymName :: RawSymbol -> Id
rawSymName (ASymbol sym) = symName sym
rawSymName (AnID i) = i
rawSymName (AKindedId _ i) = i

symOf ::  Sign f e -> SymbolSet
symOf sigma = 
    let sorts = Set.image idToSortSymbol $ sortSet sigma
        ops = Set.fromList $ 
              concatMap (\ (i, ts) -> map ( \ t -> idToOpSymbol i t) 
                         $ Set.toList ts) $ 
              Map.toList $ opMap sigma
        preds = Set.fromList $ 
              concatMap (\ (i, ts) -> map ( \ t -> idToPredSymbol i t) 
                         $ Set.toList ts) $ 
              Map.toList $ predMap sigma
        in Set.unions [sorts, ops, preds] 

statSymbMapItems :: [SYMB_MAP_ITEMS] -> Result RawSymbolMap
statSymbMapItems sl = do
  ls <- sequence $ map s1 sl
  foldl insertRsys (return Map.empty) (concat ls)
  where
  s1 (Symb_map_items kind l _) = sequence (map (symbOrMapToRaw kind) l)
  insertRsys m (rsy1,rsy2) = do
    m1 <- m
    case Map.lookup rsy1 m1 of
      Nothing -> return $ Map.insert rsy1 rsy2 m1
      Just rsy3 -> 
        plain_error m1 ("Symbol "++showPretty rsy1 " mapped twice to "
                ++showPretty rsy2 " and "++showPretty rsy3 "") nullPos

pairM :: Monad m => (m a,m b) -> m (a,b)
pairM (x,y) = do
  a <- x
  b <- y
  return (a,b)

symbOrMapToRaw :: SYMB_KIND -> SYMB_OR_MAP -> Result (RawSymbol,RawSymbol)
symbOrMapToRaw k (Symb s) = pairM (symbToRaw k s,symbToRaw k s)
symbOrMapToRaw k (Symb_map s t _) = pairM (symbToRaw k s,symbToRaw k t)

statSymbItems :: [SYMB_ITEMS] -> Result [RawSymbol]
statSymbItems sl = 
  fmap concat (sequence (map s1 sl))
  where s1 (Symb_items kind l _) = sequence (map (symbToRaw kind) l)

symbToRaw :: SYMB_KIND -> SYMB -> Result RawSymbol
symbToRaw k (Symb_id idt)     = return $ symbKindToRaw k idt
symbToRaw k (Qual_id idt t _) = typedSymbKindToRaw k idt t

symbKindToRaw :: SYMB_KIND -> Id -> RawSymbol
symbKindToRaw sk idt = case sk of
    Implicit -> AnID idt
    _ -> AKindedId (case sk of 
         Sorts_kind -> SortKind
         Preds_kind -> PredKind
         _ -> FunKind) idt

typedSymbKindToRaw :: SYMB_KIND -> Id -> TYPE -> Result RawSymbol
typedSymbKindToRaw k idt t = 
    let err = plain_error (AnID idt) 
              (showPretty idt ":" ++ showPretty t 
               "does not have kind" ++showPretty k "") nullPos
        aSymb = ASymbol $ case t of 
                 O_type ot -> idToOpSymbol idt $ toOpType ot
                 P_type pt -> idToPredSymbol idt $ toPredType pt
             -- in case of ambiguity, return a constant function type
             -- this deviates from the CASL summary !!!
                 A_type s -> 
                     let ot = OpType {opKind = Total, opArgs = [], opRes = s} 
                     in idToOpSymbol idt ot
    in case k of
    Implicit -> return aSymb
    Sorts_kind -> return $ AKindedId SortKind idt
    Ops_kind -> case t of
        P_type _ -> err
        _ -> return aSymb
    Preds_kind -> case t of
        O_type _ -> err
        A_type s -> return $ ASymbol $ 
                    let pt = PredType {predArgs = [s]} 
                    in idToPredSymbol idt pt
        P_type _ -> return aSymb

symbMapToMorphism :: Ext f e m -> Sign f e -> Sign f e 
                  -> SymbolMap -> Result (Morphism f e m)
symbMapToMorphism extEm sigma1 sigma2 smap = let
  sort_map1 = Set.fold mapMSort Map.empty (sortSet sigma1)
  mapMSort s m = 
    case Map.lookup (Symbol {symName = s, symbType = SortAsItemType}) smap
    of Just sym -> let t = symName sym in if s == t then m else
                           Map.insert s t m
       Nothing -> m
  fun_map1 = Map.foldWithKey mapFun Map.empty (opMap sigma1)
  pred_map1 = Map.foldWithKey mapPred Map.empty (predMap sigma1)
  mapFun i ots m = Set.fold (insFun i) m ots
  insFun i ot m = 
    case Map.lookup (Symbol {symName = i, symbType = OpAsItemType ot}) smap
    of Just sym -> let j = symName sym in case symbType sym of
         OpAsItemType oty -> let k = opKind oty in 
            if j == i && opKind ot == k then m
            else Map.insert (i, oty {opKind = Partial}) (j, k) m
         _ -> m
       _ -> m
  mapPred i pts m = Set.fold (insPred i) m pts
  insPred i pt m =
    case Map.lookup (Symbol {symName = i, symbType = PredAsItemType pt}) smap
    of Just sym -> let j = symName sym in  case symbType sym of
         PredAsItemType pty -> if i == j then m else Map.insert (i, pty) j m
         _ -> m
       _ -> m 
  in return (Morphism { msource = sigma1,
             mtarget = sigma2,
             sort_map = sort_map1,
             fun_map = fun_map1,
             pred_map = pred_map1,
             extended_map = extEm sigma1 sigma2})
      
morphismToSymbMap ::  Morphism f e m -> SymbolMap
morphismToSymbMap mor =
  let
    src = msource mor 
    sorts = sort_map mor
    ops = fun_map mor
    preds = pred_map mor
    sortSymMap =  Set.fold ( \ s -> Map.insert (idToSortSymbol s) $ 
                             idToSortSymbol $ mapSort sorts s)
                  Map.empty $ sortSet src
    opSymMap = Map.foldWithKey
               ( \ i s m -> Set.fold 
                 ( \ t -> Map.insert (idToOpSymbol i t)
                 $ uncurry idToOpSymbol $ mapOpSym sorts ops (i, t)) m s)
               Map.empty $ opMap src
    predSymMap = Map.foldWithKey
               ( \ i s m -> Set.fold 
                 ( \ t -> Map.insert (idToPredSymbol i t)
                 $ uncurry idToPredSymbol $ mapPredSym sorts preds (i, t)) m s)
               Map.empty $ predMap src
  in
    foldr Map.union sortSymMap [opSymMap,predSymMap]


matches :: Symbol -> RawSymbol -> Bool
matches x@(Symbol idt k) rs = case rs of
    ASymbol y -> x == y
    AnID di -> idt == di
    AKindedId rk di -> let res = idt == di in case (k, rk) of
        (SortAsItemType, SortKind) -> res
        (OpAsItemType _, FunKind) -> res
        (PredAsItemType _, PredKind) -> res
        _ -> False

idMor :: Ext f e m -> Sign f e -> Morphism f e m
idMor extEm sigma = embedMorphism extEm sigma sigma

compose :: (Eq e, Eq f) => (m -> m -> m)
        -> Morphism f e m -> Morphism f e m -> Result (Morphism f e m)
compose comp mor1 mor2 = if mtarget mor1 == msource mor2 then return $ 
  let sMap1 = sort_map mor1 
      sMap2 = sort_map mor2 
      fMap2 = fun_map mor2
      pMap2 = pred_map mor2
  in Morphism {
      msource = msource mor1,
      mtarget = mtarget mor2,
      sort_map = Map.foldWithKey ( \ i j -> 
                       Map.insert i $ mapSort sMap2 j)
                             sMap2 sMap1,
      fun_map  = Map.foldWithKey ( \ p@(_, ot) (j, k) ->
                       let (ni, nt) = mapOpSym sMap2 fMap2 (j, 
                                            mapOpTypeK sMap1 k ot)
                      in Map.insert p (ni, opKind nt)) 
                 fMap2 $ fun_map mor1,
      pred_map = Map.foldWithKey ( \ p@(_, ot) j ->
                  Map.insert p $ fst $ mapPredSym sMap2 pMap2 
                  (j, mapPredType sMap1 ot)) pMap2 $ pred_map mor1,
      extended_map = comp (extended_map mor1) (extended_map mor2)
      }
    else fail "target of first and source of second morphism are different"

legalSign ::  Sign f e -> Bool
legalSign sigma =
  Map.foldWithKey (\s sset b -> b && legalSort s && Set.all legalSort sset)
                  True (Rel.toMap (sortRel sigma))
  && Map.fold (\ts b -> b && Set.all legalOpType ts) 
              True (opMap sigma)
  && Map.fold (\ts b -> b && Set.all legalPredType ts) 
              True (predMap sigma)
  where sorts = sortSet sigma
        legalSort s = Set.member s sorts
        legalOpType t = legalSort (opRes t) 
                        && all legalSort (opArgs t) 
        legalPredType t = all legalSort (predArgs t) 

legalMor ::  Morphism f e m -> Bool
legalMor mor =
  legalSign sigma1
  && legalSign sigma2
  && Map.foldWithKey
        (\s1 s2 b -> b && Set.member s1 (sortSet sigma1)
                       && Set.member s2 (sortSet sigma2))
        True smap
  && Map.foldWithKey 
        (\(id1,t) (id2,k) b -> 
           b
           &&
           Set.member t (Map.findWithDefault Set.empty id1 (opMap sigma1)) 
           &&
           Set.member (mapOpTypeK smap k t) 
                      (Map.findWithDefault Set.empty id2 (opMap sigma2))
        )
        True (fun_map mor)
  && Map.foldWithKey 
        (\(id1,t) id2 b -> 
           b
           &&
           Set.member t (Map.findWithDefault Set.empty id1 (predMap sigma1)) 
           &&
           Set.member (mapPredType smap t) 
                      (Map.findWithDefault Set.empty id2 (predMap sigma2))
        )
        True (pred_map mor)
  where sigma1 = msource mor
        sigma2 = mtarget mor
        smap = sort_map mor

sigInclusion :: (PrettyPrint e, PrettyPrint f) 
             => Ext f e m -- ^ compute extended morphism 
             -> (e -> e -> Bool) -- ^ subsignature test of extensions
             -> Sign f e -> Sign f e -> Result (Morphism f e m)
sigInclusion extEm isSubExt sigma1 sigma2 = 
  if isSubSig isSubExt sigma1 sigma2 
     then return (embedMorphism extEm sigma1 sigma2)
     else pfatal_error 
          (text "Attempt to construct inclusion between non-subsignatures:"
           $$ text "Singature 1:" $$ printText sigma1
           $$ text "Singature 2:" $$ printText sigma2)
           nullPos

morphismUnion :: (m -> m -> m)  -- ^ join morphism extensions
              -> (e -> e -> e) -- ^ join signature extensions
              -> Morphism f e m -> Morphism f e m -> Result (Morphism f e m)
-- consider identity mappings but filter them eventually
morphismUnion uniteM addSigExt mor1 mor2 =
  let smap1 = sort_map mor1
      smap2 = sort_map mor2
      s1 = msource mor1
      s2 = msource mor2
      us1 = Set.difference (sortSet s1) $ Set.fromDistinctAscList 
            $ Map.keys smap1
      us2 = Set.difference (sortSet s2) $ Set.fromDistinctAscList 
            $ Map.keys smap2
      omap1 = fun_map mor1
      omap2 = fun_map mor2
      uo1 = foldr delOp (opMap s1) $ Map.keys omap1
      uo2 = foldr delOp (opMap s2) $ Map.keys omap2
      delOp (n, ot) m = diffMapSet m $ Map.single n $ 
                    Set.fromList [ot {opKind = Partial}, ot {opKind =Total}]
      uo = addMapSet uo1 uo2
      pmap1 = pred_map mor1
      pmap2 = pred_map mor2
      up1 = foldr delPred (predMap s1) $ Map.keys pmap1
      up2 = foldr delPred (predMap s2) $ Map.keys pmap2
      up = addMapSet up1 up2
      delPred (n, pt) m = diffMapSet m $ Map.single n $ Set.single pt
      (sds, smap) = foldr ( \ (i, j) (ds, m) -> case Map.lookup i m of
          Nothing -> (ds, Map.insert i j m)
          Just k -> if j == k then (ds, m) else 
              (Diag Error 
               ("incompatible mapping of sort " ++ showId i " to " 
                ++ showId j " and " ++ showId k "")
               nullPos : ds, m)) ([], smap1) 
          (Map.toList smap2 ++ map (\ a -> (a, a)) 
                      (Set.toList $ Set.union us1 us2))
      (ods, omap) = foldr ( \ (isc@(i, ot), jsc@(j, t)) (ds, m) -> 
          case Map.lookup isc m of
          Nothing -> (ds, Map.insert isc jsc m)
          Just (k, p) -> if j == k then if p == t then (ds, m)
                            else (ds, Map.insert isc (j, Total) m) else 
              (Diag Error 
               ("incompatible mapping of op " ++ showId i ":" 
                ++ showPretty ot { opKind = t } " to " 
                ++ showId j " and " ++ showId k "") nullPos : ds, m))
           (sds, omap1) (Map.toList omap2 ++ concatMap 
              ( \ (a, s) -> map ( \ ot -> ((a, ot {opKind = Partial}), 
                                           (a, opKind ot))) 
              $ Set.toList s) (Map.toList uo))
      (pds, pmap) = foldr ( \ (isc@(i, pt), j) (ds, m) -> 
          case Map.lookup isc m of
          Nothing -> (ds, Map.insert isc j m)
          Just k -> if j == k then (ds, m) else 
              (Diag Error 
               ("incompatible mapping of pred " ++ showId i ":" 
                ++ showPretty pt " to " ++ showId j " and " 
                ++ showId k "") nullPos : ds, m)) (ods, pmap1) 
          (Map.toList pmap2 ++ concatMap ( \ (a, s) -> map 
              ( \ pt -> ((a, pt), a)) $ Set.toList s) (Map.toList up))
      s3 = addSig addSigExt s1 s2
      o3 = opMap s3 in 
      if null pds then Result [] $ Just Morphism 
         { msource = s3,
           mtarget = addSig addSigExt (mtarget mor1) $ mtarget mor2,
           sort_map = Map.filterWithKey (/=) smap, 
           fun_map = Map.filterWithKey 
              (\ (i, ot) (j, k) -> i /= j || k == Total && Set.member ot 
               (Map.findWithDefault Set.empty i o3)) omap, 
           pred_map = Map.filterWithKey (\ (i, _) j -> i /= j) pmap,
           extended_map = uniteM (extended_map mor1) $ extended_map mor2 }
      else Result pds Nothing

instance PrettyPrint Symbol where
  printText0 ga sy = 
    printText0 ga (symName sy) <> 
    case symbType sy of
    SortAsItemType -> empty
    st -> space <> colon <> printText0 ga st

instance PrettyPrint SymbType where
  -- op types try to place a question mark immediately after a colon
  printText0 ga (OpAsItemType ot) = printText0 ga ot
  printText0 ga (PredAsItemType pt) = space <> printText0 ga pt
  printText0 _ SortAsItemType = empty 

instance PrettyPrint Kind where
  printText0 _ SortKind = text sortS
  printText0 _ FunKind = text opS
  printText0 _ PredKind = text predS

instance PrettyPrint RawSymbol where
  printText0 ga rsym = case rsym of
    ASymbol sy -> printText0 ga sy
    AnID i -> printText0 ga i
    AKindedId k i -> printText0 ga k <+> printText0 ga i

instance (PrettyPrint e, PrettyPrint f, PrettyPrint m) => 
    PrettyPrint (Morphism f e m) where
  printText0 ga mor = 
   printText0 ga (Map.filterWithKey (/=) $ morphismToSymbMap mor)
   $$ printText0 ga (extended_map mor)
   $$ nest 1 colon $$ 
   nest 3 (braces (space <> printText0 ga (msource mor) <> space))
   $$ nest 1 (text funS) 
   $$ nest 4 (braces (space <>  printText0 ga (mtarget mor) <> space))
