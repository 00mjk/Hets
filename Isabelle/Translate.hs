{- |
Module      :  $Header$
Copyright   :  (c) University of Cambridge, Cambridge, England
               adaption (c) Till Mossakowski, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

   translate 'Id' to Isabelle strings
-}

module Isabelle.Translate (showIsa, showIsaSid, showIsaI, transString) where

import Common.Id 
import qualified Common.Lib.Map as Map
import Data.Char

------------------- Id translation functions -------------------

showIsa :: Id -> String
showIsa = transString . show

showIsaSid :: SIMPLE_ID -> String
showIsaSid = transString . show

showIsaI :: Id -> Int -> String
showIsaI ident i = showIsa ident ++ "_" ++ show i

isIsaChar :: Char -> Bool
isIsaChar c = (isAlphaNum c && isAscii c) || c `elem` "_'"

replaceChar1 :: Char -> String
replaceChar1 c | isIsaChar c = [c] 
               | otherwise = replaceChar c++"__"

transString :: String -> String
transString "" = "X"
transString (c:s) = 
   if isInf (c:s) then concat $ map replaceChar1 (cut (c:s))
     else ((if isAlpha c && isAscii c then [c] 
              else 'X':replaceChar1 c) ++ (concat $ map replaceChar1 s))

isInf :: String -> Bool
isInf s = has2Under s && has2Under (reverse s)

has2Under :: String -> Bool
has2Under (fs:sn:_) = fs == '_' && sn == '_'
has2Under _ = False

cut :: String -> String
cut = reverse . tail . tail . reverse . tail . tail

-- Replacement of special characters

replaceChar :: Char -> String
replaceChar c = Map.findWithDefault "_" c $ Map.fromList 
 [('!' , "Exclam"),
  ('#' , "Sharp"),
  ('$' , "Dollar"),
  ('%' , "Percent"),
  ('&' , "Amp"),
  ('(' , "OBra"),
  (')' , "CBra"),
  ('*' , "x"),
  ('+' , "Plus"),
  (',' , "Comma"),
  ('-' , "Minus"),
  ('.' , "Dot"),
  ('/' , "Div"),
  (':' , "Colon"),
  (';' , "Semi"),
  ('<' , "Lt"),
  ('=' , "Eq"),
  ('>' , "Gt"),
  ('?' , "Q"),
  ('@' , "At"),
  ('\\' , "Back"),
  ('^' , "Hat"),
  ('`' , "'"),
  ('{' , "Cur"),
  ('|' , "Bar"),
  ('}' , "Ruc"),
  ('~' , "Tilde"),
  ('\128' , "A1"),
  ('\129' , "A2"),
  ('\130' , "A3"),
  ('\131' , "A4"),
  ('\132' , "A5"),
  ('\133' , "A6"),
  ('\134' , "AE"),
  ('\135' , "C"),
  ('\136' , "E1"),
  ('\137' , "E2"),
  ('\138' , "E3"),
  ('\139' , "E4"),
  ('\140' , "I1"),
  ('\141' , "I2"),
  ('\142' , "I3"),
  ('\143' , "I4"),
  ('\144' , "D1"),
  ('\145' , "N1"),
  ('\146' , "O1"),
  ('\147' , "O2"),
  ('\148' , "O3"),
  ('\149' , "O4"),
  ('\150' , "O5"),
  ('\151' , "x"),
  ('\152' , "O"),
  ('\153' , "U1"),
  ('\154' , "U2"),
  ('\155' , "U3"),
  ('\156' , "U4"),
  ('\157' , "Y"),
  ('\158' , "F"),
  ('\159' , "ss"),
  ('�' , "SpanishExclam"),
  ('�' , "c"),
  ('�' , "Lb"),
  ('�' , "o"),
  ('�' , "Yen"),
  ('�' , "Bar1"),
  ('�' , "Paragraph"),
  ('�' , "\"),"),
  ('�' , "Copyright"),
  ('�' , "a1"),
  ('�' , "\"),"),
  ('�' , "not"),
  ('�' , "Minus1"),
  ('�' , "Regmark"),
  ('�' , "Degree"),
  ('�' , "Plusminus"),
  ('�' , "2"),
  ('�' , "3"),
  ('�' , "'"),
  ('�' , "Mu"),
  ('�' , "q"),
  ('�' , "Dot"),
  ('�' , "'"),
  ('�' , "1"),
  ('�' , "2"),
  ('�' , "\"),"),
  ('�' , "Quarter"),
  ('�' , "Half"),
  ('�' , "Threequarter"),
  ('�' , "Q"),
  ('�' , "A7"),
  ('�' , "A8"),
  ('�' , "A9"),
  ('�' , "A10"),
  ('�' , "A11"),
  ('�' , "A12"),
  ('�' , "AE2"),
  ('�' , "C2"),
  ('�' , "E5"),
  ('�' , "E6"),
  ('�' , "E7"),
  ('�' , "E8"),
  ('�' , "I5"),
  ('�' , "I6"),
  ('�' , "I7"),
  ('�' , "I8"),
  ('�' , "D2"),
  ('�' , "N2"),
  ('�' , "O6"),
  ('�' , "O7"),
  ('�' , "O8"),
  ('�' , "O9"),
  ('�' , "O10"),
  ('�' , "xx"),
  ('�' , "011"),
  ('�' , "U5"),
  ('�' , "U6"),
  ('�' , "U7"),
  ('�' , "U8"),
  ('�' , "Y"),
  ('�' , "F"),
  ('�' , "ss"),
  ('�' , "a2"),
  ('�' , "a3"),
  ('�' , "a4"),
  ('�' , "a5"),
  ('�' , "a6"),
  ('�' , "a7"),
  ('�' , "ae"),
  ('�' , "c"),
  ('�' , "e1"),
  ('�' , "e2"),
  ('�' , "e3"),
  ('�' , "e4"),
  ('�' , "i1"),
  ('�' , "i2"),
  ('�' , "i3"),
  ('�' , "i4"),
  ('�' , "d"),
  ('�' , "n"),
  ('�' , "o1"),
  ('�' , "o2"),
  ('�' , "o3"),
  ('�' , "o4"),
  ('�' , "o5"),
  ('�' , "Div1"),
  ('�' , "o6"),
  ('�' , "u1"),
  ('�' , "u2"),
  ('�' , "u3"),
  ('�' , "u4"),
  ('�' , "y5"),
  ('�' , "f"),
  ('�' , "y")]
