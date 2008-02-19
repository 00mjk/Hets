{- |
Module      :$Header$
Description : The definition of CMDL interface for
              standard input and file input
Copyright   : uni-bremen and DFKI
License     : similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  : r.pascanu@jacobs-university.de
Stability   : provisional
Portability : portable

PGIP.Interface describes the interface specific function
for standard input and file input
-}

module PGIP.Interface where


import System.Console.Shell
import System.Console.Shell.Backend.Readline
import System.IO

import PGIP.Shell
import PGIP.DataTypes
import PGIP.Commands

import PGIP.StringInterface
import PGIP.StdInterface
import PGIP.FileInterface

-- | Creates an empty CMDL_State
emptyCMDL_State ::  CMDL_State
emptyCMDL_State =
   CMDL_State {
     devGraphState = Nothing,
     proveState = Nothing,
     prompter = " > ",
     output = CMDL_Output {
                 errorMsg   = [],
                 outputMsg  = [],
                 fatalError = False
                  },
     history = CMDL_History {
                 undoList      = [],
                 redoList      = [],
                 oldEnv        = Nothing,
                 undoInstances = [],
                 redoInstances = []
                 },
      openComment = False,
      connections = []
     }




-- | The function runs hets in a shell
cmdlRunShell :: [String] ->IO CMDL_State
cmdlRunShell files
   = do
      state <- recursiveApplyUse  files emptyCMDL_State
      runShell stdShellDescription
                {defaultCompletions= Just (cmdlCompletionFn getCommands) }
              readlineBackend
              state

-- | The function processes the file of instructions
cmdlProcessFile :: String -> IO CMDL_State
cmdlProcessFile filename =
        (runShell fileShellDescription
                 (fileBackend filename)
                 emptyCMDL_State) `catch`
                               (\_ -> return emptyCMDL_State )

-- | The function processes a string of instructions starting from a given
-- state
cmdlProcessString :: String -> CMDL_State -> IO CMDL_State
cmdlProcessString input st =
       (runShell stringShellDescription
                    (stringBackend input)
                    st) `catch`
                        (\_ -> return st )

