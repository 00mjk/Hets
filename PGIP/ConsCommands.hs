{- |
Module      :$Header$
Description : CMDL interface commands
Copyright   : uni-bremen and DFKI
License     : similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  : r.pascanu@jacobs-university.de
Stability   : provisional
Portability : portable

PGIP.ConsCommands contains all commands
related to consistency\/conservativity checks
-}

module PGIP.ConsCommands
       ( 
         cConservCheck
       , cConservCheckAll
       , cConsistCheck
       , cConsistCheckAll
       ) where

import PGIP.DataTypes
import PGIP.Utils
import PGIP.DataTypesUtils
import Static.DevGraph
import Data.Graph.Inductive.Graph
import Data.List
import Data.Char
import Logic.Logic(conservativityCheck)
import Logic.Coerce(coerceSign, coerceMorphism)
import Logic.Grothendieck
import Logic.Comorphism
import Logic.Prover
import CASL.CCC.FreeTypes
import Syntax.AS_Library(LIB_NAME)
import Static.GTheory
import Static.DGToSpec( computeTheory)
import qualified HTk
import Common.Result as Res
import Common.ExtSign



cConservCheck:: String -> CMDL_State -> IO CMDL_State
cConservCheck input state =
  case devGraphState state of
   Nothing ->
     return $ genErrorMsg "No library loaded" state
   Just dgState -> do
     let (_,edg,nbEdg,errs) = decomposeIntoGoals input
         tmpErrs = prettyPrintErrList errs
     case (edg,nbEdg) of
      ([],[]) ->
        return $genErrorMsg( tmpErrs++"No edges in input string\n") state
      (_,_) ->
        do
         let lsNodes = getAllNodes dgState
             lsEdges = getAllEdges dgState
         allList <- conservativityList lsNodes lsEdges
                                  (libEnv dgState) (ln dgState)
         let edgLs = concatMap (\x -> case find (
                                        \(s1,_) -> s1 == x) allList of
                                       Nothing -> []
                                       Just (s1,s2) -> [(s1,s2)]) edg
             nbEdgLs = concatMap (\x -> case find (
                                        \(s1,_) -> s1 == x) allList of
                                       Nothing -> []
                                       Just (s1,s2) -> [(s1,s2)]) nbEdg
         case edgLs++nbEdgLs of
          [] -> return $ genErrorMsg (tmpErrs ++ "No edge in input string\n")
                                                             state
          _ ->
           do
              return $ genMessage tmpErrs
                         (concatMap (\(s1,s2) -> s1++" : "++s2++"\n")
                                       (edgLs ++ nbEdgLs) ) state




cConservCheckAll :: CMDL_State -> IO CMDL_State
cConservCheckAll state =
   case devGraphState state of
    Nothing ->
              return $ genErrorMsg "No library loaded" state
    Just dgState ->
     do
      resTxt <- conservativityList (getAllNodes dgState)
                                   (getAllEdges dgState)
                                   (libEnv dgState)
                                   (ln dgState)
      return $ genMessage []
                (concatMap (\(s1,s2) -> s1++" : "++s2++"\n") resTxt)  state


cConsistCheck :: String -> CMDL_State -> IO CMDL_State
cConsistCheck _ state =
        return state

cConsistCheckAll :: CMDL_State -> IO CMDL_State
cConsistCheckAll state =
        return state

conservativityList:: [LNode DGNodeLab] ->
                     [LEdge DGLinkLab] ->
                     LibEnv -> LIB_NAME -> IO [(String,String)]
conservativityList lsN lsE le libname
 =
  do
   let
  -- function that returns the name of a node given its number
    nameOf x ls = case find(\(nb,_) -> nb == x) ls of
                   Nothing -> "Unknown node"
                   Just (_, nlab) -> showName $ dgn_name nlab
    ordFn x y = let (x1,x2,_) = x
                    (y1,y2,_) = y
                in if (x1,x2) > (y1,y2) then GT
                   else if (x1,x2) < (y1,y2) then LT
                        else EQ
  -- sorted and grouped list of edges
    edgs = groupBy ( \(x1,x2,_) (y1,y2,_)-> (x1,x2)==(y1,y2)) $
           sortBy ordFn lsE
    edgtm = concatMap (\l -> case l of
                              [(x,y,edgLab)] ->[((x,y,edgLab),True)]
                              _ -> map (\(x,y,edgLab) -> ((x,y,edgLab),
                                                                False)) l)
                                                  edgs
   allEds <- mapM (\((x,y,edgLab),vl) -> case vl of
                             True->(edgeConservativityState
                                               ((nameOf x lsN) ++ " -> " ++
                                               (nameOf y lsN)) (x,y,edgLab)
                                                    le libname)
                             False -> (edgeConservativityState
                                            ((nameOf x lsN) ++ " -> " ++
                                            (show $ getInt $dgl_id edgLab) ++
                                             " -> " ++
                                             (nameOf y lsN)) (x,y,edgLab)
                                                        le libname)) edgtm
   return allEds

edgeConservativityState :: String->LEdge DGLinkLab -> LibEnv -> LIB_NAME
                           -> IO (String,String)
edgeConservativityState nm (source,target,linklab) libenv libname
 = do
    let dgraph = lookupDGraph libname libenv
        dgtar = labDG dgraph target
    if isDGRef dgtar then return (nm,"no DGNode") else do
        G_theory lid _ _ sens _ <- return $ dgn_theory dgtar
        GMorphism cid _ _ morphism2 _ <- return $ dgl_morphism linklab
        morphism2' <- coerceMorphism (targetLogic cid) lid
                          "edgeConservativityState" morphism2
        let th = case computeTheory libenv libname source of
                   Res.Result _ (Just th1) -> th1
                   _ -> error "edgeConservativityState: computeTheory"
        G_theory lid1 sign1 _ sens1 _ <- return th
        sign2 <- coerceSign lid1 lid "edgeConservativityState.coerceSign"
                                    sign1
        sens2 <- coerceThSens lid1 lid "" sens1
        let Res.Result ds res =
                conservativityCheck lid
                   (plainSign sign2, toNamedList sens2)
                   morphism2' $ toNamedList sens
            showRes = case res of
                       Just (Just Inconsistent) ->
                                     "not conservative"
                       Just (Just Conservative) ->
                                     "conservative"
                       Just (Just Monomorphic) ->
                                     "monomorphic"
                       Just (Just Definitional) ->
                                     "definitional"
                       _ -> "Could not determine whether link is conservative"
            myDiags = showRelDiags 2 ds
        return (nm,showRes++"\n"++myDiags)

