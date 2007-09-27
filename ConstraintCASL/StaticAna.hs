{- |
Module      :  $Header$
Description :  static analysis for ConstraintCASL
Copyright   :  (c) Uni Bremen 2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  till@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

static analysis for ConstraintCASL specifications
 Follows Chaps. III:2 and III:3 of the CASL Reference Manual.
-}

module ConstraintCASL.StaticAna where

import ConstraintCASL.AS_ConstraintCASL
import ConstraintCASL.Print_AS ()
import CASL.StaticAna
import CASL.Sign
import CASL.Morphism
import CASL.MixfixParser
import Common.Result
import Common.AS_Annotation
import Common.GlobalAnnotations

type ConstraintCASLSign = Sign ConstraintFORMULA ()
type ConstraintCASLMor = Morphism ConstraintFORMULA () ()

basicConstraintCASLAnalysis ::
        (ConstraintCASLBasicSpec, ConstraintCASLSign, GlobalAnnos)
                  -> Result (ConstraintCASLBasicSpec,
                             ConstraintCASLSign, [Named ConstraintCASLFORMULA])
basicConstraintCASLAnalysis =
    basicAnalysis (const return) (const return) (const return) emptyMix
