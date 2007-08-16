{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Heng Jiang, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

Here is the place where the class Logic is instantiated for OWL DL.
-}

module OWL_DL.Logic_OWL_DL where

import Common.AS_Annotation
import Common.DefaultMorphism
import Common.Doc
import Common.DocUtils

import Logic.Logic

import OWL_DL.AS
import OWL_DL.Print
import OWL_DL.ATC_OWL_DL
import OWL_DL.Sign
import OWL_DL.StaticAna

data OWL_DL = OWL_DL deriving Show

instance Language OWL_DL where
 description _ =
  "OWL DL -- Web Ontology Language Description Logic http://wwww.w3c.org/"

type OWL_DLMorphism = DefaultMorphism Sign

instance Category OWL_DL Sign OWL_DLMorphism
    where
  dom OWL_DL = domOfDefaultMorphism
  cod OWL_DL = codOfDefaultMorphism
  ide OWL_DL = ideOfDefaultMorphism
  comp OWL_DL = compOfDefaultMorphism
  legal_obj OWL_DL = const True
  legal_mor OWL_DL = legalDefaultMorphism (legal_obj OWL_DL)

-- abstract syntax, parsing (and printing)

instance Syntax OWL_DL Ontology () ()
    -- default implementation is fine!

-- OWL DL logic

instance Sentences OWL_DL Sentence Sign OWL_DLMorphism () where
    map_sen OWL_DL _ s = return s
    print_named OWL_DL namedSen =
        pretty (sentence namedSen) <>
           if null (senAttr namedSen) then empty
        else space <> text "%%" <+> text (senAttr namedSen)

instance StaticAnalysis OWL_DL Ontology Sentence
               () ()
               Sign
               OWL_DLMorphism
               () ()   where
{- these functions are be implemented in OWL_DL.StaticAna and OWL_DL.Sign: -}
      basic_analysis OWL_DL = Just basicOWL_DLAnalysis
      empty_signature OWL_DL = emptySign
      signature_union OWL_DL s = return . addSign s
      signature_difference OWL_DL s = return . diffSig s
      final_union OWL_DL = signature_union OWL_DL
      inclusion OWL_DL = defaultInclusion (is_subsig OWL_DL)
      is_subsig OWL_DL = isSubSign


{-   this function will be implemented in OWL_DL.Taxonomy
         theory_to_taxonomy OWL_DL = convTaxo
-}

instance Logic OWL_DL ()
               Ontology Sentence () ()
               Sign
               OWL_DLMorphism
               () () () where
      empty_proof_tree _ = ()
                  
