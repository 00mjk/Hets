{-# LANGUAGE MultiParamTypeClasses #-}
{- |
Module      :  $Header$
Description :  Morphism extension for modal signature morphisms
Copyright   :  DFKI GmbH 2009
License     :  GPLv2 or higher, see LICENSE.txt
Maintainer  :  codruta.liliana@gmail.com
Stability   :  experimental
Portability :  portable

-}

module ExtModal.MorphismExtension where

import qualified Data.Map as Map
import qualified Data.Set as Set

import CASL.Morphism
import CASL.MapSentence

import Common.Doc
import Common.DocUtils
import Common.Id

import ExtModal.ExtModalSign
import ExtModal.AS_ExtModal
import ExtModal.Print_AS ()

data MorphExtension = MorphExtension
        { source :: EModalSign
        , target :: EModalSign
        , mod_map :: Map.Map Id Id
        , nom_map :: Map.Map SIMPLE_ID SIMPLE_ID
        } deriving (Show, Eq, Ord)

emptyMorphExtension :: MorphExtension
emptyMorphExtension =
  MorphExtension emptyEModalSign emptyEModalSign Map.empty Map.empty

instance Pretty MorphExtension where
        pretty me = specBraces (pretty $ source me) $+$
           mapsto <+> specBraces (pretty $ target me)
           $+$ pretty (mod_map me) $+$ pretty (nom_map me)

instance MorphismExtension EModalSign MorphExtension where

        ideMorphismExtension sgn =
                let insert_next old_map s_id = Map.insert s_id s_id old_map in
                MorphExtension sgn sgn
                  (foldl insert_next Map.empty (Map.keys (modalities sgn)))
                  (foldl insert_next Map.empty (Set.toList (nominals sgn)))

        composeMorphismExtension fme1 fme2 = let
          me1 = extended_map fme1
          me2 = extended_map fme2
          in if me1 == me2
                   then let me_compos second_map old_map (me_k, me_val) =
                                if Map.member me_val second_map
                                then Map.insert me_k (second_map Map.! me_val)
                                     old_map
                                else old_map
                        in return $ MorphExtension (source me1) (target me2)
                               (foldl (me_compos (mod_map me2))
                                      Map.empty (Map.toList (mod_map me1)))
                               (foldl (me_compos (nom_map me2))
                                      Map.empty (Map.toList (nom_map me1)))
                   else return emptyMorphExtension

        inverseMorphismExtension fme = let me = extended_map fme in
                let swap_arrows old_map (me_k, me_val) =
                        Map.insert me_val me_k old_map
                    occurs_alt [] once _ = once
                    occurs_alt ((_, me_val1) : l) True me_val2 =
                        me_val1 == me_val2 ||
                            occurs_alt l True me_val2
                    occurs_alt ((_, me_val1) : l) False me_val2 =
                        if me_val1 == me_val2
                        then occurs_alt l True me_val2
                        else occurs_alt l False me_val2
                in if Map.keys (modalities (target me))
                       == Map.elems (mod_map me)
                       && Set.toList (nominals (target me))
                              == Map.elems (nom_map me)
                       && Map.filter (occurs_alt (Map.toList (mod_map me))
                                      False) (mod_map me) == Map.empty
                        && Map.filter (occurs_alt (Map.toList (nom_map me))
                                       False) (nom_map me) == Map.empty
                      then return $ MorphExtension (target me) (source me)
                               (foldl swap_arrows Map.empty
                                (Map.toList (mod_map me)))
                                (foldl swap_arrows Map.empty
                                 (Map.toList (nom_map me)))
                      else return emptyMorphExtension

        isInclusionMorphismExtension me =
                let target_ide = ideMorphismExtension (target me) in
                Map.isSubmapOf (mod_map me) (mod_map target_ide)
                        && Map.isSubmapOf (nom_map me) (nom_map target_ide)

mapEMmod :: Morphism EM_FORMULA EModalSign MorphExtension -> MODALITY
  -> MODALITY
mapEMmod morph tm = case tm of
  SimpleMod sm -> case Map.lookup (simpleIdToId sm) $ mod_map
      $ extended_map morph of
    Just ni -> SimpleMod $ idToSimpleId ni
    Nothing -> tm
  ModOp o tm1 tm2 -> ModOp o (mapEMmod morph tm1) $ mapEMmod morph tm2
  TransClos tm1 -> TransClos $ mapEMmod morph tm1
  Guard frm -> Guard $ mapSen mapEMform morph frm
  TermMod trm -> TermMod $ mapTerm mapEMform morph trm

-- Modal formula mapping via signature morphism
mapEMform :: MapSen EM_FORMULA EModalSign MorphExtension
mapEMform morph frm = let rmapf = mapSen mapEMform morph in case frm of
  BoxOrDiamond choice tm leq_geq number f pos ->
    BoxOrDiamond choice (mapEMmod morph tm) leq_geq number (rmapf f) pos
  Hybrid choice nom f pos -> Hybrid choice
    (Map.findWithDefault nom nom $ nom_map $ extended_map morph)
    (rmapf f) pos
  UntilSince choice f1 f2 pos -> UntilSince choice (rmapf f1) (rmapf f2) pos
  NextY choice f pos -> NextY choice (rmapf f) pos
  PathQuantification choice f pos -> PathQuantification choice (rmapf f) pos
  StateQuantification t_dir choice f pos ->
    StateQuantification t_dir choice (rmapf f) pos
  FixedPoint choice p_var f pos -> FixedPoint choice p_var (rmapf f) pos
