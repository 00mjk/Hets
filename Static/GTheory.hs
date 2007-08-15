{- |
Module      :  $Header$
Description :  theory datastructure for development graphs
Copyright   :  (c) Till Mossakowski, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  :  till@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable(Logic)

theory datastructure for development graphs
-}

module Static.GTheory  where

import Logic.Prover
import Logic.Logic
import Logic.Grothendieck
import Logic.Comorphism
import Logic.Coerce

import qualified Common.OrderedMap as OMap

import Common.AS_Annotation
import Common.Doc
import Common.DocUtils
import Common.Result

import Data.Typeable

import Control.Monad (foldM)
import Control.Exception

-- | Grothendieck theories
data G_theory = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
  G_theory lid sign Int (ThSens sentence (AnyComorphism, BasicProof)) Int

coerceThSens ::
   ( Logic lid1 sublogics1 basic_spec1 sentence1 symb_items1 symb_map_items1
           sign1 morphism1 symbol1 raw_symbol1 proof_tree1
   , Logic lid2 sublogics2 basic_spec2 sentence2 symb_items2 symb_map_items2
           sign2 morphism2 symbol2 raw_symbol2 proof_tree2
   , Monad m, Typeable b)
   => lid1 -> lid2 -> String -> ThSens sentence1 b -> m (ThSens sentence2 b)
coerceThSens l1 l2 msg t1 = primCoerce l1 l2 msg t1

instance Eq G_theory where
  G_theory l1 sig1 ind1 sens1 ind1' == G_theory l2 sig2 ind2 sens2 ind2' =
     G_sign l1 sig1 ind1 == G_sign l2 sig2 ind2
     && (ind1' > 0 && ind2' > 0 && ind1' == ind2'
         || coerceThSens l1 l2 "" sens1 == Just sens2)

instance Show G_theory where
  show (G_theory _ sign _ sens _) =
     shows sign $ "\n" ++ show sens

instance Pretty G_theory where
  pretty g = case simplifyTh g of
     G_theory lid sign _ sens _-> let l = toNamedList sens in
         if null l && is_subsig lid sign (empty_signature lid) then
             specBraces Common.Doc.empty else
         pretty sign $++$ vsep (map (print_named lid) l)

-- | compute sublogic of a theory
sublogicOfTh :: G_theory -> G_sublogics
sublogicOfTh (G_theory lid sigma _ sens _) =
  let sub = foldl join
                  (minSublogic sigma)
                  (map snd $ OMap.toList $
                   OMap.map (minSublogic . value)
                       sens)
   in G_sublogics lid sub

-- | simplify a theory (throw away qualifications)
simplifyTh :: G_theory -> G_theory
simplifyTh (G_theory lid sigma ind1 sens ind2) = G_theory lid sigma ind1
      (OMap.map (mapValue $ simplify_sen lid sigma) sens) ind2

-- | apply a comorphism to a theory
mapG_theory :: AnyComorphism -> G_theory -> Result G_theory
mapG_theory (Comorphism cid) (G_theory lid sign ind1 sens ind2) = do
  bTh <- coerceBasicTheory lid (sourceLogic cid)
                    "mapG_theory" (sign, toNamedList sens)
  (sign', sens') <- wrapMapTheory cid bTh
  return $ G_theory (targetLogic cid) sign' ind1 (toThSens sens') ind2

-- | Translation of a G_theory along a GMorphism
translateG_theory :: GMorphism -> G_theory -> Result G_theory
translateG_theory (GMorphism cid _ _ morphism2 _)
                      (G_theory lid sign _ sens ind)  = do
  let tlid = targetLogic cid
  bTh <- coerceBasicTheory lid (sourceLogic cid)
                    "translateG_theory" (sign, toNamedList sens)
  (_, sens'') <- wrapMapTheory cid bTh
  sens''' <- mapM (mapNamedM $ map_sen tlid morphism2) sens''
  return $ G_theory tlid (cod tlid morphism2) 0 (toThSens sens''') ind

-- | Join the sentences of two G_theories
joinG_sentences :: Monad m => G_theory -> G_theory -> m G_theory
joinG_sentences (G_theory lid1 sig1 ind sens1 _)
                    (G_theory lid2 sig2 _ sens2 _) = do
  sens2' <- coerceThSens lid2 lid1 "joinG_sentences" sens2
  sig2' <- coerceSign lid2 lid1 "joinG_sentences" sig2
  return $ assert (sig1 == sig2')
             $ G_theory lid1 sig1 ind (joinSens sens2' sens1) 0

-- | flattening the sentences form a list of G_theories
flatG_sentences :: Monad m => G_theory -> [G_theory] -> m G_theory
flatG_sentences th ths = foldM joinG_sentences th ths

-- | Get signature of a theory
signOf :: G_theory -> G_sign
signOf (G_theory lid sign ind _ _) = G_sign lid sign ind

data BasicProof =
  forall lid sublogics
        basic_spec sentence symb_items symb_map_items
        sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree =>
        BasicProof lid (Proof_status proof_tree)
     |  Guessed
     |  Conjectured
     |  Handwritten

instance Eq BasicProof where
  Guessed == Guessed = True
  Conjectured == Conjectured = True
  Handwritten == Handwritten = True
  BasicProof lid1 p1 == BasicProof lid2 p2 =
    coerceBasicProof lid1 lid2 "Eq BasicProof" p1 == Just p2
  _ == _ = False

instance Ord BasicProof where
    Guessed <= _ = True
    Conjectured <= x = case x of
                       Guessed -> False
                       _ ->  True
    Handwritten <= x = case x of
                       Guessed -> False
                       Conjectured -> False
                       _ ->  True
    BasicProof lid1 pst1 <= x =
        case x of
        BasicProof lid2 pst2
            | isProvedStat pst1 && not (isProvedStat pst2) -> False
            | not (isProvedStat pst1) && isProvedStat pst2 -> True
            | otherwise -> case primCoerce lid1 lid2 "" pst1 of
                           Nothing -> False
                           Just pst1' -> pst1' <= pst2
        _ -> False

instance Show BasicProof where
  show (BasicProof _ p1) = show p1
  show Guessed = "Guessed"
  show Conjectured = "Conjectured"
  show Handwritten = "Handwritten"

_basicProofTc :: TyCon
_basicProofTc = mkTyCon "Static.DevGraph.BasicProof"

instance Typeable BasicProof where
    typeOf _ = mkTyConApp _basicProofTc []
