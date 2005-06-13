{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski, C. Maeder, Uni Bremen 2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  luettich@tzi.de
Stability   :  provisional
Portability :  portable

   Signatures for modal logic, as extension of CASL signatures.
-}

module Modal.ModalSign where

import CASL.Sign
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import Common.Id
import Modal.AS_Modal
import qualified Data.List as List
                       
data ModalSign = ModalSign { rigidOps :: OpMap
                           , rigidPreds :: Map.Map Id (Set.Set PredType)
                           , modies :: Map.Map SIMPLE_ID [AnModFORM]
                           , termModies :: Map.Map Id [AnModFORM] --SORT
                           } deriving (Show, Eq)

emptyModalSign :: ModalSign
emptyModalSign = ModalSign Map.empty Map.empty Map.empty Map.empty 

addModalSign :: ModalSign -> ModalSign -> ModalSign
addModalSign a b = a
     { rigidOps = addOpMapSet (rigidOps a) $ rigidOps b
     , rigidPreds = addMapSet (rigidPreds a) $ rigidPreds b
     , modies = Map.unionWith  List.union (modies a) $ modies b
     , termModies = Map.unionWith List.union (termModies a) $ termModies b
     } 

diffModalSign :: ModalSign -> ModalSign -> ModalSign
diffModalSign a b = a
     { rigidOps = diffMapSet (rigidOps a) $ rigidOps b
     , rigidPreds = diffMapSet (rigidPreds a) $ rigidPreds b
     , modies = Map.differenceWith diffList (modies a) $ modies b
     , termModies = Map.differenceWith diffList (termModies a) $ termModies b 
     } where diffList c d = let e = c List.\\ d in if null e then Nothing
                                                             else Just e

isSubModalSign :: ModalSign -> ModalSign -> Bool
isSubModalSign a b = 
    isSubOpMap (rigidOps a) (rigidOps b)
    && isSubMapSet (rigidPreds a) (rigidPreds b)
    && Map.isSubmapOfBy sublist (modies a) (modies b)
    && Map.isSubmapOfBy sublist (termModies a) (termModies b)
    where sublist = const $ const True
