{- |
Module      :  $Header$
Description :  replace casts with explicit projection functions
Copyright   :  (c) Christian Maeder, Uni Bremen 2005-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

Replace casts with explicit projection functions


This module replaces Cast(s) with explicit projection
   functions.  Don't do this after simplification since crucial sort
   information may be missing

   Membership test are replaced with Definedness formulas

   projection names may be also made unique by appending the source
   and target sort
-}

module CASL.Project where

import CASL.AS_Basic_CASL
import CASL.Fold
import CASL.Inject
import Common.Id

projRecord :: FunKind -> (f -> f) -> Record f (FORMULA f) (TERM f)
projRecord fk mf = (mapRecord mf)
  { foldCast = \ _ st s ps -> projectUnique fk ps st s
  , foldMembership = \ _ t s ps -> Definedness (projectUnique fk ps t s) ps }

projTerm :: FunKind -> (f -> f) -> TERM f -> TERM f
projTerm fk = foldTerm . projRecord fk

projFormula :: FunKind -> (f -> f) -> FORMULA f -> FORMULA f
projFormula fk = foldFormula . projRecord fk

uniqueProjName :: OP_TYPE -> Id
uniqueProjName t = case t of
    Op_type _ [from] to _ -> mkUniqueProjName from to
    _ -> error "CASL.Project.uniqueProjName"

botTok :: Token
botTok = genToken "bottom"

bottom :: Id
bottom = mkId [botTok]

uniqueBotName :: OP_TYPE -> Id
uniqueBotName t = case t of
    Op_type _ [] to _ -> mkUniqueName botTok [to]
    _ -> error "CASL.Project.uniqueBotName"

projectUnique :: FunKind -> Range -> TERM f -> SORT -> TERM f
projectUnique = makeInjOrProj uniqueProjName

rename :: OP_SYMB -> OP_SYMB
rename o = case o of
    Qual_op_name i t r -> Qual_op_name
        (if i == injName then uniqueInjName t
         else if i == projName then uniqueProjName t
         else if i == bottom then uniqueBotName t
              else i) t r
    _ -> o

renameRecord :: (f -> f) -> Record f (FORMULA f) (TERM f)
renameRecord mf = (mapRecord mf)
     { foldApplication = \ _ o args r -> Application (rename o) args r }

renameTerm :: (f -> f) -> TERM f -> TERM f
renameTerm = foldTerm . renameRecord

renameFormula :: (f -> f) -> FORMULA f -> FORMULA f
renameFormula = foldFormula . renameRecord
