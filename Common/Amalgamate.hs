{- | 
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Uni Bremen 2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

data types for amalgamability options and analysis

-}

module Common.Amalgamate where

import Data.List

{- | 'CASLAmalgOpt' describes the options for CASL amalgamability analysis 
     algorithms -}

data CASLAmalgOpt = Sharing         -- ^ perform the sharing checks
    | ColimitThinness -- ^ perform colimit thinness check (implies Sharing)
    | Cell            -- ^ perform cell condition check (implies Sharing)
    | NoAnalysis      -- ^ dummy option to indicate empty option string

-- | Amalgamability analysis might be undecidable, so we need
-- a special type for the result of ensures_amalgamability
data Amalgamates = Amalgamates
                 | NoAmalgamation String       -- ^ failure description
                 | DontKnow String           -- ^ the reason for unknown status
-- | The default value for 'DontKnow' amalgamability result
defaultDontKnow :: Amalgamates
defaultDontKnow = DontKnow "Unable to assert that amalgamability is ensured"

instance Show CASLAmalgOpt where
    show o = case o of 
             Sharing -> "sharing"
             ColimitThinness -> "colimit-thinness"
             Cell -> "cell"
             NoAnalysis -> "none"

instance Read CASLAmalgOpt where
    readsPrec _ = readShow caslAmalgOpts

-- | input all possible values and read one as it is shown
readShow :: Show a => [a] -> ReadS a
readShow l s = case find ( \ o -> isPrefixOf (show o) s) l of
               Nothing -> []
               Just t -> [(t, drop (length $ show t) s)]
             
-- | possible CASL amalgamability options
caslAmalgOpts :: [CASLAmalgOpt]
caslAmalgOpts = [NoAnalysis, Sharing, Cell, ColimitThinness]

