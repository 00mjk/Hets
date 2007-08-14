{- |
Module      :  $Header$
Description :  interface to the Isabelle theorem prover
Copyright   :  (c) University of Cambridge, Cambridge, England
               adaption (c) Till Mossakowski, Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

Interface for Isabelle theorem prover.
-}
{-
  Interface between Isabelle and Hets:
   Hets writes Isabelle .thy file and starts Isabelle
   User extends .thy file with proofs
   User finishes Isabelle
   Hets reads in created *.deps files
-}

module Isabelle.IsaProve where

import Logic.Prover
import Isabelle.IsaSign
import Isabelle.IsaConsts
import Isabelle.IsaPrint
import Isabelle.IsaParse
import Isabelle.Translate

import Common.AS_Annotation
import Common.DocUtils
import Common.DefaultMorphism
import Common.ProofUtils
import qualified Data.Map as Map
import qualified Data.Set as Set

import Text.ParserCombinators.Parsec

import Driver.Options

import Data.Char
import Control.Monad

import System.Directory
import System.Environment
import System.Exit
import System.Cmd

isabelleS :: String
isabelleS = "Isabelle"

isabelleProver :: Prover Sign Sentence () ()
isabelleProver = emptyProverTemplate
        { prover_name = isabelleS,
          prover_sublogic = (),
          proveGUI = Just isaProve }

isabelleConsChecker :: ConsChecker Sign Sentence () (DefaultMorphism Sign) ()
isabelleConsChecker = emptyProverTemplate
       { prover_name = "Isabelle-refute",
         prover_sublogic = (),
         proveGUI = Just consCheck }

openIsaProof_status :: String -> Proof_status ()
openIsaProof_status n = openProof_status n (prover_name isabelleProver) ()

-- | the name of the inconsistent lemma for consistency checks
inconsistentS :: String
inconsistentS = "inconsistent"

consCheck :: String -> TheoryMorphism Sign Sentence (DefaultMorphism Sign) ()
          -> IO([Proof_status ()])
consCheck thName tm = case t_target tm of
    Theory sig nSens -> let (axs, _) = getAxioms $ toNamedList nSens in
       isaProve (thName ++ "_c") $
           Theory sig
               $ markAsGoal $ toThSens $ if null axs then [] else
                   [ makeNamed inconsistentS $ mkRefuteSen $ termAppl notOp
                     $ foldr1 binConj $ map (senTerm . sentence) axs ]

prepareTheory :: Theory Sign Sentence ()
    -> (Sign, [Named Sentence], [Named Sentence], Map.Map String String)
prepareTheory (Theory sig nSens) = let
    oSens = toNamedList nSens
    nSens' = prepareSenNames transString oSens
    (disAxs, disGoals) = getAxioms nSens'
    in (sig, map markSimp disAxs, map markSimp disGoals,
       Map.fromList $ zip (map senName nSens') $ map senName oSens)
-- return a reverse mapping for renamed sentences

removeDepFiles :: String -> [String] -> IO ()
removeDepFiles thName = mapM_ $ \ thm -> do
  let depFile = getDepsFileName thName thm
  ex <- doesFileExist depFile
  when ex $ removeFile depFile

getDepsFileName :: String -> String -> String
getDepsFileName thName thm = thName ++ "_" ++ thm ++ ".deps"

getProofDeps :: Map.Map String String -> String -> String
             -> IO (Proof_status ())
getProofDeps m thName thm = do
    let file = getDepsFileName thName thm
        mapN n = Map.findWithDefault n n m
        strip = takeWhile (not . isSpace) . dropWhile isSpace
    b <- checkInFile file
    if b then do
        s <- readFile file
        return $ mkProved (mapN thm) $ map mapN $
               Set.toList $ Set.filter (not . null) $
               Set.fromList $ map strip $ lines s
      else return $ openIsaProof_status $ mapN thm

getAllProofDeps :: Map.Map String String -> String -> [String]
                -> IO([Proof_status ()])
getAllProofDeps m thName = mapM $ getProofDeps m thName

checkFinalThyFile :: (TheoryHead, Body) -> String -> IO Bool
checkFinalThyFile (ho, bo) thyFile = do
  s <- readFile thyFile
  case parse parseTheory thyFile s of
    Right (hb, b) -> do
            let ds = compatibleBodies bo b
            mapM_ (\ d -> putStrLn $ showDoc d "") $ ds ++ warnSimpAttr b
            if hb /= ho then do
                  putStrLn "illegal change of theory header"
                  return False
              else return $ null ds
    Left err -> putStrLn (show err) >> return False

mkProved :: String -> [String] -> Proof_status ()
mkProved thm used = (openIsaProof_status thm)
    { goalStatus = Proved Nothing
    , usedAxioms = used
    , tacticScript = Tactic_script "unknown isabelle user input"
    }

prepareThyFiles :: (TheoryHead, Body) -> String -> String -> IO ()
prepareThyFiles ast thyFile thy = do
    let origFile = thyFile ++ ".orig"
    exOrig <- checkInFile origFile
    exThyFile <- checkInFile thyFile
    if exOrig then return () else writeFile origFile thy
    if exThyFile then return () else writeFile thyFile thy
    thy_time <- getModificationTime thyFile
    orig_time <- getModificationTime origFile
    s <- readFile origFile
    unless (thy_time >= orig_time && s == thy)
      $ patchThyFile ast origFile thyFile thy

patchThyFile :: (TheoryHead, Body) -> FilePath -> FilePath -> String -> IO ()
patchThyFile (ho, bo) origFile thyFile thy = do
  let patchFile = thyFile ++ ".patch"
      oldFile = thyFile ++ ".old"
      diffCall = "diff -u " ++ origFile ++ " " ++ thyFile
                 ++ " > " ++ patchFile
      patchCall = "patch -bfu " ++ thyFile ++ " " ++ patchFile
  callSystem diffCall
  renameFile thyFile oldFile
  removeFile origFile
  writeFile origFile thy
  writeFile thyFile thy
  callSystem patchCall
  s <- readFile thyFile
  case parse parseTheory thyFile s of
    Right (hb, b) -> do
            let ds = compatibleBodies bo b
                h = hb == ho
            mapM_ (\ d -> putStrLn $ showDoc d "") ds
            unless h $ putStrLn "theory header is corrupt"
            unless (h && null ds) $ revertThyFile thyFile thy
    Left err -> do
      putStrLn $ show err
      revertThyFile thyFile thy

revertThyFile :: String -> String -> IO ()
revertThyFile thyFile thy = do
    putStrLn $ "replacing corrupt file " ++ show thyFile
    removeFile thyFile
    writeFile thyFile thy

callSystem :: String -> IO ExitCode
callSystem s = putStrLn s >> system s

isaProve :: String -> Theory Sign Sentence () -> IO([Proof_status ()])
isaProve thName th = do
  let (sig, axs, ths, m) = prepareTheory th
      thms = map senName ths
      thBaseName = reverse . takeWhile (/= '/') $ reverse thName
      thy = shows (printIsaTheory thBaseName sig $ axs ++ ths) "\n"
      thyFile = thBaseName ++ ".thy"
  case parse parseTheory thyFile thy of
    Right (ho, bo) -> do
      prepareThyFiles (ho, bo) thyFile thy
      removeDepFiles thBaseName thms
      isabelleEnv <- getEnv "HETS_ISABELLE"
      let isabelle = if null isabelleEnv then "Isabelle" else isabelleEnv
      callSystem $ isabelle ++ " " ++ thyFile
      ok <- checkFinalThyFile (ho, bo) thyFile
      if ok then getAllProofDeps m thBaseName thms
          else return []
    Left err -> do
      putStrLn $ show err
      putStrLn $ "Sorry, generated theory cannot be parsed, see: " ++ thyFile
      writeFile thyFile thy
      putStrLn "aborting Isabelle proof attempt"
      return []

markSimp :: Named Sentence -> Named Sentence
markSimp s = if isDef s then s else
             mapNamed (markSimpSen isSimpRuleSen) s

markSimpSen :: (Sentence -> Bool) -> Sentence -> Sentence
markSimpSen f s = case s of
                  Sentence {} -> s {isSimp = f s}
                  _ -> s

isSimpRuleSen :: Sentence -> Bool
isSimpRuleSen sen = case sen of
    RecDef {} -> False
    _ -> isSimpRule $ senTerm sen

-- | test whether a formula should be put into the simpset
isSimpRule :: Term -> Bool
-- only universal quantifications
isSimpRule trm = case trm of
    App (Const q _) arg@Abs{} _
        | new q == exS || new q == ex1S -> False
        | new q == allS  -> isSimpRule (termId arg)
    App (App (Const q _) a1 _) a2 _
        | new q == eq -> sizeOfTerm a1 > sizeOfTerm a2
        | new q == impl -> sizeOfTerm a1 < sizeOfTerm a2
    _ -> True

sizeOfTerm :: Term -> Int
sizeOfTerm trm = case trm of
    Abs { termId = t } -> sizeOfTerm t + 1
    App { funId = t1, argId = t2 } -> sizeOfTerm t1 + sizeOfTerm t2
    If { ifId = t1, thenId = t2, elseId = t3 } ->
        sizeOfTerm t1 + max (sizeOfTerm t2) (sizeOfTerm t3)
    Case { termId = t1, caseSubst = cs } ->
        sizeOfTerm t1 + foldr max 0 (map (sizeOfTerm . snd) cs)
    Let { letSubst = es, inId = t } ->
        sizeOfTerm t + sum (map (sizeOfTerm . snd) es)
    IsaEq { firstTerm = t1, secondTerm = t2 } ->
        sizeOfTerm t1 + sizeOfTerm t2 + 1
    Tuplex ts _ -> sum $ map sizeOfTerm ts
    _ -> 1
