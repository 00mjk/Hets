{-| 
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  non-portable 

-}

module Haskell.HatAna (module Haskell.HatAna, PNT, TiDecl) where

import Common.AS_Annotation 
import Common.Id(Pos(..))
import Common.Result 
import Common.GlobalAnnotations
import Haskell.HatParser hiding (hatParser)
import Haskell.PreludeString
import Common.PrettyPrint
import Common.Lib.Pretty
import Data.List
import Data.Char
import Data.Set as DSet
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set

type Scope = Rel (SN HsName) (Ent (SN String))

data Sign = Sign 
    { instances :: [Instance PNT]
    , types :: Map.Map (HsIdentI PNT) (Kind, TypeInfo PNT)
    , values :: Map.Map (HsIdentI PNT) (Scheme PNT) 
    , scope :: Scope
    , fixities :: Map.Map (HsIdentI (SN String)) HsFixity
    } deriving (Show, Eq)

diffSign :: Sign -> Sign -> Sign
diffSign e1 e2 = emptySign 
    { instances = instances e1 \\ instances e2
    , types = types e1 `Map.difference` types e2
    , values = values e1 `Map.difference` values e2 
    , scope = scope e1 `minusRel` scope e2 
    , fixities = fixities e1 `Map.difference` fixities e2
    }

addSign :: Sign -> Sign -> Sign
addSign e1 e2 = emptySign 
    { instances = let is = instances e2 in (instances e1 \\ is) ++ is
    , types = types e1 `Map.union` types e2
    , values = values e1 `Map.union` values e2 
    , scope = scope e1 `DSet.union` scope e2 
    , fixities = fixities e1 `Map.union` fixities e2
    }

isSubSign :: Sign -> Sign -> Bool
isSubSign e1 e2 = diffSign e1 e2 == emptySign

instance Eq (TypeInfo i) where
    _ == _ = True

instance Eq (TiDecl PNT) where
    s1 == s2 = show s1 == show s2

instance Ord (TiDecl PNT) where
    s1 <= s2 = show s1 <= show s2

instance PrettyPrint (TiDecl PNT) where
     printText0 _ = text . pp

instance PrettyPrint Sign where
    printText0 _ Sign { instances = is, types = ts, 
                        values = vs, fixities = fs, scope = sc }
        = text "{-" $$ (if null is then empty else
              text "instances:" $$ 
                   vcat (map (text . pp) is)) $$ 
          (if Map.isEmpty ts then empty else
              text "\ntypes:" $$ 
                   vcat (map (text . pp) 
                         [ a :>: b | (a, b) <- Map.toList ts ])) $$
          (if Map.isEmpty vs then empty else
              text "\nvalues:" $$ 
                   vcat (map (text . pp) 
                         [ a :>: b | (a, b) <- Map.toList vs ])) $$
          (if Map.isEmpty fs then empty else
              text "\nfixities:" $$ 
                   vcat [ text (pp b) <+> text (pp a) 
                              | (a, b) <- Map.toList fs ]) $$
          text "\nscope:" $$ 
          text (pp sc) $$
          text "-}" $$
          text "module Dummy where"
          $$ text "import MyLogic"

extendSign :: Sign -> [Instance PNT]
            -> [TAssump PNT] 
            -> [Assump PNT] 
            -> Scope
            -> [(HsIdentI (SN String), HsFixity)]
            -> Sign
extendSign e is ts vs s fs = addSign e emptySign 
    { instances = is 
    , types = Map.fromList [ (a, b) | (a :>: b) <- ts ]
    , values = Map.fromList [ (a, b) | (a :>: b) <- vs ] 
    , scope = s
    , fixities = Map.fromList fs 
    } 

emptySign :: Sign
emptySign = Sign 
    { instances = []
    , types = Map.empty
    , values = Map.empty 
    , scope = emptyRel 
    , fixities = Map.empty 
    }

hatAna :: (HsDecls, Sign, GlobalAnnos) -> 
          Result (HsDecls, Sign, Sign, [Named (TiDecl PNT)])
hatAna (hs, e, ga) = do
    (decls, diffSig, accSig, sens) <- hatAna2 (hs, addSign e preludeSign, ga)
    return (decls, diffSig, diffSign accSig preludeSign, sens)

preludeSign :: Sign
preludeSign = case maybeResult $ hatAna2 
                (HsDecls $ preludeDecls, 
                         emptySign, emptyGlobalAnnos) of
                Just (_, _, sig, _) -> sig
                _ -> error "preludeSign"

hatAna2 :: (HsDecls, Sign, GlobalAnnos) -> 
          Result (HsDecls, Sign, Sign, [Named (TiDecl PNT)])
hatAna2 (hs@(HsDecls ds), e, _) = do
   let parsedMod = HsModule loc0 (SN mod_Prelude loc0) Nothing [] ds
       astMod = toMod parsedMod
       insc = inscope astMod (const emptyRel)
       osc = scope e `DSet.union` insc
       expScope :: Rel (SN String) (Ent (SN String))
       expScope = mapDom (fmap hsUnQual) osc
       wm :: WorkModuleI QName (SN String)
       wm = mkWM (osc, expScope)
       fixs = mapFst getQualified $ getInfixes parsedMod
       fixMap = Map.fromList fixs `Map.union` fixities e
       rm = reAssocModule wm [(mod_Prelude, Map.toList fixMap)] parsedMod
       (HsModule _ _ _ _ sds, _) = 
           scopeModule (wm, [(mod_Prelude, expScope)]) rm
       ent2pnt (Ent m (HsCon i) t) = 
           HsCon (topName Nothing m (bn i) (origt m t))
       ent2pnt (Ent m (HsVar i) t) = 
           HsVar (topName Nothing m (bn i) (origt m t))
       bn i = getBaseName i
       origt m = fmap (osub m) 
       osub m n = origName n m n
       findPredef ns (_, n) = 
           case filter ((==ns) . namespace) $ applyRel expScope (fakeSN n) of
           [v] -> Right (ent2pnt v)
           _ -> Left ("'" ++ n ++ "' unknown or ambiguous")
       inMyEnv =  withStdNames findPredef
               . inModule (const mod_Prelude) []
               . extendts [ a :>: b | (a, b) <- Map.toList $ values e ] 
               . extendkts [ a :>: b | (a, b) <- Map.toList $ types e ] 
               . extendIEnv (instances e)
   case sds of 
       [] -> return ()
       d : _ -> Result [Diag Hint ("\n" ++ pp sds) 
                       $ formSrcLoc $ srcLoc d] $ Just ()
   fs :>: (is, (ts, vs)) <- 
        lift $ inMyEnv $ tcTopDecls id sds
   let accSign = extendSign e is ts vs insc fixs
   return (hs, diffSign accSign e, accSign, map emptyName $ fromDefs 
             (fs :: TiDecls PNT))

-- filtering some Prelude stuff

formSrcLoc :: SrcLoc -> Pos
formSrcLoc (SrcLoc file _ line col) = SourcePos file line col

getHsDecl = maybe (error "FromHasCASL.getHsDecl") id . basestruct . struct 

preludeConflicts f = 
    foldr ( \ d (es, ds) -> let e = f d
                                p = formSrcLoc $ srcLoc e
                            in
        if preludeEntity e then 
            (es, 
             Diag Warning ("possible Prelude conflict:\n  " ++ pp e) p : ds)
           else (d : es, ds)) ([], [])

preludeEntity d = case d of 
    HsFunBind _ ms -> any preludeMatch ms
    HsTypeSig _ ts _ _ -> any (flip Set.member preludeValues . pp) ts
    HsTypeDecl _ ty _ -> Set.member (pp $ definedType ty) preludeTypes
    HsDataDecl _ _ ty cs _ -> Set.member (pp $ definedType ty) preludeTypes
                              || any preludeConstr cs
    _ -> True -- ignore others

preludeMatch m = case m of 
    HsMatch _ n _ _ _ -> let s = pp n in
        Set.member s preludeValues || prefixed s

preludeConstr c = let s = pp $ case c of
                          HsConDecl _ _ _ n _ -> n 
                          HsRecDecl _ _ _ n _ -> n 
                  in Set.member s preludeConstrs

genPrefixes :: [String]
genPrefixes = ["$--", "default__", "derived__Prelude", "inst__Prelude"]

prefixed :: String -> Bool
prefixed s = any (flip isPrefixOf s) genPrefixes

preludeValues :: Set.Set String
preludeValues = Set.fromList $ filter (not . prefixed) $ map pp 
                $ Map.keys $ values preludeSign

preludeConstrs :: Set.Set String
preludeConstrs = 
    Set.filter ( \ s -> not (null s) && isUpper (head s)) preludeValues

preludeTypes :: Set.Set String
preludeTypes = Set.fromList $ map pp $ Map.keys $ types preludeSign


