{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  hausmann@tzi.de
Stability   :  provisional
Portability :  portable

Instance of class Logic for CoCASL.
-}

module CoCASL.Logic_CoCASL where

import CoCASL.AS_CoCASL
import CoCASL.CoCASLSign
import CoCASL.ATC_CoCASL()
import CoCASL.Parse_AS
import CoCASL.StatAna
import CoCASL.Sublogic
import CASL.Sign
import CASL.Morphism
import CASL.SymbolMapAnalysis
import CASL.Logic_CASL
import CASL.AS_Basic_CASL
import CASL.Parse_AS_Basic
import CASL.MapSentence
import CASL.SymbolParser
import CASL.Sublogic
import Logic.Logic

data CoCASL = CoCASL deriving Show

instance Language CoCASL  where
 description _ =
  "CoCASL is the coalgebraic extension of CASL."

type CoCASLMor = Morphism C_FORMULA CoCASLSign ()
type CoCASLFORMULA = FORMULA C_FORMULA

instance Category CoCASL CSign CoCASLMor
    where
         -- ide :: id -> object -> morphism
         ide CoCASL = idMor dummy
         -- comp :: id -> morphism -> morphism -> Maybe morphism
         comp CoCASL = compose (const id)
         -- dom, cod :: id -> morphism -> object
         dom CoCASL = msource
         cod CoCASL = mtarget
         -- legal_obj :: id -> object -> Bool
         legal_obj CoCASL = legalSign
         -- legal_mor :: id -> morphism -> Bool
         legal_mor CoCASL = legalMor

-- abstract syntax, parsing (and printing)

instance Syntax CoCASL C_BASIC_SPEC
                SYMB_ITEMS SYMB_MAP_ITEMS
      where
         parse_basic_spec CoCASL = Just $ basicSpec cocasl_reserved_words
         parse_symb_items CoCASL = Just $ symbItems cocasl_reserved_words
         parse_symb_map_items CoCASL =
             Just $ symbMapItems cocasl_reserved_words

-- CoCASL logic


map_C_FORMULA :: MapSen C_FORMULA CoCASLSign ()
map_C_FORMULA mor frm = case frm of
           BoxOrDiamond b m f ps -> let
              newF = mapSen map_C_FORMULA mor f
              newM = case m of
                   Simple_mod _ ->  m
                   Term_mod t -> Term_mod $ mapTerm map_C_FORMULA mor t
              in BoxOrDiamond b newM newF ps
           phi -> phi

instance Sentences CoCASL CoCASLFORMULA () CSign CoCASLMor Symbol where
      map_sen CoCASL m = return . mapSen map_C_FORMULA m
      parse_sentence CoCASL = Nothing
      sym_of CoCASL = symOf
      symmap_of CoCASL = morphismToSymbMap
      sym_name CoCASL = symName
      provers CoCASL = []
      cons_checkers CoCASL = []

instance StaticAnalysis CoCASL C_BASIC_SPEC CoCASLFORMULA ()
               SYMB_ITEMS SYMB_MAP_ITEMS
               CSign
               CoCASLMor
               Symbol RawSymbol where
         basic_analysis CoCASL = Just $ basicCoCASLAnalysis
         stat_symb_map_items CoCASL = statSymbMapItems
         stat_symb_items CoCASL = statSymbItems
         ensures_amalgamability CoCASL _ =
             fail "CoCASL: ensures_amalgamability nyi" -- ???

         sign_to_basic_spec CoCASL _sigma _sens = Basic_spec [] -- ???

         symbol_to_raw CoCASL = symbolToRaw
         id_to_raw CoCASL = idToRaw
         matches CoCASL = CASL.Morphism.matches

         empty_signature CoCASL = emptySign emptyCoCASLSign
         signature_union CoCASL sigma1 sigma2 =
           return $ addSig addCoCASLSign sigma1 sigma2
         morphism_union CoCASL = morphismUnion (const id) addCoCASLSign
         final_union CoCASL = finalUnion addCoCASLSign
         is_subsig CoCASL = isSubSig isSubCoCASLSign
         inclusion CoCASL = sigInclusion dummy isSubCoCASLSign
         cogenerated_sign CoCASL = cogeneratedSign dummy
         generated_sign CoCASL = generatedSign dummy
         induced_from_morphism CoCASL = inducedFromMorphism dummy
         induced_from_to_morphism CoCASL =
             inducedFromToMorphism dummy isSubCoCASLSign

instance NameSL Bool where
    nameSL b = if b then "Co" else ""

instance MinSL Bool C_FORMULA where
    minSL = minFormSublogic

instance MinSL Bool C_SIG_ITEM where
    minSL = minCSigItem

instance MinSL Bool C_BASIC_ITEM where
    minSL = minCBaseItem

instance ProjForm Bool C_FORMULA
instance ProjSigItem Bool C_SIG_ITEM C_FORMULA
instance ProjBasic Bool C_BASIC_ITEM C_SIG_ITEM C_FORMULA

instance Logic CoCASL CoCASL_Sublogics
               C_BASIC_SPEC CoCASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CSign
               CoCASLMor
               Symbol RawSymbol () where
         stability _ = Unstable
         proj_sublogic_epsilon CoCASL = pr_epsilon dummy
         all_sublogics _ = sublogics_all [False, True]


