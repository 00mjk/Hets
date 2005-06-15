
{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luettich@tzi.de
Stability   :  provisional
Portability :  portable 

This module only provides a small type for selecting different kinds
of taxonomy graphs.

-}

module Common.Taxonomy where

data TaxoGraphKind = KSubsort | KConcept 
     deriving (Show,Enum,Eq)
