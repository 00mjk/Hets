{-# OPTIONS -cpp #-}
{- |
Module      :  $Header$
Copyright   :  (c) C. Maeder, Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  non-portable (cpp)

Utilities on top of HTk or System.IO
-}

module GUI.Utils (listBox, createTextSaveDisplay, askFileNameAndSave) where

#ifdef UNI_PACKAGE
import GUI.HTkUtils
#else
import GUI.ConsoleUtils
#endif
