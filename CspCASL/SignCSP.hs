{- |
Module      :  $Header$
Copyright   :  (c) Markus Roggenbach and Till Mossakowski and Uni Bremen 2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  M.Roggenbach@swansea.ac.uk
Stability   :  provisional
Portability :  portable


  signatures for CSP-CASL

-}

{- todo:  implement isInclusion, computeExt
 
-}

module CspCASL.SignCSP where

import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.Morphism
import Common.Id
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import Data.Dynamic
import Common.DynamicUtils
import Common.Lib.Pretty
import Common.PrettyPrint
import Common.PrintLaTeX

data CSPAddSign = CSPAddSign { channelNames :: Map.Map Id SORT
                             , processNames :: Map.Map Id (Maybe SORT)}
                  deriving (Eq, Show)

type CSPSign = Sign () CSPAddSign

emptyCSPAddSign :: CSPAddSign
emptyCSPAddSign = CSPAddSign { channelNames = Map.empty
                       , processNames = Map.empty
                       }

diffCSPAddSign :: CSPAddSign -> CSPAddSign -> CSPAddSign
diffCSPAddSign a b = 
    a { channelNames = channelNames a `Map.difference` channelNames b,
        processNames = processNames a `Map.difference` processNames b
      }

diffCSPSign :: CSPSign -> CSPSign -> CSPSign
diffCSPSign sig1 sig2 = 
  diffSig sig1 sig2 
     { extendedInfo = extendedInfo sig1 `diffCSPAddSign` extendedInfo sig2 }

emptyCSPSign :: CSPSign
emptyCSPSign = emptySign emptyCSPAddSign

isInclusion :: CSPAddSign -> CSPAddSign -> Bool
isInclusion _ _ = True

data CSPAddMorphism = 
     CSPAddMorphism { channelMap :: Map.Map Id Id
                    , processMap :: Map.Map Id Id
                    }
     deriving (Eq, Show)


type CSPMorphism = Morphism () CSPAddSign CSPAddMorphism

computeExt :: Ext () CSPAddSign CSPAddMorphism
computeExt _ _  =
  CSPAddMorphism { channelMap = Map.empty -- ???
                 , processMap = Map.empty -- ???
                 }


signTc      = mkTyCon "CspCASL.SignCSP.CSPAddSign"
instance Typeable CSPAddSign where
  typeOf _ = mkTyConApp signTc []

morTc      = mkTyCon "CspCASL.SignCSP.CSPAddMorphism"
instance Typeable CSPAddMorphism where
  typeOf _ = mkTyConApp morTc []

-- dummy instances, need to be elaborated!
instance PrettyPrint CSPAddSign where
  printText0 _ x = ptext $ show x
instance PrettyPrint CSPAddMorphism where
  printText0 _ x = ptext $ show x
instance PrintLaTeX CSPAddSign where
  printLatex0 _ x = ptext $ show x
instance PrintLaTeX CSPAddMorphism where
  printLatex0 _ x = ptext $ show x
