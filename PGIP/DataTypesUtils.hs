{- |
Module      :$Header$
Description : utilitary functions used throughout the CMDL interface
Copyright   : uni-bremen and DFKI
Licence     : similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  : r.pascanu@jacobs-university.de
Stability   : provisional
Portability : portable

PGIP.Utils contains different basic functions that are
used throughout the CMDL interface and could not be found in
Prelude

-}

module PGIP.DataTypesUtils
         ( getAllNodes
         , obtainGoalNodeList
         , getAllGoalNodes
         , getAllEdges
         , getAllGoalEdges
         , initCMDLProofAbstractState
         , getTh
         , baseChannels
         , genErrorMsg
         , genMessage
         , genError
         ) where

import PGIP.Utils
import PGIP.DataTypes
import Common.Result
import Data.List
import Data.Graph.Inductive.Graph
import Static.GTheory
import Static.DevGraph
import Static.DGToSpec
import Logic.Logic
import System.IO
import Proofs.AbstractState


-- | Returns the list of all nodes, if it is not up to date
-- the function recomputes the list
getAllNodes :: CMDL_DevGraphState -> [LNode DGNodeLab]
getAllNodes state
 = case allNodesUpToDate state of
    -- nodes are up to date
    True -> allNodes state
    -- nodes are not up to date
    False -> labNodesDG $ lookupDGraph (ln state)
                             (libEnv state)

-- | Given a list of node names and the list of all nodes
-- the function returns all the nodes that have their name
-- in the name list but are also goals
obtainGoalNodeList :: CMDL_State -> [String] -> [LNode DGNodeLab]
                                 -> ([String],[LNode DGNodeLab])
obtainGoalNodeList state input ls
 = let (l1,l2) = obtainNodeList input ls
       l2' = filter (\(nb,nd) ->
                       let nwth = getTh nb state
                       in case nwth of
                           Nothing -> False
                           Just th -> nodeContainsGoals (nb,nd) th) l2
   in (l1,l2')




-- | Returns the list of all nodes that are goals,
-- taking care of the up to date status
getAllGoalNodes :: CMDL_State -> CMDL_DevGraphState -> [LNode DGNodeLab]
getAllGoalNodes st state
 = filter (\(nb,nd) ->
             let nwth = getTh nb st
             in case nwth of
                 Nothing -> False
                 Just th -> nodeContainsGoals (nb,nd) th) $
                                                     getAllNodes state

-- | Returns the list of all edges, if it is not up to date
-- the funcrion recomputes the list
getAllEdges :: CMDL_DevGraphState -> [LEdge DGLinkLab]
getAllEdges state
 = case allEdgesUpToDate state of
    -- edges are up to date
    True -> allEdges state
    -- edges are not up to date
    False -> labEdgesDG $ lookupDGraph (ln state)
                            (libEnv state)

-- | Returns the list of all goal edges taking care of the
-- up to date status
getAllGoalEdges :: CMDL_DevGraphState -> [LEdge DGLinkLab]
getAllGoalEdges state
 = filter edgeContainsGoals $ getAllEdges state

-- | Constructor for CMDLProofGUIState datatype
initCMDLProofAbstractState:: (Logic lid1 sublogics1
         basic_spec1 sentence1 symb_items1 symb_map_items1
         sign1 morphism1 symbol1 raw_symbol1 proof_tree1) =>
         ProofState lid1 sentence1 -> Int
         -> CMDL_ProofAbstractState
initCMDLProofAbstractState ps nb
 = Element ps nb


--local function that computes the theory of a node
--that takes into consideration translated theories in
--the selection too and returns the theory as a string
getTh :: Int -> CMDL_State -> Maybe G_theory
getTh x state
 = let
    -- compute the theory for a given node
    -- (see Static.DGToSpec)
       fn n = case devGraphState state of
                Nothing -> Nothing
                Just dgState ->
                 case computeTheory (libEnv dgState)
                               (ln dgState) n of
                  Result _ (Just th) -> Just th
                  _                  -> Nothing
   in case proveState state of
       Nothing -> fn x
       Just ps ->
        case find (\y -> case y of
                          Element _ z -> z == x) $
                  elements ps of
         Nothing -> fn x
         Just _ ->
           case cComorphism ps of
            Nothing -> fn x
            Just cm ->
              case fn x of
               Nothing -> Nothing
               Just sth->
                case mapG_theory cm sth of
                  Result _ Nothing -> Nothing --Just sth
                  Result _ (Just sth') -> Nothing --Just sth'


-- | Generates the base channels to be used (stdin and stdout)
baseChannels :: [CMDL_Channel]
baseChannels
 = let ch_in  = CMDL_Channel {
                  chName       = "stdin",
                  chType       = ChStdin,
                  chHandler    = stdin,
                  chSocket     = Nothing,
                  chProperties = ChRead
                  }
       ch_out = CMDL_Channel {
                  chName       = "stdout",
                  chType       = ChStdout,
                  chHandler    = stdout,
                  chSocket     = Nothing,
                  chProperties = ChWrite
                  }
   in ch_in : ch_out : []


genErrorMsg :: String -> CMDL_State -> CMDL_State
genErrorMsg msg state
 = state {
      output = CMDL_Output {
                  errorMsg = msg,
                  outputMsg = [],
                  fatalError = True
                  }
          }

genMessage :: String -> String -> CMDL_State -> CMDL_State
genMessage errMsg msg state
 = state {
      output = CMDL_Output {
                  errorMsg = errMsg,
                  outputMsg = msg,
                  fatalError = False
                  }
         }

genError :: CMDL_State -> CMDL_State
genError state
 = state {
      output = CMDL_Output {
                  errorMsg = [],
                  outputMsg = [],
                  fatalError = True
                  }
          }



