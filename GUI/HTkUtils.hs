{-
Module      :  $Header$
Copyright   :  (c)  Till Mossakowski and Klaus L�ttich, Uni Bremen 2002-2005
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic)

   Utilities on top of HTk
-}

module GUI.HTkUtils where

import System.Directory

import HTk
import Core
import ScrollBox
import TextDisplay
import FileDialog
 -- only to avoid problematic ghc 6.2.1 compilation order
import Common.Lib.Rel()

-- | create a window with title and list of options, return selected option
listBox :: String -> [String] -> IO (Maybe Int)
listBox title entries =
  do
    main <- createToplevel [text title]
    lb  <- newListBox main [value entries, bg "white", size (100, 50)] ::
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
createTextSaveDisplayExt title filename txt conf unpost =
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
     spawnEvent (forever (quit >>> do destroy win; unpost
                           +>
                         save >>> do disableButs q s
                                     askFileNameAndSave filename txt
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
                      -> [Config Editor]-- ^ configuration options for 
                      -- the text editor
                      -> IO()
createTextSaveDisplay t f txt conf = 
    do createTextSaveDisplayExt t f txt conf done; done


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