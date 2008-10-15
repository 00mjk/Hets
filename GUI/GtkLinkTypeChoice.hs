{- |
Module      :  $Header$
Description :  Gtk GUI for the selection of linktypes
Copyright   :  (c) Thiemo Wiedemeyer, Uni Bremen 2008
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  raider@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

This module provides a GUI for the selection of linktypes.
-}

module GUI.GtkLinkTypeChoice
  (showLinkTypeChoice)
  where

import Graphics.UI.Gtk
import Graphics.UI.Gtk.Glade

import GUI.GtkUtils
import qualified GUI.Glade.LinkTypeChoice as LinkTypeChoice

import Static.DevGraph

import Monad(filterM)
import Char(toLower)

import qualified Data.Map as Map

mapEdgeTypesToNames :: Map.Map String (DGEdgeType, DGEdgeType)
mapEdgeTypesToNames = Map.fromList
  $ map (\ (e, eI) -> ("cb_" ++ (map toLower $ getDGEdgeTypeName e), (e, eI)))
  $ map (\ e -> (e, e { isInc = True } ))
  $ filter (\ e -> not $ isInc e) listDGEdgeTypes

-- | Displays the linktype selection window
showLinkTypeChoice :: ([DGEdgeType] -> IO ()) -> IO ()
showLinkTypeChoice updateFunction = postGUIAsync $ do
  xml      <- getGladeXML LinkTypeChoice.get
  window   <- xmlGetWidget xml castToWindow "linktypechoice"
  ok       <- xmlGetWidget xml castToButton "b_ok"
  cancel   <- xmlGetWidget xml castToButton "b_cancel"
  select   <- xmlGetWidget xml castToButton "b_select"
  deselect <- xmlGetWidget xml castToButton "b_deselect"
  invert   <- xmlGetWidget xml castToButton "b_invert"

  let
    edgeMap = mapEdgeTypesToNames
    keys = Map.keys edgeMap
    setAllTo = (\ to -> mapM_ (\ name -> do
                                cb <- xmlGetWidget xml castToCheckButton name
                                to' <- to cb
                                toggleButtonSetActive cb to'
                              ) keys
               )

  onClicked select $ setAllTo (\ _ -> return True)
  onClicked deselect $ setAllTo (\ _ -> return False)
  onClicked invert $ setAllTo (\ cb -> do
                                selected <- toggleButtonGetActive cb
                                return $ not selected
                              )

  onClicked cancel $ widgetDestroy window

  onClicked ok $ do
    edgeTypeNames <- filterM (\ name -> do
                               cb <- xmlGetWidget xml castToCheckButton name
                               selected <- toggleButtonGetActive cb
                               return $ not selected
                             ) keys
    let edgeTypes =  foldl (\ eList (e, eI) -> e:eI:eList) []
                           $ map (\ name -> Map.findWithDefault
                                   (error "GtkLinkTypeChoice: lookup error!")
                                   name edgeMap
                                 ) edgeTypeNames
    updateFunction edgeTypes
    widgetDestroy window

  widgetShow window
