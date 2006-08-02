{- |
Module      :  $Header$
Description :  Interface for the SPASS theorem prover using MathServ.
Copyright   :  (c) Rene Wagner, Klaus L�ttich, Rainer Grabbe, Uni Bremen 2005-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  rainer25@tzi.de
Stability   :  provisional
Portability :  needs POSIX

Interface for the SPASS theorem prover, uses GUI.GenericATP.
See <http://spass.mpi-sb.mpg.de/> for details on SPASS.

-}

{-
    To do:
    - check why an internal error during batch mode running does not invoke
      an error window. Also the proving won't stop.
-}

module SPASS.ProveMathServ (mathServBroker,mathServBrokerGUI) where

import Logic.Prover

import SPASS.Sign
import SPASS.Translate
import SPASS.MathServMapping
import SPASS.MathServParsing
import SPASS.ProverState

import qualified Common.AS_Annotation as AS_Anno

import Data.List
import Data.Maybe

import HTk

import GUI.GenericATP
import GUI.GenericATPState

-- * Prover implementation

{- |
  The Prover implementation. First runs the batch prover (with graphical
  feedback), then starts the GUI prover.
-}
mathServBroker :: Prover Sign Sentence String
mathServBroker =
  Prover { prover_name = "MSBroker",
           prover_sublogic = "SoftFOL",
           prove = mathServBrokerGUI
         }

spassHelpText :: String
spassHelpText =
  "No help yet available.\n" ++
  "Ask Klaus L�ttich (luettich@informatik.uni-bremen.de) for more information.\n"


-- * Main GUI

{- |
  Invokes the generic prover GUI. SoftFOL specific functions are omitted by
  data type ATPFunctions.
-}
mathServBrokerGUI :: String -- ^ theory name
                  -> Theory Sign Sentence String
                  -- ^ theory consisting of a SPASS.Sign.Sign
                  --   and a list of Named SPASS.Sign.Sentence
                  -> IO([Proof_status String]) -- ^ proof status for each goal
mathServBrokerGUI thName th =
    genericATPgui atpFun False (prover_name mathServBroker) thName th ""

    where
      atpFun = ATPFunctions
        { initialProverState = spassProverState,
          atpTransSenName = transSenName,
          atpInsertSentence = insertSentenceGen,
          goalOutput = showTPTPProblem thName,
          proverHelpText = spassHelpText,
          batchTimeEnv = "HETS_SPASS_BATCH_TIME_LIMIT",
          fileExtensions = FileExtensions{problemOutput = ".tptp",
                                          proverOutput = ".spass",
                                          theoryConfiguration = ".spcf"},
          runProver = runMSBroker,
          createProverOptions = extraOpts}

{- |
  Runs the MathServ broker and returns GUI proof status and prover
  configuration with  proof status and complete prover output.
-}
runMSBroker :: SPASSProverState
            -- ^ logical part containing the input Sign and axioms and possibly
            --   goals that have been proved earlier as additional axioms
            -> GenericConfig String -- ^ configuration to use
            -> Bool -- ^ True means save TPTP file
            -> String -- ^ name of the theory in the DevGraph
            -> AS_Anno.Named SPTerm -- ^ goal to prove
            -> IO (ATPRetval, GenericConfig String)
            -- ^ (retval, configuration with proof status and complete output)
runMSBroker sps cfg saveTPTP thName nGoal = do
    putStrLn ("running MathServ Broker...")
    prob <- showTPTPProblem thName sps nGoal $ extraOpts cfg ++ ["[via Broker]"]
    when saveTPTP
        (writeFile (thName++'_':AS_Anno.senName nGoal++".tptp") prob)
    mathServOut <- callMathServ
        MathServCall{mathServService = Broker,
                     mathServOperation = ProblemOpt,
                     problem = prob,
                     proverTimeLimit = tLimit,
                     extraOptions = Nothing}
    msResponse <- parseMathServOut mathServOut
    return (mapMathServResponse msResponse cfg nGoal (prover_name mathServBroker))
    where
      tLimit = maybe (guiDefaultTimeLimit) id $ timeLimit cfg
