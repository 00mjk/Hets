{- |
Module      :  $Header$
Copyright   :  (c) University of Cambridge, Cambridge, England
               adaption (c) Till Mossakowski, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

   Printing functions for Isabelle logic.
-}

module Isabelle.IsaPrint where

import Common.Id 
import Common.PrettyPrint

import Data.Char

showIsa :: Id -> String
showIsa = transString . flip showPretty ""

showIsaSid :: SIMPLE_ID -> String
showIsaSid = transString . flip showPretty ""

-- disambiguation of overloaded ids
showIsaI :: Id -> Int -> String
showIsaI ident i = showIsa ident ++ "__" ++ show i


-- Replacement of special characters

replaceChar :: Char -> String
replaceChar '\t' = "_"
replaceChar '\n' = "_"
replaceChar '\r' = "_"
replaceChar ' ' = "_"
replaceChar '!' = "Exclam"
replaceChar '\"' = "_"
replaceChar '#' = "Sharp"
replaceChar '$' = "Dollar"
replaceChar '%' = "Percent"
replaceChar '&' = "Amp"
replaceChar '(' = "OBra"
replaceChar ')' = "CBra"
replaceChar '*' = "x"
replaceChar '+' = "Plus"
replaceChar ',' = "Comma"
replaceChar '-' = "Minus"
replaceChar '.' = "Dot"
replaceChar '/' = "Div"
replaceChar ':' = "Colon"
replaceChar ';' = "Semi"
replaceChar '<' = "Lt"
replaceChar '=' = "Eq"
replaceChar '>' = "Gt"
replaceChar '?' = "Q"
replaceChar '@' = "At"
replaceChar '[' = "_"
replaceChar '\\' = "Back"
replaceChar ']' = "_"
replaceChar '^' = "Hat"
replaceChar '`' = "'"
replaceChar '{' = "Cur"
replaceChar '|' = "Bar"
replaceChar '}' = "Ruc"
replaceChar '~' = "Tilde"
replaceChar '\128' = "A1"
replaceChar '\129' = "A2"
replaceChar '\130' = "A3"
replaceChar '\131' = "A4"
replaceChar '\132' = "A5"
replaceChar '\133' = "A6"
replaceChar '\134' = "AE"
replaceChar '\135' = "C"
replaceChar '\136' = "E1"
replaceChar '\137' = "E2"
replaceChar '\138' = "E3"
replaceChar '\139' = "E4"
replaceChar '\140' = "I1"
replaceChar '\141' = "I2"
replaceChar '\142' = "I3"
replaceChar '\143' = "I4"
replaceChar '\144' = "D1"
replaceChar '\145' = "N1"
replaceChar '\146' = "O1"
replaceChar '\147' = "O2"
replaceChar '\148' = "O3"
replaceChar '\149' = "O4"
replaceChar '\150' = "O5"
replaceChar '\151' = "x"
replaceChar '\152' = "O"
replaceChar '\153' = "U1"
replaceChar '\154' = "U2"
replaceChar '\155' = "U3"
replaceChar '\156' = "U4"
replaceChar '\157' = "Y"
replaceChar '\158' = "F"
replaceChar '\159' = "ss"
replaceChar '\160' = "_"
replaceChar '�' = "SpanishExclam"
replaceChar '�' = "c"
replaceChar '�' = "Lb"
replaceChar '�' = "o"
replaceChar '�' = "Yen"
replaceChar '�' = "Bar1"
replaceChar '�' = "Paragraph"
replaceChar '�' = "\""
replaceChar '�' = "Copyright"
replaceChar '�' = "a1"
replaceChar '�' = "\""
replaceChar '�' = "not"
replaceChar '�' = "Minus1"
replaceChar '�' = "Regmark"
replaceChar '�' = "_"
replaceChar '�' = "Degree"
replaceChar '�' = "Plusminus"
replaceChar '�' = "2"
replaceChar '�' = "3"
replaceChar '�' = "'"
replaceChar '�' = "Mu"
replaceChar '�' = "q"
replaceChar '�' = "Dot"
replaceChar '�' = "'"
replaceChar '�' = "1"
replaceChar '�' = "2"
replaceChar '�' = "\""
replaceChar '�' = "Quarter"
replaceChar '�' = "Half"
replaceChar '�' = "Threequarter"
replaceChar '�' = "Q"
replaceChar '�' = "A7"
replaceChar '�' = "A8"
replaceChar '�' = "A9"
replaceChar '�' = "A10"
replaceChar '�' = "A11"
replaceChar '�' = "A12"
replaceChar '�' = "AE2"
replaceChar '�' = "C2"
replaceChar '�' = "E5"
replaceChar '�' = "E6"
replaceChar '�' = "E7"
replaceChar '�' = "E8"
replaceChar '�' = "I5"
replaceChar '�' = "I6"
replaceChar '�' = "I7"
replaceChar '�' = "I8"
replaceChar '�' = "D2"
replaceChar '�' = "N2"
replaceChar '�' = "O6"
replaceChar '�' = "O7"
replaceChar '�' = "O8"
replaceChar '�' = "O9"
replaceChar '�' = "O10"
replaceChar '�' = "xx"
replaceChar '�' = "011"
replaceChar '�' = "U5"
replaceChar '�' = "U6"
replaceChar '�' = "U7"
replaceChar '�' = "U8"
replaceChar '�' = "Y"
replaceChar '�' = "F"
replaceChar '�' = "ss"
replaceChar '�' = "a2"
replaceChar '�' = "a3"
replaceChar '�' = "a4"
replaceChar '�' = "a5"
replaceChar '�' = "a6"
replaceChar '�' = "a7"
replaceChar '�' = "ae"
replaceChar '�' = "c"
replaceChar '�' = "e1"
replaceChar '�' = "e2"
replaceChar '�' = "e3"
replaceChar '�' = "e4"
replaceChar '�' = "i1"
replaceChar '�' = "i2"
replaceChar '�' = "i3"
replaceChar '�' = "i4"
replaceChar '�' = "d"
replaceChar '�' = "n"
replaceChar '�' = "o1"
replaceChar '�' = "o2"
replaceChar '�' = "o3"
replaceChar '�' = "o4"
replaceChar '�' = "o5"
replaceChar '�' = "Div1"
replaceChar '�' = "o6"
replaceChar '�' = "u1"
replaceChar '�' = "u2"
replaceChar '�' = "u3"
replaceChar '�' = "u4"
replaceChar '�' = "y5"
replaceChar '�' = "f"
replaceChar '�' = "y"
replaceChar  _ = "_"

isIsaChar :: Char -> Bool
isIsaChar c = (isAlphaNum c && isAscii c) || c `elem` "_'"


replaceChar1 :: Char -> String
replaceChar1 c | isIsaChar c = [c] 
               | otherwise = replaceChar c++"__"

transString :: String -> String
transString "" = "X"
transString (c:s) = 
  (if isAlpha c && isAscii c then [c] else 'X':replaceChar1 c)
   ++ (concat $ map replaceChar1 s)


