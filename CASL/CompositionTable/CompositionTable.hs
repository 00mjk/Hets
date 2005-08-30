module CompositionTable where

import Text.XML.HaXml.Xml2Haskell
import Text.XML.HaXml.OneOfN
import Text.XML.HaXml.Types
import Text.XML.HaXml.Pretty
import Text.PrettyPrint.HughesPJ (Doc, vcat, render)

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
systemURI = "http://www.tzi.de/cofi/hets/CompositionTable.dtd"
-- for testing
--systemURI = "CompositionTable.dtd"

-- The root tag to use (derivated from Table-datatye)
rootTag::String
rootTag = "table"

-- Create DTD without internal entities
table_dtd::DocTypeDecl
table_dtd = DTD rootTag (Just (PUBLIC (PubidLiteral publicId) (SystemLiteral systemURI))) []

-- Create a Prolog for XML-Version 1.0 and UTF-8 encoding (or ISO ?)
table_prolog::Prolog
table_prolog = Prolog (Just (XMLDecl "1.0" (Just (EncodingDecl "UTF-8")) Nothing)) (Just table_dtd)

-- This function renders a Table-instance into a Doc-instance (pretty printing)
table_document::Table->Doc
table_document t = vcat $ (prolog table_prolog):(map content (toElem t))

-- This function should be used when writing out a Table-instance
-- It adds a DOCTYPE-Element and encoding information to the generated Xml
-- HaXmlS fWriteXml-function would omit this extra-information
writeTable::FilePath->Table->IO ()
writeTable f t = writeFile f $ render $ table_document t 

-- Shortcut to 'fReadXml f :: (IO Table)'
readTable::FilePath->(IO Table)
readTable = fReadXml

{-Type decls-}

data Table = Table Table_Attrs Compositiontable Conversetable
                   Models
           deriving (Eq,Show)
data Table_Attrs = Table_Attrs
    { tableName :: String
    , tableIdentity :: String
    } deriving (Eq,Show)
newtype Compositiontable = Compositiontable [Cmptabentry] 		deriving (Eq,Show)
newtype Conversetable = Conversetable [Contabentry] 		deriving (Eq,Show)
newtype Models = Models [Model] 		deriving (Eq,Show)
data Cmptabentry = Cmptabentry Cmptabentry_Attrs [Baserel]
                 deriving (Eq,Show)
data Cmptabentry_Attrs = Cmptabentry_Attrs
    { cmptabentryArgBaserel1 :: String
    , cmptabentryArgBaserel2 :: String
    } deriving (Eq,Show)
data Contabentry = Contabentry
    { contabentryArgBaseRel :: String
    , contabentryConverseBaseRel :: String
    } deriving (Eq,Show)
data Model = Model
    { modelString1 :: String
    , modelString2 :: String
    } deriving (Eq,Show)
data Baserel = Baserel
    { baserelBaserel :: String
    } deriving (Eq,Show)


{-Instance decls-}

instance XmlContent Table where
    fromElem (CElem (Elem "table" as c0):rest) =
        (\(a,ca)->
           (\(b,cb)->
              (\(c,cc)->
                 (Just (Table (fromAttrs as) a b c), rest))
              (definite fromElem "<models>" "table" cb))
           (definite fromElem "<conversetable>" "table" ca))
        (definite fromElem "<compositiontable>" "table" c0)
    fromElem (CMisc _:rest) = fromElem rest
    fromElem rest = (Nothing, rest)
    toElem (Table as a b c) =
        [CElem (Elem "table" (toAttrs as) (toElem a ++ toElem b ++
                                           toElem c))]
instance XmlAttributes Table_Attrs where
    fromAttrs as =
        Table_Attrs
          { tableName = definiteA fromAttrToStr "table" "name" as
          , tableIdentity = definiteA fromAttrToStr "table" "identity" as
          }
    toAttrs v = catMaybes 
        [ toAttrFrStr "name" (tableName v)
        , toAttrFrStr "identity" (tableIdentity v)
        ]
instance XmlContent Compositiontable where
    fromElem (CElem (Elem "compositiontable" [] c0):rest) =
        (\(a,ca)->
           (Just (Compositiontable a), rest))
        (many fromElem c0)
    fromElem (CMisc _:rest) = fromElem rest
    fromElem rest = (Nothing, rest)
    toElem (Compositiontable a) =
        [CElem (Elem "compositiontable" [] (concatMap toElem a))]
instance XmlContent Conversetable where
    fromElem (CElem (Elem "conversetable" [] c0):rest) =
        (\(a,ca)->
           (Just (Conversetable a), rest))
        (many fromElem c0)
    fromElem (CMisc _:rest) = fromElem rest
    fromElem rest = (Nothing, rest)
    toElem (Conversetable a) =
        [CElem (Elem "conversetable" [] (concatMap toElem a))]
instance XmlContent Models where
    fromElem (CElem (Elem "models" [] c0):rest) =
        (\(a,ca)->
           (Just (Models a), rest))
        (many fromElem c0)
    fromElem (CMisc _:rest) = fromElem rest
    fromElem rest = (Nothing, rest)
    toElem (Models a) =
        [CElem (Elem "models" [] (concatMap toElem a))]
instance XmlContent Cmptabentry where
    fromElem (CElem (Elem "cmptabentry" as c0):rest) =
        (\(a,ca)->
           (Just (Cmptabentry (fromAttrs as) a), rest))
        (many fromElem c0)
    fromElem (CMisc _:rest) = fromElem rest
    fromElem rest = (Nothing, rest)
    toElem (Cmptabentry as a) =
        [CElem (Elem "cmptabentry" (toAttrs as) (concatMap toElem a))]
instance XmlAttributes Cmptabentry_Attrs where
    fromAttrs as =
        Cmptabentry_Attrs
          { cmptabentryArgBaserel1 = definiteA fromAttrToStr "cmptabentry" "argBaserel1" as
          , cmptabentryArgBaserel2 = definiteA fromAttrToStr "cmptabentry" "argBaserel2" as
          }
    toAttrs v = catMaybes 
        [ toAttrFrStr "argBaserel1" (cmptabentryArgBaserel1 v)
        , toAttrFrStr "argBaserel2" (cmptabentryArgBaserel2 v)
        ]
instance XmlContent Contabentry where
    fromElem (CElem (Elem "contabentry" as []):rest) =
        (Just (fromAttrs as), rest)
    fromElem (CMisc _:rest) = fromElem rest
    fromElem rest = (Nothing, rest)
    toElem as =
        [CElem (Elem "contabentry" (toAttrs as) [])]
instance XmlAttributes Contabentry where
    fromAttrs as =
        Contabentry
          { contabentryArgBaseRel = definiteA fromAttrToStr "contabentry" "argBaseRel" as
          , contabentryConverseBaseRel = definiteA fromAttrToStr "contabentry" "converseBaseRel" as
          }
    toAttrs v = catMaybes 
        [ toAttrFrStr "argBaseRel" (contabentryArgBaseRel v)
        , toAttrFrStr "converseBaseRel" (contabentryConverseBaseRel v)
        ]
instance XmlContent Model where
    fromElem (CElem (Elem "model" as []):rest) =
        (Just (fromAttrs as), rest)
    fromElem (CMisc _:rest) = fromElem rest
    fromElem rest = (Nothing, rest)
    toElem as =
        [CElem (Elem "model" (toAttrs as) [])]
instance XmlAttributes Model where
    fromAttrs as =
        Model
          { modelString1 = definiteA fromAttrToStr "model" "string1" as
          , modelString2 = definiteA fromAttrToStr "model" "string2" as
          }
    toAttrs v = catMaybes 
        [ toAttrFrStr "string1" (modelString1 v)
        , toAttrFrStr "string2" (modelString2 v)
        ]
instance XmlContent Baserel where
    fromElem (CElem (Elem "baserel" as []):rest) =
        (Just (fromAttrs as), rest)
    fromElem (CMisc _:rest) = fromElem rest
    fromElem rest = (Nothing, rest)
    toElem as =
        [CElem (Elem "baserel" (toAttrs as) [])]
instance XmlAttributes Baserel where
    fromAttrs as =
        Baserel
          { baserelBaserel = definiteA fromAttrToStr "baserel" "baserel" as
          }
    toAttrs v = catMaybes 
        [ toAttrFrStr "baserel" (baserelBaserel v)
        ]


{-Done-}
