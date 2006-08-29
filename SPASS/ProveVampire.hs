{- |
Module      :  $Header$
Description :  Interface for the SPASS theorem prover using Vampire.
Copyright   :  (c) Rene Wagner, Klaus L�ttich, Rainer Grabbe, Uni Bremen 2005-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  rainer25@tzi.de
Stability   :  provisional
Portability :  needs POSIX

Interface for the Vampire service, uses GUI.GenericATP.
See <http://spass.mpi-sb.mpg.de/> for details on SPASS.

-}

module SPASS.ProveVampire (vampire,vampireGUI) where

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
vampire :: Prover Sign Sentence ATP_ProofTree
vampire = emptyProverTemplate
         { prover_name = "Vampire",
           prover_sublogic = "SoftFOL",
           proveGUI = Just vampireGUI
         }

spassHelpText :: String
spassHelpText =
  "No help yet available.\n" ++
  "Ask Klaus L�ttich (luettich@informatik.uni-bremen.de) for more information.\n"


-- * Main GUI

{- |
  Invokes the generic prover GUI. SPASS specific functions are omitted by
  data type ATPFunctions.
-}
vampireGUI :: String -- ^ theory name
           -> Theory Sign Sentence ATP_ProofTree
           -- ^ theory consisting of a SPASS.Sign.Sign
           --   and a list of Named SPASS.Sign.Sentence
           -> IO([Proof_status ATP_ProofTree]) -- ^ proof status for each goal
vampireGUI thName th =
    genericATPgui atpFun True (prover_name vampire) thName th $ ATP_ProofTree ""

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
          runProver = runVampire,
          createProverOptions = extraOpts}

{- |
  Runs the Vampire service.
-}
runVampire :: SPASSProverState
           -- ^ logical part containing the input Sign and axioms and possibly
           --   goals that have been proved earlier as additional axioms
           -> GenericConfig ATP_ProofTree -- ^ configuration to use
           -> Bool -- ^ True means save TPTP file
           -> String -- ^ name of the theory in the DevGraph
           -> AS_Anno.Named SPTerm -- ^ goal to prove
           -> IO (ATPRetval, GenericConfig ATP_ProofTree)
           -- ^ (retval, configuration with proof status and complete output)
runVampire sps cfg saveTPTP thName nGoal = do
    putStrLn ("running MathServ VampireService...")
    prob <- showTPTPProblem thName sps nGoal $ extraOpts cfg ++
                                                 ["Requested prover: Vampire"]
    when saveTPTP
        (writeFile (thName++'_':AS_Anno.senName nGoal++".tptp") prob)
    mathServOut <- callMathServ
        MathServCall{ mathServService = VampireService,
                      mathServOperation = TPTPProblem,
                      problem = prob,
                      proverTimeLimit = tLimit,
                      extraOptions = Just $ unwords $ extraOpts cfg}
    msResponse <- parseMathServOut mathServOut
    return (mapMathServResponse msResponse cfg nGoal (prover_name vampire))
    where
      tLimit = maybe (guiDefaultTimeLimit) id $ timeLimit cfg
