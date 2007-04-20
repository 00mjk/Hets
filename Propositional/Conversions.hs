{- |
Module      :  $Header$
Description :  Instance of class Logic for propositional logic
Copyright   :  (c) Dominik Luecke, Uni Bremen 2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@tzi.de
Stability   :  experimental
Portability :  portable 

Helper functions for printing of Theories in DIMACS-CNF Format
-}

module Propositional.Conversions
    (
     showDIMACSProblem
    ,ioDIMACSProblem
    ,goalDIMACSProblem
    )
    where

import qualified Propositional.AS_BASIC_Propositional as AS
import qualified Common.AS_Annotation as AS_Anno
import qualified Propositional.Prop2CNF as P2C
import qualified Propositional.Sign as Sig
import qualified Common.Id as Id
import qualified Common.Result as Res
import qualified Propositional.Tools as PT
import qualified Data.Set as Set
import qualified Data.Map as Map
import qualified Propositional.ProverState as PState

-- | make a DIMACS Problem for SAT-Solvers
goalDIMACSProblem :: String                   -- name of the theory
                  -> PState.PropProverState   -- initial Prover state
                  -> AS_Anno.Named AS.FORMULA -- goal to prove
                  -> [String]                 -- Options (ignored)
                  -> IO String
goalDIMACSProblem thName pState conjec _ = 
    let
        sign = PState.initialSignature pState
        axs  = PState.initialAxioms    pState
    in
      ioDIMACSProblem thName sign axs [conjec]

-- | IO output of DIMACS Problem
ioDIMACSProblem :: String                     -- name of the theory
                -> Sig.Sign                   -- Signature
                -> [AS_Anno.Named AS.FORMULA] -- Axioms
                -> [AS_Anno.Named AS.FORMULA] -- Conjectures
                -> IO String                  -- Output
ioDIMACSProblem name sig axs cons = return $ showDIMACSProblem name sig axs cons

-- | Translation of a Propositional Formula to a String in DIMACS Format
showDIMACSProblem :: String                     -- name of the theory
                  -> Sig.Sign                   -- Signature
                  -> [AS_Anno.Named AS.FORMULA] -- Axioms
                  -> [AS_Anno.Named AS.FORMULA] -- Conjectures
                  -> String                     -- Output
showDIMACSProblem name sig axs cons =
    let 
        nakedCons   = map (AS_Anno.sentence) cons
        negatedCons = (\ncons ->
                           case ncons of
                             [] -> []
                             _  -> 
                               [(AS_Anno.makeNamed "myCons" $ 
                                        AS.Negation 
                                              (
                                               AS.Conjunction 
                                                 ncons
                                                 Id.nullRange
                                              )
                                        Id.nullRange)
                                {
                                  AS_Anno.isAxiom = True
                                , AS_Anno.isDef   = False
                                , AS_Anno.wasTheorem = False
                                }
                               ]
                      ) nakedCons
        transAx     = P2C.translateToCNF (sig, axs)
        transCon    = P2C.translateToCNF (sig, negatedCons)
        resAx       = Res.diags transAx
        resCon      = Res.diags transCon
        errors      = Res.hasErrors resAx || Res.hasErrors resCon
    in
      case errors of
        True  -> "Translation failed... sorry"
        False -> 
            let
                (tSig,tAxs)  = unwrapMaybe $ Res.maybeResult transAx
                (tpSig,tCon) = unwrapMaybe $ Res.maybeResult transCon
                fSig         = Sig.unite tSig tpSig
                tfAxs        = concat $ map PT.flatten $ 
                               map AS_Anno.sentence tAxs
                tfCon        = concat $ map PT.flatten $ 
                               map AS_Anno.sentence tCon
                numVars      = Set.size $ Sig.items fSig
                numClauses   = length tfAxs + length tfCon
                sigMap       = createSignMap fSig 1 Map.empty
            in
              "c " ++ name ++ "\n" ++ 
              "p cnf " ++ show numVars ++ " " ++ show numClauses ++ "\n"++
                  (\tflAxs ->
                   case tflAxs of
                     [] -> ""
                     _  -> "c Axioms\n" ++
                         (foldl (\sr xv -> sr ++ mapClause xv sigMap) "" tflAxs) 
                  ) tfAxs ++
              (\tflCon -> 
                   case tflCon of
                     [] -> ""
                     _  -> "c Conjectures\n" ++
                           (foldl (\sr xv -> sr ++ mapClause xv sigMap) "" 
                                  tflCon)
              )
                  tfCon

-- | Helper to get out of the Maybe Monad

unwrapMaybe :: Maybe a -> a
unwrapMaybe (Just yv) = yv
unwrapMaybe Nothing   = error "Cannot unwrap Nothing"

-- | Create signature map
createSignMap :: Sig.Sign 
              -> Integer
              -> Map.Map Id.Token Integer 
              -> Map.Map Id.Token Integer
createSignMap sig inNum inMap = 
    let
        it   = Sig.items sig
        min  = Set.findMin it
        nSig = Sig.Sign {Sig.items = Set.deleteMin it}
    in
      case (Set.null it) of
        True  -> inMap
        False -> createSignMap 
                 nSig
                 (inNum + 1)
                 (Map.insert (head $ getSimpleId min) inNum inMap) 

-- | gets simple Id
getSimpleId :: Id.Id -> [Id.Token]
getSimpleId (Id.Id toks _ _) = toks

-- | Mapping of a single Clause
mapClause :: AS.FORMULA 
          -> Map.Map Id.Token Integer
          -> String
mapClause form map =
    case form of
      AS.Disjunction ts _ -> (foldl 
                              (\sr xv -> sr ++ (mapLiteral xv map) ++ " ") 
                              "" ts
                             ) 
                            ++ "0\n"
      AS.Negation (AS.Predication _) _ -> mapLiteral form map ++ "\n"
      AS.Predication _    -> mapLiteral form map ++ "\n"
      _                   -> error "Impossible Case alternative"

-- | Mapping of a single literal
mapLiteral :: AS.FORMULA 
           -> Map.Map Id.Token Integer 
           -> String
mapLiteral form map =
    case form of
      AS.Negation (AS.Predication tok) _ -> "-" ++ 
              show (Map.findWithDefault 0 tok map)
      AS.Predication tok   -> show (Map.findWithDefault 0 tok map)
      _                    -> error "Impossible Case"
