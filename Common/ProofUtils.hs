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
import qualified Common.Lib.Set as Set
import Common.AS_Annotation

{- |
prepareSenNames prepares sentence names for the usage within provers.

 * generic names are added

 * disambiguation of duplicate assigned names

 * translation of special characters with the aid of the provided function

Warning: all sentence names are disambiguated by adding a natural number.
If that does not work for a certain reasoner you can hand in a function
which uses a different alghorithm.
-}
prepareSenNames :: (String -> String) -> [Named a] -> [Named a]
prepareSenNames trFun = 
    disambiguateSens Set.empty . transSens trFun . nameSens

-- | translate special characters in sentence names
transSens :: (String -> String) -> [Named a] -> [Named a]
transSens trFun = map (\ax -> ax{senName = trFun (senName ax)}) 

-- | disambiguate sentence names
disambiguateSens :: Set.Set String -> [Named a] -> [Named a]
disambiguateSens _ [] = []
disambiguateSens nameSet (ax : rest) = 
  let name = senName ax in case Set.splitMember name nameSet of
  (_, False, _) -> ax : disambiguateSens (Set.insert name nameSet) rest
  (_, _, greater) -> let 
      name' = fromJust $ find (not . flip Set.member greater) 
                          [name++show (i :: Int) | i<-[1..]]
      ax' = ax {senName = name'}
      in ax' : disambiguateSens (Set.insert name' nameSet) rest

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
