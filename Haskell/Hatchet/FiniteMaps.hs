{-| 
   
Module      :  $Header$
Copyright   :  (c) Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

just a wrapper for the original interface

-}

module Haskell.Hatchet.FiniteMaps (FiniteMap, zeroFM, unitFM,
		   listToFM, listToCombFM, joinFM, joinCombFM, sizeFM,
		   Haskell.Hatchet.FiniteMaps.addToFM, 
		   addToCombFM, delFromFM, diffFM,
		   intersectFM, intersectCombFM, mapFM, foldFM,
		   filterFM, lookupFM, lookupDftFM, toListFM) where

import Data.FiniteMap
import Common.DFiniteMap -- re-export Show instance

zeroFM :: Ord k => FiniteMap k e
zeroFM = emptyFM

listToCombFM :: Ord k => (e -> e -> e) -> [(k, e)] -> FiniteMap k e
listToCombFM c = addListToFM_C c emptyFM

addToFM :: Ord k => k -> e -> FiniteMap k e -> FiniteMap k e
addToFM k v m = Data.FiniteMap.addToFM m k v

addToCombFM :: Ord k
	       => (e -> e -> e) -> k -> e -> FiniteMap k e -> FiniteMap k e
addToCombFM f k v m = addToFM_C f m k v

joinFM :: Ord k => FiniteMap k e -> FiniteMap k e -> FiniteMap k e
joinFM = plusFM

joinCombFM :: Ord k 
	   => (e -> e -> e) -> FiniteMap k e -> FiniteMap k e -> FiniteMap k e
joinCombFM = plusFM_C

diffFM :: Ord k => FiniteMap k e -> FiniteMap k e -> FiniteMap k e
diffFM = minusFM

intersectCombFM :: Ord k
		=> (e -> e -> e) 
		-> FiniteMap k e 
		-> FiniteMap k e 
		-> FiniteMap k e
intersectCombFM = intersectFM_C

lookupDftFM :: Ord k => FiniteMap k e -> e -> k -> e
lookupDftFM = lookupWithDefaultFM 

toListFM :: Ord k => FiniteMap k e -> [(k, e)]
toListFM = fmToList
