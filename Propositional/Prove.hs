{- |
Module      :  $Header$
Description :  Provers for propositional logic
Copyright   :  (c) Dominik Luecke, Uni Bremen 2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  experimental
Portability :  portable

This is the connection of the SAT-Solver minisat to Hets
-}

module Propositional.Prove
    ( zchaffProver                   -- the zChaff II Prover
    , propConsChecker
    ) where

import qualified Propositional.AS_BASIC_Propositional as AS_BASIC
import qualified Propositional.Conversions as Cons
import qualified Propositional.Conversions as PC
import qualified Propositional.Morphism as PMorphism
import qualified Propositional.ProverState as PState
import qualified Propositional.Sign as Sig
import Propositional.Sublogic (PropSL, top)
import Propositional.ChildMessage

import Proofs.BatchProcessing

import qualified Logic.Prover as LP

import Interfaces.GenericATPState
import GUI.GenericATP

import Common.UniUtils as CP

import Common.ProofTree
import Common.Utils (readMaybe, basename)
import qualified Common.AS_Annotation as AS_Anno
import qualified Common.Id as Id
import qualified Common.OrderedMap as OMap
import qualified Common.Result as Result

import Control.Monad (when)
import qualified Control.Concurrent as Concurrent
import qualified Control.Exception as Exception

import Data.List
import Data.Maybe
import Data.Time (TimeOfDay, timeToTimeOfDay, midnight)

import System.Directory
import System.Cmd
import System.Exit
import System.IO

-- * Prover implementation

zchaffHelpText :: String
zchaffHelpText = "Zchaff is a very fast SAT-Solver \n" ++
                 "No additional Options are available" ++
                 "for it!"

-- | the name of the prover
zchaffS :: String
zchaffS = "zchaff"

{- |
  The Prover implementation.

  Implemented are: a prover GUI, and both commandline prover interfaces.
-}
zchaffProver
  :: LP.Prover Sig.Sign AS_BASIC.FORMULA PMorphism.Morphism PropSL ProofTree
zchaffProver = LP.mkAutomaticProver zchaffS top zchaffProveGUI
  zchaffProveCMDLautomaticBatch

{- |
   The Consistency Cheker.
-}
propConsChecker :: LP.ConsChecker Sig.Sign AS_BASIC.FORMULA PropSL
                                  PMorphism.Morphism ProofTree
propConsChecker = LP.mkConsChecker zchaffS top consCheck

consCheck :: String -> LP.TacticScript
   -> LP.TheoryMorphism Sig.Sign AS_BASIC.FORMULA PMorphism.Morphism ProofTree
   -> [LP.FreeDefMorphism AS_BASIC.FORMULA PMorphism.Morphism]
    -- ^ free definitions
   -> IO (LP.CCStatus ProofTree)
consCheck thName _ tm _ =
    case LP.tTarget tm of
      LP.Theory sig nSens -> do
            let axioms = getAxioms $ snd $ unzip $ OMap.toList nSens
                thName_clean = basename thName
                tmpFile = "/tmp/" ++ thName_clean ++ "_cc.dimacs"
                resultFile = tmpFile ++ ".result"
            dimacsOutput <- PC.showDIMACSProblem (thName ++ "_cc")
                             sig [(AS_Anno.makeNamed "myAxioms" $
                                     AS_BASIC.Implication
                                     (
                                      AS_BASIC.Conjunction
                                      (map AS_Anno.sentence axioms)
                                      Id.nullRange
                                     )
                                     (AS_BASIC.False_atom Id.nullRange)
                                     Id.nullRange
                                    )
                                    {
                                      AS_Anno.isAxiom = True
                                    , AS_Anno.isDef = False
                                    , AS_Anno.wasTheorem = False
                                    }
                                   ] []
            outputHf <- openFile tmpFile ReadWriteMode
            hPutStr outputHf dimacsOutput
            hClose outputHf
            exitCode <- system ("zchaff " ++ tmpFile ++ " >> " ++ resultFile)
            removeFile tmpFile
            if exitCode /= ExitSuccess then return $ LP.CCStatus
                   (ProofTree $ "error by call zchaff " ++ thName)
                   midnight Nothing
               else do
                   resultHf <- readFile resultFile
                   let isSAT = searchResult resultHf
                   when (length resultHf > 0) $ removeFile resultFile
                   return $ LP.CCStatus (ProofTree resultHf) midnight isSAT

    where
        getAxioms :: [LP.SenStatus AS_BASIC.FORMULA (LP.ProofStatus ProofTree)]
                  -> [AS_Anno.Named AS_BASIC.FORMULA]
        getAxioms f = map (AS_Anno.makeNamed "consistency" . AS_Anno.sentence)
          $ filter AS_Anno.isAxiom f
        searchResult :: String -> Maybe Bool
        searchResult hf = let ls = lines hf in
          if any (isInfixOf reUNSAT) ls then Just True else
          if any (isInfixOf reSAT) ls then Just False
          else Nothing

-- ** GUI

{- |
  Invokes the generic prover GUI.
-}
zchaffProveGUI :: String -- ^ theory name
          -> LP.Theory Sig.Sign AS_BASIC.FORMULA ProofTree
          -> [LP.FreeDefMorphism AS_BASIC.FORMULA PMorphism.Morphism]
          -- ^ free definitions
          -> IO [LP.ProofStatus ProofTree] -- ^ proof status for each goal
zchaffProveGUI thName th freedefs =
    genericATPgui (atpFun thName) True (LP.proverName zchaffProver) thName th
                  freedefs emptyProofTree
{- |
  Parses a given default tactic script into a
  'Interfaces.GenericATPState.ATPTacticScript' if possible.
-}
parseZchaffTacticScript :: LP.TacticScript -> ATPTacticScript
parseZchaffTacticScript = parseTacticScript batchTimeLimit []

-- ** command line function

{- |
  Implementation of 'Logic.Prover.proveCMDLautomaticBatch' which provides an
  automatic command line interface to the zchaff prover.
  zchaff specific functions are omitted by data type ATPFunctions.
-}
zchaffProveCMDLautomaticBatch ::
           Bool -- ^ True means include proved theorems
        -> Bool -- ^ True means save problem file
        -> Concurrent.MVar (Result.Result [LP.ProofStatus ProofTree])
           -- ^ used to store the result of the batch run
        -> String -- ^ theory name
        -> LP.TacticScript -- ^ default tactic script
        -> LP.Theory Sig.Sign AS_BASIC.FORMULA ProofTree
        -- ^ theory consisting of a signature and a list of Named sentences
        -> [LP.FreeDefMorphism AS_BASIC.FORMULA PMorphism.Morphism]
        -- ^ free definitions
        -> IO (Concurrent.ThreadId, Concurrent.MVar ())
           {- ^ fst: identifier of the batch thread for killing it
           snd: MVar to wait for the end of the thread -}
zchaffProveCMDLautomaticBatch inclProvedThs saveProblem_batch resultMVar
                        thName defTS th freedefs =
    genericCMDLautomaticBatch (atpFun thName) inclProvedThs saveProblem_batch
        resultMVar (LP.proverName zchaffProver) thName
        (parseZchaffTacticScript defTS) th freedefs emptyProofTree

{- |
  Record for prover specific functions. This is used by both GUI and command
  line interface.
-}
atpFun :: String            -- Theory name
  -> ATPFunctions Sig.Sign AS_BASIC.FORMULA PMorphism.Morphism ProofTree
     PState.PropProverState
atpFun thName = ATPFunctions
                { initialProverState = PState.propProverState
                , goalOutput = Cons.goalDIMACSProblem thName
                , atpTransSenName = PState.transSenName
                , atpInsertSentence = PState.insertSentence
                , proverHelpText = zchaffHelpText
                , runProver = runZchaff
                , batchTimeEnv = "HETS_ZCHAFF_BATCH_TIME_LIMIT"
                , fileExtensions = FileExtensions
                    { problemOutput = ".dimacs"
                    , proverOutput = ".zchaff"
                    , theoryConfiguration = ".czchaff"}
                , createProverOptions = createZchaffOptions }

{- |
  Runs zchaff. zchaff is assumed to reside in PATH.
-}

runZchaff :: PState.PropProverState
           {- logical part containing the input Sign and
           axioms and possibly goals that have been proved
           earlier as additional axioms -}
           -> GenericConfig ProofTree
           -- configuration to use
           -> Bool
           -- True means save DIMACS file
           -> String
           -- Name of the theory
           -> AS_Anno.Named AS_BASIC.FORMULA
           -- Goal to prove
           -> IO (ATPRetval
                 , GenericConfig ProofTree
                 )
           -- (retval, configuration with proof status and complete output)
runZchaff pState cfg saveDIMACS thName nGoal =
    do
      prob <- Cons.goalDIMACSProblem thName pState nGoal []
      when saveDIMACS (writeFile thName_clean prob)
      writeFile zFileName prob
      zchaff <- newChildProcess "zchaff" [CP.arguments allOptions]
      Exception.catch (runZchaffReal zchaff)
                   (\ excep -> do
                      -- kill zchaff process
                      destroy zchaff
                      _ <- waitForChildProcess zchaff
                      deleteJunk
                      excepToATPResult (LP.proverName zchaffProver)
                        (AS_Anno.senAttr nGoal) excep)
    where
      deleteJunk = do
        catch (removeFile zFileName) (const $ return ())
        catch (removeFile "resolve_trace") (const $ return ())
      thName_clean = basename thName ++ '_' : AS_Anno.senAttr nGoal ++ ".dimacs"
      zFileName = "/tmp/problem_" ++ thName_clean
      allOptions = zFileName : createZchaffOptions cfg
      runZchaffReal zchaff =
          do
                zchaffOut <- parseIt zchaff isEnd
                (res, usedAxs, output, tUsed) <- analyzeZchaff zchaffOut pState
                let (err, retval) = proofStat res usedAxs [] (head output)
                deleteJunk
                return (err,
                        cfg {proofStatus = retval,
                            resultOutput = output,
                            timeUsed = tUsed})
                where
                  proofStat res usedAxs options out
                           | isJust res && elem (fromJust res) proved =
                               (ATPSuccess,
                                (defaultProofStatus options)
                                {LP.goalStatus = LP.Proved True
                                , LP.usedAxioms = filter
                                    (/= AS_Anno.senAttr nGoal) usedAxs
                                , LP.proofTree = ProofTree out })
                           | isJust res && elem (fromJust res) disproved =
                               (ATPSuccess,
                                (defaultProofStatus options)
                                {LP.goalStatus = LP.Disproved} )
                           | isJust res && elem (fromJust res) timelimit =
                               (ATPTLimitExceeded, defaultProofStatus options)
                           | isNothing res =
                               (ATPError "Internal error.",
                                defaultProofStatus options)
                           | otherwise = (ATPSuccess,
                                          defaultProofStatus options)
                  defaultProofStatus opts =
                      (LP.openProofStatus (AS_Anno.senAttr nGoal)
                             (LP.proverName zchaffProver)
                                        emptyProofTree)
                      {LP.tacticScript = LP.TacticScript $ show
                            ATPTacticScript
                             { tsTimeLimit = configTimeLimit cfg
                             , tsExtraOpts = opts} }

proved :: [String]
proved = ["Proof found."]

disproved :: [String]
disproved = ["Completion found."]

timelimit :: [String]
timelimit = ["Ran out of time."]

-- | analysis of output
analyzeZchaff :: String
              -> PState.PropProverState
              -> IO (Maybe String, [String], [String], TimeOfDay)
analyzeZchaff str' pState =
    let output = [str']
        unsat = isInfixOf reUNSAT str'
        sat = isInfixOf reSAT str'
        timeLine = fromMaybe "0" $ stripPrefix reTIME str'
        timeout = isInfixOf reEndto str' || isInfixOf reEndmo str'
        time = calculateTime timeLine
        usedAx = map AS_Anno.senAttr $ PState.initialAxioms pState
    in return $ if timeout
      then (Just $ head timelimit, usedAx, output, time)
      else if sat && not unsat
           then (Just $ head disproved, usedAx, output, time)
           else if not sat && unsat
                then (Just $ head proved, usedAx, output, time)
                else (Nothing, usedAx, output, time)

-- | Calculated the time need for the proof in seconds
calculateTime :: String -> TimeOfDay
calculateTime timeLine =
    timeToTimeOfDay $ realToFrac (fromMaybe
         (error $ "calculateTime " ++ timeLine) $ readMaybe timeLine
             :: Double)

reUNSAT :: String
reUNSAT = "RESULT:\tUNSAT"
reSAT :: String
reSAT = "RESULT:\tSAT"
reTIME :: String
reTIME = "Total Run Time"

-- | We are searching for Flotter needed to determine the end of input
isEnd :: String -> Bool
isEnd inS = any (`isInfixOf` inS) ["RESULT:", reEndto, reEndmo]

reEndto :: String
reEndto = "TIME OUT"
reEndmo :: String
reEndmo = "MEM OUT"

{- |
  Creates a list of all options the zChaff prover runs with.
  Only Option is the timelimit
-}
createZchaffOptions :: GenericConfig ProofTree -> [String]
createZchaffOptions cfg =
    [show $ configTimeLimit cfg]
