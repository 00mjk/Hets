{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

   Here is the place where the class Logic is instantiated for CASL.
   Also the instances for Syntax an Category.
-}

module CASL.Logic_CASL(module CASL.Logic_CASL, CASLSign, CASLMor) where

import CASL.AS_Basic_CASL
import CASL.LaTeX_CASL
import CASL.Parse_AS_Basic
import CASL.SymbolParser
import CASL.MapSentence
import CASL.Amalgamability
import Common.AS_Annotation
import Common.AnnoState(emptyAnnos)
import Common.Lib.Parsec
import Logic.Logic
import Common.Lexer((<<))
import CASL.ATC_CASL

import CASL.Sublogic
import CASL.Sign
import CASL.StaticAna
import CASL.Morphism
import CASL.SymbolMapAnalysis
import CASL.CCC.FreeTypes
import Data.Dynamic
import Common.DynamicUtils
import CASL.SimplifySen
import Common.Result
import CASL.CCC.OnePoint -- currently unused

data CASL = CASL deriving Show

instance Language CASL where
 description _ = 
  "CASL - the Common algebraic specification language\n\ 
  \This logic is subsorted partial first-order logic \
  \with sort generation constraints\n\ 
  \See the CASL User Manual, LNCS 2900\n\ 
  \and the CASL Reference Manual, LNCS 2960\n\ 
  \See also http://www.cofi.info/CASL.html"

type CASLBasicSpec = BASIC_SPEC () () ()
type CASLFORMULA = FORMULA ()
-- Following types are imported from CASL.Amalgamability:
-- type CASLSign = Sign () ()
-- type CASLMor = Morphism () () ()

dummy :: a -> b -> ()
dummy _ _ = ()


-- dummy of "Min f e"
dummyMin :: a -> b -> c -> Result ()
dummyMin _ _ _ = Result {diags = [], maybeResult = Just ()}

trueC :: a -> b -> Bool
trueC _ _ = True

-- Typeable instance
tc_BASIC_SPEC, tc_SYMB_ITEMS, tc_SYMB_MAP_ITEMS, casl_SublocigsTc,
             sentenceTc, signTc, morphismTc, symbolTc, rawSymbolTc :: TyCon

casl_SublocigsTc  = mkTyCon "CASL.Sublogics.CASL_Sublogics"
tc_BASIC_SPEC     = mkTyCon "CASL.AS_Basic_CASL.BASIC_SPEC"
tc_SYMB_ITEMS     = mkTyCon "CASL.AS_Basic_CASL.SYMB_ITEMS"  
tc_SYMB_MAP_ITEMS = mkTyCon "CASL.AS_Basic_CASL.SYMB_MAP_ITEMS" 
sentenceTc       = mkTyCon "CASL.AS_Basic_CASL.FORMULA"
signTc           = mkTyCon "CASL.Morphism.Sign"
morphismTc       = mkTyCon "CASL.Morphism.Morphism"
symbolTc         = mkTyCon "CASL.Morphism.Symbol"
rawSymbolTc      = mkTyCon "CASL.Morphism.RawSymbol"

instance (Typeable b, Typeable s, Typeable f) 
    => Typeable (BASIC_SPEC b s f) where
  typeOf b = mkTyConApp tc_BASIC_SPEC 
             [typeOf $ (undefined :: BASIC_SPEC b s f -> b) b,
              typeOf $ (undefined :: BASIC_SPEC b s f -> s) b,
              typeOf $ (undefined :: BASIC_SPEC b s f -> f) b]
instance Typeable SYMB_ITEMS where
  typeOf _ = mkTyConApp tc_SYMB_ITEMS []
instance Typeable SYMB_MAP_ITEMS where
  typeOf _ = mkTyConApp tc_SYMB_MAP_ITEMS []
instance Typeable f => Typeable (FORMULA f) where
  typeOf f = mkTyConApp sentenceTc 
             [typeOf $ (undefined :: FORMULA f -> f) f]
instance (Typeable f, Typeable e) => Typeable (Sign f e) where
  typeOf s = mkTyConApp signTc 
             [typeOf $ (undefined :: Sign f e -> f) s,
              typeOf $ (undefined :: Sign f e -> e) s]
instance (Typeable e, Typeable f, Typeable m) => 
    Typeable (Morphism f e m) where
  typeOf m = mkTyConApp morphismTc
             [typeOf $ (undefined :: Morphism f e m -> f) m,
              typeOf $ (undefined :: Morphism f e m -> e) m,
              typeOf $ (undefined :: Morphism f e m -> m) m]
instance Typeable Symbol where
  typeOf _ = mkTyConApp symbolTc []
instance Typeable RawSymbol where
  typeOf _ = mkTyConApp rawSymbolTc []
instance Typeable CASL_Sublogics where
  typeOf _ = mkTyConApp casl_SublocigsTc []

instance Category CASL CASLSign CASLMor  
    where
         -- ide :: id -> object -> morphism
         ide CASL = idMor dummy
         -- comp :: id -> morphism -> morphism -> Maybe morphism
         comp CASL = compose (const id)
         -- dom, cod :: id -> morphism -> object
         dom CASL = msource
         cod CASL = mtarget
         -- legal_obj :: id -> object -> Bool
         legal_obj CASL = legalSign
         -- legal_mor :: id -> morphism -> Bool
         legal_mor CASL = legalMor

-- abstract syntax, parsing (and printing)

instance Syntax CASL CASLBasicSpec
                SYMB_ITEMS SYMB_MAP_ITEMS
      where 
         parse_basic_spec CASL = Just $ basicSpec []
         parse_symb_items CASL = Just $ symbItems []
         parse_symb_map_items CASL = Just $ symbMapItems []

-- lattices (for sublogics)

instance LatticeWithTop CASL_Sublogics where
    -- meet, join :: l -> l -> l
    meet = CASL.Sublogic.sublogics_min
    join = CASL.Sublogic.sublogics_max
    -- top :: l
    top = CASL.Sublogic.top

-- CASL logic

instance Sentences CASL CASLFORMULA () CASLSign CASLMor Symbol where
      map_sen CASL = mapSen (const return)
      parse_sentence CASL = Just
        ( \ _sign str ->
          case runParser (aFormula [] << eof) emptyAnnos "" str of
          Right x -> return $ item x
          Left err -> fail $ show err )
      sym_of CASL = symOf
      symmap_of CASL = morphismToSymbMap
      sym_name CASL = symName
      consCheck CASL = checkFreeType
      simplify_sen CASL = simplifySen dummyMin dummy dummy

instance StaticAnalysis CASL CASLBasicSpec CASLFORMULA ()
               SYMB_ITEMS SYMB_MAP_ITEMS
               CASLSign 
               CASLMor 
               Symbol RawSymbol where
         basic_analysis CASL = Just $ basicAnalysis
                               (const $ const return)
                               (const True)
                               (const $ const return) 
                               (const return)
                               (const return) const
         stat_symb_map_items CASL = statSymbMapItems
         stat_symb_items CASL = statSymbItems
         ensures_amalgamability CASL (opts, diag, sink, desc) = 
             ensuresAmalgamability opts diag sink desc

         sign_to_basic_spec CASL _sigma _sens = Basic_spec [] -- ???

         symbol_to_raw CASL = symbolToRaw
         id_to_raw CASL = idToRaw
         matches CASL = CASL.Morphism.matches
         
         empty_signature CASL = emptySign ()
         signature_union CASL sigma1 sigma2 = 
           return $ addSig dummy sigma1 sigma2
         morphism_union CASL = morphismUnion (const id) dummy
         final_union CASL = finalUnion dummy
         is_subsig CASL = isSubSig trueC
         inclusion CASL = sigInclusion dummy trueC
         cogenerated_sign CASL = cogeneratedSign dummy
         generated_sign CASL = generatedSign dummy
         induced_from_morphism CASL = inducedFromMorphism dummy
         induced_from_to_morphism CASL = inducedFromToMorphism dummy trueC

instance Logic CASL CASL.Sublogic.CASL_Sublogics
               CASLBasicSpec CASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CASLSign 
               CASLMor
               Symbol RawSymbol () where
         sublogic_names CASL = CASL.Sublogic.sublogics_name
         all_sublogics CASL = CASL.Sublogic.sublogics_all

         data_logic CASL = Nothing

         is_in_basic_spec CASL = CASL.Sublogic.in_basic_spec
         is_in_sentence CASL = CASL.Sublogic.in_sentence
         is_in_symb_items CASL = CASL.Sublogic.in_symb_items
         is_in_symb_map_items CASL = CASL.Sublogic.in_symb_map_items
         is_in_sign CASL = CASL.Sublogic.in_sign
         is_in_morphism CASL = CASL.Sublogic.in_morphism
         is_in_symbol CASL = CASL.Sublogic.in_symbol

         min_sublogic_basic_spec CASL = CASL.Sublogic.sl_basic_spec
         min_sublogic_sentence CASL = CASL.Sublogic.sl_sentence
         min_sublogic_symb_items CASL = CASL.Sublogic.sl_symb_items
         min_sublogic_symb_map_items CASL = CASL.Sublogic.sl_symb_map_items
         min_sublogic_sign CASL = CASL.Sublogic.sl_sign
         min_sublogic_morphism CASL = CASL.Sublogic.sl_morphism
         min_sublogic_symbol CASL = CASL.Sublogic.sl_symbol

         proj_sublogic_basic_spec CASL = CASL.Sublogic.pr_basic_spec
         proj_sublogic_symb_items CASL = CASL.Sublogic.pr_symb_items
         proj_sublogic_symb_map_items CASL = CASL.Sublogic.pr_symb_map_items
         proj_sublogic_sign CASL = CASL.Sublogic.pr_sign
         proj_sublogic_morphism CASL = CASL.Sublogic.pr_morphism
         proj_sublogic_epsilon CASL = CASL.Sublogic.pr_epsilon dummy
         proj_sublogic_symbol CASL = CASL.Sublogic.pr_symbol
