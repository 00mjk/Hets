{-# LANGUAGE DeriveDataTypeable, DeriveGeneric #-}
{- |
Module      :  ./HolLight/Term.hs
Description :  Tern for HolLight logic
Copyright   :  (c) Jonathan von Schroeder, DFKI GmbH 2010
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  jonathan.von_schroeder@dfki.de
Stability   :  experimental
Portability :  portable

Definition of terms for HolLight logic

  Ref.

  <http://www.cl.cam.ac.uk/~jrh13/hol-light/>

-}

module HolLight.Term where

import Data.Data

import GHC.Generics (Generic)
import Data.Hashable

data HolType = TyVar String | TyApp String [HolType]
  deriving (Eq, Ord, Show, Read, Typeable, Data, Generic)

instance Hashable HolType

data HolProof = NoProof deriving (Eq, Ord, Show, Typeable, Data, Generic)

instance Hashable HolProof

data HolParseType = Normal | PrefixT
 | InfixL Int | InfixR Int | Binder
 deriving (Eq, Ord, Show, Read, Typeable, Data, Generic)

instance Hashable HolParseType

data HolTermInfo = HolTermInfo (HolParseType, Maybe (String, HolParseType))
  deriving (Eq, Ord, Show, Read, Typeable, Data, Generic)

instance Hashable HolTermInfo

data Term = Var String HolType HolTermInfo
     | Const String HolType HolTermInfo
     | Comb Term Term
     | Abs Term Term deriving (Eq, Ord, Show, Read, Typeable, Data, Generic)

instance Hashable Term
