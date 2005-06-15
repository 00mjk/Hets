{- |
Module      :  $Header$
Copyright   :  (c) Katja Groeblinghoff, C.Maeder, Uni Bremen 2003 - 2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  experimental
Portability :  portable 

Translation of identifiers to Haskell.
-}

module Haskell.TranslateId (IdCase(..), translateIdWithType) where

import Common.Id
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import Data.Char

-- | Converts an identifier to a valid lower or upper case Haskell name
translateIdWithType :: IdCase -> Id -> String
translateIdWithType ty i = 
  let s = translateId i ""
      c = if null s then error "translateIdWithTyper" else head s
  in case ty of 
     UpperId -> 
	 if isLower c || c == '_' || isDigit c
	    then  "A__" ++ s else s  
     LowerId -> 
	 if isUpper c || c == '_' || isDigit c || s `Set.member` lowerCaseList
	    then "a__" ++ s  else s 

-- reserved Haskell keywords
lowerCaseList :: Set.Set String
lowerCaseList = Set.fromList [
		 "case", "class", "data", "default", "deriving", "do", "else",
	         "if", "import", "in", "infix", "infixl", "infixr", "instance",
	         "let", "module", "newtype", "of", "then", "type", "where"]

-- | Letter case indicator
data IdCase = UpperId | LowerId

-- | Converts an identifier to a valid Haskell name
translateId :: Id -> ShowS
translateId (Id tlist idlist _) = 
    showSepList id translateToken tlist . translateCompound idlist

-- | Translate a 'Token' according to the 'symbolMapping'.
translateToken :: Token -> ShowS
translateToken t = let str = tokStr t in showString $
    if isPlace t then "_2"
    else if all isDigit str && not (isSingle str) then '_' : str
    else if head str == '\'' then
         "_3" ++ concatMap (('_' : ) . show . ord) (tail str) ++ "_X"
    else concatMap symbolMapping str

-- | Translate a compound list
translateCompound :: [Id] -> ShowS
--  [      ,      ]
translateCompound ids = noShow (null ids) $ showString "_F"
	     . showSepList (showString "_K") translateId ids
	     . showString "_J"

-- | Converts characters to parts of Haskell identifiers
-- thereby translating special ones
symbolMapping :: Char -> String
symbolMapping c = Map.findWithDefault [c] c $ Map.fromList 
-- avoid compound symbols and keep map injective
-- Special / reserved
   [('_' , "_1"),    -- \95
    ('{' , "_b"),    -- \123
    ('}' , "_r"),    -- \125
    ('[' , "_s"),    -- \91
    (']' , "_q"),    -- \93
    ('.' , "_d"),    -- \46
    ('\'', "_p"),
-- Symbols
    ('+' , "_P"),    -- \43
    ('-' , "_M"),    -- \45
    ('*' , "_T"),    -- \42
    ('/' , "_S"),    -- \47
    ('\\', "_B"),    -- \92
    ('&' , "_A"),    -- \38
    ('=' , "_E"),    -- \61
    ('<' , "_L"),    -- \60
    ('>' , "_G"),    -- \62
    ('!' , "_R"),    -- \33
    ('?' , "_Q"),    -- \63
    (':' , "_C"),    -- \58
    ('$' , "_D"),    -- \36
    ('@' , "_O"),    -- \64
    ('#' , "_H"),    -- \35
    ('^' , "_V"),    -- \94
    ('|' , "_I"),    -- \124
    ('~' , "_N"),    -- \126
    ('�' , "_e"),    -- \161
    ('�' , "_c"),    -- \162   
    ('�' , "_l"),    -- \163
    ('�' , "_f"),    -- \167
    ('�' , "_a"),    -- \169
    ('�' , "_n"),    -- \172
    ('�' , "_h"),    -- \176
    ('�' , "_k"),    -- \177
    ('�' , "_w"),    -- \178
    ('�' , "_t"),    -- \179
    ('�' , "_y"),    -- \181
    ('�' , "_j"),    -- \182
    ('�' , "_i"),    -- \183
    ('�' , "_o"),    -- \185
    ('�' , "_u"),    -- \191
    ('�' , "_m"),    -- \215
    ('�' , "_g")]    -- \247
