{-
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

  Abstract syntax for CASL_DL logic extension of CASL
  Only the added syntax is specified
-}

module CASL_DL.AS_CASL_DL where

import Common.Id
import Common.AS_Annotation 
import CASL.AS_Basic_CASL

-- DrIFT command
{-! global: UpPos !-}

type DL_BASIC_SPEC = BASIC_SPEC () () DL_FORMULA

type AnDLFORM = Annoted (FORMULA DL_FORMULA)

data CardType = CMin | CMax | CExact deriving (Eq, Ord, Show)

data DL_FORMULA = Cardinality CardType PRED_NAME 
                              (TERM DL_FORMULA) (TERM DL_FORMULA) [Pos]
               -- the PRED_NAME refers to a declared binary predicate; 
               -- the first term is restricted to constructors
               -- denoting a variable;
               -- the second term is restricted to an Application denoting 
               -- a literal of type nonNegativeInteger (Nat)
	       -- pos: position of keyword, brackets, parens and comma
             deriving (Eq, Ord, Show)

minCardinalityS,maxCardinalityS,cardinalityS :: String 
cardinalityS = "cardinality"
minCardinalityS = "minC" ++ tail cardinalityS
maxCardinalityS = "maxC" ++ tail cardinalityS

casl_DL_reserved_words :: [String]
casl_DL_reserved_words = minCardinalityS:maxCardinalityS:cardinalityS:[]
