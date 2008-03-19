{- |
Module      :  $Header$
Description :  Grothendieck logic (flattening of logic graph to a single logic)
Copyright   :  (c) Till Mossakowski, and Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  :  till@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable (overlapping instances, dynamics, existentials)

Grothendieck logic (flattening of logic graph to a single logic)

The Grothendieck logic is defined to be the
   heterogeneous logic over the logic graph.
   This will be the logic over which the data
   structures and algorithms for specification in-the-large
   are built.

   This module heavily works with existential types, see
   <http://haskell.org/hawiki/ExistentialTypes> and chapter 7 of /Heterogeneous
   specification and the heterogeneous tool set/
   (<http://www.informatik.uni-bremen.de/~till/papers/habil.ps>).

   References:

   R. Diaconescu:
   Grothendieck institutions
   J. applied categorical structures 10, 2002, p. 383-402.

   T. Mossakowski:
   Comorphism-based Grothendieck institutions.
   In K. Diks, W. Rytter (Eds.), Mathematical foundations of computer science,
   LNCS 2420, pp. 593-604

   T. Mossakowski:
   Heterogeneous specification and the heterogeneous tool set.
-}

module Logic.Grothendieck
  ( G_basic_spec (..)
  , G_sign (..)
  , SigId(..)
  , startSigId
  , isHomSubGsign
  , isSubGsign
  , langNameSig
  , G_symbol (..)
  , G_symb_items_list (..)
  , G_symb_map_items_list (..)
  , G_sublogics (..)
  , isProperSublogic
  , G_morphism (..)
  , MorId(..)
  , startMorId
  , mkG_morphism
  , lessSublogicComor
  , LogicGraph (..)
  , emptyLogicGraph
  , lookupLogic
  , lookupCurrentLogic
  , logicUnion
  , lookupCompComorphism
  , lookupComorphism
  , lookupModification
  , GMorphism (..)
  , isHomogeneous
  , Grothendieck (..)
  , normalize
  , gEmbed
  , gEmbed2
  , gEmbedComorphism
  , gsigUnion
  , gsigManyUnion
  , homogeneousMorManyUnion
  , logicInclusion
  , updateMorIndex
  , toG_morphism
  , ginclusion
  , compInclusion
  , compHomInclusion
  , findComorphismPaths
  , findComorphism
  , isTransportable
  , G_prover (..)
  , getProverName
  , coerceProver
  , G_cons_checker (..)
  , coerceConsChecker
  , Square (..)
  , LaxTriangle (..)
  , mkIdSquare
  , mirrorSquare
  ) where

import Logic.Logic
import Logic.ExtSign
import Logic.Prover
import Logic.Comorphism
import Logic.Morphism
import Logic.Coerce
import Common.ExtSign
import Common.Doc
import Common.DocUtils
import qualified Data.Map as Map
import qualified Data.Set as Set
import Common.Result
import Common.Utils
import Data.Typeable
import Data.List (nub)
import Data.Maybe (catMaybes)
import Control.Monad (foldM)
import Logic.Modification
import Text.ParserCombinators.Parsec (Parser, try, parse, eof, string, (<|>))
-- for looking up modifications
import Common.Token
import Common.Lexer
import Common.Id

-- * \"Grothendieck\" versions of the various parts of type class Logic

-- | Grothendieck basic specifications
data G_basic_spec = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
  G_basic_spec lid basic_spec
  deriving Typeable

instance Show G_basic_spec where
    show (G_basic_spec _ s) = show s

instance Pretty G_basic_spec where
    pretty (G_basic_spec _ s) = pretty s

-- | index for signatures
newtype SigId = SigId Int deriving (Typeable, Show, Eq, Ord, Enum)

startSigId :: SigId
startSigId = SigId 0

{- | Grothendieck signatures with an lookup index. Zero indices
 indicate unknown ones. It would be nice to have special (may be
 negative) indices for empty signatures (one for every logic). -}
data G_sign = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree => G_sign
    { gSignLogic :: lid
    , gSign :: (ExtSign sign symbol)
    , gSignSelfIdx :: SigId -- ^ index to lookup this 'G_sign' in sign map
    } deriving Typeable

instance Eq G_sign where
  G_sign l1 sigma1 s1 == G_sign l2 sigma2 s2 =
    (s1 > startSigId && s2 > startSigId && s1 == s2) ||
     coerceSign l1 l2 "Eq G_sign" sigma1 == Just sigma2

-- | prefer a faster subsignature test if possible
isHomSubGsign :: G_sign -> G_sign -> Bool
isHomSubGsign (G_sign l1 sigma1 s1) (G_sign l2 sigma2 s2) =
    (s1 > startSigId && s2 > startSigId && s1 == s2) ||
    maybe False (ext_is_subsig l1 sigma1)
      (coerceSign l2 l1 "isHomSubGsign" sigma2)

isSubGsign :: LogicGraph -> G_sign -> G_sign -> Bool
isSubGsign lg (G_sign lid1 (ExtSign sigma1 _) _)
               (G_sign lid2 (ExtSign sigma2 _) _) =
  Just True ==
  do Comorphism cid <- resultToMaybe $
                         logicInclusion lg (Logic lid1) (Logic lid2)
     sigma1' <- coercePlainSign lid1 (sourceLogic cid)
                "Grothendieck.isSubGsign: cannot happen" sigma1
     sigma2' <- coercePlainSign lid2 (targetLogic cid)
                "Grothendieck.isSubGsign: cannot happen" sigma2
     sigma1t <- resultToMaybe $ map_sign cid sigma1'
     return $ is_subsig (targetLogic cid) (fst sigma1t) sigma2'

instance Show G_sign where
    show (G_sign _ s _) = show s

instance Pretty G_sign where
    pretty (G_sign _ (ExtSign s _) _) = pretty s

langNameSig :: G_sign -> String
langNameSig (G_sign lid _ _) = language_name lid

-- | Grothendieck symbols
data G_symbol = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree  =>
  G_symbol lid symbol
  deriving Typeable

instance Show G_symbol where
    show (G_symbol _ s) = show s

instance Pretty G_symbol where
    pretty (G_symbol _ s) = pretty s

instance Eq G_symbol where
  (G_symbol i1 s1) == (G_symbol i2 s2) =
     language_name i1 == language_name i2 && coerceSymbol i1 i2 s1 == s2

-- | Grothendieck symbol lists
data G_symb_items_list = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree  =>
        G_symb_items_list lid [symb_items]
  deriving Typeable

instance Show G_symb_items_list where
    show (G_symb_items_list _ l) = show l

instance Pretty G_symb_items_list where
    pretty (G_symb_items_list _ l) = ppWithCommas l

instance Eq G_symb_items_list where
  (G_symb_items_list i1 s1) == (G_symb_items_list i2 s2) =
     coerceSymbItemsList i1 i2 "Eq G_symb_items_list" s1 == Just s2

-- | Grothendieck symbol maps
data G_symb_map_items_list = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree  =>
        G_symb_map_items_list lid [symb_map_items]
  deriving Typeable

instance Show G_symb_map_items_list where
    show (G_symb_map_items_list _ l) = show l

instance Pretty G_symb_map_items_list where
    pretty (G_symb_map_items_list _ l) = ppWithCommas l

instance Eq G_symb_map_items_list where
  (G_symb_map_items_list i1 s1) == (G_symb_map_items_list i2 s2) =
     coerceSymbMapItemsList i1 i2 "Eq G_symb_map_items_list" s1 == Just s2

-- | Grothendieck sublogics
data G_sublogics = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
        G_sublogics lid sublogics
  deriving Typeable

instance Show G_sublogics where
    show (G_sublogics lid sub) = case sublogic_names sub of
      [] -> error "show G_sublogics"
      h : _ -> show lid ++ (if null h then "" else "." ++ h)

instance Eq G_sublogics where
    g1 == g2 = compare g1 g2 == EQ

instance Ord G_sublogics where
    compare (G_sublogics lid1 l1) (G_sublogics lid2 l2) =
       case compare (language_name lid1) $ language_name lid2 of
         EQ -> compare (forceCoerceSublogic lid1 lid2 l1) l2
         r -> r

isProperSublogic :: G_sublogics -> G_sublogics -> Bool
isProperSublogic a@(G_sublogics lid1 l1) b@(G_sublogics lid2 l2) =
    isSubElem (forceCoerceSublogic lid1 lid2 l1) l2 && a /= b

-- | index for morphisms
newtype MorId = MorId Int deriving (Typeable, Show, Eq, Ord, Enum)

startMorId :: MorId
startMorId = MorId 0

{- | Homogeneous Grothendieck signature morphisms with indices. For
the domain index it would be nice it showed also the emptiness. -}
data G_morphism = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree => G_morphism
    { gMorphismLogic :: lid
    , gMorphism :: morphism
    , gMorphismSelfIdx :: MorId -- ^ lookup index in morphism map
    } deriving Typeable

instance Show G_morphism where
    show (G_morphism _ m _) = show m

instance Pretty G_morphism where
    pretty (G_morphism _ m _) = pretty m

mkG_morphism :: forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree
  => lid -> morphism -> G_morphism
mkG_morphism l m = G_morphism l m startMorId

-- | check if sublogic fits for comorphism
lessSublogicComor :: G_sublogics -> AnyComorphism -> Bool
lessSublogicComor (G_sublogics lid1 sub1) (Comorphism cid) =
    let lid2 = sourceLogic cid
    in language_name lid2 == language_name lid1
        && isSubElem (forceCoerceSublogic lid1 lid2 sub1) (sourceSublogic cid)

-- | Logic graph
data LogicGraph = LogicGraph
    { logics :: Map.Map String AnyLogic
    , currentLogic :: String
    , comorphisms :: Map.Map String AnyComorphism
    , inclusions :: Map.Map (String, String) AnyComorphism
    , unions :: Map.Map (String, String) (AnyComorphism, AnyComorphism)
    , morphisms :: Map.Map String AnyMorphism
    , modifications :: Map.Map String AnyModification
    , squares :: Map.Map (AnyComorphism, AnyComorphism) [Square]
    } deriving Show

emptyLogicGraph :: LogicGraph
emptyLogicGraph = LogicGraph
    { logics = Map.empty
    , currentLogic = "CASL"
    , comorphisms = Map.empty
    , inclusions = Map.empty
    , unions = Map.empty
    , morphisms = Map.empty
    , modifications = Map.empty
    , squares = Map.empty }

instance Pretty LogicGraph where
    pretty lg = text ("current logic is: " ++ currentLogic lg)
       $+$ text "all logics:"
       $+$ sepByCommas (map text $ Map.keys $ logics lg)
       $+$ text "comorphism inclusions:"
       $+$ vcat (map pretty $ Map.elems $ inclusions lg)
       $+$ text "all comorphisms:"
       $+$ vcat (map pretty $ Map.elems $ comorphisms lg)

-- | find a logic in a logic graph
lookupLogic :: Monad m => String -> String -> LogicGraph -> m AnyLogic
lookupLogic error_prefix logname logicGraph =
    case Map.lookup logname $ logics logicGraph of
    Nothing -> fail $ error_prefix ++" in LogicGraph logic \""
                      ++ logname ++ "\" unknown"
    Just lid -> return lid

lookupCurrentLogic :: Monad m => String -> LogicGraph -> m AnyLogic
lookupCurrentLogic msg lg = lookupLogic msg (currentLogic lg) lg

-- | union to two logics
logicUnion :: LogicGraph -> AnyLogic -> AnyLogic
           -> Result (AnyComorphism, AnyComorphism)
logicUnion lg l1@(Logic lid1) l2@(Logic lid2) =
  case logicInclusion lg l1 l2 of
    Result _ (Just c) -> return (c,idComorphism l2)
    _ -> case logicInclusion lg l2 l1 of
      Result _ (Just c) -> return (idComorphism l1,c)
      _ -> case Map.lookup (ln1,ln2) (unions lg) of
        Just u -> return u
        Nothing -> case Map.lookup (ln2,ln1) (unions lg) of
          Just (c2,c1) -> return (c1,c2)
          Nothing -> fail $ "Union of logics " ++ ln1 ++
                     " and " ++ ln2 ++ " does not exist"
   where ln1 = language_name lid1
         ln2 = language_name lid2

-- | find a comorphism composition in a logic graph
lookupCompComorphism :: Monad m => [String] -> LogicGraph -> m AnyComorphism
lookupCompComorphism nameList logicGraph = do
  cs <- sequence $ map lookupN nameList
  case cs of
    c:cs1 -> foldM compComorphism c cs1
    _ -> fail "Illegal empty comorphism composition"
  where
  hasSublogic name (Logic lid) = elem name (sublogic_names $ top_sublogic lid)
  lookupN name =
    case name of
      'i':'d':'_':logic -> do
         let (mainLogic, subLogicD) = span (/= '.') logic
          --subLogicD will begin with a . which has to be removed
         l <- maybe (fail ("Cannot find Logic "++mainLogic)) return
                 $ Map.lookup mainLogic (logics logicGraph)
         case hasSublogic (tail subLogicD) l of
           True ->  return $ idComorphism l
           False -> fail ("Error in sublogic name"++logic)
      _ -> maybe (fail ("Cannot find logic comorphism "++name)) return
             $ Map.lookup name (comorphisms logicGraph)

-- | find a comorphism in a logic graph
lookupComorphism :: Monad m => String -> LogicGraph -> m AnyComorphism
lookupComorphism coname = lookupCompComorphism $ splitOn ';' coname

-- | find a modification in a logic graph
lookupModification :: (Monad m) => String -> LogicGraph -> m AnyModification
lookupModification input lG
        = case parse (parseModif lG << eof) "" input of
            Left err -> fail $ show err
            Right x  -> x

parseModif :: (Monad m) => LogicGraph -> Parser (m AnyModification)
parseModif lG = do
             (xs, _) <- separatedBy (vertcomp lG) crossT
             let r = do  y <- sequence xs
                         case y of
                           m:ms -> return $ foldM horCompModification m ms
                           _ -> Nothing
             case r of
               Nothing -> fail "Illegal empty horizontal composition"
               Just m -> return m

vertcomp :: (Monad m) => LogicGraph -> Parser (m AnyModification)
vertcomp lG = do
             (xs, _) <- separatedBy (pm lG) semiT
             let r = do
                      y <- sequence xs
                      case y of
                       m:ms -> return $ foldM vertCompModification m ms
                       _  -> Nothing
             --r has type Maybe (m AnyModification)
             case r of
               Nothing -> fail "Illegal empty vertical composition"
               Just m -> return m

pm :: (Monad m) => LogicGraph -> Parser (m AnyModification)
pm lG = parseName lG <|> bracks lG

bracks :: (Monad m) => LogicGraph -> Parser (m AnyModification)
bracks lG = do
  oParenT
  modif <- parseModif lG
  cParenT
  return modif

parseIdentity :: (Monad m) => LogicGraph -> Parser (m AnyModification)
parseIdentity lG = do
  try (string "id_")
  tok <- simpleId
  let name = tokStr tok
  case Map.lookup name (comorphisms lG) of
    Nothing -> fail $ "Cannot find comorphism" ++ name
    Just x -> return $ return $ idModification x

parseName :: (Monad m) => LogicGraph -> Parser (m AnyModification)
parseName lG = parseIdentity lG <|> do
  tok <- simpleId
  let name = tokStr tok
  case Map.lookup name (modifications lG) of
    Nothing -> fail $ "Cannot find modification" ++ name
    Just x -> return $ return x

-- * The Grothendieck signature category

-- | Grothendieck signature morphisms with indices
data GMorphism = forall cid lid1 sublogics1
        basic_spec1 sentence1 symb_items1 symb_map_items1
        sign1 morphism1 symbol1 raw_symbol1 proof_tree1
        lid2 sublogics2
        basic_spec2 sentence2 symb_items2 symb_map_items2
        sign2 morphism2 symbol2 raw_symbol2 proof_tree2 .
      Comorphism cid
        lid1 sublogics1 basic_spec1 sentence1
        symb_items1 symb_map_items1
        sign1 morphism1 symbol1 raw_symbol1 proof_tree1
        lid2 sublogics2 basic_spec2 sentence2
        symb_items2 symb_map_items2
        sign2 morphism2 symbol2 raw_symbol2 proof_tree2 => GMorphism
    { gMorphismComor :: cid
    , gMorphismSign :: ExtSign sign1 symbol1
    , gMorphismSignIdx :: SigId -- ^ 'G_sign' index of source signature
    , gMorphismMor :: morphism2
    , gMorphismMorIdx :: MorId  -- ^ `G_morphism index of target morphism
    } deriving Typeable

instance Eq GMorphism where
  GMorphism cid1 sigma1 in1 mor1 in1' == GMorphism cid2 sigma2 in2 mor2 in2'
     = Comorphism cid1 == Comorphism cid2
       && G_sign (sourceLogic cid1) sigma1 in1 ==
          G_sign (sourceLogic cid2) sigma2 in2
       && (in1' > startMorId && in2' > startMorId && in1' == in2'
          || coerceMorphism (targetLogic cid1) (targetLogic cid2)
                   "Eq GMorphism.coerceMorphism" mor1 == Just mor2)

isHomogeneous :: GMorphism -> Bool
isHomogeneous (GMorphism cid _ _ _ _) =
  isIdComorphism (Comorphism cid)

data Grothendieck = Grothendieck deriving (Typeable, Show)

instance Language Grothendieck

instance Show GMorphism where
    show (GMorphism cid s _ m _) =
      show (normalize (Comorphism cid)) ++ "(" ++ show s ++ ")" ++ show m

instance Pretty GMorphism where
    pretty (GMorphism cid (ExtSign s _) _ m _) = let c = Comorphism cid in fsep
      [ text $ show $ normalize c
      , if isIdComorphism c then empty else specBraces $ space <> pretty s
      , pretty m ]

normalize :: AnyComorphism -> AnyComorphism
normalize = id
{- todo: somthing like the following...
normalize (Comorphism cid) =
  case cid of
   CompComorphism r1 r2 ->
    case (normalize (Comorphism r1),  normalize (Comorphism r2)) of
     (Comorphism n1, Comorphism n2) ->
       if isIdComorphism (Comorphism n1) then Comorphism n2
         else if isIdComorphism (Comorphism n2) then Comorphism n1
           else Comorphism (CompComorphism n1 n2)
   _ -> Comorphism cid
-}

-- signature category of the Grothendieck institution
instance Category G_sign GMorphism where
  ide (G_sign lid sigma@(ExtSign s _) ind) =
    GMorphism (mkIdComorphism lid (top_sublogic lid))
              sigma ind (ide s) startMorId
  --  composition of Grothendieck signature morphisms
  comp (GMorphism r1 sigma1 ind1 mor1 _)
       (GMorphism r2 _sigma2 _ mor2 _) =
    do let lid1 = sourceLogic r1
           lid2 = targetLogic r1
           lid3 = sourceLogic r2
           lid4 = targetLogic r2
       -- coercion between target of first and
       --   source of second Grothendieck morphism
       mor1' <- coerceMorphism lid2 lid3 "Grothendieck.comp" mor1
       -- map signature morphism component of first Grothendieck morphism
       --  along the comorphism component of the second one ...
       mor1'' <- map_morphism r2 mor1'
       -- and then compose the result with the signature morphism component
       --   of first one
       mor <- comp mor1'' mor2
       -- if the first comorphism is the identity...
       if isIdComorphism (Comorphism r1) &&
          case coerceSublogic lid2 lid3 "Grothendieck.comp"
                              (targetSublogic r1) of
            Just sl1 -> maybe (error ("Logic.Grothendieck: Category "++
                                      "instance.comp: no mapping for " ++
                                      show sl1))
                              (isSubElem (targetSublogic r2))
                              (mapSublogic r2 sl1)
            _ -> False
         -- ... then things simplify ...
         then do
           sigma1' <- coerceSign lid1 lid3 "Grothendieck.comp" sigma1
           return (GMorphism r2 sigma1' ind1 mor startMorId)
         -- ... also, if the second comorphism is the identity ...
         else if isIdComorphism (Comorphism r2)
           then do mor2' <- coerceMorphism lid4 lid2 "Grothendieck.comp" mor2
                   mor' <- comp mor1 mor2'
                   return (GMorphism r1 sigma1 ind1 mor' startMorId)
           -- ... if not, use the composite comorphism
           else return $ GMorphism (CompComorphism r1 r2)
                sigma1 ind1 mor startMorId
  dom (GMorphism r sigma ind _mor _) =
    G_sign (sourceLogic r) sigma ind
  cod (GMorphism r (ExtSign _ sys) _ mor _) =
    let lid1 = sourceLogic r
        lid2 = targetLogic r
        sig2 = cod mor
    in case coerceSymbolSet lid1 lid2 "" sys of
      Nothing ->  G_sign lid2 (makeExtSign lid2 sig2) startSigId
      Just sys2 -> G_sign lid2 (ExtSign sig2 $ Set.map (\ sy ->
        Map.findWithDefault sy sy $ symmap_of lid2 mor) sys2) startSigId
  legal_mor (GMorphism r (ExtSign s _) _ mor _) =
    legal_mor mor &&
    case maybeResult $ map_sign r s of
      Just (sigma',_) -> sigma' == cod mor
      Nothing -> False

-- | Embedding of homogeneous signature morphisms as Grothendieck sig mors
gEmbed2 :: G_sign -> G_morphism -> GMorphism
gEmbed2 (G_sign lid2 sig si) (G_morphism lid mor ind) =
  let cid = mkIdComorphism lid (top_sublogic lid)
      Just sig1 = coerceSign lid2 (sourceLogic cid) "gEmbed2" sig
  in GMorphism cid sig1 si mor ind

-- | Embedding of homogeneous signature morphisms as Grothendieck sig mors
gEmbed :: G_morphism -> GMorphism
gEmbed (G_morphism lid mor ind) = let sig = dom mor in
  GMorphism (mkIdComorphism lid (top_sublogic lid))
                (makeExtSign lid sig) startSigId mor ind

-- | Embedding of comorphisms as Grothendieck sig mors
gEmbedComorphism :: AnyComorphism -> G_sign -> Result GMorphism
gEmbedComorphism (Comorphism cid) (G_sign lid sig ind) = do
  sig'@(ExtSign s _) <- coerceSign lid (sourceLogic cid) "gEmbedComorphism" sig
  (sigTar,_) <- map_sign cid s
  return (GMorphism cid sig' ind (ide sigTar) startMorId)

-- | heterogeneous union of two Grothendieck signatures
gsigUnion :: LogicGraph -> G_sign -> G_sign -> Result G_sign
gsigUnion lg gsig1@(G_sign lid1 (ExtSign sigma1 _) _)
          gsig2@(G_sign lid2 (ExtSign sigma2 _) _) =
  if language_name lid1 == language_name lid2
     then homogeneousGsigUnion gsig1 gsig2
     else do
      (Comorphism cid1, Comorphism cid2) <-
            logicUnion lg (Logic lid1) (Logic lid2)
      let lidS1 = sourceLogic cid1
          lidS2 = sourceLogic cid2
          lidT1 = targetLogic cid1
          lidT2 = targetLogic cid2
      sigma1' <- coercePlainSign lid1 lidS1 "Union of signaturesa" sigma1
      sigma2' <- coercePlainSign lid2 lidS2 "Union of signaturesb" sigma2
      (sigma1'',_) <- map_sign cid1 sigma1'  -- where to put axioms???
      (sigma2'',_) <- map_sign cid2 sigma2'  -- where to put axioms???
      sigma2''' <- coercePlainSign lidT2 lidT1 "Union of signaturesc" sigma2''
      sigma3 <- signature_union lidT1 sigma1'' sigma2'''
      return (G_sign lidT1 (makeExtSign lidT1 sigma3) startSigId)

-- | homogeneous Union of two Grothendieck signatures
homogeneousGsigUnion :: G_sign -> G_sign -> Result G_sign
homogeneousGsigUnion (G_sign lid1 sigma1 _) (G_sign lid2 sigma2 _) = do
  sigma2' <- coerceSign lid2 lid1 "Union of signaturesd" sigma2
  sigma3 <- ext_signature_union lid1 sigma1 sigma2'
  return (G_sign lid1 sigma3 startSigId)

-- | union of a list of Grothendieck signatures
gsigManyUnion :: LogicGraph -> [G_sign] -> Result G_sign
gsigManyUnion _ [] =
  fail "union of emtpy list of signatures"
gsigManyUnion lg (gsigma : gsigmas) =
  foldM (gsigUnion lg) gsigma gsigmas

-- | homogeneous Union of a list of morphisms
homogeneousMorManyUnion :: [G_morphism] -> Result G_morphism
homogeneousMorManyUnion [] =
  fail "homogeneous union of emtpy list of morphisms"
homogeneousMorManyUnion (gmor : gmors) =
  foldM ( \ (G_morphism lid2 mor2 _) (G_morphism lid1 mor1 _) -> do
            mor1' <- coerceMorphism lid1 lid2  "homogeneousMorManyUnion" mor1
            mor <- morphism_union lid2 mor1' mor2
            return (G_morphism lid2 mor startMorId)) gmor gmors

-- | inclusion between two logics
logicInclusion :: LogicGraph -> AnyLogic -> AnyLogic -> Result AnyComorphism
logicInclusion logicGraph l1@(Logic lid1) (Logic lid2) =
     let ln1 = language_name lid1
         ln2 = language_name lid2 in
     if ln1==ln2 then
       return (idComorphism l1)
      else case Map.lookup (ln1,ln2) (inclusions logicGraph) of
           Just (Comorphism i) ->
               return (Comorphism i)
           Nothing ->
               fail ("No inclusion from "++ln1++" to "++ln2++" found")

updateMorIndex :: MorId -> GMorphism -> GMorphism
updateMorIndex i (GMorphism cid sign si mor _) = GMorphism cid sign si mor i

toG_morphism :: GMorphism -> G_morphism
toG_morphism (GMorphism cid _ _ mor i) = G_morphism (targetLogic cid) mor i

-- | inclusion morphism between two Grothendieck signatures
ginclusion :: LogicGraph -> G_sign -> G_sign -> Result GMorphism
ginclusion logicGraph (G_sign lid1 sigma1 ind) (G_sign lid2 sigma2 _) = do
    Comorphism i <- logicInclusion logicGraph (Logic lid1) (Logic lid2)
    ext1@(ExtSign sigma1' _) <-
        coerceSign lid1 (sourceLogic i) "Inclusion of signatures" sigma1
    (sigma1'',_) <- map_sign i sigma1'
    ExtSign sigma2' _ <-
        coerceSign lid2 (targetLogic i) "Inclusion of signatures" sigma2
    mor <- inclusion (targetLogic i) sigma1'' sigma2'
    return (GMorphism i ext1 ind mor startMorId)

genCompInclusion :: (G_sign -> G_sign -> Result GMorphism)
                 -> GMorphism -> GMorphism -> Result GMorphism
genCompInclusion f mor1 mor2 = do
  let sigma1 = cod mor1
      sigma2 = dom mor2
  incl <- f sigma1 sigma2
  mor <- comp mor1 incl
  comp mor mor2

-- | Composition of two Grothendieck signature morphisms
-- | with itermediate inclusion
compInclusion :: LogicGraph -> GMorphism -> GMorphism -> Result GMorphism
compInclusion lg = genCompInclusion (ginclusion lg)

-- | Composition of two Grothendieck signature morphisms
-- | with intermediate homogeneous inclusion
compHomInclusion :: GMorphism -> GMorphism -> Result GMorphism
compHomInclusion = genCompInclusion homInclusion

-- | compose homogeneous inclusions avoiding mapping of signatures
homInclusion :: G_sign -> G_sign -> Result GMorphism
homInclusion (G_sign lid1 sigma1 ind) (G_sign lid2 sigma2 _) =
  case idComorphism $ Logic lid2 of
    Comorphism i -> do
      let tlid = targetLogic i
      ext1 <- coerceSign lid1 (sourceLogic i) "homInclusion1" sigma1
      ExtSign sigma1'' _ <- coerceSign lid1 tlid "homInclusion2" sigma1
      ExtSign sigma2' _ <- coerceSign lid2 tlid "homInclusion3" sigma2
      mor <- inclusion tlid sigma1'' sigma2'
      return (GMorphism i ext1 ind mor startMorId)

-- | Find all (composites of) comorphisms starting from a given logic
findComorphismPaths :: LogicGraph ->  G_sublogics -> [AnyComorphism]
findComorphismPaths lg (G_sublogics lid sub) =
  nub $ map fst $ iterateComp (0::Int) [(idc,[idc])]
  where
  idc = Comorphism (mkIdComorphism lid sub)
  coMors = Map.elems $ comorphisms lg
  -- compute possible compositions, but only up to depth 3
  iterateComp n l = -- (l::[(AnyComorphism,[AnyComorphism])]) =
    if n>1 || l==newL then newL else iterateComp (n+1) newL
    where
    newL = nub (l ++ (concat (map extend l)))
    -- extend comorphism list in all directions, but no cylces
    extend (coMor, cmps) =
       let addCoMor c =
            case compComorphism coMor c of
              Nothing -> Nothing
              Just c1 -> Just (c1, c : cmps)
        in catMaybes $ map addCoMor $ filter (not . (`elem` cmps)) $ coMors

-- | finds first comorphism with a matching sublogic
findComorphism ::Monad m => G_sublogics -> [AnyComorphism] -> m AnyComorphism
findComorphism _ [] = fail "No matching comorphism found"
findComorphism gsl@(G_sublogics lid sub) ((Comorphism cid):rest) =
    let l2 = sourceLogic cid
        rec = findComorphism gsl rest in
   if language_name lid == language_name l2
      then if isSubElem (forceCoerceSublogic lid l2 sub) $ sourceSublogic cid
              then return $ Comorphism cid
              else rec
      else rec

-- | check transportability of Grothendieck signature morphisms
-- | (currently returns false for heterogeneous morphisms)
isTransportable :: GMorphism -> Bool
isTransportable (GMorphism cid _ ind1 mor ind2) =
    ind1 > startSigId && ind2 > startMorId
    && isModelTransportable(Comorphism cid)
    && is_transportable (targetLogic cid) mor

-- * Provers

-- | provers and consistency checkers for specific logics
data G_prover = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
       G_prover lid (Prover sign sentence sublogics proof_tree)
  deriving Typeable

getProverName :: G_prover -> String
getProverName (G_prover _ p) = prover_name p

coerceProver ::
  (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String
      -> Prover sign1 sentence1 sublogics1 proof_tree1
      -> m (Prover sign2 sentence2 sublogics2 proof_tree2)
coerceProver l1 l2 msg m1 = primCoerce l1 l2 msg m1

data G_cons_checker = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
       G_cons_checker lid
                (ConsChecker sign sentence sublogics morphism proof_tree)
  deriving Typeable

coerceConsChecker ::
  (Logic  lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
                sign1 morphism1 symbol1 raw_symbol1 proof_tree1,
   Logic  lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
                sign2 morphism2 symbol2 raw_symbol2 proof_tree2,
   Monad m) => lid1 -> lid2 -> String
      -> ConsChecker sign1 sentence1 sublogics1 morphism1 proof_tree1
      -> m (ConsChecker sign2 sentence2 sublogics2 morphism2 proof_tree2)
coerceConsChecker l1 l2 msg m1 = primCoerce l1 l2 msg m1

-- * Lax triangles and weakly amalgamable squares of lax triangles
-- a lax triangle looks like:
--             laxTarget
--   i -------------------------------------> k
--                   ^  laxModif
--                  | |
--   i ------------- > j -------------------> k
--        laxFst              laxSnd
--
-- and I_k is quasi-semi-exact

data LaxTriangle = LaxTriangle {
                     laxModif :: AnyModification,
                     laxFst, laxSnd, laxTarget :: AnyComorphism
                   } deriving Show
-- a weakly amalgamable square of lax triangles
-- consists of two lax triangles with the same laxTarget

data Square = Square {
                 leftTriangle, rightTriangle :: LaxTriangle
              } deriving Show

-- for deriving Eq, first equality for modifications is needed

mkIdSquare :: AnyLogic -> Square
mkIdSquare (Logic lid) = let
   idCom = Comorphism (mkIdComorphism lid (top_sublogic lid))
   idMod = idModification idCom
   idTriangle = LaxTriangle{
                 laxModif = idMod,
                 laxFst = idCom,
                 laxSnd = idCom,
                 laxTarget = idCom}
 in Square{leftTriangle = idTriangle, rightTriangle = idTriangle}

mirrorSquare :: Square -> Square
mirrorSquare s = Square{
                 leftTriangle = rightTriangle s,
                 rightTriangle = leftTriangle s}
