{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski and Uni Bremen 2003-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  hausmann@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

The embedding comorphism from CoCASL to Isabelle-HOL.
-}

module Comorphisms.CoCFOL2IsabelleHOL (CoCFOL2IsabelleHOL(..)) where

import Logic.Logic as Logic
import Logic.Comorphism
-- CoCASL
import CoCASL.Logic_CoCASL
import CoCASL.CoCASLSign
import CoCASL.AS_CoCASL
import CoCASL.StatAna
import CoCASL.Sublogic
import CASL.Sublogic
import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.Morphism
import Comorphisms.CFOL2IsabelleHOL

-- Isabelle
import Isabelle.IsaSign as IsaSign
import Isabelle.IsaConsts
import Isabelle.Logic_Isabelle

import Debug.Trace
import Data.List (findIndex)
import Data.Char (ord, chr)


-- | The identity of the comorphism
data CoCFOL2IsabelleHOL = CoCFOL2IsabelleHOL deriving (Show)

instance Language CoCFOL2IsabelleHOL -- default definition is okay

instance Comorphism CoCFOL2IsabelleHOL
               CoCASL CoCASL_Sublogics
               C_BASIC_SPEC CoCASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CSign
               CoCASLMor
               Symbol RawSymbol ()
               Isabelle () () IsaSign.Sentence () ()
               IsaSign.Sign
               IsabelleMorphism () () ()  where
    sourceLogic CoCFOL2IsabelleHOL = CoCASL
    sourceSublogic CoCFOL2IsabelleHOL =
      CASL_SL
          { ext_features = True,
            sub_features = NoSub,
            has_part = False,
            cons_features = SortGen { emptyMapping = False,
                                      onlyInjConstrs = False},
            has_eq = True,
            has_pred = True,
            which_logic = FOL
          }
    targetLogic CoCFOL2IsabelleHOL = Isabelle
    mapSublogic cid sl = if sl `isSubElem` sourceSublogic cid
                       then Just () else Nothing
    map_theory CoCFOL2IsabelleHOL = transTheory sigTrCoCASL formTrCoCASL
    map_morphism = mapDefaultMorphism
    map_sentence CoCFOL2IsabelleHOL sign =
      return . mapSen formTrCoCASL sign
    has_model_expansion CoCFOL2IsabelleHOL = True
    is_weakly_amalgamable CoCFOL2IsabelleHOL = True

xvar :: Int -> String
xvar i = if i<=26 then [chr (i+ord('a'))] else "x"++show i

rvar :: Int -> String
rvar i = if i<=9 then [chr (i+ord('R'))] else "R"++show i

-- | extended signature translation for CoCASL
sigTrCoCASL :: SignTranslator C_FORMULA CoCASLSign
sigTrCoCASL _ _ = id

conjs :: [Term] -> Term
conjs l = if null l then true else foldr1 binConj l

-- | extended formula translation for CoCASL
formTrCoCASL :: FormulaTranslator C_FORMULA CoCASLSign
formTrCoCASL sign (CoSort_gen_ax sorts ops _) =
  foldr (quantifyIsa "All") phi (predDecls++[("u",ts),("v",ts)])
  where
  ts = transSort $ head sorts
  -- phi expresses: all bisimulations are the equality
  phi = prems `binImpl` concls
  -- indices and predicates for all involved sorts
  indices = [0..length sorts - 1]
  predDecls = zip [rvar i | i<-indices] (map binPred sorts)
  binPred s = let s' = transSort s in mkCurryFunType [s',s'] boolType
  -- premises: all relations are bisimulations
  prems = conjs (map prem (zip sorts indices))
  {- generate premise for s, where s is the i-th sort
     for all x,y of that sort,
      if all sel_j(x) R_j sel_j(y), where sel_j ranges over the selectors for s
      then x R y
     here, R_i is the relation for the result type of sel_j, or the equality
  -}
  prem (s,i) =
    let -- get all selectors with first argument sort s
        sels = filter isSelForS ops
        isSelForS (Qual_op_name _ t _) = case args_OP_TYPE t of
           (s1:_) -> s1 == s
           _ -> False
        isSelForS _ = False
        premSel opsymb@(Qual_op_name _n t _) =
         let -- get extra parameters of the selectors
             args = tail $ args_OP_TYPE t
             indicesArgs = [1..length args]
             res = res_OP_TYPE t
             -- variables for the extra parameters
             varDecls = zip [xvar j | j <- indicesArgs] (map transSort args)
             -- the selector ...
             topC = con (transOP_SYMB sign opsymb)
             -- applied to x and extra parameter vars
             appFold = foldl ( \ t1 t2 -> App t1 t2 NotCont)
             rhs = appFold (App topC (var "x") NotCont)
                       (map (var . xvar) indicesArgs)
             -- applied to y and extra parameter vars
             lhs = appFold (App topC (var "y") NotCont)
                             (map (var . xvar) indicesArgs)
             chi = -- is the result of selector non-observable?
                   if res `elem` sorts
                     -- then apply corresponding relation
                     then App (App (var $
                          rvar $ maybe (error "CoCASL2Isabelle.premSel.chi") id
                               $ findIndex (==res) sorts)
                               rhs NotCont) lhs NotCont
                     -- else use equality
                     else binEq rhs lhs
          in foldr (quantifyIsa "All") chi varDecls
        premSel _ = error "CoCASL2Isabelle.premSel"
        prem1 = conjs (map premSel sels)
        concl1 = App (App (var $ rvar i) (var "x") NotCont) (var "y") NotCont
        psi = concl1 `binImpl` prem1
        typS = transSort s
     in foldr (quantifyIsa "All") psi [("x",typS),("y",typS)]
  -- conclusion: all relations are the equality
  concls = conjs (map concl (zip sorts indices))
  concl (_,i) = binImpl (App (App (var $ rvar i) (var "u") NotCont)
                     (var "v") NotCont)
                             (binEq (var "u") (var "v"))
formTrCoCASL _sign (BoxOrDiamond _ _mod _phi _) =
   trace "WARNING: ignoring modal forumla"
          $ true
