{- |
Module      :  $Header$
Description :  XML output for composition tables of qualitative calculi
Copyright   :  (c) Uni Bremen 2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  till@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable(HaXml package)

XML output for composition tables
-}

module CASL.CompositionTable.ToXml (table_document) where

{-
DTD see systemURI

-- hets -v2 -n RCC8CompositionTable -o comptable.xml Calculi/Space/RCC8.het

-- writes Calculi/Space/RCC8_RCC8CompositionTable.comptable.xml

eliminate ops on rhs, resulting in list of base relations
add equations for id
-}

import CASL.CompositionTable.CompositionTable
import Text.XML.Light

{-
Using HaXml it is not very easy to just add a DOCTYPE to the derivated
XmlContent-instances so the following code takes care to create it.
Reading in the created files with standard HaXml-functions is not a problem.
-}

-- Public identifier (suggestion)
publicId::String
publicId = "-//CoFI//DTD CompositionTable 1.1//EN"

-- System URI
systemURI::String
systemURI =
  "http://www.informatik.uni-bremen.de/cofi/hets/CompositionTable.dtd"

table_prolog :: [String]
table_prolog =
    [ "<?xml version='1.0absd' encoding='UTF-8' ?>"
    , "<!DOCTYPE table PUBLIC " ++ shows publicId " "
      ++ shows systemURI ">" ]

-- this function renders a Table as xml string
table_document :: Table -> String
table_document t = unlines $ table_prolog ++ lines (ppElement $ table2Elem t)

table2Elem :: Table -> Element
table2Elem (Table as a b (Reflectiontable _) c) =
  add_attrs (tabAttr2Attrs as)
  $ unode "table" $ compTable2Elem a : conTable2Elems b  ++ [models2Elem c]

toAttrFrStr :: String -> String -> Attr
toAttrFrStr key = Attr (unqual key)

tabAttr2Attrs :: Table_Attrs -> [Attr]
tabAttr2Attrs v =
  [ toAttrFrStr "name" $ tableName v
  , toAttrFrStr "identity" $ baserelBaserel $ tableIdentity v ]

compTable2Elem :: Compositiontable -> Element
compTable2Elem (Compositiontable a) =
  unode "compositiontable" $ map cmpEntry2Elem a

cmpEntry2Elem :: Cmptabentry -> Element
cmpEntry2Elem (Cmptabentry as a) =
  add_attrs (cmpEntryAttrs2Attrs as)
  $ unode "cmptabentry" $ map baserel2Elem a

cmpEntryAttrs2Attrs :: Cmptabentry_Attrs -> [Attr]
cmpEntryAttrs2Attrs (Cmptabentry_Attrs b1 b2) =
  [ toAttrFrStr "argBaserel1" $ baserelBaserel b1
  , toAttrFrStr "argBaserel2" $ baserelBaserel b2 ]

baserel2Elem :: Baserel -> Element
baserel2Elem b = unode "baserel" $ baserel2Attr b

baserel2Attr :: Baserel -> Attr
baserel2Attr = toAttrFrStr "baserel" . baserelBaserel

conTable2Elems :: Conversetable -> [Element]
conTable2Elems ct = case ct of
  Conversetable a ->
    [unode  "conversetable" $ map conEntry2Elem a]
  _ -> []

conEntry2Elem :: Contabentry -> Element
conEntry2Elem as = unode "contabentry" $ conEntry2Attrs as

conEntry2Attrs :: Contabentry -> [Attr]
conEntry2Attrs (Contabentry a c) =
  [ toAttrFrStr "argBaseRel" $ baserelBaserel a
  , toAttrFrStr "converseBaseRel" $ baserelBaserel c ]

models2Elem :: Models -> Element
models2Elem (Models a) = unode "models" $ map model2Elem a

model2Elem :: Model -> Element
model2Elem as = unode "model" $ model2Attrs as

model2Attrs :: Model -> [Attr]
model2Attrs (Model s1 s2) =
  [ toAttrFrStr "string1" s1
  , toAttrFrStr "string2" s2 ]
