{- |
Module      :  $Header$
Copyright   :  Christian Maeder and Uni Bremen 2004 
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  experimental
Portability :  portable

generically converting literals 
-}

module Common.ConvertLiteral 
    (convertMixfixToken
    , isGenLiteral
    , isGenNumber
    , isGenSignedNumber
    , isGenString
    , isGenList
    , isGenFloat
    , isGenFrac
    ) where

import Common.Id
import Common.Lexer
import Common.GlobalAnnotations
import Common.Result
import Data.Char (isDigit)

-- * convert a literal to a term 

type AsAppl a = Id -> [a] -> Range -> a

inc :: Int -> Range -> Range
inc n (Range p) = 
  Range (map (flip incSourceColumn n) p)

makeStringTerm :: Id -> Id -> AsAppl a -> Token -> a
makeStringTerm c f asAppl tok = 
  makeStrTerm (inc 1 sp) str
  where 
  sp = tokPos tok
  str = init (tail (tokStr tok))
  makeStrTerm p l = 
    if null l then asAppl c [] p
    else let (hd, tl) = splitString caslChar l
         in asAppl f [asAppl (Id [Token ("'" ++ hd ++ "'") p]
                              [] nullRange) [] p, 
                      makeStrTerm (inc (length hd) p) tl] p

makeNumberTerm :: Id -> AsAppl a -> Token -> a
makeNumberTerm f asAppl t@(Token n p) =
    case n of
           [] -> error "makeNumberTerm"
           [_] -> asAppl (Id [t] [] nullRange) [] p
           hd:tl -> asAppl f [asAppl (Id [Token [hd] p] [] nullRange) [] p, 
                              makeNumberTerm f asAppl (Token tl 
                                                $ inc 1 p)] p

makeFraction :: Id -> Id -> AsAppl a -> Token -> a
makeFraction f d asAppl t@(Token s p) = 
    let (n, r) = span (\c -> c /= '.') s
        dotOffset = length n 
    in if null r then makeNumberTerm f asAppl t
       else asAppl d [makeNumberTerm f asAppl (Token n p),
                      makeNumberTerm f asAppl $ Token (tail r) 
                                      $ inc (dotOffset + 1) p]
            $ inc dotOffset p 

makeSignedNumber :: Id -> AsAppl a -> Token -> a
makeSignedNumber f asAppl t@(Token n p) = 
  case n of 
  [] -> error "makeSignedNumber"
  hd:tl ->   
    if hd == '-' || hd == '+' then
       asAppl (Id [Token [hd] p] [] nullRange) 
                  [makeNumberTerm f asAppl $ Token tl 
                                         $ inc 1 p] p
    else makeNumberTerm f asAppl t

makeFloatTerm :: Id -> Id -> Id -> AsAppl a -> Token -> a
makeFloatTerm f d e asAppl t@(Token s p) = 
    let (m, r) = span (\c -> c /= 'E') s
        offset = length m
    in if null r then makeFraction f d asAppl t
       else asAppl e [makeFraction f d asAppl (Token m p),
                      makeSignedNumber f asAppl $ Token (tail r)
                                          $ inc (offset + 1) p]
                $ inc offset p

-- | convert a literal token to an application term 
convertMixfixToken ::  LiteralAnnos -> AsAppl a 
                  -> (Token -> a) -> Token -> ([Diagnosis], a) 
convertMixfixToken ga asAppl toTerm t = 
     if isString t then 
        case string_lit ga of
        Nothing -> err "string"
        Just (c, f) -> ([], makeStringTerm c f asAppl t)
     else if isNumber t then
          case number_lit ga of
          Nothing -> err "number"
          Just f -> if isFloating t then
                        case float_lit ga of
                        Nothing -> err "floating"
                        Just (d, e) -> ([], makeFloatTerm f d e asAppl t)
                    else ([], makeNumberTerm f asAppl t)
     else ([], te)
    where te =  toTerm t
          err s = ([Diag Error ("missing %" ++ s ++ " annotation") (tokPos t)]
                  , te)

-- * test if term is a literal

type Split a = a -> Maybe (Id, [a])

isGenLiteral :: Split a -> GlobalAnnos -> Id -> [a] -> Bool
isGenLiteral splt ga i trm =
       or [ isGenNumber splt ga i trm 
          , isGenString splt ga i trm
          , isGenList   splt ga i trm
          , isGenFloat  splt ga i trm
          , isGenFrac   splt ga i trm
          ]

isGenNumber :: Split a -> GlobalAnnos -> Id -> [a] -> Bool
isGenNumber splt ga i trs = 
    (digitTest i && null trs) 
    || (getLiteralType ga i == Number && all (sameId splt digitTest i) trs)
    where digitTest ii = 
              (getLiteralType ga ii == Number) || case ii of
                         Id [t] [] _ 
                             | not $ null tstr -> isDigit $ head $ tstr 
                             | otherwise    -> False
                             where tstr = tokStr t
                         _           -> False

isGenSignedNumber :: Split a -> GlobalAnnos -> Id -> [a] -> Bool
isGenSignedNumber splt ga i trs = 
    case trs of 
    [hd] -> case splt hd of 
            Just (ni, nt) -> isSign i && isGenNumber splt ga ni nt
            Nothing -> False
    _ -> False

isSign :: Id -> Bool
isSign i = case i of
           Id [tok] [] _ -> let ts = tokStr tok 
                            in ts == "-" || ts == "+" 
           _             -> False

isGenString :: Split a -> GlobalAnnos -> Id -> [a] -> Bool
isGenString splt ga i trs = case getLiteralType ga i of 
                    StringNull -> null trs
                    StringCons _ -> all (sameId splt stringTest i) trs
                    _ -> False
    where 
          stringTest ii = case getLiteralType ga ii of 
                          StringNull -> True 
                          _ -> case ii of
                               Id [t] [] _ -> take 1 (tokStr t) == "\'"
                               _           -> False

isGenList :: Split a -> GlobalAnnos -> Id -> [a] -> Bool
isGenList splt ga i trms =
                   (case getLiteralType ga i of 
                     ListNull _ -> null trms
                     ListCons _ n -> listTest n i trms
                     _ -> False)
    where listTest n1 i1 terms = case getLiteralType ga i1 of 
              ListNull _ -> n1 == i1 && null terms
              ListCons _ n2 -> n1 == n2 && case terms of 
                               [_, hd] -> case splt hd of 
                                    Just (i2, ts) -> listTest n1 i2 ts
                                    Nothing -> False
                               _ -> False
              _ -> False

isGenFloat :: Split a -> GlobalAnnos -> Id -> [a] -> Bool
isGenFloat splt ga i [l, r] =
    case getLiteralType ga i of 
    Floating -> case (splt l, splt r) of 
        (Just (li, ltrm), Just (ri, rtrm)) -> 
            (isGenNumber splt ga li ltrm || isGenFrac splt ga li ltrm) && 
            (isGenSignedNumber splt ga ri rtrm || isGenNumber splt ga ri rtrm)
        _ -> False
    _ -> False
isGenFloat _ _ _ _ = False

isGenFrac :: Split a -> GlobalAnnos -> Id -> [a] -> Bool
isGenFrac splt ga i [l, r] = 
    case getLiteralType ga i of 
    Fraction -> case (splt l, splt r) of 
       (Just (li, ltrm), Just (ri, rtrm)) -> 
                   isGenNumber splt ga li ltrm && isGenNumber splt ga ri rtrm
       _ -> False
    _ -> False
isGenFrac _ _ _ _ = False

sameId :: Split a -> (Id -> Bool) -> Id -> a -> Bool
sameId splt test i t = case splt t of
    Just (j, ts) -> if null ts then test j 
                    else j == i && all (sameId splt test i) ts
    _ -> False
