{- |
Module      :  $Header$
Description :  Provers for propositional logic
Copyright   :  (c) Dominik Luecke, Uni Bremen 2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@tzi.de
Stability   :  experimental
Portability :  portable

This is the connection of the SAT-Solver minisat to Hets
-}

module Propositional.Prove
    (
     zchaffProver,                   -- the zChaff II Prover
     propConsChecker
    )
    where

import qualified Logic.Prover as LP
import qualified Propositional.Sign as Sig
import qualified Propositional.AS_BASIC_Propositional as AS_BASIC
import qualified Propositional.ProverState as PState
import qualified Propositional.Morphism as PMorphism
import qualified GUI.GenericATPState as ATPState
import qualified Propositional.Conversions as Cons
import qualified Common.AS_Annotation as AS_Anno
import Proofs.BatchProcessing 
import qualified Common.Result as Result

import qualified Control.Exception as Exception
import GHC.Read (readEither)
import qualified Control.Concurrent as Concurrent

import Char
import Data.Maybe
import Data.List
import Data.Time (TimeOfDay,timeToTimeOfDay)

import System
import Directory

import ChildProcess
import ProcessClasses
import Text.Regex

import HTk

import GUI.GenericATP
import GUI.HTkUtils
-- import Debug.Trace
import IO
import qualified Common.OrderedMap as OMap
import qualified Propositional.Conversions as PC

-- * Prover implementation

zchaffHelpText :: String
zchaffHelpText = "Zchaff is a very fast SAT-Solver \n"++
                 "No additional Options are available"++
                 "for it!"

propositionalS :: String
propositionalS = "Prop"
-- | the name of the inconsistent lemma for consistency checks
zchaffS :: String
zchaffS = "zchaff"

{- |
  The Prover implementation.

  Implemented are: a prover GUI, and both commandline prover interfaces.
-}
zchaffProver :: LP.Prover Sig.Sign AS_BASIC.FORMULA Sig.ATP_ProofTree
zchaffProver = LP.emptyProverTemplate
             {
               LP.prover_name             = zchaffS
             , LP.prover_sublogic         = propositionalS
             , LP.proveGUI                = Just $ zchaffProveGUI
             , LP.proveCMDLautomatic      = Just $ zchaffProveCMDLautomatic
             , LP.proveCMDLautomaticBatch = Just $ zchaffProveCMDLautomaticBatch
             }

{- |
   The Consistency Cheker.
-}
propConsChecker :: LP.ConsChecker Sig.Sign AS_BASIC.FORMULA PMorphism.Morphism Sig.ATP_ProofTree
propConsChecker = LP.emptyProverTemplate
       { LP.prover_name = zchaffS,
         LP.prover_sublogic = propositionalS,
         LP.proveGUI = Just consCheck }

consCheck :: String 
          -> LP.TheoryMorphism Sig.Sign AS_BASIC.FORMULA PMorphism.Morphism Sig.ATP_ProofTree 
          -> IO([LP.Proof_status Sig.ATP_ProofTree])
consCheck thName tm = 
    case LP.t_target tm of
      LP.Theory sig nSens -> do
            let axioms = getAxioms $ snd $ unzip $ OMap.toList nSens
                tmpFile = "/tmp/" ++ (thName ++ "_cc.dimacs")
                resultFile = tmpFile ++ ".result"
            dimacsOutput <-  PC.ioDIMACSProblem (thName ++ "_cc")
                                sig axioms axioms
            outputHf <- openFile tmpFile ReadWriteMode
            hPutStr outputHf dimacsOutput
            hClose outputHf
            exitCode <- system ("zchaff " ++ tmpFile ++ " >> " ++ resultFile)
            removeFile tmpFile
            if exitCode /= ExitSuccess then 
                createInfoWindow "consistency checker" 
                          ("check consistency: " ++ "error by call zchaff " ++ thName)
               else do
                   resultHf <- openFile resultFile ReadMode
                   isSAT <- searchResult resultHf
                   hClose resultHf
                   removeFile resultFile
                   if isSAT then 
                       createInfoWindow "consistency checker" 
                          ("check consistency: consistent.")
                     else 
                         createInfoWindow "consistency checker" 
                          ("check consistency: inconsistent.")
            return []
            
    where
        getAxioms :: [LP.SenStatus AS_BASIC.FORMULA (LP.Proof_status Sig.ATP_ProofTree)] 
                  -> [AS_Anno.Named AS_BASIC.FORMULA]
        getAxioms f = map (AS_Anno.makeNamed "consistency" . AS_Anno.sentence) $ filter AS_Anno.isAxiom f

        searchResult :: Handle -> IO Bool
        searchResult hf = do
            eof <- hIsEOF hf
            if eof then 
                return False
              else
               do
                line <- hGetLine hf
                if line == "RESULT:\tUNSAT" then
                      return True
                  else if line == "RESULT:\tSAT" then
                          return False
                         else searchResult hf

-- ** GUI

{- |
  Invokes the generic prover GUI. 
-}
zchaffProveGUI :: String -- ^ theory name
          -> LP.Theory Sig.Sign AS_BASIC.FORMULA Sig.ATP_ProofTree 
          -> IO([LP.Proof_status Sig.ATP_ProofTree]) -- ^ proof status for each goal
zchaffProveGUI thName th =
    genericATPgui (atpFun thName) True (LP.prover_name zchaffProver) thName th
                  $ Sig.ATP_ProofTree ""
{- |
  Parses a given default tactic script into a
  'GUI.GenericATPState.ATPTactic_script' if possible.
-}
parseZchaffTactic_script :: LP.Tactic_script
                        -> ATPState.ATPTactic_script
parseZchaffTactic_script =
    parseTactic_script batchTimeLimit

{- |
  Parses a given default tactic script into a
  'GUI.GenericATPState.ATPTactic_script' if possible. Otherwise a default
  prover's tactic script is returned.
-}
parseTactic_script :: Int -- ^ default time limit (standard:
                          -- 'Proofs.BatchProcessing.batchTimeLimit')
                   -> LP.Tactic_script
                   -> ATPState.ATPTactic_script
parseTactic_script tLimit (LP.Tactic_script ts) =
    either (\_ -> ATPState.ATPTactic_script { ATPState.ts_timeLimit = tLimit,
                                              ATPState.ts_extraOpts = [] })
           id
           (readEither ts :: Either String ATPState.ATPTactic_script)

-- ** command line functions

{- |
  Implementation of 'Logic.Prover.proveCMDLautomatic' which provides an
  automatic command line interface for a single goal.
  SPASS specific functions are omitted by data type ATPFunctions.
-}
zchaffProveCMDLautomatic ::
           String -- ^ theory name
        -> LP.Tactic_script -- ^ default tactic script
        -> LP.Theory Sig.Sign AS_BASIC.FORMULA Sig.ATP_ProofTree  -- ^ theory consisting of a
                                -- signature and a list of Named sentence
        -> IO (Result.Result ([LP.Proof_status Sig.ATP_ProofTree]))
           -- ^ Proof status for goals and lemmas
zchaffProveCMDLautomatic thName defTS th =
    genericCMDLautomatic (atpFun thName) (LP.prover_name zchaffProver) thName
        (parseZchaffTactic_script defTS) th (Sig.ATP_ProofTree "")

{- |
  Implementation of 'Logic.Prover.proveCMDLautomaticBatch' which provides an
  automatic command line interface to the zchaff prover.
  zchaff specific functions are omitted by data type ATPFunctions.
-}
zchaffProveCMDLautomaticBatch ::
           Bool -- ^ True means include proved theorems
        -> Bool -- ^ True means save problem file
        -> Concurrent.MVar (Result.Result [LP.Proof_status Sig.ATP_ProofTree])
           -- ^ used to store the result of the batch run
        -> String -- ^ theory name
        -> LP.Tactic_script -- ^ default tactic script
        -> LP.Theory Sig.Sign AS_BASIC.FORMULA Sig.ATP_ProofTree -- ^ theory consisting of a
           --   'SPASS.Sign.Sign' and a list of Named 'SPASS.Sign.Sentence'
        -> IO (Concurrent.ThreadId,Concurrent.MVar ())
           -- ^ fst: identifier of the batch thread for killing it
           --   snd: MVar to wait for the end of the thread
zchaffProveCMDLautomaticBatch inclProvedThs saveProblem_batch resultMVar
                        thName defTS th =
    genericCMDLautomaticBatch (atpFun thName) inclProvedThs saveProblem_batch
        resultMVar (LP.prover_name zchaffProver) thName
        (parseZchaffTactic_script defTS) th (Sig.ATP_ProofTree "")

{- |
  Record for prover specific functions. This is used by both GUI and command
  line interface.
-}
atpFun :: String            -- Theory name
       -> ATPState.ATPFunctions Sig.Sign AS_BASIC.FORMULA Sig.ATP_ProofTree PState.PropProverState
atpFun thName = ATPState.ATPFunctions
                {
                  ATPState.initialProverState = PState.propProverState
                , ATPState.goalOutput         = Cons.goalDIMACSProblem thName
                , ATPState.atpTransSenName    = PState.transSenName
                , ATPState.atpInsertSentence  = PState.insertSentence
                , ATPState.proverHelpText     = zchaffHelpText
                , ATPState.runProver          = runZchaff
                , ATPState.batchTimeEnv       = "HETS_ZCHAFF_BATCH_TIME_LIMIT"
                , ATPState.fileExtensions     = ATPState.FileExtensions{ATPState.problemOutput = ".dimacs",
                                                                        ATPState.proverOutput = ".zchaff",
                                                                        ATPState.theoryConfiguration = ".czchaff"}
                , ATPState.createProverOptions = createZchaffOptions
                }

{- |
  Runs zchaff. zchaff is assumed to reside in PATH.
-}

runZchaff :: PState.PropProverState 
           -- logical part containing the input Sign and
           -- axioms and possibly goals that have been proved
           -- earlier as additional axioms
           -> ATPState.GenericConfig Sig.ATP_ProofTree
           -- configuration to use
           -> Bool                                     
           -- True means save DIMACS file
           -> String                                   
           -- Name of the theory
           -> AS_Anno.Named AS_BASIC.FORMULA           
           -- Goal to prove
           -> IO (ATPState.ATPRetval
                 , ATPState.GenericConfig Sig.ATP_ProofTree
                 )
           -- (retval, configuration with proof status and complete output)
runZchaff pState cfg saveDIMACS thName nGoal = 
    do
      prob <- Cons.goalDIMACSProblem thName pState nGoal [] 
      when saveDIMACS
               (writeFile (thName++'_':AS_Anno.senName nGoal++".dimacs") 
                          prob)
      (writeFile (zFileName)
                 prob)
      zchaff <- newChildProcess "zchaff" [ChildProcess.arguments allOptions]
      Exception.catch (runZchaffReal zchaff)
                   (\ excep -> do
                      -- kill zchaff process
                      destroy zchaff
                      _ <- waitForChildProcess zchaff
                      deleteJunk
                      excepToATPResult (LP.prover_name zchaffProver) nGoal excep)
    where
      deleteJunk = do
        ex <- (doesFileExist zFileName)
        when ex $ 
             do
               p <- (getPermissions zFileName)
               when (writable p == True) $
                    removeFile (zFileName)
        ex1 <- (doesFileExist "resolve_trace")
        when ex1 $
             do
               p1 <- getPermissions "resolve_trace"
               when (writable p1 == True) $
                   removeFile ("resolve_trace")       
      zFileName = "/tmp/problem_"++thName++'_':AS_Anno.senName nGoal++".dimacs"
      allOptions = zFileName : (createZchaffOptions cfg)
      runZchaffReal zchaff = 
          do
            e <- getToolStatus zchaff
            if isJust e
              then
                  do
                    deleteJunk
                    return
                      (ATPState.ATPError "Could not start zchaff. Is zchaff in your $PATH?",
                               ATPState.emptyConfig (LP.prover_name zchaffProver)
                                           (AS_Anno.senName nGoal) $ Sig.ATP_ProofTree "")
              else do
                zchaffOut <- parseProtected zchaff
                (res, usedAxs, output, tUsed) <- analyzeZchaff zchaffOut pState
                let (err, retval) = proof_stat res usedAxs [] (head output)
                deleteJunk
                return (err,
                        cfg{ATPState.proof_status = retval,
                            ATPState.resultOutput = output,
                            ATPState.timeUsed     = tUsed})
                where
                  proof_stat res usedAxs options out
                           | isJust res && elem (fromJust res) proved =
                               (ATPState.ATPSuccess,
                                (defaultProof_status options)
                                {LP.goalStatus = LP.Proved $ Nothing
                                , LP.usedAxioms = filter (/=(AS_Anno.senName nGoal)) usedAxs
                                , LP.proofTree = Sig.ATP_ProofTree $ out })
                           | isJust res && elem (fromJust res) disproved =
                               (ATPState.ATPSuccess,
                                (defaultProof_status options) {LP.goalStatus = LP.Disproved} )
                           | isJust res && elem (fromJust res) timelimit =
                               (ATPState.ATPTLimitExceeded, defaultProof_status options)
                           | isNothing res =
                               (ATPState.ATPError "Internal error.", defaultProof_status options)
                           | otherwise = (ATPState.ATPSuccess, defaultProof_status options)
                  defaultProof_status opts =
                      (LP.openProof_status (AS_Anno.senName nGoal) (LP.prover_name zchaffProver) $
                                        Sig.ATP_ProofTree "")
                      {LP.tacticScript = LP.Tactic_script $ show $ ATPState.ATPTactic_script
                                         {ATPState.ts_timeLimit = configTimeLimit cfg,
                                          ATPState.ts_extraOpts = opts} }

proved :: [String]
proved = ["Proof found."]
disproved :: [String]
disproved = ["Completion found."]
timelimit :: [String]
timelimit = ["Ran out of time."]

-- | analysis of output 
analyzeZchaff :: String 
              ->  PState.PropProverState 
              -> IO (Maybe String, [String], [String], TimeOfDay)
analyzeZchaff str pState = 
    let 
        str' = foldr (\ch li -> if ch == '\x9'
                                then ""++li
                                else ch:li) "" str
        str2 = foldr (\ch li -> if ch == '\x9'
                                then "        "++li
                                else ch:li) "" str
        output = [str2]
        unsat  = (\xv ->
                      case xv of 
                        Just _  -> True
                        Nothing -> False
            ) $ matchRegex re_UNSAT str'
        sat    = (\xv ->
                      case xv of 
                        Just _  -> True
                        Nothing -> False
                    ) $ matchRegex re_SAT   str'
        timeLine = (\xv ->
                      case xv of 
                        Just yv  -> head yv
                        Nothing  -> "Total Run Time0"
                    ) $ matchRegex re_TIME str'
        timeout =  ((\xv ->
                    case xv of 
                      Just _  -> True
                      Nothing -> False
                   ) $ matchRegex re_end_to str')
                  ||
                  ((\xv ->
                   case xv of 
                     Just _  -> True
                     Nothing -> False
                  ) $ matchRegex re_end_mo str')
        time   = calculateTime timeLine
        usedAx = map (AS_Anno.senAttr) $ PState.initialAxioms pState
    in
      if timeout 
      then 
          return (Just $ head timelimit, usedAx, output, time)
          else
              if (sat && (not unsat)) 
              then
                  return (Just $ head $ disproved, usedAx, output, time)
              else if ((not sat) && unsat)
                   then
                       return (Just $ head $ proved, usedAx, output, time)
                   else
                       do
                         return (Nothing, usedAx, output, time)

-- | Calculated the time need for the proof in seconds
calculateTime :: String -> TimeOfDay
calculateTime timeLine = 
    timeToTimeOfDay $ realToFrac $ ((read $ subRegex re_SUBPOINT 
               (subRegex re_SUBTIME timeLine "") "")::Float)
      
re_UNSAT :: Regex  
re_UNSAT = mkRegex "(.*)RESULT:UNSAT(.*)"
re_SAT :: Regex
re_SAT   = mkRegex "(.*)RESULT:SAT(.*)"
re_TIME :: Regex
re_TIME  = mkRegex "Total Run Time(.*)"
re_SUBTIME :: Regex
re_SUBTIME = mkRegex "Total Run Time"
re_SUBPOINT :: Regex
re_SUBPOINT = mkRegex ".(.*)"

-- | Helper for reading zChaff output
parseProtected :: ChildProcess -> IO String
parseProtected zchaff = do
  e <- getToolStatus zchaff
  case e of 
    Nothing                   -> 
        do  
          miniOut <- parseIt zchaff
          _   <- waitForChildProcess zchaff
          return miniOut
    Just (ExitFailure retval) -> 
        do
          _ <- waitForChildProcess zchaff
          return ("Error!!! Cause was: " ++ show retval)
    Just ExitSuccess          -> 
        do  
          miniOut <- parseIt zchaff
          _   <- waitForChildProcess zchaff
          return miniOut       

-- | Helper function for parsing zChaff output
parseIt :: ChildProcess -> IO String
parseIt zchaff = do
  line <- return ""
  msg  <- parseItHelp zchaff $ return line
  return msg

-- | Helper function for parsing zChaff output
parseItHelp :: ChildProcess -> IO String -> IO String
parseItHelp zchaff inp = do
  e <- getToolStatus zchaff
  inT <- inp
  case e of 
    Nothing
         -> 
           do
             line <- readMsg zchaff
             case isEnd line of
               True -> 
                   return (inT ++ "\n" ++ line)
               _    ->
                   do
                     parseItHelp zchaff $ return (inT ++ "\n" ++ line)
    Just (ExitFailure retval)
        -- returned error
        -> do
           _ <- waitForChildProcess zchaff
           return $ "zchaff returned error: "++(show retval)
    Just ExitSuccess
         -- completed successfully. read remaining output.
         -> 
           do
             line <- readMsg zchaff
             case isEnd line of
               True -> 
                   return (inT ++ "\n" ++ line)
               _    ->
                   do
                     parseItHelp zchaff $ return (inT ++ "\n" ++ line)
  
-- | We are searching for Flotter needed to determine the end of input
isEnd :: String -> Bool
isEnd inS = ((\xv ->
                 case xv of 
                   Just _  -> True
                   Nothing -> False
            ) $ matchRegex re_end inS)
            ||
            ((\xv ->
                 case xv of 
                   Just _  -> True
                   Nothing -> False
            ) $ matchRegex re_end_to inS)
            ||
            ((\xv ->
                 case xv of 
                   Just _  -> True
                   Nothing -> False
            ) $ matchRegex re_end_mo inS)

re_end :: Regex
re_end = mkRegex "(.*)RESULT:(.*)"
re_end_to :: Regex
re_end_to = mkRegex "(.*)TIME OUT(.*)"
re_end_mo :: Regex
re_end_mo = mkRegex "(.*)MEM OUT(.*)"

-- | Converts a thrown exception into an ATP result (ATPRetval and proof tree).
excepToATPResult :: String 
                 -- ^ name of running prover
                 -> AS_Anno.Named AS_BASIC.FORMULA 
                 -- ^ goal to prove
                 -> Exception.Exception 
                 -- ^ occured exception
                 -> IO (ATPState.ATPRetval, 
                        ATPState.GenericConfig Sig.ATP_ProofTree) 
                    -- ^ (retval,
                    -- configuration with proof status and complete output)
excepToATPResult prName nGoal excep = return $ case excep of
    -- this is supposed to distinguish "fd ... vanished"
    -- errors from other exceptions
    Exception.IOException e ->
        (ATPState.ATPError ("Internal error communicating with " ++ 
                            prName ++ ".\n"
                            ++ show e), emptyCfg)
    Exception.AsyncException Exception.ThreadKilled ->
        (ATPState.ATPBatchStopped, emptyCfg)
    _ -> (ATPState.ATPError ("Error running " ++ prName ++ ".\n" 
                             ++ show excep),
          emptyCfg)
  where
    emptyCfg = ATPState.emptyConfig prName (AS_Anno.senName nGoal) $ 
               Sig.ATP_ProofTree ""

{- |
  Returns the time limit from GenericConfig if available. Otherwise
  guiDefaultTimeLimit is returned.
-}
configTimeLimit :: ATPState.GenericConfig Sig.ATP_ProofTree
                -> Int
configTimeLimit cfg = 
    maybe (guiDefaultTimeLimit) id $ ATPState.timeLimit cfg

{- |
  Creates a list of all options the zChaff prover runs with.
  Only Option is the timelimit
-}
createZchaffOptions :: ATPState.GenericConfig Sig.ATP_ProofTree -> [String]
createZchaffOptions cfg =
    [(show $ configTimeLimit cfg)]
