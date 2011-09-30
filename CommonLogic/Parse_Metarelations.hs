{- |
Module      :  $Header$
Description :  Analysis and parsing of metarelations between texts
Copyright   :  (c) Eugen Kuksa, Universität Bremen 2011
License     :  GPLv2 or higher

Maintainer  :  eugenk@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

Analysis and parsing of metarelations between texts
-}

{-
  Ref. Common Logic ISO/IEC IS 24707:2007(E)
-}

module CommonLogic.Parse_Metarelations
  ( metarelations
  ) where

import CommonLogic.AS_CommonLogic
import CommonLogic.Lexer_CLIF
import CommonLogic.Lexer_Metarelations
import CommonLogic.Parse_Symbols (symbMapItems)

import qualified Common.AnnoState as AnnoState

import Data.Set (Set)
import qualified Data.Set as Set

import Text.ParserCombinators.Parsec as Parsec

metarelations :: TEXT -> Set METARELATION
metarelations (Text phrs _) = Set.unions $ map mrels_phr phrs
metarelations (Named_text _ t _) = metarelations t

mrels_phr :: PHRASE -> Set METARELATION
mrels_phr (Comment_text (Comment c _) _ _) = mrels c
mrels_phr _ = Set.empty

mrels :: String -> Set METARELATION
mrels s = case runParser parse_mrels (AnnoState.emptyAnnos ()) "" s of
  Right mr -> Set.singleton mr
  Left _ -> Set.empty

parse_mrels :: CharParser st METARELATION
parse_mrels = parens $ do
    relativeInterpretsKey
    t1 <- identifier
    delta <- identifier
    t2 <- identifier
    symbMaps <- parse_mrels_symbMap
    return $ RelativeInterprets t1 delta t2 symbMaps
  <|> do
    nonconservativeExtensionKey
    t1 <- identifier
    t2 <- identifier
    symbMaps <- parse_mrels_symbMap
    return $ NonconservativeExtends t1 t2 symbMaps

parse_mrels_symbMap :: CharParser st [SYMB_MAP_ITEMS]
parse_mrels_symbMap = do
    symbMap <- parens $ symbMapItems
    return [symbMap]
  <|> do
    return []