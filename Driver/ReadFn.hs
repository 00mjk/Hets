{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, C. Maeder, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luettich@tzi.de
Stability   :  provisional
Portability :  non-portable(DevGraph)

reading ATerms, CASL, HetCASL files and parsing them into an
   appropriate data structure
-}

module Driver.ReadFn where

import Logic.Logic
import Logic.Grothendieck
import Syntax.AS_Library
import Syntax.Parse_AS_Library
import Syntax.Print_AS_Library()
import Static.DevGraph
import Proofs.EdgeUtils

import ATC.AS_Library()
import ATC.DevGraph()
import ATC.GlobalAnnotations()
import ATC.Sml_cats

import Common.ATerm.Lib
import Common.ATerm.ReadWrite
import qualified Common.Lib.Map as Map
import Common.AnnoState
import Common.Id
import Common.Result
import Common.PrettyPrint
import Text.ParserCombinators.Parsec

import Driver.Options
import System.Directory
import Control.Monad
import Data.List

read_LIB_DEFN_M :: Monad m => LogicGraph -> AnyLogic -> HetcatsOpts
                -> FilePath -> String -> m LIB_DEFN
read_LIB_DEFN_M lgraph defl opts file input =
    if null input then fail ("empty input file: " ++ file) else
    case intype opts of
    ATermIn _  -> return $ from_sml_ATermString input
    ASTreeIn _ -> fail "Abstract Syntax Trees aren't implemented yet"
    _ -> case runParser (library (defl, lgraph)) (emptyAnnos defl)
              file input of
         Left err  -> fail (showErr err)
         Right ast -> return ast

readShATermFile :: ShATermConvertible a => FilePath -> IO (Result a)
readShATermFile fp = do
    str <- readFile fp
    r <- return $ fromShATermString str
    case r of
      Result _ Nothing -> removeFile fp
      _ -> return ()
    return r

fromVersionedATT :: ShATermConvertible a => ATermTable -> Result a
fromVersionedATT att =
    case getATerm att of
    ShAAppl "hets" [versionnr,aterm] [] ->
        if hetsVersion == snd (fromShATermAux versionnr att)
        then Result [] (Just $ snd $ fromShATermAux aterm att)
        else Result [Diag Warning
                     "Wrong version number ... re-analyzing"
                     nullRange] Nothing
    _  ->  Result [Diag Warning
                   "Couldn't convert ShATerm back from ATermTable"
                   nullRange] Nothing

fromShATermString :: ShATermConvertible a => String -> Result a
fromShATermString str = if null str then
    Result [Diag Warning "got empty string from file" nullRange] Nothing
    else fromVersionedATT $ readATerm str

readVerbose :: ShATermConvertible a => HetcatsOpts -> LIB_NAME -> FilePath
            -> IO (Maybe a)
readVerbose opts ln file = do
    putIfVerbose opts 1 $ "Reading " ++ file
    Result ds mgc <- readShATermFile file
    showDiags opts ds
    case mgc of
      Nothing -> return Nothing
      Just (ln2, a) -> do
        unless (ln2 == ln) $
               putIfVerbose opts 0 $ "incompatible library names: "
               ++ showPretty ln " (requested) vs. "
               ++ showPretty ln2 " (found)"
        return $ Just a

-- | create a file name without suffix from a library name
libNameToFile :: HetcatsOpts -> LIB_NAME -> FilePath
libNameToFile opts ln =
           case getLIB_ID ln of
                Indirect_link file _ ->
                  let path = libdir opts
                     -- add trailing "/" if necessary
                  in pathAndBase path file
                Direct_link _ _ -> error "libNameToFile"

-- | convert a file name that may have a suffix to a library name
fileToLibName :: HetcatsOpts -> FilePath -> LIB_NAME
fileToLibName opts efile =
    let path = libdir opts
        file = rmSuffix efile -- cut of extension
        nfile = dropWhile (== '/') $         -- cut off leading slashes
                if isPrefixOf path file
                then drop (length path) file -- cut off libdir prefix
                else file
    in Lib_id $ Indirect_link nfile nullRange

readPrfFile :: HetcatsOpts -> LibEnv -> LIB_NAME -> IO LibEnv
readPrfFile opts ps ln = do
    let fname = libNameToFile opts ln
        prfFile = fname ++ prfSuffix
    recent <- checkRecentEnv opts prfFile fname
    h <- if recent then
          fmap (maybe [emptyHistory] id) $ readVerbose opts ln prfFile
       else return [emptyHistory]
    return $ Map.update (Just . applyProofHistory h) ln ps

readPrfFiles :: HetcatsOpts -> LibEnv -> IO LibEnv
readPrfFiles opts le = do
    foldM (readPrfFile opts) le $ Map.keys le
