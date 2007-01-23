{- |
Module      :  $Header$
Copyright   :  (c) C. Maeder and Uni Bremen 2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

parse Isabelle theory files
-}

module Main where

import System.Environment
import Text.ParserCombinators.Parsec
import Isabelle.IsaParse
import Isabelle.IsaConsts
import qualified Common.Lib.Map as Map
import Common.Doc as Doc
import Common.DocUtils

main :: IO ()
main = getArgs >>= mapM_ process

process :: String -> IO ()
process f = do
  s <- readFile f
  putStrLn $ case parse parseTheory f s of
             Right (_, b) -> show $ printBody b
             Left err -> show err

printBody :: Body -> Doc
printBody f = let
    axs = axiomsF f
    gls = goalsF f
    cns = constsF f
    dts = datatypesF f
    col a b = a <+> colon <+> b
    dcol a b = a <+> text "::" <+> b
    in (if Map.null axs then empty else keyword axiomsS)
       $+$ 
       printMap id vcat col axs
       $+$
       (if Map.null gls then empty else keyword lemmaS)
       $+$
       ppMap pretty (sep . prepPunctuate (text andS <> Doc.space) 
                             . map pretty . simpValue)
             id vcat col gls
       $+$
       (if Map.null cns then empty else keyword constsS)
       $+$
       printMap id vcat dcol cns
       $+$
       (if Map.null dts then empty else keyword datatypeS)
       $+$
       printMap id vcat dcol dts
