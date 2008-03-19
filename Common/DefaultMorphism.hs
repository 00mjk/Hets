{- |
Module      :  $Header$
Description :  supply a default morphism for a given signature type
Copyright   :  (c) C. Maeder, and Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

Supply a default morphism for a given signature type
-}

-- due to functional deps the instance for Logic.Category cannot be supplied

module Common.DefaultMorphism
  ( DefaultMorphism(..) -- constructor is only exported for ATC
  , ideOfDefaultMorphism
  , compOfDefaultMorphism
  , legalDefaultMorphism
  , mkDefaultMorphism
  , defaultInclusion
  ) where

import Common.Keywords
import Common.Doc
import Common.DocUtils

data DefaultMorphism sign = MkMorphism
  { domOfDefaultMorphism :: sign
  , codOfDefaultMorphism :: sign
  , isInclusionDefaultMorphism :: Bool
  } deriving (Show, Eq)

instance Pretty a => Pretty (DefaultMorphism a) where
    pretty = printDefaultMorphism pretty

printDefaultMorphism :: (a -> Doc) -> DefaultMorphism a -> Doc
printDefaultMorphism fA (MkMorphism s t b) =
    (if b then text "inclusion" else empty) $+$
    specBraces (fA s) $+$ text mapsTo <+> specBraces (fA t)

ideOfDefaultMorphism :: sign -> DefaultMorphism sign
ideOfDefaultMorphism s = MkMorphism s s True

compOfDefaultMorphism :: (Monad m, Eq sign) => DefaultMorphism sign
                      -> DefaultMorphism sign -> m (DefaultMorphism sign)
compOfDefaultMorphism (MkMorphism s1 s b1) (MkMorphism s2 s3 b2) =
    if s == s2 then return $ MkMorphism s1 s3 $ min b1 b2 else
    fail "intermediate signatures are different"

legalDefaultMorphism :: (sign -> Bool) -> DefaultMorphism sign -> Bool
legalDefaultMorphism legalSign (MkMorphism s t _) =
    legalSign s && legalSign t

mkDefaultMorphism :: sign -> sign -> DefaultMorphism sign
mkDefaultMorphism s1 s2 = MkMorphism s1 s2 False

defaultInclusion :: (Monad m) => (sign -> sign -> Bool) -> sign -> sign
                 -> m (DefaultMorphism sign)
defaultInclusion isSubSig s1 s2 =
    if isSubSig s1 s2 then return $ MkMorphism s1 s2 True else
    fail "non subsignatures for inclusion"
