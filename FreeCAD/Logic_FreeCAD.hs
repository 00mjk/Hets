{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, DeriveDataTypeable
  , GeneralizedNewtypeDeriving, TypeSynonymInstances #-}
{- |
Module      :  $Header$
Description :  Instance of class Logic for FreeCAD
Copyright   :  (c) Christian Maeder DFKI, Uni Bremen 2009
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

dummy instance of class Logic for FreeCAD

-}

module FreeCAD.Logic_FreeCAD where

import Logic.Logic

import Common.DefaultMorphism
import Common.Doc
import Common.DocUtils
import Common.ExtSign
import Common.Id
import Common.Utils

import ATerm.Lib

-- import Common.XmlParser (XmlParseable, parseXml)

import Data.List
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Typeable

import FreeCAD.As
import FreeCAD.ATC_FreeCAD ()
import FreeCAD.PrintAs

data FreeCAD = FreeCAD deriving Show

instance Language FreeCAD where
  description _ = "FreeCAD object representation language"

newtype Text = Text { fromText :: String }
  deriving (Show, Eq, Ord, GetRange, Typeable, ShATermConvertible)

instance Pretty Text where
  pretty (Text s) = text s

type FCMorphism = DefaultMorphism Sign

-- use generic Category instance from Logic.Logic

instance Syntax FreeCAD Document () () where
  parse_basic_spec FreeCAD = Nothing

instance Sentences FreeCAD () Sign FCMorphism () where
  map_sen FreeCAD _ = return
  sym_of FreeCAD _ = [Set.singleton ()]
  symmap_of FreeCAD _ = Map.empty
  sym_name FreeCAD _ = genName "FreeCAD"

instance StaticAnalysis FreeCAD Document () () () Sign FCMorphism () ()
  where
  basic_analysis FreeCAD = Just $ \ (bs, s, _) ->
    return (bs, mkExtSign s, [])
  empty_signature FreeCAD = Sign { objects = Set.empty }
  is_subsig FreeCAD s1 s2 = Set.isSubsetOf (objects s1) $ objects s2

-- instance Logic FreeCAD () Text () () () Text (DefaultMorphism Text) () () ()

instance Logic FreeCAD
    ()                        -- Sublogics
    Document                  -- basic_spec
    ()                        -- no sentences
    ()                        -- no symb_items
    ()                        -- no symb_map_items
    Sign                      -- sign
    (DefaultMorphism Sign)    -- morphism
    ()                        -- no symbol
    ()                        -- no raw_symbol
    ()                        -- no proof_tree
    where
      stability FreeCAD = Experimental

