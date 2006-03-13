{- |
Module      :  $Header$
Copyright   :  (c) T.Mossakowski, C.Maeder and Uni Bremen 2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

converting (ie. kif) strings to CASL identifiers
-}

module Common.ToId where

import Common.Id
import Common.ProofUtils
import Common.Token
import Common.Lexer
import qualified Common.Lib.Map as Map 
import Text.ParserCombinators.Parsec

-- | convert a string to a legal CASL identifier
toId :: String -> Id
toId s = simpleIdToId $ mkSimpleId $ 
    case parse (reserved casl_reserved_words scanAnyWords) "Common.ToId" s of
    Left _ -> if null s then error "Common.ToId" else 
              '.' : tail (concatMap ( \ c -> '_' : Map.findWithDefault [c] c 
                              (Map.insert '_' "U" charMap)) s) 
    Right _ -> s
