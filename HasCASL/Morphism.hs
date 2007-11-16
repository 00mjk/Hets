{- |
Module      :  $Header$
Description :  morphisms implementation
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

mapping entities of morphisms

-}

module HasCASL.Morphism where

import HasCASL.Le
import HasCASL.As
import HasCASL.FoldType
import HasCASL.TypeAna
import HasCASL.AsUtils
import HasCASL.AsToLe
import HasCASL.MapTerm
import HasCASL.Merge

import Common.DocUtils
import Common.Id
import Common.Result
import qualified Data.Set as Set
import qualified Data.Map as Map

instance Eq Morphism where
  m1 == m2 = (msource m1, mtarget m1, typeIdMap m1, classIdMap m1, funMap m1)
     == (msource m2, mtarget m2, typeIdMap m2, classIdMap m2, funMap m2)

-- | map a kind along an identifier map
mapKindI :: IdMap -> Kind -> Kind
mapKindI jm = mapKind $ (\ a -> Map.findWithDefault a a jm)

-- | map a kind along a signature morphism (variance is preserved)
mapKinds :: Morphism -> Kind -> Kind
mapKinds mor  = mapKindI $ classIdMap mor

-- | only rename the kinds in a type
mapKindsOfType :: IdMap -> TypeMap -> IdMap -> Type -> Type
mapKindsOfType jm tm im = foldType mapTypeRec
    { foldTypeAbs = \ _ a t p -> TypeAbs (mapTypeArg jm tm im a) t p
    , foldKindedType = \ _ t ks p -> KindedType t
          (Set.map (mapKindI jm) ks) p }

-- | map type, expand it, and also adjust the kinds
mapTypeE :: IdMap -> TypeMap -> IdMap -> Type -> Type
mapTypeE jm tm im =
  mapKindsOfType jm tm im . expandAliases tm . mapType im

-- | map a kind along a signature morphism (variance is preserved)
mapVarKind :: IdMap -> TypeMap -> IdMap -> VarKind -> VarKind
mapVarKind jm tm im vk = case vk of
  VarKind k -> VarKind $ mapKindI jm k
  Downset ty -> Downset $ mapTypeE jm tm im ty
  _ -> vk

mapTypeArg :: IdMap -> TypeMap -> IdMap -> TypeArg -> TypeArg
mapTypeArg jm tm im (TypeArg i v vk rk c s r) =
  TypeArg i v (mapVarKind jm tm im vk) rk c s r

mapTypeScheme :: IdMap -> TypeMap -> IdMap -> TypeScheme -> TypeScheme
mapTypeScheme jm tm im (TypeScheme args ty ps) =
    TypeScheme (map (mapTypeArg jm tm im) args) (mapTypeE jm tm im ty) ps

mapSen :: IdMap -> TypeMap -> IdMap -> FunMap -> Term -> Term
mapSen jm tm im fm = mapTerm (mapFunSym jm tm im fm, mapTypeE jm tm im)

setToMap :: Ord a => Set.Set a -> Map.Map a a
setToMap = Map.fromAscList . map ( \ a -> (a, a)) . Set.toList

getDatatypeIds :: DataEntry -> Set.Set Id
getDatatypeIds (DataEntry _ i _ _ _ alts) =
    let getAltIds (Construct _ tys _ sels) = Set.union
            (Set.unions $ map getTypeIds tys)
            $ Set.unions $ concatMap (map getSelIds) sels
        getSelIds (Select _ ty _) = getTypeIds ty
        getTypeIds = idsOf (== 0)
    in Set.insert i $ Set.unions $ map getAltIds $ Set.toList alts

mapDataEntry :: IdMap -> TypeMap -> IdMap -> FunMap -> DataEntry -> DataEntry
mapDataEntry jm tm im fm de@(DataEntry dm i k args rk alts) =
    let tim = Map.intersection (compIdMap dm im) $ setToMap $ getDatatypeIds de
        newargs = map (mapTypeArg jm tm im) args
    in DataEntry tim i k newargs rk $ Set.map
           (mapAlt jm tm tim fm newargs
           $ patToType (Map.findWithDefault i i tim) args rk) alts

mapAlt :: IdMap -> TypeMap -> IdMap -> FunMap -> [TypeArg] -> Type -> AltDefn
       -> AltDefn
mapAlt jm tm im fm args dt c@(Construct mi ts p sels) =
    case mi of
    Just i ->
      let sc = TypeScheme args
             (getFunType dt p $ map (mapTypeE jm tm im) ts) nullRange
          (j, TypeScheme _ ty _) = mapFunSym jm tm im fm (i, sc)
          in Construct (Just j) ts (getPartiality ts ty) $
             map (map (mapSel jm tm im fm args dt)) sels
    Nothing -> c

mapSel :: IdMap -> TypeMap -> IdMap -> FunMap -> [TypeArg] -> Type -> Selector
       -> Selector
mapSel jm tm im fm args dt s@(Select mid t p) = case mid of
    Nothing -> s
    Just i -> let
        sc = TypeScheme args (getSelType dt p $ mapTypeE jm tm im t) nullRange
        (j, TypeScheme _ ty _) = mapFunSym jm tm im fm (i, sc)
        in Select (Just j) t $ getPartiality [dt] ty

-- | get the partiality from a constructor type
-- with a given number of curried arguments
getPartiality :: [a] -> Type -> Partiality
getPartiality args t = case getTypeAppl t of
   (TypeName i _ _, [_, res]) | isArrow i -> case args of
     [] -> Total
     [_] -> if isPartialArrow i then Partial else Total
     _ : rs -> getPartiality rs res
   (TypeName i _ _, [_]) | i == lazyTypeId ->
        if null args then Partial else error "getPartiality"
   _ -> Total

mapSentence :: Morphism -> Sentence -> Result Sentence
mapSentence m s = let
    tm = filterAliases $ typeMap $ mtarget m
    im = typeIdMap m
    jm = classIdMap m
    fm = funMap m
    f = mapFunSym jm tm im fm
    in return $ case s of
      Formula t -> Formula $ mapSen jm tm im fm t
      DatatypeSen td -> DatatypeSen $ map (mapDataEntry jm tm im fm) td
      ProgEqSen i sc pe ->
        let (ni, nsc) = f (i, sc)
        in ProgEqSen ni nsc $ mapEq (f,  mapTypeE jm tm im) pe

mapFunSym :: IdMap -> TypeMap -> IdMap -> FunMap -> (Id, TypeScheme)
          -> (Id, TypeScheme)
mapFunSym jm tm im fm (i, sc) =
    let msc = mapTypeScheme jm tm im sc
    in Map.findWithDefault (i, msc) (i, msc) fm

embedMorphism :: Env -> Env -> Morphism
embedMorphism = mkMorphism

ideMor :: Env -> Morphism
ideMor e = embedMorphism e e

compIdMap :: IdMap -> IdMap -> IdMap
compIdMap im1 im2 = Map.foldWithKey ( \ i j ->
    let k = Map.findWithDefault j j im2 in
    if i == k then id else Map.insert i k) im2 im1

compMor :: Morphism -> Morphism -> Result Morphism
compMor m1 m2 =
  if mtarget m1 == msource m2 then
      let tm2 = typeIdMap m2
          im = compIdMap (typeIdMap m1) tm2
          cm2 = classIdMap m2
          cm = compIdMap (classIdMap m1) cm2
          fm2 = funMap m2
          tar = mtarget m2
          src = msource m1
          tm = filterAliases $ typeMap tar
      in return (mkMorphism src tar)
      { typeIdMap = Map.intersection im $ typeMap src
      , classIdMap = Map.intersection cm $ classMap src
      , funMap = Map.intersection (Map.foldWithKey ( \ p1 p2 ->
                       let p3 = mapFunSym cm tm tm2 fm2 p2 in
                       if p1 == p3 then id else Map.insert p1 p3)
                 fm2 $ funMap m1) $ Map.fromList $
                    concatMap ( \ (k, os) ->
                          map ( \ o -> ((k, mapTypeScheme cm tm im
                                        $ opType o), ())) $ Set.toList os)
                     $ Map.toList $ assumps src
      }
   else fail "intermediate signatures of morphisms do not match"

inclusionMor :: Env -> Env -> Result Morphism
inclusionMor e1 e2 =
  if isSubEnv e1 e2
     then return (embedMorphism e1 e2)
     else Result [Diag Error
          ("Attempt to construct inclusion between non-subsignatures:\n"
           ++ showEnvDiff e1 e2) nullRange] Nothing

showEnvDiff :: Env -> Env -> String
showEnvDiff e1 e2 =
    "Signature 1:\n" ++ showDoc e1 "\nSignature 2:\n"
           ++ showDoc e2 "\nDifference\n" ++ showDoc
              (diffEnv e1 e2) ""

legalEnv :: Env -> Bool
legalEnv _ = True -- maybe a closure test?

legalMor :: Morphism -> Bool
legalMor m = let
    s = msource m
    t = mtarget m
    ts = typeIdMap m
    cs = classIdMap m
    fs = funMap m in
       all (`elem` Map.keys (typeMap s)) (Map.keys ts)
    && all (`elem` Map.keys (typeMap t)) (Map.elems ts)
    && all (`elem` Map.keys (classMap s)) (Map.keys cs)
    && all (`elem` Map.keys (classMap t)) (Map.elems cs)
    && all ((`elem` Map.keys (assumps s)) . fst) (Map.keys fs)
    && all ((`elem` Map.keys (assumps t)) . fst) (Map.elems fs)

morphismUnion :: Morphism -> Morphism -> Result Morphism
morphismUnion m1 m2 = do
  let s1 = msource m1
      s2 = msource m2
  s <- merge s1 s2
  t <- merge (mtarget m1) $ mtarget m2
  let tm1 = typeMap s1
      tm2 = typeMap s2
      im1 = typeIdMap m1
      im2 = typeIdMap m2
      -- unchanged types
      ut1 = Map.keysSet tm1 Set.\\ Map.keysSet im1
      ut2 = Map.keysSet tm2 Set.\\ Map.keysSet im2
      ima1 = Map.union im1 $ setToMap ut1
      ima2 = Map.union im2 $ setToMap ut2
      sAs = filterAliases $ typeMap s
      tAs = filterAliases $ typeMap t
      cm1 = classMap s1
      cm2 = classMap s2
      jm1 = classIdMap m1
      jm2 = classIdMap m2
      -- unchanged classes
      cut1 = Map.keysSet cm1 Set.\\ Map.keysSet jm1
      cut2 = Map.keysSet cm2 Set.\\ Map.keysSet jm2
      cima1 = Map.union jm1 $ setToMap cut1
      cima2 = Map.union jm2 $ setToMap cut2
      expP = Map.fromList . map ( \ ((i, o), (j, p)) ->
                            ((i, expand tAs o), (j, expand tAs p)))
                  . Map.toList
      fm1 = expP $ funMap m1
      fm2 = expP $ funMap m2
      af jm im = Set.unions . map ( \ (i, os) ->
                   Set.map ( \ o -> (i, mapTypeScheme jm tAs im
                                    $ expand sAs $ opType o)) os)
                      . Map.toList
                 -- unchanged functions
      uf1 = af jm1 im1 (assumps s1) Set.\\ Map.keysSet fm1
      uf2 = af jm2 im2 (assumps s2) Set.\\ Map.keysSet fm2
      fma1 = Map.union fm1 $ setToMap uf1
      fma2 = Map.union fm2 $ setToMap uf2
      showFun (i, ty) = showId i . (" : " ++) . showDoc ty
  tma <- mergeMap ( \ t1 t2 -> if t1 == t2 then return t1 else
                      fail $ "incompatible type mapping to `"
                         ++ showId t1 "' and '" ++ showId t2 "'") ima1 ima2
  cma <- mergeMap ( \ t1 t2 -> if t1 == t2 then return t1 else
                      fail $ "incompatible class mapping to `"
                         ++ showId t1 "' and '" ++ showId t2 "'") cima1 cima2
  fma <- mergeMap ( \ o1 o2 -> if o1 == o2 then return o1 else
                      fail $ "incompatible mapping to '"
                         ++ showFun o1 "' and '" ++ showFun o2 "'") fma1 fma2
  return (mkMorphism s t)
    { typeIdMap = tma
    , classIdMap = cma
    , funMap = fma }

morphismToSymbMap :: Morphism -> SymbolMap
morphismToSymbMap mor = let
    src = msource mor
    tar = mtarget mor
    im = typeIdMap mor
    jm = classIdMap mor
    tm = filterAliases $ typeMap tar
    classSymMap = Map.foldWithKey ( \ i ti ->
       let j = Map.findWithDefault i i jm
           k = rawKind ti
           in Map.insert (idToClassSymbol src i k)
               $ idToClassSymbol tar j k) Map.empty $ classMap src
    typeSymMap = Map.foldWithKey ( \ i ti ->
       let j = Map.findWithDefault i i im
           k = typeKind ti
           in Map.insert (idToTypeSymbol src i k)
               $ idToTypeSymbol tar j k) classSymMap $ typeMap src
   in Map.foldWithKey
         ( \ i s m ->
             Set.fold ( \ oi ->
             let ty = opType oi
                 (j, t2) = mapFunSym jm tm im (funMap mor) (i, ty)
             in Map.insert (idToOpSymbol src i ty)
                        (idToOpSymbol tar j t2)) m s)
         typeSymMap $ assumps src
