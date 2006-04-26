

{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Till Mossakowski and Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

Symbols and signature morphisms for the CASL logic
-}

{-
todo:
issue warning for symbols lists like __ * __, __ + __: Elem * Elem -> Elem
the qualification only applies to __+__ !

possibly reuse SYMB_KIND for Kind
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
import Control.Exception (assert)
import Common.Doc
import Common.Print_AS_Annotation


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

instance PosItem Symbol where
    getRange = getRange . symName

type SymbolSet = Set.Set Symbol
type SymbolMap = Map.Map Symbol Symbol

data RawSymbol = ASymbol Symbol | AnID Id | AKindedId Kind Id
                 deriving (Show, Eq, Ord)

instance PosItem RawSymbol where
    getRange rs = 
        case rs of
        ASymbol s -> getRange s
        AnID i -> getRange i
        AKindedId _ i -> getRange i

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
mapOpType sorts t = if Map.null sorts then t else
                    t { opArgs = map (mapSort sorts) $ opArgs t
                      , opRes = mapSort sorts $ opRes t }

mapOpTypeK :: Sort_map -> FunKind -> OpType -> OpType
mapOpTypeK sorts k t = makeTotal k $ mapOpType sorts t

makeTotal :: FunKind -> OpType -> OpType
makeTotal Total t = t { opKind = Total }
makeTotal _ t = t

mapOpSym :: Sort_map -> Fun_map -> (Id, OpType) -> (Id, OpType)
mapOpSym sMap fMap (i, ot) =
    let mot = mapOpType sMap ot in
    case Map.lookup (i, ot {opKind = Partial} ) fMap of
    Nothing -> (i, mot)
    Just (j, k) -> (j, makeTotal k mot)

-- | Check if two OpTypes are equal modulo totality or partiality
compatibleOpTypes :: OpType -> OpType -> Bool
compatibleOpTypes ot1 ot2 = opArgs ot1 == opArgs ot2 && opRes ot1 == opRes ot2

mapPredType :: Sort_map -> PredType -> PredType
mapPredType sorts t = if Map.null sorts then t else
                      t { predArgs = map (mapSort sorts) $ predArgs t }

mapPredSym :: Sort_map -> Pred_map -> (Id, PredType) -> (Id, PredType)
mapPredSym sMap fMap (i, pt) =
    (Map.findWithDefault i (i, pt) fMap, mapPredType sMap pt)

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
    let sorts = Set.map idToSortSymbol $ sortSet sigma
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
        plain_error m1 ("Symbol " ++ showPretty rsy1 " mapped twice to "
                ++ showPretty rsy2 " and " ++ showPretty rsy3 "") nullRange

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
               "does not have kind" ++ showPretty k "") nullRange
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
            else Map.insert (i, ot {opKind = Partial}) (j, k) m
         _ -> m
       _ -> m
  mapPred i pts m = Set.fold (insPred i) m pts
  insPred i pt m =
    case Map.lookup (Symbol {symName = i, symbType = PredAsItemType pt}) smap
    of Just sym -> let j = symName sym in  case symbType sym of
         PredAsItemType _ -> if i == j then m else Map.insert (i, pt) j m
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
      src = msource mor1
      tar = mtarget mor2
      fMap1 = fun_map mor1
      pMap1 = pred_map mor1
      sMap2 = sort_map mor2
      fMap2 = fun_map mor2
      pMap2 = pred_map mor2
      sMap = if Map.null sMap2 then sMap1 else
             Set.fold ( \ i ->
                       let j = mapSort sMap2 (mapSort sMap1 i) in
                       if i == j then id else Map.insert i j)
                 Map.empty $ sortSet src
  in
     Morphism {
      msource = src,
      mtarget = tar,
      sort_map = sMap,
      fun_map  = if Map.null fMap2 then fMap1 else
                 Map.foldWithKey ( \ i t m ->
                   Set.fold ( \ ot ->
                       let (ni, nt) = mapOpSym sMap2 fMap2 $
                                      mapOpSym sMap1 fMap1 (i, ot)
                           k = opKind nt
                       in assert (mapOpTypeK sMap k ot == nt) $
                          if i == ni && opKind ot == k then id else
                          Map.insert (i, ot {opKind = Partial }) (ni, k)) m t)
                     Map.empty $ opMap src,
      pred_map = if Map.null pMap2 then pMap1 else
                 Map.foldWithKey ( \ i t m ->
                   Set.fold ( \ pt ->
                       let (ni, nt) = mapPredSym sMap2 pMap2 $
                                     mapPredSym sMap1 pMap1 (i, pt)
                       in assert (mapPredType sMap pt == nt) $
                       if i == ni then id else Map.insert (i, pt) ni) m t)
                      Map.empty $ predMap src,
      extended_map = comp (extended_map mor1) (extended_map mor2)
      }
    else fail "target of first and source of second morphism are different"

legalSign ::  Sign f e -> Bool
legalSign sigma =
  Map.foldWithKey (\s sset b -> b && legalSort s && all legalSort
                                (Set.toList sset))
                  True (Rel.toMap (sortRel sigma))
  && Map.fold (\ts b -> b && all legalOpType (Set.toList ts))
              True (opMap sigma)
  && Map.fold (\ts b -> b && all legalPredType (Set.toList ts))
              True (predMap sigma)
  where sorts = sortSet sigma
        legalSort s = Set.member s sorts
        legalOpType t = legalSort (opRes t)
                        && all legalSort (opArgs t)
        legalPredType t = all legalSort (predArgs t)

legalMor :: Morphism f e m -> Bool
legalMor mor =
  let s1 = msource mor
      s2 = mtarget mor
      smap = sort_map mor
      msorts = Set.map (mapSort smap) $ sortSet s1
      mops = Map.foldWithKey ( \ i ->
                 flip $ Set.fold ( \ ot ->
                        let (j, nt) = mapOpSym smap (fun_map mor) (i, ot)
                        in Rel.setInsert j nt)) Map.empty $ opMap s1
      mpreds = Map.foldWithKey ( \ i ->
                 flip $ Set.fold ( \ pt ->
                        let (j, nt) = mapPredSym smap (pred_map mor) (i, pt)
                        in Rel.setInsert j nt)) Map.empty $ predMap s1
  in
  legalSign s1
  && Set.isSubsetOf msorts (sortSet s2)
  && isSubOpMap mops (opMap s2)
  && isSubMapSet mpreds (predMap s2)
  && legalSign s2

sigInclusion :: (PrettyPrint e, PrettyPrint f)
             => Ext f e m -- ^ compute extended morphism
             -> (e -> e -> Bool) -- ^ subsignature test of extensions
             -> Sign f e -> Sign f e -> Result (Morphism f e m)
sigInclusion extEm isSubExt sigma1 sigma2 =
  assert (isSubSig isSubExt sigma1 sigma2) $
     return (embedMorphism extEm sigma1 sigma2)

morphismUnion :: (m -> m -> m)  -- ^ join morphism extensions
              -> (e -> e -> e) -- ^ join signature extensions
              -> Morphism f e m -> Morphism f e m -> Result (Morphism f e m)
-- consider identity mappings but filter them eventually
morphismUnion uniteM addSigExt mor1 mor2 =
  let smap1 = sort_map mor1
      smap2 = sort_map mor2
      s1 = msource mor1
      s2 = msource mor2
      us1 = Set.difference (sortSet s1) $ Rel.keysSet smap1
      us2 = Set.difference (sortSet s2) $ Rel.keysSet smap2
      omap1 = fun_map mor1
      omap2 = fun_map mor2
      uo1 = foldr delOp (opMap s1) $ Map.keys omap1
      uo2 = foldr delOp (opMap s2) $ Map.keys omap2
      delOp (n, ot) m = diffMapSet m $ Map.singleton n $
                    Set.fromList [ot {opKind = Partial}, ot {opKind =Total}]
      uo = addMapSet uo1 uo2
      pmap1 = pred_map mor1
      pmap2 = pred_map mor2
      up1 = foldr delPred (predMap s1) $ Map.keys pmap1
      up2 = foldr delPred (predMap s2) $ Map.keys pmap2
      up = addMapSet up1 up2
      delPred (n, pt) m = diffMapSet m $ Map.singleton n $ Set.singleton pt
      (sds, smap) = foldr ( \ (i, j) (ds, m) -> case Map.lookup i m of
          Nothing -> (ds, Map.insert i j m)
          Just k -> if j == k then (ds, m) else
              (Diag Error
               ("incompatible mapping of sort " ++ showId i " to "
                ++ showId j " and " ++ showId k "")
               nullRange : ds, m)) ([], smap1)
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
                ++ showId j " and " ++ showId k "") nullRange : ds, m))
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
                ++ showId k "") nullRange : ds, m)) (ods, pmap1)
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

isSortInjective :: Morphism f e m -> Bool
isSortInjective m =
   null [() | k1 <- src, k2 <-src, k1 /= k2,
              (Map.lookup k1 sm::Maybe SORT)==Map.lookup k2 sm]
   where sm = sort_map m
         src = Map.keys sm

instance PrettyPrint Symbol where
    printText0 ga = toText ga . pretty

instance Pretty Symbol where
  pretty sy = pretty (symName sy) <>
    case symbType sy of
       SortAsItemType -> empty
       st -> space <> colon <> pretty st
    

instance PrettyPrint SymbType where
  -- op types try to place a question mark immediately after a colon
  printText0 ga = toText ga . pretty

instance Pretty SymbType where
  pretty st = case st of
     OpAsItemType ot -> pretty ot
     PredAsItemType pt -> space <> pretty pt
     SortAsItemType -> empty
 
instance PrettyPrint Kind where
    printText0 ga = toText ga . pretty

instance Pretty Kind where
  pretty k = keyword $ case k of 
      SortKind -> sortS
      FunKind -> opS
      PredKind -> predS

instance PrettyPrint RawSymbol where
    printText0 ga = toText ga . pretty

instance Pretty RawSymbol where
  pretty rsym = case rsym of
    ASymbol sy -> pretty sy
    AnID i -> pretty i
    AKindedId k i -> pretty k <+> pretty i

instance (PrettyPrint e, PrettyPrint f, PrettyPrint m) =>
    PrettyPrint (Morphism f e m) where
        printText0 ga = toText ga . 
          printMorphism (fromText ga) (fromText ga) (fromText ga)



printMorphism :: (f->Doc) -> (e->Doc) -> (m->Doc) -> Morphism f e m -> Doc
printMorphism fF fE fM mor =
    printSymbolMap (Map.filterWithKey (/=) $ morphismToSymbMap mor)
    $+$ fM (extended_map mor) $+$ colon $+$
    specBraces (space <> printSign fF fE (msource mor) <> space)
    $+$ text funS $+$ 
    specBraces (space <> printSign fF fE (mtarget mor) <> space)

instance (Pretty e, Pretty f, Pretty m) =>
    Pretty (Morphism f e m) where
       pretty = printMorphism pretty pretty pretty

printSymbolMap :: SymbolMap -> Doc
printSymbolMap = printMap specBraces (fsep . punctuate comma) 
    (\ a b -> a <+> mapsto <+> b)
                   

printMap :: (Pretty a,Ord a,Pretty b) => (Doc->Doc) -> ([Doc]->Doc)
               -> (Doc->Doc->Doc) ->Map.Map a b -> Doc
printMap brace inter pairDoc m = printList brace inter 
     $ map ( \ (a, b) -> pairDoc (pretty a) (pretty b))
     $ Map.toList m 