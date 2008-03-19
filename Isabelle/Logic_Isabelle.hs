{- |
Module      :  $Header$
Description :  Isabelle instance of class Logic
Copyright   :  (c) Till Mossakowski, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  non-portable (imports Logic)

Instance of class Logic for Isabelle (including Pure, HOL etc.).
-}

module Isabelle.Logic_Isabelle where

import Common.DefaultMorphism
import Logic.Logic

import Isabelle.ATC_Isabelle()
import Isabelle.IsaSign
import Isabelle.IsaPrint
import Isabelle.IsaProve

type IsabelleMorphism = DefaultMorphism Sign

-- a dummy datatype for the LogicGraph and for identifying the right
-- instances
data Isabelle = Isabelle deriving (Show)
instance Language Isabelle where
 description _ =
  "Isabelle - a generic theorem prover\n" ++
  "This logic corresponds to the logic of Isabelle,\n" ++
  "a weak intuitionistic type theory\n" ++
  "Also, the logics encoded in Isabelle, like FOL, HOL, HOLCF, ZF " ++
  "are made available\n" ++
  "See http://www.cl.cam.ac.uk/Research/HVG/Isabelle/"

instance Logic.Logic.Syntax Isabelle () () ()
    -- default implementation is fine!

instance Sentences Isabelle Sentence Sign IsabelleMorphism ()  where
      map_sen Isabelle _ s = return s
      print_named Isabelle = printNamedSen
    -- other default implementations are fine

instance StaticAnalysis Isabelle () Sentence
               () ()
               Sign
               IsabelleMorphism () ()  where
         sign_to_basic_spec Isabelle _sigma _sens = ()
         empty_signature Isabelle = emptySign
         inclusion Isabelle = defaultInclusion (is_subsig Isabelle)

instance Logic Isabelle () () Sentence () ()
               Sign
               IsabelleMorphism () () () where
         stability _ = Testing
    -- again default implementations are fine
         empty_proof_tree _ = ()
         provers Isabelle = [isabelleProver]
         cons_checkers Isabelle = [isabelleConsChecker]

