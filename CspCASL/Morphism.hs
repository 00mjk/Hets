{-# LANGUAGE MultiParamTypeClasses #-}
{- |
Module      :  $Header$
Description :  Symbols and signature morphisms for the CspCASL logic
Copyright   :  (c) Liam O'Reilly, Markus Roggenbach, Swansea University 2008
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  csliam@swansea.ac.uk
Stability   :  provisional
Portability :  portable

Symbols and signature morphisms for the CspCASL logic
-}

module CspCASL.Morphism
    ( CspCASLMorphism
    , CspAddMorphism (..)
    , ChanMap
    , ProcessMap
    , mapProcProfile
    , cspSubsigInclusion
    , emptyCspAddMorphism
    , cspAddMorphismUnion
    , cspMorphismToCspSymbMap
    , inducedCspSign
    , mapSen
    ) where

import CspCASL.AS_CspCASL_Process
import CspCASL.SignCSP
import CspCASL.Symbol
import qualified CspCASL.LocalTop as LT

import CASL.AS_Basic_CASL (FORMULA, TERM, SORT)
import CASL.Sign as CASL_Sign
import CASL.Morphism as CASL_Morphism
import qualified CASL.MapSentence as CASL_MapSen

import Common.Doc
import Common.DocUtils
import Common.Id
import Common.Result
import Common.Utils (composeMap, isSingleton)
import qualified Common.Lib.MapSet as MapSet
import qualified Common.Lib.Rel as Rel

import qualified Data.Map as Map
import qualified Data.Set as Set

-- Morphisms

{- | This is the second component of a CspCASL signature moprhism, the process
name map. We map process name with a profile into new names and
communications alphabet. We follow CASL here and instread of mapping to a new
name and a new profile, we map just to the new name and the new
communications alphabet of the profile. This is because the argument sorts of
the profile have no chocie they have to be the sorts resultsing from maping
the original sorts in the profile with the data part map. Note: the
communications alphabet of the source profile must be downward closed with
respect to the CASL signature sub-sort relation (at source) and also the
target communications alphabet must be downward closed with respect to the
CASL signature sub-sort relation (at target). -}
type ProcessMap =
  Map.Map (PROCESS_NAME, ProcProfile) (PROCESS_NAME, CommAlpha)

type ChanMap = Map.Map (CHANNEL_NAME, SORT) CHANNEL_NAME

-- | CspAddMorphism - This is just the extended part
data CspAddMorphism = CspAddMorphism
    {- Note that when applying the CspAddMorphism to process names or channel
    names, if the name is not in the map in the morphism, then the
    application is the identity function. Thus empty maps are used to form
    the empty morphism and the identity morphism. -}
    { channelMap :: ChanMap
    , processMap :: ProcessMap
    } deriving (Eq, Ord, Show)

-- | The empty CspAddMorphism.
emptyCspAddMorphism :: CspAddMorphism
emptyCspAddMorphism = CspAddMorphism
    {- Note that when applying the CspAddMorphism to process names or
    channel names, if the name is not in the map in the morphism,
    then the application is the identity function. Thus empty maps
    are used to form the empty morphism. -}
    { channelMap = Map.empty
    , processMap = Map.empty
    }

{- | Given two signatures (the first being a sub signature of the second
according to CspCASL.SignCSP.isCspCASLSubSig) compute the inclusion morphism. -}
cspSubsigInclusion :: CspCASLSign -> CspCASLSign -> Result CspCASLMorphism
cspSubsigInclusion = CASL_Morphism.sigInclusion emptyCspAddMorphism
{- We use the empty morphism as it also represents the identity, thus this
will embed channel names and process names properly. -}

-- | lookup a typed channel
mapChan :: Sort_map -> ChanMap -> (CHANNEL_NAME, SORT) -> (CHANNEL_NAME, SORT)
mapChan sm cm p@(c, s) = (Map.findWithDefault c p cm, mapSort sm s)

-- | Apply a signature morphism to a channel name
mapChannel :: Morphism f CspSign CspAddMorphism -> (CHANNEL_NAME, SORT)
  -> (CHANNEL_NAME, SORT)
mapChannel mor = mapChan (sort_map mor) $ channelMap $ extended_map mor

mapCommTypeAux :: Sort_map -> ChanMap -> CommType -> CommType
mapCommTypeAux sm cm ct = case ct of
   CommTypeSort s -> CommTypeSort $ mapSort sm s
   CommTypeChan (TypedChanName c s) -> let (d, t) = mapChan sm cm (c, s) in
     CommTypeChan $ TypedChanName d t

-- | Apply a signature morphism to a CommType
mapCommType :: Morphism f CspSign CspAddMorphism -> CommType -> CommType
mapCommType mor = mapCommTypeAux (sort_map mor) (channelMap $ extended_map mor)

mapCommAlphaAux :: Sort_map -> ChanMap -> CommAlpha -> CommAlpha
mapCommAlphaAux sm = Set.map . mapCommTypeAux sm

-- | Apply a signature morphism  to a CommAlpha
mapCommAlpha :: Morphism f CspSign CspAddMorphism -> CommAlpha -> CommAlpha
mapCommAlpha = Set.map . mapCommType

mapProcProfile :: Sort_map -> ChanMap -> ProcProfile -> ProcProfile
mapProcProfile sm cm (ProcProfile sl cs) =
  ProcProfile (map (mapSort sm) sl) $ mapCommAlphaAux sm cm cs

mapProcId :: Sort_map -> ChanMap -> ProcessMap
  -> (PROCESS_NAME, ProcProfile) -> (PROCESS_NAME, ProcProfile)
mapProcId sm cm pm (i, p) = let
  n@(ProcProfile args _) = mapProcProfile sm cm p
  in case Map.lookup (i, p) pm of
       Nothing -> (i, n)
       Just (j, alpha) -> (j, ProcProfile args alpha)

mapProcess :: Morphism f CspSign CspAddMorphism
  -> (PROCESS_NAME, ProcProfile) -> (PROCESS_NAME, ProcProfile)
mapProcess mor = let em = extended_map mor in
  mapProcId (sort_map mor) (channelMap em) $ processMap em

-- | Compose two CspAddMorphisms
composeCspAddMorphism :: Morphism f CspSign CspAddMorphism
  -> Morphism f CspSign CspAddMorphism -> Result CspAddMorphism
composeCspAddMorphism m1 m2 = let
    sMap1 = sort_map m1
    sMap2 = sort_map m2
    sMap = composeMap (MapSet.setToMap $ sortSet src) sMap1 sMap2
    src = msource m1
    cSrc = extendedInfo src
    cMap = MapSet.foldWithKey ( \ c s ->
                       let p = (c, s)
                           ni = fst $ mapChannel m2 $ mapChannel m1 p
                       in if c == ni then id else Map.insert p ni)
                      Map.empty $ chans cSrc
    pMap = MapSet.foldWithKey ( \ p pr@(ProcProfile _ a) ->
                       let pp = (p, pr)
                           (ni, ProcProfile _ na) =
                             mapProcess m2 $ mapProcess m1 pp
                           oa = mapCommAlphaAux sMap cMap a
                       in if p == ni && oa == na then id else
                              Map.insert pp (ni, na))
                      Map.empty $ procSet cSrc
  in return emptyCspAddMorphism
  { channelMap = cMap
  , processMap = pMap }

{- | A CspCASLMorphism is a CASL Morphism with the extended_map to be a
CspAddMorphism. -}
type CspCASLMorphism = CASL_Morphism.Morphism CspSen CspSign CspAddMorphism

-- | Check if a CspCASL signature morphism has the refl property i.e.,
-- sigma(s1) <= sigma(s2) implies s1 <= s2 for all s1, s2 in S
checkReflCondition :: CspCASLMorphism -> Bool
checkReflCondition mor =
  let sig = msource mor
      sig' = mtarget mor
      sm = sort_map mor
      rel = Rel.transClosure $ sortRel sig
      rel' = Rel.transClosure $ sortRel sig'
      allPairs = LT.cartesian $ sortSet sig
      failures = Set.filter (not . test) allPairs
      test (s1,s2) =  if Rel.member (mapSort sm s1) (mapSort sm s2) rel'
                    then Rel.member s1 s2 rel
                    else True
  in Set.null failures

-- | Check if a CspCASL signature morphism has the weak non extension property
-- i.e.,
-- sigma(s1) <= u' and -- sigma(s2) <= u' implies there exists t in S with
-- s1 <= t and s2 <= t and sigma(t) <= u' for all s1,s2 in S and u' in S'
checkWNECondition :: CspCASLMorphism -> Bool
checkWNECondition mor =
  let sig = msource mor
      sig' = mtarget mor
      sm = sort_map mor
      rel' = Rel.transClosure $ sortRel sig'
      supers s signature = Set.insert s $ supersortsOf s signature
      allPairsInSource = LT.cartesian $ sortSet sig
      commonSuperSortsInTarget s1 s2 = Set.intersection
                                       (supers (mapSort sm s1) sig')
                                       (supers (mapSort sm s2) sig')
      conclusionCheck s1 s2 u' =
        let possibleWitnesses =
              Set.intersection (supers s1 sig) (supers s2 sig)
            test t = Rel.member (mapSort sm t) u' rel'
        in or $ Set.toList $ Set.map test possibleWitnesses
      mainTest (s1,s2) =
        Set.filter (not . conclusionCheck s1 s2)
        (commonSuperSortsInTarget s1 s2)
      failures = Set.map mainTest allPairsInSource
  in Set.null failures

-- | unite morphisms
cspAddMorphismUnion :: CspCASLMorphism -> CspCASLMorphism
  -> Result CspAddMorphism
cspAddMorphismUnion mor1 mor2 = let
    s1 = extendedInfo $ msource mor1
    s2 = extendedInfo $ msource mor2
    m1 = extended_map mor1
    m2 = extended_map mor2
    chan1 = channelMap m1
    chan2 = channelMap m2
    delChan (n, s) m = MapSet.delete n s m
    uc1 = foldr delChan (chans s1) $ Map.keys chan1
    uc2 = foldr delChan (chans s2) $ Map.keys chan2
    uc = MapSet.union uc1 uc2
    proc1 = processMap m1
    proc2 = processMap m2
    delProc (n, p) m = MapSet.delete n p m
    up1 = foldr delProc (procSet s1) $ Map.keys proc1
    up2 = foldr delProc (procSet s2) $ Map.keys proc2
    up = MapSet.union up1 up2
    showAlpha (i, s) l = shows i (if null l then "" else "(..)") ++ ":"
      ++ if isSingleton s then showDoc (Set.findMin s) "" else showDoc s ""
    (cds, cMap) = foldr ( \ (isc@(i, s), j) (ds, m) ->
          case Map.lookup isc m of
          Nothing -> (ds, Map.insert isc j m)
          Just k -> if j == k then (ds, m) else
              (Diag Error
               ("incompatible mapping of channel " ++ shows i ":"
                ++ showDoc s " to " ++ shows j " and "
                ++ shows k "") nullRange : ds, m)) ([], chan1)
          (Map.toList chan2 ++ concatMap ( \ (c, ts) -> map
              ( \ s -> ((c, s), c)) ts) (MapSet.toList uc))
    (pds, pMap) =
      foldr ( \ (isc@(i, pt@(ProcProfile args _)), j) (ds, m) ->
          case Map.lookup isc m of
          Nothing -> (ds, Map.insert isc j m)
          Just k -> if j == k then (ds, m) else
              (Diag Error
               ("incompatible mapping of process " ++ shows i " "
                ++ showDoc pt " to " ++ showAlpha j args ++ " and "
                ++ showAlpha k args) nullRange : ds, m)) (cds, proc1)
          (Map.toList proc2 ++ concatMap ( \ (p, pts) -> map
              ( \ pt@(ProcProfile _ al) -> ((p, pt), (p, al))) pts)
              (MapSet.toList up))
     in if null pds then return emptyCspAddMorphism
        { channelMap = cMap
        , processMap = pMap }
        else Result pds Nothing

toCspSymbMap :: Bool -> Morphism f CspSign CspAddMorphism
  -> Map.Map CspSymbol CspSymbol
toCspSymbMap b mor = let
    src = extendedInfo $ msource mor
    chanSymMap = MapSet.foldWithKey
      ( \ i t -> let
              p = (i, t)
              q@(j, _) = mapChannel mor p
              in if b && i == j then id else
                     Map.insert (toChanSymbol p) $ toChanSymbol q)
      Map.empty $ chans src
    procSymMap = MapSet.foldWithKey
      ( \ i t@(ProcProfile _ al) -> let
              p = (i, t)
              al1 = mapCommAlpha mor al
              q@(j, ProcProfile _ al2) = mapProcess mor p
              in if b && i == j && al1 == al2 then id else
                     Map.insert (toProcSymbol p) $ toProcSymbol q)
      Map.empty $ procSet src
  in Map.union chanSymMap procSymMap

cspMorphismToCspSymbMap :: CspCASLMorphism -> Map.Map CspSymbol CspSymbol
cspMorphismToCspSymbMap mor =
  Map.union (Map.fromList
    . map (\ (a, b) -> (caslToCspSymbol a, caslToCspSymbol b))
    $ Map.toList $ morphismToSymbMap mor)
  $ toCspSymbMap False mor

-- | Instance for CspCASL signature extension
instance SignExtension CspSign where
  isSubSignExtension = isCspSubSign

-- | a dummy instances used for the default definition
instance Pretty CspAddMorphism where
  pretty m = pretty $ toCspSymbMap False
    $ embedMorphism m emptyCspCASLSign emptyCspCASLSign

-- | Instance for CspCASL morphism extension (used for Category)
instance CASL_Morphism.MorphismExtension CspSign CspAddMorphism
    where
      ideMorphismExtension _ = emptyCspAddMorphism
      composeMorphismExtension = composeCspAddMorphism
      -- we omit inverses here
      isInclusionMorphismExtension m =
        Map.null (channelMap m) && Map.null (processMap m)
      -- pretty printing for Csp morphisms
      prettyMorphismExtension = printMap id sepByCommas pairElems
        . toCspSymbMap True

-- * induced signature extension

inducedChanMap :: Sort_map -> ChanMap -> ChanNameMap -> ChanNameMap
inducedChanMap sm cm = MapSet.foldWithKey
  ( \ i s ->
      let (j, t) = mapChan sm cm (i, s)
      in MapSet.insert j t) MapSet.empty

inducedProcMap :: Sort_map -> ChanMap -> ProcessMap -> ProcNameMap
  -> ProcNameMap
inducedProcMap sm cm pm = MapSet.foldWithKey
  ( \ n p ->
      let (m, q) = mapProcId sm cm pm (n, p)
      in MapSet.insert m q) MapSet.empty

inducedCspSign :: InducedSign f CspSign CspAddMorphism CspSign
inducedCspSign sm _ _ m sig =
  let csig = extendedInfo sig
      cm = channelMap m
  in emptyCspSign
     { chans = inducedChanMap sm cm $ chans csig
     , procSet = inducedProcMap sm cm (processMap m) $ procSet csig }

-- * application of morhisms to sentences

-- | Apply a Signature Morphism to a CspCASL Sentence
mapSen :: CspCASLMorphism -> CspSen -> CspSen
mapSen mor sen =
    if CASL_Morphism.isInclusionMorphism
       CASL_Morphism.isInclusionMorphismExtension mor
    then sen
    else case sen of
           ProcessEq procName fqVarList commAlpha proc ->
               let {- Map the morphism over all the parts of the process
                   equation -}
                   newProcName = mapProcessName mor procName
                   newFqVarList = mapFQProcVarList mor fqVarList
                   newCommAlpha = mapCommAlpha mor commAlpha
                   newProc = mapProc mor proc
               in ProcessEq newProcName newFqVarList
                                    newCommAlpha newProc

-- | Apply a signature morphism  to a Fully Qualified Process Variable List
mapFQProcVarList :: CspCASLMorphism -> FQProcVarList -> FQProcVarList
mapFQProcVarList mor =
    -- As these are terms, just map the morphism over CASL TERMs
    map (mapCASLTerm mor)

-- | Apply a signature morphism to a process
mapProc :: CspCASLMorphism -> PROCESS -> PROCESS
mapProc mor proc =
    let mapProc' = mapProc mor
        mapProcessName' = mapProcessName mor
        mapEvent' = mapEvent mor
        mapEventSet' = mapEventSet mor
        mapRenaming' = mapRenaming mor
        mapCommAlpha' = mapCommAlpha mor
        mapCASLTerm' = mapCASLTerm mor
        mapCASLFormula' = mapCASLFormula mor
    in case proc of
         Skip r -> Skip r
         Stop r -> Stop r
         Div r -> Div r
         Run es r -> Run (mapEventSet' es) r
         Chaos ev r -> Chaos (mapEventSet' ev) r
         PrefixProcess e p r ->
             PrefixProcess (mapEvent' e) (mapProc' p) r
         Sequential p q r -> Sequential (mapProc' p) (mapProc' q) r
         ExternalChoice p q r -> ExternalChoice (mapProc' p) (mapProc' q) r
         InternalChoice p q r -> InternalChoice (mapProc' p) (mapProc' q) r
         Interleaving p q r -> Interleaving (mapProc' p) (mapProc' q) r
         SynchronousParallel p q r ->
             SynchronousParallel (mapProc' p) (mapProc' q) r
         GeneralisedParallel p es q r ->
             GeneralisedParallel (mapProc' p) (mapEventSet' es) (mapProc' q) r
         AlphabetisedParallel p les res q r ->
             AlphabetisedParallel (mapProc' p) (mapEventSet' les)
                                      (mapEventSet' res) (mapProc' q) r
         Hiding p es r ->
             Hiding (mapProc' p) (mapEventSet' es) r
         RenamingProcess p re r ->
             RenamingProcess (mapProc' p) (mapRenaming' re) r
         ConditionalProcess f p q r ->
             ConditionalProcess (mapCASLFormula' f)
                                    (mapProc' p) (mapProc' q) r
         NamedProcess pn fqParams r ->
             NamedProcess (mapProcessName' pn) (map mapCASLTerm' fqParams) r
         FQProcess p commAlpha r ->
             FQProcess (mapProc' p) (mapCommAlpha' commAlpha) r

-- | Apply a signature morphism to an event set
mapEventSet :: CspCASLMorphism -> EVENT_SET -> EVENT_SET
mapEventSet mor (EventSet fqComms r) =
  EventSet (map (mapCommType mor) fqComms) r

-- | Apply a signature morphism to an event
mapEvent :: CspCASLMorphism -> EVENT -> EVENT
mapEvent mor e =
    let mapEvent' = mapEvent mor
        mapCASLTerm' = mapCASLTerm mor
        mapSort' = CASL_MapSen.mapSrt mor
        mapChannelName' = mapChannel mor
    in case e of
      TermEvent t r ->
          -- Just map the morphism over the event (a term)
          TermEvent (mapCASLTerm' t) r
      InternalPrefixChoice v s r ->
          -- Just map the morphism over the sort, we keep the variable name
          InternalPrefixChoice v (mapSort' s) r
      ExternalPrefixChoice v s r ->
          -- Just map the morphism over the sort, we keep the variable name
          ExternalPrefixChoice v (mapSort' s) r
      ChanSend c t r ->
          -- Just map the morphism over the event (a term) and the channel name
          ChanSend (fst $ mapChannelName' (c, sortOfTerm t)) (mapCASLTerm' t) r
      ChanNonDetSend c v s r ->
          {- Just map the morphism over the sort and the channel name, we keep
          the variable name -}
          ChanNonDetSend (fst $ mapChannelName' (c, s)) v (mapSort' s) r
      ChanRecv c v s r ->
          {- Just map the morphism over the sort and the channel name, we keep
          the variable name -}
          ChanRecv (fst $ mapChannelName' (c, s)) v (mapSort' s) r
      FQEvent ev mfqc fqTerm r ->
          -- Map the morphism over each part of the FQEvent
          FQEvent (mapEvent' ev) (fmap mapChannelName' mfqc)
              (mapCASLTerm' fqTerm) r

mapRenaming :: CspCASLMorphism -> RENAMING -> RENAMING
mapRenaming mor re =
    case re of
      Renaming _ ->
          {- There should be no (non fully qualified) Renamings (only
          FQRenamings) as the static analysis should have transformed
          EventSets into FQEventSets -}
          error "CspCASL.Morphism.mapRenaming: Unexpected Renaming"
      FQRenaming rs -> FQRenaming $ map (mapCASLTerm mor) rs

cspCASLMorphism2caslMorphism :: CspCASLMorphism -> Morphism () () ()
cspCASLMorphism2caslMorphism m =
  m { msource = ccSig2CASLSign $ msource m
    , mtarget = ccSig2CASLSign $ mtarget m
    , extended_map = () }

{- | Apply a signature morphism to a CASL TERM (for CspCASL only, i.e. a CASL
TERM that appears in CspCASL). -}
mapCASLTerm :: CspCASLMorphism -> TERM () -> TERM ()
mapCASLTerm =
    {- The error here is not used. It is a function to map over the morphism,
    CspCASL does not use this functionality. -}
    CASL_MapSen.mapTerm (error "CspCASL.Morphism.mapCASLTerm")
      . cspCASLMorphism2caslMorphism

{- | Apply a signature morphism to a CASL FORMULA (for CspCASL only, i.e. a CASL
FORMULA that appears in CspCASL). -}
mapCASLFormula :: CspCASLMorphism -> FORMULA () -> FORMULA ()
mapCASLFormula =
    {- The error here is not used. It is a function to map over the morphism,
    CspCASL does not use this functionality. -}
    CASL_MapSen.mapSen (error "CspCASL.Morphism.mapCASLFormula")
      . cspCASLMorphism2caslMorphism

-- | Apply a signature morphism to a process name
mapProcessName :: CspCASLMorphism -> FQ_PROCESS_NAME -> FQ_PROCESS_NAME
mapProcessName mor pn = case pn of
    FQ_PROCESS_NAME pn' procProfilePn' ->
      let (m, procProfileM) =
            mapProcess mor (pn', procProfilePn')
      in FQ_PROCESS_NAME m procProfileM
    _ -> error "unqualifed FQ_PROCESS_NAME"
