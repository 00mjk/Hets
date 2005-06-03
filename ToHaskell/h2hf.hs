{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  experimental
Portability :  portable 
   
test translation
-}

module Main where

import System.Environment

import Text.ParserCombinators.Parsec
import Common.Result
import Common.AnnoState
import Common.AS_Annotation
import Common.GlobalAnnotations
-- import Common.PrettyPrint
import Common.Lib.Pretty

-- import Comorphisms.HasCASL2Haskell
import Comorphisms.Hs2HOLCF

import Isabelle.CreateThy
import Isabelle.IsaSign as IsaSign

import Haskell.HatAna as HatAna
import Haskell.HatParser

-- import HasCASL.Le
-- import HasCASL.AsToLe
-- import HasCASL.ParseItem(basicSpec)
-- import HasCASL.ProgEq

hParser :: AParser () (IsaSign.Sign, [Named IsaSign.Sentence])
hParser = do 
   b <- hatParser
   let res@(Result _ m) = do 
          (_, _, sig, sens) <- hatAna (b, HatAna.emptySign, emptyGlobalAnnos)
--          sens <- return [x | Named _ True x <- nsens]
          transTheory sig sens
   case m of 
      Nothing -> error $ show res
      Just x -> return x

main :: IO ()
main = do l <- getArgs
	  if length l >= 1 then
	     do s <- readFile $ head l
		let r = runParser hParser (emptyAnnos ()) (head l) s 
	        case r of 
		       Right (sig, hs) -> let 
                         tn = (takeWhile (/= '.') $ reverse (takeWhile (\x -> x /= '/' && x /= '"') $ reverse $ show $ head l))
                            ++ "_theory" 
                         doc = text "theory" <+> text tn <+> text "=" $$
                            createTheoryText sig hs
                         in writeFile (tn ++ ".thy") (shows doc "\n")
		       Left err -> putStrLn $ show err
	   else putStrLn "missing argument"
--       _ -> return ()

