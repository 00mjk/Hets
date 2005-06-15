{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Uni Bremen 2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

translate HasCASL formulas to HasCASL program equations

-}

module Comorphisms.HasCASL2HasCASL where

import Logic.Logic
import Logic.Comorphism

import HasCASL.Logic_HasCASL
import HasCASL.As
import HasCASL.Le
import HasCASL.Morphism
import HasCASL.ProgEq

import qualified Common.Lib.Set as Set
import Common.AS_Annotation

-- | The identity of the comorphism
data HasCASL2HasCASL = HasCASL2HasCASL deriving Show

instance Language HasCASL2HasCASL -- default definition is okay

instance Comorphism HasCASL2HasCASL
               HasCASL HasCASL_Sublogics
               BasicSpec Sentence SymbItems SymbMapItems
               Env Morphism Symbol RawSymbol ()
               HasCASL HasCASL_Sublogics
               BasicSpec Sentence SymbItems SymbMapItems
               Env Morphism Symbol RawSymbol () where
    sourceLogic HasCASL2HasCASL = HasCASL
    sourceSublogic HasCASL2HasCASL = top
    targetLogic HasCASL2HasCASL = HasCASL
    targetSublogic HasCASL2HasCASL = top
    map_morphism HasCASL2HasCASL = return
    map_sentence HasCASL2HasCASL env = return . translateSen env
    map_symbol HasCASL2HasCASL = Set.singleton 
    map_theory HasCASL2HasCASL (sig, sen) = return 
      (sig, map  (mapNamed (translateSen sig)) sen)

