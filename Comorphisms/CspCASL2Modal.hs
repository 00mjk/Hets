{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski and Uni Bremen 2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

   
   The embedding comorphism from CspCASL to ModalCASL.
   It keeps the CASL part and interprets the CspCASL LTS semantics as 
   Kripke structure
-}

module Comorphisms.CspCASL2Modal where

import Logic.Logic
import Logic.Comorphism
import qualified Common.Lib.Set as Set

-- CASL
import CASL.Sign
import CASL.AS_Basic_CASL
import CASL.Morphism

-- CspCASL
import CspCASL.Logic_CspCASL 
import CspCASL.SignCSP
import CspCASL.AS_CSP_CASL

-- ModalCASL
import Modal.Logic_Modal
import Modal.AS_Modal
import Modal.ModalSign

-- | The identity of the comorphism
data CspCASL2Modal = CspCASL2Modal deriving (Show)

instance Language CspCASL2Modal -- default definition is okay

instance Comorphism CspCASL2Modal
               CspCASL ()
               Basic_CSP_CASL_C_SPEC () SYMB_ITEMS SYMB_MAP_ITEMS
               CSPSign
               CSPMorphism
               () () ()
               Modal ()
               M_BASIC_SPEC ModalFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               MSign 
               ModalMor
               Symbol RawSymbol () where
    sourceLogic CspCASL2Modal = CspCASL
    sourceSublogic CspCASL2Modal = ()
    targetLogic CspCASL2Modal = Modal
    targetSublogic CspCASL2Modal = ()
    map_sign CspCASL2Modal sig = let e = mapSig sig in return (e, [])
    map_morphism CspCASL2Modal = return . mapMor
    map_sentence CspCASL2Modal _ = return . mapSen
    map_symbol CspCASL2Modal = Set.single . mapSym

mapSig :: CSPSign -> MSign
mapSig sign = 
     (emptySign emptyModalSign) {sortSet = sortSet sign
	       , sortRel = sortRel sign
               , opMap = opMap sign
	       , assocOps = assocOps sign
	       , predMap = predMap sign }
    -- ??? add modalities

mapMor :: CSPMorphism -> ModalMor
mapMor m = Morphism {msource = mapSig $ msource m
	           , mtarget = mapSig $ mtarget m
                   , sort_map = sort_map m
                   , fun_map = fun_map m
                   , pred_map = pred_map m
	           , extended_map = ()}
    -- ??? add modalities


mapSym :: () -> Symbol
mapSym = error "CspCASL2Modal.mapSym not yet implemented"
   -- needs to be changed once modal symbols are added


mapSen :: () -> ModalFORMULA
mapSen _f = True_atom []

{- case f of 
    Quantification q vs frm ps ->
	Quantification q vs (mapSen frm) ps
    Conjunction fs ps -> 
        Conjunction (map mapSen fs) ps 
    Disjunction fs ps -> 
        Disjunction (map mapSen fs) ps
    Implication f1 f2 b ps ->
	Implication (mapSen f1) (mapSen f2) b ps
    Equivalence f1 f2 ps -> 
	Equivalence (mapSen f1) (mapSen f2) ps
    Negation frm ps -> Negation (mapSen frm) ps
    True_atom ps -> True_atom ps
    False_atom ps -> False_atom ps
    Existl_equation t1 t2 ps -> 
	Existl_equation (mapTERM t1) (mapTERM t2) ps
    Strong_equation t1 t2 ps -> 
	Strong_equation (mapTERM t1) (mapTERM t2) ps
    Predication pn as qs ->
        Predication pn (map mapTERM as) qs
    Definedness t ps -> Definedness (mapTERM t) ps
    Membership t ty ps -> Membership (mapTERM t) ty ps
    Sort_gen_ax constrs isFree -> Sort_gen_ax constrs isFree
    _ -> error "CspCASL2Modal.mapSen"

mapTERM :: TERM () -> TERM M_FORMULA
mapTERM t = case t of
    Qual_var v ty ps -> Qual_var v ty ps
    Application opsym as qs  -> Application opsym (map mapTERM as) qs
    Sorted_term trm ty ps -> Sorted_term (mapTERM trm) ty ps 
    Cast trm ty ps -> Cast (mapTERM trm) ty ps 
    Conditional t1 f t2 ps -> 
       Conditional (mapTERM t1) (mapSen f) (mapTERM t2) ps
    _ -> error "CspCASL2Modal.mapTERM"

-}
