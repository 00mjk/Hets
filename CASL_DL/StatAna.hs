{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2005
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

static analysis of DL parts especially cardinalities, predefined datatypes
and additional annottations
-}

module CASL_DL.StatAna ( basicCASL_DLAnalysis
                       , minDLForm
                       , checkSymbolMapDL
                       , DLSign) where

import CASL_DL.AS_CASL_DL
import CASL_DL.Print_AS ()
import CASL_DL.Sign
import CASL_DL.PredefinedSign
import CASL_DL.PredefinedGlobalAnnos

import CASL.Sign
import CASL.MixfixParser
import CASL.Morphism
import CASL.StaticAna
import CASL.Utils
import CASL.AS_Basic_CASL
import CASL.ShowMixfix
import CASL.Overload
import CASL.Inject

import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Common.Lib.Rel as Rel

import Common.AS_Annotation
import Common.GlobalAnnotations
import Common.AnalyseAnnos
import Common.DocUtils
import Common.Id
import Common.Result
import Common.ConvertLiteral

import Data.List

import Debug.Trace

basicCASL_DLAnalysis :: (BASIC_SPEC () () DL_FORMULA,
                         Sign DL_FORMULA CASL_DLSign, GlobalAnnos)
                     -> Result (BASIC_SPEC () () DL_FORMULA,
                                Sign DL_FORMULA CASL_DLSign,
                                [Named (FORMULA DL_FORMULA)])
basicCASL_DLAnalysis (bs,sig,ga) =
    do ga' <- addGlobalAnnos ga caslDLGlobalAnnos
       case basicAnalysis minDLForm (const return)
             (const return) ana_Mix (bs,sig,ga') of
        r@(Result ds1 mr) -> maybe r (postAna ds1 sig) mr

{- |
  postAna checks the Signature for

  * all new sorts must be a proper subsort of Thing and
    must not be related to DATA

  * no new subsort relations with DATA

  * all new predicates must have a subsort of Thing as subject (1st argument)

  * all new operations must have a subsort of Thing as 1st argument

-}
postAna :: [Diagnosis]
        -> Sign DL_FORMULA CASL_DLSign
        -> (BASIC_SPEC () () DL_FORMULA,
            Sign DL_FORMULA CASL_DLSign,
            [Named (FORMULA DL_FORMULA)])
        -> Result (BASIC_SPEC () () DL_FORMULA,
                   Sign DL_FORMULA CASL_DLSign,
                   [Named (FORMULA DL_FORMULA)])
postAna ds1 in_sig i@(_, acc_sig, _) =
    Result (ds1++ds_sig) $ if null ds_sig then Just i else Nothing
    where ds_sig = chkSorts ++ checkPreds ++ checkOps
          diff_sig = diffSig diffCASL_DLSign acc_sig in_sig
          chkSorts = Set.fold chSort [] (sortSet diff_sig) ++
             (if Set.member topSortD (supersortsOf topSort acc_sig) ||
                 Set.member topSortD (subsortsOf topSort acc_sig) ||
                 (supersortsOf topSortD predefinedSign /=
                  supersortsOf topSortD acc_sig) ||
                 (selectDATAKernel (sortRel predefinedSign)
                  /=
                  selectDATAKernel (sortRel acc_sig))
               then [Diag Error
                        ("\n     new subsort relations with data "++
                         "topsort are not allowed") nullRange]
                  else [])

          chSort s ds = ds ++
              (if Set.member topSort (supersortsOf s acc_sig)
                  then []
                  else [mkDiag Error
                        ("\n     new sort is not a subsort of '"++
                         showDoc topSort "':") s]) ++
              (if Set.member topSort (subsortsOf s acc_sig)
                  then [mkDiag Error
                        ("\n     new sort must not be a supersort of '"++
                         showDoc topSort "':") s]
                  else [])

          selectDATAKernel rel =
              Rel.intransKernel $ Rel.restrict rel $
                 Set.insert topSortD
                        (subsortsOf topSortD predefinedSign)

          checkPreds = Map.foldWithKey chPred [] (predMap diff_sig)
          chPred p ts ds = ds ++
              Set.fold (\ t -> chArgs "pred" p $ predArgs t) [] ts

          checkOps = Map.foldWithKey chOp [] (opMap diff_sig)
          chOp o ts ds = ds ++
              Set.fold (\ t -> chArgs "op" o $ opArgs t) [] ts

          chArgs kstr sym args ds = ds ++
              case args of
              [] -> if kstr == "op"
                    then []
                    else [mkDiag Error
                        ("\n     propositional symbols are not allowed") sym]
              (s:_) ->
                  if s == topSort ||
                     Set.member topSort (supersortsOf s acc_sig)
                  then []
                  else [mkDiag Error
                        ("\n     the first argument sort of this "++kstr++
                        " is not a subsort of '"++ showDoc topSort "':")
                        sym]


{- sketch of Annotation analysis:

    where callAna bsRes =
              case analyseAnnos ga acc_sig bs of
              Result ds2 mESig ->
                  maybe (Result (ds1++ds2) Nothing)
                        (integrateExt (ds1++ds2) baRes) mESig
          integrateExt ds (bs',dif_sig,acc_sig,sens) eSig =
              Result ds (bs',
                         dif_sig {extendedInfo = dif eSig (extendedInfo sig)},
                         acc_sig {extendedInfo = eSig},
                         sens)
-}

ana_Mix :: Mix () () DL_FORMULA CASL_DLSign
ana_Mix = emptyMix
    { putParen = mapDL_FORMULA
    , mixResolve = resolveDL_FORMULA
    , checkMix = noExtMixfixDL
    , putInj = injDL_FORMULA
    }

type DLSign = Sign DL_FORMULA CASL_DLSign

-- |
-- static analysis of annotations
analyseAnnos :: GlobalAnnos -> Sign DL_FORMULA CASL_DLSign
             -> BASIC_SPEC () () DL_FORMULA -> Result DLSign
analyseAnnos _ga sig _bs =
    Result [Diag Warning "Analysis of Annotations not yet implemented"
                 nullRange]
           (Just $ {- extentedInfo -} sig)

injDL_FORMULA :: DL_FORMULA -> DL_FORMULA
injDL_FORMULA (Cardinality ct pn varTerm natTerm ps) =
    Cardinality ct pn (injT varTerm) (injT natTerm) ps
    where injT = injTerm injDL_FORMULA

mapDL_FORMULA :: DL_FORMULA -> DL_FORMULA
mapDL_FORMULA (Cardinality ct pn varTerm natTerm ps) =
    Cardinality ct pn (mapT varTerm) (mapT natTerm) ps
    where mapT = mapTerm mapDL_FORMULA

resolveDL_FORMULA :: MixResolve DL_FORMULA
resolveDL_FORMULA ga ids (Cardinality ct ps varTerm natTerm ran) =
    do vt <- resMixTerm varTerm
       nt <- resMixTerm natTerm
       return $ Cardinality ct ps vt nt ran
    where resMixTerm = resolveMixTrm mapDL_FORMULA
                                     resolveDL_FORMULA ga ids

noExtMixfixDL :: DL_FORMULA -> Bool
noExtMixfixDL f =
    let noInner = noMixfixT noExtMixfixDL in
    case f of
    Cardinality _ _ t1 t2 _ -> noInner t1 && noInner t2

minDLForm :: Min DL_FORMULA CASL_DLSign
minDLForm sign form =
    case form of
    Cardinality ct ps varTerm natTerm ran ->
     case predName ps of
     pn ->
        case Map.findWithDefault Set.empty pn (predMap sign) of
        pn_typeSet
            | Set.null pn_typeSet ->
                Result [Diag Error ("Unknown predicate: \""++
                                    show pn++"\"") (posOfId pn)]
                       Nothing
            | otherwise ->
              let pn_RelTypes = Set.filter (\pt -> length (predArgs pt) == 2)
                                           pn_typeSet
              in if Set.null pn_RelTypes
                 then Result [Diag Error ("No binary predicate \""++
                                    show pn++"\" declared") (posOfId pn)]
                       Nothing
                 else do
                   v2 <- oneExpTerm minDLForm sign varTerm
                   let v_sort = term_sort v2
                   n2 <- oneExpTerm minDLForm sign natTerm
                   let n_sort = term_sort n2
                   ps' <- case sub_sort_of_subj pn v_sort pn_RelTypes of
                          Result ds mts ->
                            let ds' =
                                 if null ds
                                 then [mkDiag Error
                                       ("Variable in cardinality constraint\n"
                                        ++ "    has wrong type")
                                       varTerm]
                                 else ds
                                amigDs ts =
                                 [Diag Error
                                  ("Ambigous types found for\n    pred '"++
                                   showDoc pn "' in cardinalty "++
                                   "constraint: (showing only two of them)\n"++
                                   "    '"++ showDoc (head ts) "', '"++
                                   showDoc (head $ tail ts) "'") ran]
                             in maybe (Result ds' Nothing)
                              (\ ts -> case ts of
                                [] -> error "CASL_DL.StatAna: Internal error"
                                [x] -> maybe
                                         (return $
                                            Qual_pred_name pn x nullRange)
                                         (\ pt -> if x == pt
                                                  then return ps
                                                  else noPredTypeErr ps)
                                         (getType ps)
                                _ -> maybe (Result (amigDs ts) Nothing)
                                           (\ pt -> if pt `elem` ts
                                                    then return ps
                                                    else noPredTypeErr ps)
                                           (getType ps))
                              mts
                   let isNatTerm =
                           if isNumberTerm (globAnnos sign) n2 &&
                              (show n_sort == "nonNegativeInteger" ||
                               trace (show n_sort) True)
                           then []
                           else [mkDiag Error
                                    ("The second argument of a\n    "++
                                     "cardinality constrain must be a "++
                                     "number literal\n    typeable as "++
                                     "nonNegativeInteger")
                                    natTerm]
                       ds = isNatTerm
                   appendDiags ds
                   if null ds
                    then return (Cardinality ct ps' v2 n2 ran)
                    else Result [] Nothing
    where predName ps = case ps of
                        Pred_name pn -> pn
                        Qual_pred_name pn _pType _ -> pn
          getType ps = case ps of
                        Pred_name _ -> Nothing
                        Qual_pred_name _ pType _ -> Just pType
          isNumberTerm ga t =
              maybe False (uncurry (isNumber ga)) (splitApplM t)

          noPredTypeErr ps = Result
              [mkDiag Error "no predicate with \n    given type found" ps]
              Nothing

          sub_sort_of_subj pn v_sort typeSet =
              foldl (\ (Result ds mv) pt ->
                         case predArgs pt of
                         (s:_)
                             | leq_SORT sign v_sort s ->
                                 maybe (Result ds $ Just [toPRED_TYPE pt])
                                       (\ l -> Result ds $
                                                   Just $ l++[toPRED_TYPE pt])
                                       mv
                             | otherwise ->
                                 Result ds mv
                         _ -> Result (ds++[mkDiag Error
                                                  ("no propositional " ++
                                                   "symbols are allowed\n    "
                                                   ++ "within cardinality " ++
                                                   "constraints")
                                                  pn]) mv
                  ) (Result [] Nothing) $ Set.toList typeSet

-- | symbol map analysis
checkSymbolMapDL ::  RawSymbolMap -> Result RawSymbolMap
{-    - implement a symbol mapping that forbids mapping of predefined symbols
       from emptySign
       use from Logic.Logic.Logic and from CASL:
          matches, symOf, statSymbMapItems
-}
checkSymbolMapDL rsm =
    let syms = Map.foldWithKey checkSourceSymbol [] rsm
    in if null syms
       then return rsm
       else Result (ds syms) Nothing
    where checkSourceSymbol sSym _ syms =
              if Set.fold (\ ps -> (||) $ matches ps sSym) False
                          symOfPredefinedSign
              then syms ++ [sSym]
              else syms
          -- ds :: [RawSymbol] -> [Diagnosis]
          ds syms = [Diag Error
                     ("Predefined CASL_DL symbols\n    cannot be mapped: "++
                      concat (intersperse ", " $
                              map (\x -> showDoc x "") syms))
                     (minimum $ map getRange syms)]

symOfPredefinedSign :: SymbolSet
symOfPredefinedSign = symOf predefinedSign

isNumber :: GlobalAnnos -> Id -> [TERM f] -> Bool
isNumber = isGenNum splitApplM

splitApplM :: TERM f -> Maybe (Id, [TERM f])
splitApplM t = case t of
    Application _ _ _ -> Just $ splitAppl t
    _ -> Nothing

splitAppl :: TERM f -> (Id, [TERM f])
splitAppl t = case t of
              Application oi ts _ -> (op_id oi,ts)
              _ -> error "splitAppl: no Application found"

-- | extract the Id from any OP_SYMB
op_id :: OP_SYMB -> Id
op_id op = case op of
           Qual_op_name x _ _ -> x
           Op_name x          -> x
