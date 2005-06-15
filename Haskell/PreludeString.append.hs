{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  experimental
Portability :  portable 

provide the programatica prelude as a string

-}

module Haskell.PreludeString (preludeDecls) where

import Haskell.HatParser

preludeDecls :: [HsDecl]
preludeDecls = let ts = pLexerPass0 lexerflags0 preludeString
   in case parseTokens parse "Haskell/ProgramaticaPrelude.hs" ts of
      Just (HsModule _ _ _ _ ds) -> ds
      _ -> error "preludeDecls"

preludeString :: String
preludeString = 
{- append Haskell/ProgramaticaPrelude.hs by
   utils/appendHaskellPreludeString -}
