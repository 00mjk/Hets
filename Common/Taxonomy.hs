
{- |
Module      :  $Header$
Description :  type for selecting different kinds of taxonomy graphs
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable 

Type for selecting different kinds of taxonomy graphs

This module only provides a small type for selecting different kinds
of taxonomy graphs.

-}

module Common.Taxonomy where

data TaxoGraphKind = KSubsort | KConcept 
     deriving (Show,Enum,Eq)

data OntoObjectType =
    OntoClass | OntoObject | OntoPredicate deriving (Show, Eq)
