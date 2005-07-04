{- |
Module      :  $Header$
Copyright   :  (c) various people and Klaus L�ttich, Uni Bremen 2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  l�ttich@tzi.de
Stability   :  provisional
Portability :  needs POSIX

this module collects functions useful for all prover connections in Hets
some are moved from Isabelle.Translate and some others are moved from
Isabelle.IsaProve.
-}


module Common.ProofUtils where

import Data.Maybe
import Data.List 

import qualified Common.Lib.Map as Map
import Common.AS_Annotation

{- |
prepareSenNames prepares sentence names for the usage within provers.

 * generic names are added

 * disambiguation of duplicate assigned names

 * translation of special characters with the aid of the provided function

-}
prepareSenNames :: (String -> String) -> [Named a] -> [Named a]
prepareSenNames trFun = 
    transSens trFun . disambiguateSens [] . nameSens

-- | translate special characters in sentence names
transSens :: (String -> String) -> [Named a] -> [Named a]
transSens trFun = map (\ax -> ax{senName = trFun (senName ax)}) 

-- | disambiguate sentence names
disambiguateSens :: [Named a] -> [Named a] -> [Named a]
disambiguateSens others axs = reverse $ disambiguateSensAux others axs []

disambiguateSensAux :: [Named a] -> [Named a] -> [Named a] -> [Named a]
disambiguateSensAux _ [] soFar = soFar
disambiguateSensAux others (ax:rest) soFar =
  disambiguateSensAux (ax':others) rest (ax':soFar)
  where
  name' = fromJust $ find (not . flip elem namesSoFar) 
                          (name:[name++show (i :: Int) | i<-[1..]])
  name = senName ax 
  namesSoFar = map senName others
  ax' = ax{senName = name'}

-- | name unlabeled axioms with "Axnnn"
nameSens :: [Named a] -> [Named a]
nameSens sens = 
  map nameSen (zip sens [1..length sens])
  where nameSen (sen,no) = if senName sen == "" 
                              then sen{senName = "Ax"++show no}
                              else sen
 
-- | collect the mapping of new to old names 
collectNameMapping :: [Named a] -> [Named a] -> Map.Map String String
collectNameMapping n o = Map.fromList (zipWith toPair n o) 
    where toPair nSen oSen = (senName nSen, 
                              if null oName 
                                 then "<unnamed>"++senName nSen
                                 else oName)
              where oName = senName oSen

-- | a separate Map speeds up lookup
charMap :: Map.Map Char String
charMap = Map.fromList
 [('!' , "Exclam"),
  ('"' , "Quot"),
  ('#' , "Hash"),
  ('$' , "Dollar"),
  ('%' , "Percent"),
  ('&' , "Amp"),
  ('(' , "OBr"),
  (')' , "CBr"),
  ('*' , "x"), 
  ('+' , "Plus"),
  (',' , "Comma"),
  ('-' , "Minus"),
  ('.' , "Period"), -- Dot?
  ('/' , "Slash"), -- Div?
  (':' , "Colon"),
  (';' , "Semi"),
  ('<' , "Lt"),
  ('=' , "Eq"),
  ('>' , "Gt"),
  ('?' , "Quest"),
  ('@' , "At"),
  ('[' , "OSqBr"),
  ('\\' , "Bslash"),
  (']' , "CSqBr"),        
  ('^' , "Caret"), -- Hat?
  ('`' , "Grave"),
  ('{' , "LBrace"),
  ('|' , "VBar"),
  ('}' , "RBrace"),
  ('~' , "Tilde"),
  ('\160', "nbsp"),
  ('�' , "iexcl"),
  ('�' , "cent"),
  ('�' , "pound"),
  ('�' , "curren"),
  ('�' , "yen"),
  ('�' , "brvbar"),
  ('�' , "sect"),
  ('�' , "uml"),
  ('�' , "copy"),
  ('�' , "ordf"),
  ('�' , "laquo"),
  ('�' , "not"),
  ('�' , "shy"),
  ('�' , "reg"),
  ('\175', "macr"), 
  ('�' , "deg"),
  ('�' , "plusmn"),
  ('�' , "sup2"),
  ('�' , "sup3"),
  ('�' , "acute"),
  ('�' , "micro"),
  ('�' , "para"),
  ('�' , "middot"),
  ('�' , "cedil"),
  ('�' , "sup1"),
  ('�' , "ordm"),
  ('�' , "raquo"),
  ('�' , "quarter"),
  ('�' , "half"),
  ('�' , "frac34"),
  ('�' , "iquest"),
  ('�' , "Agrave"),
  ('�' , "Aacute"),
  ('�' , "Acirc"),
  ('�' , "Atilde"),
  ('�' , "Auml"),
  ('�' , "Aring"),
  ('�' , "AElig"),
  ('�' , "Ccedil"),
  ('�' , "Egrave"),
  ('�' , "Eacute"),
  ('�' , "Ecirc"),
  ('�' , "Euml"),
  ('�' , "Igrave"),
  ('�' , "Iacute"),
  ('�' , "Icirc"),
  ('�' , "Iuml"),
  ('�' , "ETH"),
  ('�' , "Ntilde"),
  ('�' , "Ograve"),
  ('�' , "Oacute"),
  ('�' , "Ocirc"),
  ('�' , "Otilde"),
  ('�' , "Ouml"),
  ('�' , "Times"),
  ('�' , "OSlash"),
  ('�' , "Ugrave"),
  ('�' , "Uacute"),
  ('�' , "Ucirc"),
  ('�' , "Uuml"),
  ('�' , "Yacute"),
  ('�' , "THORN"),
  ('�' , "szlig"),
  ('�' , "agrave"),
  ('�' , "aacute"),
  ('�' , "acirc"),
  ('�' , "atilde"),
  ('�' , "auml"),
  ('�' , "aring"),
  ('�' , "aelig"),
  ('�' , "ccedil"),
  ('�' , "egrave"),
  ('�' , "eacute"),
  ('�' , "ecirc"),
  ('�' , "euml"),
  ('�' , "igrave"),
  ('�' , "iacute"),
  ('�' , "icirc"),
  ('�' , "iuml"),
  ('�' , "eth"),
  ('�' , "ntilde"),
  ('�' , "ograve"),
  ('�' , "oacute"),
  ('�' , "ocirc"),
  ('�' , "otilde"),
  ('�' , "ouml"),
  ('�' , "Divide"),
  ('�' , "oslash"),
  ('�' , "ugrave"),
  ('�' , "uacute"),
  ('�' , "ucirc"),
  ('�' , "uuml"),
  ('�' , "yacute"),
  ('�' , "thorn"),
  ('�' , "yuml")]
