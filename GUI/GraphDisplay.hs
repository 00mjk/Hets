{- |
Module      :  $Header$
Description :  Central GUI for Hets, with display of development graph
Copyright   :  (c) Jorina Freya Gerken, Till Mossakowski, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  till@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable (imports Logic)

Conversion of development graphs from Logic.DevGraph
   to abstract graphs of the graph display interface

A composition table is used when abstracting the graph and composing
multiple edges. It looks like this

@
 [(\"normal\",\"normal\",\"normal\"),
 (\"normal\",\"inclusion\",\"normal\"),
 (\"inclusion\",\"normal\",\"normal\"),
 (\"inclusion\",\"inclusion\",\"inclusion\")]
@

A ginfo can be created with initgraphs. The graph is then created with
addnode and addlink.

-}

module GUI.GraphDisplay
    (convertGraph,initializeConverter)
    where

import Static.DevGraph

import GUI.GraphMenu
import GUI.GraphTypes
import GUI.GraphLogic( convert, applyChanges )
import qualified GUI.GraphAbstraction as GA

import qualified GUI.HTkUtils as HTk

import Data.IORef
import qualified Data.Map as Map(lookup, insert)
import Control.Concurrent.MVar

import Interfaces.DataTypes

initializeConverter :: IO (GInfo,HTk.HTk)
initializeConverter = do
  wishInst <- HTk.initHTk [HTk.withdrawMainWin]
  gInfo <- emptyGInfo
  return (gInfo,wishInst)

{- | converts the development graph given by its libname into an
    abstract graph and returns the descriptor of the latter, the
    graphInfo it is contained in and the conversion maps. -}
convertGraph :: ConvFunc
convertGraph gInfo@(GInfo { gi_GraphInfo = actGraphInfo
                          , windowCount = wc
                          }) title showLib = do
 ost <- readIORef $ intState gInfo
 case i_state ost of
  Nothing -> error "Something went wrong, no library loaded"
  Just ist -> do
   let libEnv = i_libEnv ist
       libname = i_ln ist
   case Map.lookup libname libEnv of
    Just dgraph -> do
      case openlock dgraph of
        Just lock -> do
          notopen <- tryPutMVar lock $ \ hst -> do
            hhn <- GA.hasHiddenNodes actGraphInfo
            if hhn then GA.showAll actGraphInfo else return ()
            applyChanges actGraphInfo hst
          case notopen of
            True -> do
              count <- takeMVar wc
              putMVar wc $ count + 1
              initializeGraph gInfo title showLib
              if (isEmptyDG dgraph) then return ()
                else do
                  convert actGraphInfo dgraph
                  return ()
            False -> error $ "development graph with libname " ++ show libname
                             ++" is already open"
        Nothing -> do
          lock <- newEmptyMVar
          let nwle = Map.insert libname dgraph{openlock = Just lock} libEnv
              nwst = ost { i_state = Just $ ist { i_libEnv = nwle}}
          writeIORef (intState gInfo) nwst
          convertGraph gInfo title showLib
    Nothing -> error $ "development graph with libname " ++ show libname
                       ++" does not exist"

-- | initializes an empty abstract graph with the needed node and edge types,
-- return type equals the one of convertGraph
initializeGraph :: GInfo -> String -> LibFunc -> IO ()
initializeGraph gInfo title showLib = do
 ost <- readIORef $ intState gInfo
 case i_state ost of
  Nothing -> return ()
  Just ist -> do
   let ln = i_ln ist
       title' = (title ++ " for " ++ show ln)
   createGraph gInfo title' (convertGraph) (showLib)
