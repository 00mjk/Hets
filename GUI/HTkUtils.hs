{- |
Module      :  $Header$
Copyright   :  (c) K. L�ttich, Rene Wagner, Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luettich@tzi.de
Stability   :  provisional
Portability :  non-portable (imports HTk)

Utilities on top of HTk
-}

module GUI.HTkUtils where

import System.Directory

import HTk
import ScrollBox
import FileDialog

import Logic.Prover hiding(value)
import Static.DevGraph

-- | create a window with title and list of options, return selected option
listBox :: String -> [String] -> IO (Maybe Int)
listBox title entries =
  do
    main <- createToplevel [text title]
    lb  <- newListBox main [value entries, bg "white", size (100, 39)] ::
             IO (ListBox String)
    pack lb [Side AtLeft, 
                 Expand On, Fill Both]
    scb <- newScrollBar main []
    pack scb [Side AtRight, Fill Y]
    lb # scrollbar Vertical scb
    (press, _) <- bindSimple lb (ButtonPress (Just 1))
    sync press
    sel <- getSelection lb
    destroy main
    return (case sel of
       Just [i] -> Just i
       _ -> Nothing)


-- |
-- Display some (longish) text in an uneditable, scrollable editor.
-- Returns immediately-- the display is forked off to separate thread.
createTextSaveDisplayExt :: String -- ^ title of the window
                         -> String -- ^ default filename for saving the text
                         -> String -- ^ text to be displayed
                         -> [Config Editor] -- ^ configuration options for 
                         -- the text editor
                         -> IO() -- ^ action to be executed when 
                         -- the window is closed
                         -> IO (Toplevel,Editor) -- ^ the window in which 
                         -- the text is displayed
createTextSaveDisplayExt title fname txt conf upost =
  do win <- createToplevel [text title]
     b   <- newFrame win  [relief Groove, borderwidth (cm 0.05)]    
     t   <- newLabel b [text title, HTk.font (Helvetica, Roman, 18::Int)]
     q   <- newButton b [text "Close", width 12]
     s   <- newButton b [text "Save", width 12]
     (sb, ed) <- newScrollBox b (\p-> newEditor p (state Normal:conf)) []
     pack b [Side AtTop, Fill X, Expand On]
     pack t [Side AtTop, Expand Off, PadY 10]
     pack sb [Side AtTop, Expand On]
     pack ed [Side AtTop, Expand On, Fill X]
     pack q [Side AtRight, PadX 5, PadY 5]               
     pack s [Side AtLeft, PadX 5, PadY 5]                

     ed # value txt
     ed # state Disabled

     quit <- clicked q
     save <- clicked s
     spawnEvent (forever (quit >>> do destroy win; upost
                           +>
                         save >>> do disableButs q s
                                     askFileNameAndSave fname txt
                                     enableButs q s
                                     done))
     return (win, ed)
   where disableButs b1 b2 = do disable b1
                                disable b2
         enableButs b1 b2 = do enable b1
                               enable b2
-- |
-- Display some (longish) text in an uneditable, scrollable editor.
-- Simplified version of createTextSaveDisplayExt

createTextSaveDisplay :: String -- ^ title of the window
                      -> String -- ^ default filename for saving the text
                      -> String -- ^ text to be displayed
                      -> IO()
createTextSaveDisplay t f txt = 
    do createTextSaveDisplayExt t f txt [size(100,50)] done; done


--- added by KL
-- |
-- opens a FileDialog and saves to the selected file if OK is clicked
-- otherwise nothing happens
askFileNameAndSave :: String -- ^ default filename for saving the text
                   -> String -- ^ text to be saved
                   -> IO ()
askFileNameAndSave defFN txt =
    do curDir <- getCurrentDirectory
       selev <- newFileDialogStr "Save file" (curDir++'/':defFN)
       mfile <- sync selev
       maybe done saveFile mfile
    where saveFile fp = writeFile fp txt

--- added by RW
{- |
Represents the state of a goal in a 'ListBox' that uses 'populateGoalsListBox'
-}
data LBStatusIndicator = LBIndicatorProved
                       | LBIndicatorDisproved
                       | LBIndicatorOpen
                       | LBIndicatorGuessed
                       | LBIndicatorConjectured
                       | LBIndicatorHandwritten

-- |
-- Converts a 'LBStatusIndicator' into a short 'String' representing it in
-- a 'ListBox'
indicatorString :: LBStatusIndicator
                -> String
indicatorString i = case i of
  LBIndicatorProved      -> "[+]"
  LBIndicatorDisproved   -> "[-]"
  LBIndicatorOpen        -> "[ ]"
  LBIndicatorGuessed     -> "[.]"
  LBIndicatorConjectured -> "[:]"
  LBIndicatorHandwritten -> "[/]"

-- |
-- Represents a goal in a 'ListBox' that uses 'populateGoalsListBox'
data LBGoalView = LBGoalView { -- | status indicator
                               statIndicator :: LBStatusIndicator,
                               -- | description
                               goalDescription :: String
                             }

-- |
-- Populates a 'ListBox' with goals. After the initial call to this function
-- the number of goals is assumed to remain constant in ensuing calls.
populateGoalsListBox :: ListBox String -- ^ listbox
                     -> [LBGoalView] -- ^ list of goals
--  length must remain constant after the first call
                     -> IO ()
populateGoalsListBox lb v = do
  selectedOld <- (getSelection lb) :: IO (Maybe [Int])
  lb # value (toString v)
  maybe (return ()) (mapM_ (\n -> selection n lb)) selectedOld
  where
    toString = map (\ LBGoalView {statIndicator = i, goalDescription = d} -> 
                        (indicatorString i) ++ (' ' : d))

-- | Converts a 'Logic.Prover.Proof_status' into a 'LBStatusIndicator'
indicatorFromProof_status :: Proof_status a
                          -> LBStatusIndicator
indicatorFromProof_status st = case st of
  Proved _ _ _ _ _ -> LBIndicatorProved
  Disproved _ -> LBIndicatorDisproved
  _ -> LBIndicatorOpen

-- | Converts a 'BasicProof' into a 'LBStatusIndicator'
indicatorFromBasicProof :: BasicProof
                        -> LBStatusIndicator
indicatorFromBasicProof p = case p of
  BasicProof _ st -> indicatorFromProof_status st
  Guessed         -> LBIndicatorGuessed
  Conjectured     -> LBIndicatorConjectured
  Handwritten     -> LBIndicatorHandwritten

-- | existential type for widgets that can be enabled and disabled
data EnableWid = forall wid . HasEnable wid => EnW wid        

enableWids :: [EnableWid] -> IO ()
enableWids = mapM_ ( \ ew -> case ew of EnW w -> enable w >> return ())

disableWids :: [EnableWid] -> IO ()
disableWids = mapM_ ( \ ew -> case ew of EnW w -> disable w >> return ())

-- | enables widgets only if at least one entry is selected in the listbox, 
-- otherwise the widgets are disabled
enableWidsUponSelection :: ListBox String -> [EnableWid] -> IO ()
enableWidsUponSelection lb goalSpecificWids =
    do sel <- (getSelection lb) :: IO (Maybe [Int])
       maybe (disableWids goalSpecificWids)
             (const $ enableWids goalSpecificWids)
             sel
