{- |
Module      :  $Header$
Description :  Import data generated by hol2hets into a DG
Copyright   :  (c) Jonathan von Schroeder, DFKI GmbH 2010
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  jonathan.von_schroeder@dfki.de
Stability   :  experimental
Portability :  portable

-}

module Isabelle.Isa2DG where

import Static.GTheory
import Static.DevGraph

import Static.DgUtils
import Static.History
import Static.ComputeTheory

import Logic.Prover
import Logic.ExtSign
import Logic.Grothendieck

import Common.LibName
import Common.Id
import Common.AS_Annotation
import Common.IRI (simpleIdToIRI)

import Isabelle.Logic_Isabelle
import Isabelle.IsaSign
import Isabelle.IsaConsts (mkVName)
import Isabelle.IsaImport (importIsaDataIO)

import Driver.Options

import qualified Data.Map as Map

import Control.Monad (unless)
import Control.Concurrent (forkIO,killThread)

import Common.Utils
import System.Exit
import System.Directory
import System.FilePath.Posix

makeNamedSentence :: (String, Term) -> Named Sentence
makeNamedSentence (n, t) = makeNamed n $ mkSen t

_insNodeDG :: Sign -> [Named Sentence] -> String
              -> DGraph -> DGraph
_insNodeDG sig sens n dg =
 let gt = G_theory Isabelle Nothing (makeExtSign Isabelle sig) startSigId
           (toThSens sens) startThId
     labelK = newInfoNodeLab
      (makeName (simpleIdToIRI (mkSimpleId n)))
      (newNodeInfo DGEmpty)
      gt
     k = getNewNodeDG dg
     insN = [InsertNode (k, labelK)]
     newDG = changesDGH dg insN
     labCh = [SetNodeLab labelK (k, labelK
      { globalTheory = computeLabelTheory Map.empty newDG
        (k, labelK) })]
     newDG1 = changesDGH newDG labCh in newDG1

analyzeMessages :: Int -> [String] -> IO ()
analyzeMessages _ []     = return ()
analyzeMessages i (x:xs) = do
 case x of
  'v':i':':':msg -> if (read [i']) < i then putStr $ msg ++ "\n"
                                 else return ()
  _ -> putStr $ x ++ "\n"
 analyzeMessages i xs

anaThyFile :: HetcatsOpts -> FilePath -> IO (Maybe (LibName, LibEnv))
anaThyFile opts path = do
 fp <- canonicalizePath path
 tempFile <- getTempFile "" (takeBaseName fp)
 fifo <- getTempFifo (takeBaseName fp)
 exportScript' <- fmap (</> "export.sh") $ getEnvDef
  "HETS_ISA_TOOLS" "./Isabelle/export"
 exportScript <- canonicalizePath exportScript'
 e1 <- doesFileExist exportScript
 unless e1 $ fail $ "Export script not available! Maybe you need to specify HETS_ISA_TOOLS"
 (l,close) <- readFifo fifo
 tid <- forkIO $ analyzeMessages (verbose opts) (lines . concat $ l)
 (ex, sout, err) <- executeProcess exportScript [fp,tempFile,fifo] ""
 close
 killThread tid
 removeFile fifo
 case ex of
  ExitFailure _ -> do
   removeFile tempFile
   soutF <- getTempFile sout ((takeBaseName fp) ++ ".sout")
   errF <- getTempFile err ((takeBaseName fp) ++ ".serr")
   fail $ "Export Failed! - Export script died prematurely. See " ++ soutF
          ++ " and " ++ errF ++ " for details."
  ExitSuccess -> do
   ret <- anaIsaFile opts tempFile
   removeFile tempFile
   return ret

anaIsaFile :: HetcatsOpts -> FilePath -> IO (Maybe (LibName, LibEnv))
anaIsaFile _ path = do
 (name,imps,consts,axioms,theorems,types,classes,locales')
   <- importIsaDataIO path
 let sens = map makeNamedSentence (axioms ++ theorems
             ++ (foldl (\ l c -> case c of
                          (_,_,Nothing) -> l
                          (n,_,Just tm) -> (n,tm):l) [] consts))
 let sgn = emptySign { constTab = foldl (\ m (n,t,_) -> Map.insert (mkVName n) t m) Map.empty consts, domainTab = types, imports = imps,
   tsig = emptyTypeSig { classrel = Map.fromList classes,
   locales = Map.fromList locales' }}
 let dg = _insNodeDG sgn sens name emptyDG
     le = Map.insert (emptyLibName name)
           dg Map.empty
 return $ Just (emptyLibName name,
  computeLibEnvTheories le)
