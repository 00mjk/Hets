{- |
Module      :  $Header$
Copyright   :  (c) Hendrik Iben, Uni Bremen 2005-2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  hiben@tzi.de
Stability   :  provisional
Portability :  non-portable(Logic)

Output-methods for writing OMDoc
-}
module OMDoc.OMDocOutput
  (
    hetsToOMDoc
  )  
  where

import qualified OMDoc.HetsDefs as Hets
import CASL.Sign
import CASL.Logic_CASL
import CASL.AS_Basic_CASL
import qualified CASL.Morphism as Morphism
import qualified Common.Id as Id
import qualified Syntax.AS_Library as ASL
import qualified CASL.AS_Basic_CASL as ABC

import qualified CASL.Induction as Induction
import qualified Common.Result as Result
import qualified Common.DocUtils as Pretty

import Driver.Options

import Common.Utils (joinWith)

import Static.DevGraph
import qualified Data.Graph.Inductive.Graph as Graph

-- Often used symbols from HXT
import Text.XML.HXT.Parser
  ( 
      {- a_name, k_public, k_system, -} emptyRoot
    , v_1, a_indent, a_output_file
  )
        
import qualified Text.XML.HXT.Parser as HXT hiding (run, trace, when)
import qualified Text.XML.HXT.DOM.XmlTreeTypes as HXTT hiding (when)

import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Common.Lib.Rel as Rel

import qualified Common.AS_Annotation as Ann

import Data.Maybe (fromMaybe)
import Data.List (find)

import Debug.Trace (trace)

import qualified System.Directory as System.Directory

import Control.Monad

import Data.Char (toLower)

import OMDoc.Util
import OMDoc.XmlHandling
import OMDoc.OMDocDefs

import qualified OMDoc.OMDocInterface as OMDoc
import qualified OMDoc.OMDocXml as OMDocXML

import qualified Network.URI as URI


-- DTD is currently suspended in favor of RelaxNG (DTD violates RNG)
{-
-- | generate a DOCTYPE-Element for output
mkOMDocTypeElem::
  String -- ^ URI for DTD
  ->HXTT.XNode -- ^ DOCTYPE-Element
mkOMDocTypeElem system =
  HXTT.XDTD
    HXTT.DOCTYPE
      [
         (a_name, "omdoc")
        ,(k_public, "-//OMDoc//DTD OMDoc V1.2//EN")
        ,(k_system, system)
      ]
-}
{-
{- |
        default OMDoc-DTD-URI
        www.mathweb.org does not provide the dtd anymore (or it is hidden..)
        defaultDTDURI = <http://www.mathweb.org/src/mathweb/omdoc/dtd/omdoc.dtd>
        the svn-server does provide the dtd but all my validating software refuses to load it...
        defaultDTDURI = <https://svn.mathweb.org/repos/mathweb.org/trunk/omdoc/dtd/omdoc.dtd>
        my private copy of the modular omdoc 1.2 dtd...
        defaultDTDURI = </home/hendrik/Dokumente/Studium/Hets/cvs/HetCATScopy/utils/Omdoc/dtd/omdoc.dtd>
        until dtd-retrieving issues are solved I put the dtd online...
-}
defaultDTDURI::String
defaultDTDURI = "http://www.tzi.de/~hiben/omdoc/dtd/omdoc.dtd"

envDTDURI::IO String
envDTDURI = getEnvDef "OMDOC_DTD_URI" defaultDTDURI
-}
{-
-- | this function wraps trees into a form that can be written by HXT
writeableTreesDTD::String->HXT.XmlTrees->HXT.XmlTree
writeableTreesDTD dtd' t =
  (HXT.NTree
    ((\(HXT.NTree a _) -> a) emptyRoot)
    ((HXT.NTree (mkOMDocTypeElem dtd' ) [])
      :(HXT.NTree (HXT.XText "\n")[])
      :t)
  )
-}

-- | this function wraps trees into a form that can be written by HXT
writeableTrees::HXT.XmlTrees->HXT.XmlTree
writeableTrees t =
  (HXT.NTree
    ((\(HXT.NTree a _) -> a) emptyRoot)
    t
  )

{- -- debug
-- | this function shows Xml with indention
showOMDoc::HXT.XmlTrees->IO HXT.XmlTrees
showOMDoc t = HXT.run' $
  HXT.writeDocument
    [(a_indent, v_1), (a_issue_errors, v_1)] $
    writeableTrees t
-}              

{- -- debug
-- | this function shows Xml with indention
showOMDocDTD::String->HXT.XmlTrees->IO HXT.XmlTrees
showOMDocDTD dtd' t = HXT.run' $
  HXT.writeDocument
    [(a_indent, v_1), (a_issue_errors, v_1)] $
    writeableTreesDTD dtd' t
-}

-- | this function writes Xml with indention to a file
writeOMDoc::
  HXT.XmlTrees -- ^ tree to write
  ->String  -- ^ name of file to output to
  ->IO HXT.XmlTrees -- ^ errors are wrapped inside 'XmlTrees'
writeOMDoc t f = HXT.run' $
  HXT.writeDocument
    [(a_indent, v_1), (a_output_file, f)] $
    writeableTrees t

{-
-- | this function writes Xml with indention to a file
writeOMDocDTD::String->HXT.XmlTrees->String->IO HXT.XmlTrees
writeOMDocDTD dtd' t f = HXT.run' $
  HXT.writeDocument
    [(a_indent, v_1), (a_output_file, f)] $
    writeableTreesDTD dtd' t
-}

-- | Hets interface for writing OMDoc files.
--   Output is written into directory specified in options.
hetsToOMDoc::
  HetcatsOpts -- ^ if recurse is set, all libraries are exported.
              --   Else only the loaded library is exported.
  ->(ASL.LIB_NAME, LibEnv) -- ^ Name of loaded library and it's environment
  ->FilePath -- ^ Name of output-file (ignored when recurse is true)
  ->IO () 
hetsToOMDoc hco lnle file =
  do
    --libToOMDocIdNameMapping hco lnle file
    libToOMDoc hco lnle file

-- | Create one ore more OMDoc-documents from a library-environment
libToOMDoc::
  HetcatsOpts -- ^ Hetcats-Options, if recurse is set, all libraries are
              --   extracted. 
  ->(ASL.LIB_NAME, LibEnv) -- ^ Name of the loaded library and the environment
  ->FilePath               -- ^ Name of output-file (not used when recurse is set)
  ->IO ()
libToOMDoc
  hco
  (ln, lenv)
  fp
  =
    let
      -- get all names used in the environment
      flatNames = Hets.getFlatNames lenv
      -- identify names so we know where a name has it's origin
      identMap = Hets.identifyFlatNames lenv flatNames
      -- referenced identifiers are imported and are not needed 
      -- for name generation
      remMap = Hets.removeReferencedIdentifiers flatNames identMap
      -- tag same names with different origins according to their appearance
      useMap = Hets.getIdUseNumber remMap
      -- create unique names by creating new names from use tag and name
      unnMap = Hets.makeUniqueNames useMap
      -- use the unique names to created before to create a mapping
      -- of names corresponding to their use in the library environment
      uniqueNames = Hets.makeUniqueIdNameMapping lenv unnMap
      -- similar to uniqueNames but also populate the mappings with all
      -- names known in a theory (still annotated with their origin)
      fullNames = Hets.makeFullNames lenv unnMap identMap
      -- transform names to XML-conform strings
      uniqueNamesXml = (createXmlNameMapping uniqueNames)
      fullNamesXml = (createXmlNameMapping fullNames)
      outputio =
        -- write all libraries in the library environment ?
        if recurse hco
          then
            do
              -- dtduri <- envDTDURI
              mapM
                (\libname ->
                  let
                    -- get filename of library
                    filename = unwrapLinkSource libname
                    -- transform to an OMDoc-filename in outout directory
                    outfile = fileSandbox (outdir hco) $ asOMDocFile filename
                  in
                    do
                      -- create OMDoc
                      omdoc <-
                        libEnvLibNameIdNameMappingToOMDoc
                          (emptyGlobalOptions { hetsOpts = hco })
                          lenv
                          libname
                          (createLibName libname)
                          uniqueNamesXml
                          fullNamesXml
                      -- transform to HXT-Data
                      omdocxml <- return $ (OMDocXML.toXml omdoc) HXT.emptyRoot
                      -- Tell user what we do
                      putStrLn ("Writing " ++ filename ++ " to " ++ outfile)
                      -- setup path
                      System.Directory.createDirectoryIfMissing True (snd $ splitPath outfile)
                      --writeOMDocDTD dtduri omdocxml outfile >> return ()
                      -- write XML to the file
                      writeOMDoc omdocxml outfile >> return ()
                )
                (Map.keys lenv) -- all libnames
              return ()
          else -- only single library
            do
              -- dtduri <- envDTDURI
              -- create OMDoc
              omdoc <-
                libEnvLibNameIdNameMappingToOMDoc
                  (emptyGlobalOptions { hetsOpts = hco })
                  lenv
                  ln
                  (createLibName ln)
                  uniqueNamesXml
                  fullNamesXml
              -- transform to HXT-Data
              omdocxml <- return $ (OMDocXML.toXml omdoc) HXT.emptyRoot
              --writeOMDocDTD dtduri omdocxml fp >> return ()
              -- write to given file
              writeOMDoc omdocxml fp >> return ()
    in
        -- actually perform IO
        outputio

-- | creates a xml structure describing a Hets-presentation for a symbol 
makePresentationForOM::
  XmlName -- ^ Xml-Name (xml:id) of symbol to represent
  ->String -- ^ Hets-representation (as 'String')
  ->OMDoc.Presentation -- ^ Wrapped \"/\<presentation>\<use>.../\"-element
makePresentationForOM xname presstring =
  OMDoc.mkPresentation xname [OMDoc.mkUse "Hets" presstring]  

{-
 assuming unique names in a list of 'IdNameMapping'S each id (String) is
 converted to an xml:id-conform string by replacing invalid characters
-}
{- |
  create xml ids from unique names. Adjusts names to conform to XML-Standards.
-}
createXmlNameMapping::
  [Hets.IdNameMapping] 
  ->[Hets.IdNameMapping]
createXmlNameMapping =
  map
    (\(
        libName
      , nodeName
      , uniqueNodeName
      , nodeNum
      , idNameSortSet
      , idNamePredSet
      , idNameOpSet
      , idNameSensSet
      , idNameConsSet
      , idNameGaPredSet
      ) ->
      (
          libName
        , nodeName
        , adjustStringForXmlName uniqueNodeName
        , nodeNum
        , Set.map (\(id', uN) -> (id', adjustStringForXmlName uN)) idNameSortSet
        , Set.map (\(a, uN) -> (a, adjustStringForXmlName uN)) idNamePredSet
        , Set.map (\(a, uN) -> (a, adjustStringForXmlName uN)) idNameOpSet
        , Set.map (\(a, uN) -> (a, adjustStringForXmlName uN)) idNameSensSet
        , Set.map (\(a, uN) -> (a, adjustStringForXmlName uN)) idNameConsSet
        , Set.map (\(a, uN) -> (a, adjustStringForXmlName uN)) idNameGaPredSet
      )
    )

-- | translate a definitional link to OMDoc (/imports/)
createOMDefLink::
  Static.DevGraph.LibEnv -- ^ library environment 
  ->Hets.LIB_NAME        -- ^ library (where link occures)
  ->Graph.LEdge Static.DevGraph.DGLinkLab -- ^ the link
  ->[Hets.IdNameMapping] -- ^ mapping of unique names (Hets\<->OMDoc)
  ->[Hets.IdNameMapping] -- ^ mapping of names (Hets\<->OMDoc)
  ->OMDoc.Imports
createOMDefLink lenv ln (from, to, ll) uniqueNames names =
  let
    e_fname = "OMDoc.OMDocOutput.createOMDefLink: "
    dg = lookupDGraph ln lenv
    fromnode =
      Data.Maybe.fromMaybe
        (error (e_fname ++ "No such node!"))
        $
        Graph.lab dg from
    fromname =
      case
        find
          (\ inm ->
            Hets.inmGetLibName inm == ln && Hets.inmGetNodeNum inm == from
          )
          names
      of
        Nothing ->
          error (e_fname ++ "No such node in names!")
        (Just inm) -> Hets.inmGetNodeId inm
    liburl =
      if isDGRef fromnode
        then
          asOMDocFile $ unwrapLinkSource $ dgn_libname fromnode
        else
          ""
    linktype =
      case dgl_type ll of
        (LocalDef {}) ->
            OMDoc.ITLocal
        _ -> OMDoc.ITGlobal
    mommorph = createOMMorphism lenv ln (from, to, ll) uniqueNames names
    fromuri = case URI.parseURIReference (liburl ++ "#" ++ fromname) of
      Nothing ->
        error (e_fname ++ "Error parsing URI!")
      (Just u) -> u
  in
    OMDoc.Imports fromuri mommorph Nothing linktype OMDoc.CNone

{-
  since 'conservativity' has been dropped from
  x-inclusionS, it should be carried by an
  imports element that refers to the x-inclusion
  via 'base'
-}
-- | translate a theorem-link to OMDoc (/(axiom|theory)-inclusion/).
--   This may result in an additional /imports/-element for the /linked-to/-theory
--   carrying conservativity-information.
createXmlThmLinkOM::
    Int -- ^ link number (for disambiguation when there are multiple similar links)
  ->Static.DevGraph.LibEnv -- ^ library environment
  ->Hets.LIB_NAME -- ^ library (where link occures)
  ->Graph.LEdge Static.DevGraph.DGLinkLab -- ^ the link
  ->[Hets.IdNameMapping] -- ^ mapping of unique names (Hets\<->OMDoc)
  ->[Hets.IdNameMapping] -- ^ mapping of names (Hets\<->OMDoc)
  ->(OMDoc.Inclusion, Maybe OMDoc.Imports)
createXmlThmLinkOM lnum lenv ln (edge@(from, to, ll)) uniqueNames names =
  let
    e_fname = "OMDoc.OMDocOutput.createXmlThmLinkOM: "
    dg = lookupDGraph ln lenv
    fromnode =
      Data.Maybe.fromMaybe
        (error (e_fname ++ "No such node (from)!"))
        $
        Graph.lab dg from
    tonode =
      Data.Maybe.fromMaybe
        (error (e_fname ++ "No such node (to)!"))
        $
        Graph.lab dg to
    fromname =
      case
        find
          (\inm ->
            Hets.inmGetLibName inm == ln && Hets.inmGetNodeNum inm == from
          )
          names
      of
        Nothing ->
          error (e_fname ++ "No such node in names!")
        (Just inm) -> Hets.inmGetNodeId inm
    toname =
      case
        find
          (\inm ->
            Hets.inmGetLibName inm == ln && Hets.inmGetNodeNum inm == to
          )
          names
      of
        Nothing ->
          error (e_fname ++ "No such node in names!")
        (Just inm) -> Hets.inmGetNodeId inm
    -- if the link comes from a referenced library 
    -- we need the (assumed) URL of this library to build
    -- the OMDoc-link
    liburl =
      if isDGRef fromnode
        then
          asOMDocFile $ unwrapLinkSource $ dgn_libname fromnode
        else
          ""
    -- the same applies to links into referenced libraries
    toliburl =
      if isDGRef tonode
        then
          asOMDocFile $ unwrapLinkSource $ dgn_libname tonode
        else
          ""
    -- does this link get translated into an axiom-inclusion ?
    isaxinc =
      case dgl_type ll of
        (Static.DevGraph.GlobalThm {}) -> False
        (Static.DevGraph.LocalThm {}) -> True
        _ -> error (e_fname ++ "corrupt data!")
    -- translate conservativity
    cons =
      case dgl_type ll of
        (Static.DevGraph.GlobalThm _ c _) -> consConv c
        (Static.DevGraph.LocalThm _ c _) -> consConv c
        _ -> error (e_fname ++ "corrupt data!")
    touri = case URI.parseURIReference (toliburl ++ "#" ++ toname) of
      Nothing -> error (e_fname ++ "Error parsing URI (to)!")
      (Just u) -> u
    fromuri = case URI.parseURIReference (liburl ++ "#" ++ fromname) of
      Nothing -> error (e_fname ++ "Error parsing URI (from)!")
      (Just u) -> u
    -- construct a (somewhat) human readable id for this link
    iid =
      (if isaxinc then "ai" else "ti")
        ++ "." ++ toname ++ "." ++ fromname ++ "_" ++ (show lnum)
    -- create morphism if necessary
    mommorph' = createOMMorphism lenv ln edge uniqueNames names
    mommorph =
      -- if we have a helper-imports we need to modify the base of the morphism
      -- (or even create an empty morphism)
      case helpimports of
        Nothing -> mommorph'
        _ ->
          case mommorph' of
            Nothing ->
              Just
                $
                OMDoc.Morphism
                  {
                      OMDoc.morphismId = Nothing
                    , OMDoc.morphismHiding = []
                    , OMDoc.morphismBase = [iid ++ "-base"]
                    , OMDoc.morphismRequations = []
                  }
            (Just mm') ->
              Just (mm' { OMDoc.morphismBase = (OMDoc.morphismBase mm') ++ [iid ++ "-base"] })
    -- a helper imports is needed to carry conservativity  (the feature has been taken out of
    -- OMDoc, so we need this workaround)
    helpimports =
      case cons of
        OMDoc.CNone -> Nothing
        _ ->
          Just $
            OMDoc.Imports
              fromuri
              (
                Just
                  $
                  OMDoc.Morphism
                    (Just (iid ++ "-base"))
                    []
                    []
                    []
              )
              Nothing
              (if isaxinc then OMDoc.ITLocal else OMDoc.ITGlobal)
              cons -- the reason for this
  in
    if isaxinc
      then
        (OMDoc.AxiomInclusion fromuri touri mommorph (Just iid) cons, helpimports)
      else
        (OMDoc.TheoryInclusion fromuri touri mommorph (Just iid) cons, helpimports)
  where
  consConv::Static.DevGraph.Conservativity->OMDoc.Conservativity
  consConv Static.DevGraph.None = OMDoc.CNone
  consConv Static.DevGraph.Mono = OMDoc.CMonomorphism
  consConv Static.DevGraph.Cons = OMDoc.CConservative
  consConv Static.DevGraph.Def = OMDoc.CDefinitional

{- |
  create a xml-representation of a (CASL-)morphism.
-}
createOMMorphism::
  Static.DevGraph.LibEnv -- ^ library environment
  ->Hets.LIB_NAME -- ^ library (of morphism)
  ->Graph.LEdge Static.DevGraph.DGLinkLab -- ^ link carrying morphism
  ->[Hets.IdNameMapping] -- ^ mapping of unique names (Hets\<->OMDoc)
  ->[Hets.IdNameMapping] -- ^ mapping of names (Hets\<->OMDoc)
  ->Maybe OMDoc.Morphism 
createOMMorphism
  _
  ln
  (from, to, ll)
  {-uniqueNames-}_
  names
  =
  let
    e_fname = "OMDoc.OMDocOutput.createOMMorphism: "
    caslmorph = Hets.getCASLMorphLL ll
    -- get name mapping from the from-node
    fromIdNameMapping =
      Data.Maybe.fromMaybe
        (error (e_fname ++ "Cannot find Id-Name-Mapping (from)!"))
        $
        Hets.inmFindLNNN (ln, from) names
    -- get name mapping from the to-node
    toIdNameMapping =
      Data.Maybe.fromMaybe
        (error (e_fname ++ "Cannot find Id-Name-Mapping (to)!"))
        $
        Hets.inmFindLNNN (ln, to) names
    -- retrieve the XML-names for the sort mapping
    mappedsorts =
      Map.foldWithKey
        (\origsort newsort ms ->
          let
            oname =
              case
                Set.toList
                  $
                  Set.filter
                    (\(oid', _) -> oid' == origsort)
                    (Hets.inmGetIdNameSortSet fromIdNameMapping)
              of
               [] -> error (e_fname ++ "Sort not in From-Set!")
               s:_ -> snd s
            nname =
              case
                Set.toList 
                  $
                  Set.filter
                    (\(nid', _) -> nid' == newsort)
                    (Hets.inmGetIdNameSortSet toIdNameMapping)
              of
               [] -> error (e_fname ++ "Sort not in To-Set!")
               s:_ -> snd s
            oorigin =
              case
                Hets.getNameOrigin names ln from oname
              of
                [] -> error (e_fname ++ "Cannot find origin of name (from)!")
                o:[] -> o
                o:_ ->
                  Debug.Trace.trace
                    ("more than one origin for Sort \""
                      ++ show oname ++ "\"...")
                    o
            norigin =
              case
                Hets.getNameOrigin names ln to nname
              of
                [] -> error (e_fname ++ "Cannot find origin of name (to)!")
                n:[] -> n
                n:_ ->
                  Debug.Trace.trace
                    ("more than one origin for Sort \""
                      ++ show nname ++ "\"...")
                    n
         in
          ms ++ [ ((oname, oorigin), (nname, norigin)) ]
        )
        []
        (Morphism.sort_map caslmorph)
    -- retrieve the XML-names for the predicate mapping
    mappedpreds =
      Map.foldWithKey
        (\(origpred, _) newpred mp ->
          let
            oname =
              case
                Set.toList
                  $
                  Set.filter
                    (\((oid', _), _) -> oid' == origpred)
                    (Hets.inmGetIdNamePredSet fromIdNameMapping)
              of
               [] ->
                error 
                  (
                    e_fname
                    ++ "Pred not in From-Set! " ++ show origpred
                    ++ " not in "
                    ++ show (Hets.inmGetIdNamePredSet fromIdNameMapping)
                  )
               s:_ -> snd s
            nname =
              case
                Set.toList 
                  $
                  Set.filter
                    (\((nid', _), _) -> nid' == newpred)
                    (Hets.inmGetIdNamePredSet toIdNameMapping)
              of
               [] -> error (e_fname ++ "Pred not in To-Set!")
               s:_ -> snd s
            oorigin =
              case
                Hets.getNameOrigin names ln from oname
              of
                [] -> error (e_fname ++ "No origin for predicate (from)!")
                o:[] -> o
                o:_ ->
                  Debug.Trace.trace
                    ("more than one origin for Pred \""
                      ++ show oname ++ "\"...")
                    o
            norigin =
              case
                Hets.getNameOrigin names ln to nname
              of
                [] -> error (e_fname ++ "No origin for predicate (to)!")
                n:[] -> n
                n:_ ->
                  Debug.Trace.trace
                    ("more than one origin for Pred \""
                      ++ show nname ++ "\"...")
                    n
         in
          mp ++ [ ((oname, oorigin), (nname, norigin)) ]
        )
        []
        (Morphism.pred_map caslmorph)
    -- retrieve the XML-names for the operator mapping
    mappedops =
      Map.foldWithKey
        (\(origop, _) (newop, _) mo ->
          let
            oname =
              case
                Set.toList
                  $
                  Set.filter
                    (\((oid', _), _) -> oid' == origop)
                    (Hets.inmGetIdNameOpSet fromIdNameMapping)
              of
               [] -> error (e_fname ++ "Op not in From-Set!")
               s:_ -> snd s
            nname =
              case
                Set.toList 
                  $
                  Set.filter
                    (\((nid', _), _) -> nid' == newop)
                    (Hets.inmGetIdNameOpSet toIdNameMapping)
              of
               [] -> error (e_fname ++ "Op not in To-Set!")
               s:_ -> snd s
            oorigin =
              case
                Hets.getNameOrigin names ln from oname
              of
                [] -> error (e_fname ++ "No origin for operator (from)!")
                o:[] -> o
                o:_ ->
                  Debug.Trace.trace
                    ("more than one origin for Op \""
                      ++ show oname ++ "\"...")
                    o
            norigin =
              case
                Hets.getNameOrigin names ln to nname
              of
                [] -> error (e_fname ++ "No origin for operator (to)!")
                n:[] -> n
                n:_ ->
                  Debug.Trace.trace
                    ("more than one origin for Op \""
                      ++ show nname ++ "\"...")
                    n
         in
          mo ++ [ ((oname, oorigin), (nname, norigin)) ]
        )
        []
        (Morphism.fun_map caslmorph)
    -- retrieved names are all of same type, so merge
    allmapped = mappedsorts ++ mappedpreds ++ mappedops
    -- merging makes hiding easier also...
    hidden =
      case dgl_type ll of
        (HidingDef {}) ->
          mkHiding fromIdNameMapping toIdNameMapping allmapped
        (HidingThm {}) ->
          mkHiding fromIdNameMapping toIdNameMapping allmapped
        _ -> []
    -- create requations
    reqs =
      foldl
        (\r ((f,fo), (t,to')) ->
          r
          ++
          [
            (
                OMDoc.MTextOM $ OMDoc.mkOMOBJ $ OMDoc.mkOMS (Hets.inmGetNodeId fo) f
              , OMDoc.MTextOM $ OMDoc.mkOMOBJ $ OMDoc.mkOMS (Hets.inmGetNodeId to') t
            )
          ]
        )
        []
        allmapped
  in
    -- empty morphism still can contain hiding information
    if Hets.isEmptyMorphism caslmorph && null hidden
      then
        Nothing
      else
        -- construct morphism
        Just $ OMDoc.Morphism Nothing hidden [] reqs
  where
  -- find the hidden symbols by comparing the name mappings
  -- from each node and the mapping created by the morphism
  mkHiding::Hets.IdNameMapping->Hets.IdNameMapping->[((String,a),b)]->[String]
  mkHiding fromIdNameMapping toIdNameMapping mappedIds =
    let
      -- uniformly get all symbols
      idsInFrom = Hets.inmGetIdNameAllSet fromIdNameMapping
      idsInTo = Hets.inmGetIdNameAllSet toIdNameMapping
    in
      -- for every symbol in the source node...
      Set.fold
        (\(_, fname) h ->
          case
            -- try to find it in the mapping...
            find
              (\( (fname', _)  , _ ) -> fname == fname')
              mappedIds
          of
            -- it's not in the mapping...
            Nothing ->
              if
                -- make sure that it is not already defined in the target node
                Set.null
                  $
                  Set.filter
                    (\(_, tname) -> tname == fname)
                    idsInTo
                then
                  -- then this symbol is hidden
                  h ++ [fname]
                else
                  h
            _ -> h
        )
        []
        idsInFrom

{- |
  filter definitional links (LocalDef, GlobalDef, HidingDef, FreeDef, CofreeDef)
-}
filterDefLinks::
  [Graph.LEdge Static.DevGraph.DGLinkLab]
  ->[Graph.LEdge Static.DevGraph.DGLinkLab]
filterDefLinks =
  filter
    (\(_, _, ll) ->
      case dgl_type ll of
        (LocalDef {}) -> True
        (GlobalDef {}) -> True
        (HidingDef {}) -> True
        (FreeDef {}) -> True
        (CofreeDef {}) -> True
        _ -> False
    )

{- |
  filter theorem links (LocalThm, GlobalThm, HidingThm)
-}
filterThmLinks::
  [Graph.LEdge Static.DevGraph.DGLinkLab]
  ->[Graph.LEdge Static.DevGraph.DGLinkLab]
filterThmLinks =
  filter
    (\(_, _, ll) ->
      case dgl_type ll of
        (LocalThm {}) -> True
        (GlobalThm {}) -> True
        (HidingThm {}) -> True
        _ -> False
    )

{- |
  filter sort generating constructors (from a list of sort constructors) 
-}
filterSORTConstructors::Set.Set (OpType, String)->SORT->Set.Set (OpType, String)
filterSORTConstructors
  conset
  s
  =
  Set.filter
    (\(ot, _) -> opRes ot == s )
    conset

-- | translate operators representing sort constructors to 
--   OMDoc-ADT-constructors.
createConstructorsOM::
  Hets.LIB_NAME
  ->Graph.Node
  ->[Hets.IdNameMapping]
  ->[Hets.IdNameMapping]
  ->Set.Set (OpType, String)
  ->[OMDoc.Constructor]
createConstructorsOM
  ln
  nn
  uniqueNames
  fullNames
  conset
  =
    Set.fold
      (\c cs ->
        cs
        ++
        [
          createConstructorOM 
            ln
            nn
            uniqueNames
            fullNames
            c
        ]
      )
      []
      conset

-- | translate a single sort constructing operator to
-- an OMDoc-ADT-constructor
createConstructorOM::
  Hets.LIB_NAME
  ->Graph.Node
  ->[Hets.IdNameMapping]
  ->[Hets.IdNameMapping]
  ->(OpType, String)
  ->OMDoc.Constructor
createConstructorOM
  ln
  nn
  uniqueNames
  fullNames
  (ot, oxmlid)
  =
  OMDoc.mkConstructor
    oxmlid
    (
      foldl
        (\args arg ->
          args
          ++
          [
            OMDoc.mkType
              Nothing
              (
              OMDoc.OMOMOBJ
                $
                OMDoc.mkOMOBJ
                  $
                  createSymbolForSortOM
                    ln
                    nn
                    uniqueNames
                    fullNames
                    arg
              )
          ]
        )
        []
        (opArgs ot) -- op result is not needed. it is bound by the ADT
    )
    
{- | 
  check if a relation contains information about a certain sort
-}
emptyRelForSort::Rel.Rel SORT->SORT->Bool
emptyRelForSort rel s =
  null $ filter (\(s', _) -> s' == s) $ Rel.toList rel

-- | create an OMDoc-Abstract-Data-Type for a sort
--   with respect to the relation of sorts and previously
--   translated sort constructors.
createADTFor::
    String
  ->Rel.Rel SORT
  ->SORT
  ->Hets.IdNameMapping
  ->[OMDoc.Constructor] -- ^ contructors generated via 'createConstructorsOM'
  ->[SORT]
  ->(OMDoc.ADT, [SORT])
createADTFor theoname rel s idNameMapping constructors fixed =
  let
    adtSortID = getSortIdName idNameMapping s
    -- compute insorts for this ADT and find out
    -- for which sorts this sort should show up
    -- in an insort-element but does not
    (insorts, recogs, pins) =
      foldl
        (\(is, recogs', pins') (s'', s') ->
          -- normal insort, this means s'' needs to appear
          -- in an insort in this ADT
          if s' == s
            then
              (
                  is
                  ++
                  [
                    OMDoc.mkInsort
                      (OMDoc.mkSymbolRef (getSortIdName idNameMapping s''))
                  ]
                , recogs'
                , pins'
              )
            else
              -- this means that this sort should be in an insort for s'
              -- but maybe s' has already been defined (fixed)
              if s'' == s && elem s' fixed
                then
                  let
                    recognizer =
                      OMDoc.mkRecognizer
                        $
                        OMDoc.mkSymbolRef
                          (
                            "recognizer_"
                            ++ (getSortIdName idNameMapping s')
                            ++ "_in_"
                            ++ adtSortID
                          )
                    -- this debug message is a reminder to
                    -- find a way out of this...
                  in
                    Debug.Trace.trace
                      ("Generating recognizer for " ++ (show s) ++ " in " ++ (show s'))
                      (is, recogs' ++ [recognizer], pins' ++ [s'])
                else
                  -- is s' is not fixed, the ADT will be generated later
                  (is, recogs', pins')
        )
        ([], [], [])
        (Rel.toList rel)
  in
    (
        OMDoc.mkADTEx
          (Just (theoname ++ "-" ++ adtSortID ++ "-adt"))
          $
          [
            OMDoc.mkSortDef
              (getSortIdName idNameMapping s)
              constructors
              insorts
              recogs
          ]
      , pins
    )
 
-- | lookup a symbols XML-name
lookupIdName::
  Set.Set (Id.Id, String) -- ^ Set containing associating tuples
  ->Id.Id                 -- ^ Symbol to lookup
  ->Maybe String
lookupIdName ss sid =
  case
    find
      (\(sid', _) -> sid' == sid)
      (Set.toList ss)
  of
    Nothing -> Nothing
    (Just x) -> Just (snd x)

-- | lookup a sorts XML-name
getSortIdName::
    Hets.IdNameMapping -- ^ Mapping to use
  ->Id.Id              -- ^ Sort to lookup
  ->String
getSortIdName idNameMapping sid =
  Data.Maybe.fromMaybe
    (error "OMDoc.OMDocOutput.getSortIdName: Cannot find name!")
    $
    lookupIdName (Hets.inmGetIdNameSortSet idNameMapping) sid

-- | convert a library from a library-environment into OMDoc 
libEnvLibNameIdNameMappingToOMDoc::
  GlobalOptions           -- ^ HetcatsOpts and debugging information
  ->LibEnv                -- ^ Library-Environment to process
  ->Hets.LIB_NAME         -- ^ Libary to process
  ->OMDoc.XmlId           -- ^ Name (xml:id) for OMDoc-Document
  ->[Hets.IdNameMapping]  -- ^ Mapping of unique names (Hets\<->XML)
  ->[Hets.IdNameMapping]  -- ^ Mapping of names (duplicate entries for
                          --   imported symbols) (Hets\<->XML)
  ->IO OMDoc.OMDoc
libEnvLibNameIdNameMappingToOMDoc
  go
  lenv
  ln
  omdocId
  uniqueNames
  fullNames
  =
    let
      e_fname = "OMDoc.OMDocOutput.libEnvLibNameIdNameMappingToOMDoc: "
      dummyTheoryComment =
        (
          Just "This theory is not used. It serves only as a semantic\
            \ 'anchor' for theory- and axiom-inclusions."
        )
      dg = lookupDGraph ln lenv
      -- get all theorem links pointing
      -- to external libraries
      thmLinksToRefs =
        filter
          (\(_, to, _) ->
            case Graph.lab dg to of
              Nothing -> False
              (Just n) -> isDGRef n
          )
          (filterThmLinks $ Graph.labEdges dg)
      -- translate these external links to OMDoc
      -- and create helper imports to preserve 
      -- conservativity information
      (thmLinksToRefsOM, dummyImports) =
        foldl
          (\(tL, dI) (lnum, edge) ->
            let
              (newTL, mDI) =
                createXmlThmLinkOM
                  lnum
                  lenv
                  ln
                  edge
                  uniqueNames
                  fullNames
            in
              case mDI of
                Nothing -> (tL ++ [newTL], dI)
                (Just newDI) -> (tL ++ [newTL], dI ++ [newDI])
          )
          ([], [])
          (zip [1..] thmLinksToRefs) -- numbers for disambiguation 
      -- dummy-theory to attach links with information to it
      dummyTheory =
        OMDoc.Theory
          "import-dummy-for-hets"
          (map OMDoc.CIm dummyImports)
          []
          dummyTheoryComment
      -- initial present theories.
      -- either none or the dummy
      initTheories =
        case dummyImports of
          [] -> []
          _ -> [dummyTheory]
      -- create an initial (emtpy) OMDoc-Document
      initialOMDoc =
        OMDoc.OMDoc omdocId initTheories thmLinksToRefsOM  
      -- appending theories and inclusions must be done
      -- in the IO-Monad because axioms pull in their
      -- original (CASL) Source in CMP elements
      omdocio =
        foldl
          (\xio (nn, node) -> -- fold over labnodes
            do
              -- get current OMDoc and a list of created ADTs
              -- The ADTs are needed to work around changing 
              -- sort-relation-information
              (omdoc, fixedADTs) <- xio 
              -- this is the new state (OMDoc, ADTs)
              res <-
                let
                  dgnodename = dgn_name node
                  caslsign = (\(Just a) -> a) $ Hets.getCASLSign (dgn_sign node)
                  -- get the (full) name mapping for this theory (node)
                  idnamemapping =
                    case
                      find
                        (\inm ->
                          (Hets.inmGetLibName inm) == ln
                          && (Hets.inmGetNodeName inm) == dgnodename
                          && (Hets.inmGetNodeNum inm) == nn
                        )
                        fullNames
                    of
                      Nothing -> error (e_fname ++ "No such name...")
                      (Just a) -> a
                  -- get the (unique) name mapping for this theory (node)
                  uniqueidnamemapping =
                    case
                      find
                        (\inm ->
                          (Hets.inmGetLibName inm) == ln
                          && (Hets.inmGetNodeName inm) == dgnodename
                          && (Hets.inmGetNodeNum inm) == nn
                        )
                        uniqueNames
                    of
                      Nothing -> error (e_fname ++ "No such name...")
                      (Just a) -> a
                  -- previously computed unique theory name for XML
                  theoryXmlId = (Hets.inmGetNodeId idnamemapping)
                  -- create presentatio symbol for this theory
                  -- (does this make sense in OMDoc ?)
                  theoryPresentation =
                    makePresentationForOM
                      theoryXmlId
                      (Hets.idToString $ Hets.nodeNameToId dgnodename)
                  -- create definitional links for the theory (imports)
                  theoryDefLinks =
                    map
                      (\edge ->
                        createOMDefLink
                          lenv
                          ln
                          edge
                          uniqueNames
                          fullNames
                      )
                      (filterDefLinks (Graph.inn dg nn))
                  -- process ADTs for this theory and keep track of changing sort relations
                  (theoryADTs, theoryLateInsorts, theorySorts, theoryPresentations, adtList) =
                    Set.fold
                     (\s (tadts, tlis, tsorts, tpres, adtl) ->
                      let
                        -- sentences for sort construction
                        consremap =
                          Set.map
                            (\( (_, _, ot), uname ) -> (ot, uname))
                            (Hets.inmGetIdNameConsSet uniqueidnamemapping)
                        -- constructors for current sort (s)
                        sortcons = filterSORTConstructors consremap s
                        -- translate to XML (children of adt)
                        constructors = 
                          createConstructorsOM
                            ln
                            nn
                            uniqueNames
                            fullNames
                            sortcons
                      in
                        case
                          find
                            (\(uid, _) -> uid == s)
                            (Set.toList (Hets.inmGetIdNameAllSet uniqueidnamemapping))
                        of
                          -- sort has no origin here...
                          Nothing ->
                            if (Set.size sortcons) > 0
                              then -- some constructors have been introduced here
                                let
                                  -- create ADT (and record new insorts)
                                  (newadt, adtlis) =
                                    createADTFor
                                      theoryXmlId
                                      (sortRel caslsign)
                                      s
                                      idnamemapping
                                      constructors
                                      adtl
                                  newlis =
                                    case adtlis of
                                      [] -> []
                                      _ ->
                                        -- if there are new insorts find xml-name
                                        -- and create typed variables (name == sort)
                                        -- for later use (in OpenMath)
                                        [
                                          (
                                              getSortIdName idnamemapping s
                                            , createTypedVarOM ln nn uniqueNames fullNames s (show s)
                                            , map
                                                (\s' ->
                                                  createTypedVarOM
                                                    ln
                                                    nn
                                                    uniqueNames
                                                    fullNames
                                                    s'
                                                    (show s')
                                                )
                                                adtlis
                                            , map (getSortIdName idnamemapping) adtlis
                                            , map
                                                (\s' ->
                                                  createSymbolForSortOM
                                                    ln
                                                    nn
                                                    uniqueNames
                                                    fullNames
                                                    s'
                                                )
                                                adtlis
                                          )
                                        ]
                                in
                                  (tadts ++ [newadt], tlis ++ newlis, tsorts, tpres, adtl ++ [s])
                              else
                                -- Nothing new (no origin here and no new constructors)
                                (tadts, tlis, tsorts, tpres, adtl)
                          -- this is the origin of the sort (normal case)
                          (Just (uid, uname)) ->
                            let
                              -- create sort symbol with reference to ADT
                              -- (not used yet, but conforms to OMDoc)
                              newsort =
                                genSortToXmlOM
                                  (
                                    case OMDoc.adtId newadt of
                                      Nothing ->
                                        Debug.Trace.trace "ADT without ID..."
                                        (show uid)
                                      (Just aid) -> aid
                                  )
                                  (XmlNamed s uname)
                              -- create ADT and keep track of new insorts
                              (newadt, adtlis) =
                                createADTFor
                                  theoryXmlId
                                  (sortRel caslsign)
                                  uid
                                  idnamemapping
                                  constructors
                                  adtl
                              -- create presentation for the sort
                              newpre =
                                makePresentationForOM
                                  uname
                                  (Hets.idToString s)
                              -- record new sorts
                              newsorts = tsorts ++ [newsort]
                               -- " new presentations
                              newpres = tpres ++ [newpre]
                              -- check new adts and insorts
                              (newadts, newlis) =
                                -- only record ADT if it would contain information
                                -- about the sort relation or sort constructors
                                if (not $ emptyRelForSort (sortRel caslsign) uid)
                                  || ( (Set.size sortcons) > 0 )
                                  then
                                    (
                                        tadts++[newadt]
                                      , tlis
                                        ++
                                        [
                                          (
                                              uname
                                            , createTypedVarOM ln nn uniqueNames fullNames s uname
                                            , map
                                                (\s' ->
                                                  createTypedVarOM
                                                    ln
                                                    nn
                                                    uniqueNames
                                                    fullNames
                                                    s'
                                                    (show s')
                                                )
                                                adtlis
                                            , map (getSortIdName idnamemapping) adtlis
                                            , map
                                                (\s' ->
                                                  createSymbolForSortOM
                                                    ln
                                                    nn
                                                    uniqueNames
                                                    fullNames
                                                    s'
                                                )
                                                adtlis
                                          )
                                        ]
                                    )
                                  else
                                    -- ...else the ADT would say nothing
                                    (tadts, tlis)
                            in
                              (newadts, newlis, newsorts, newpres, adtl ++ [uid])
                     )
                     -- start empty, except for known ADTs
                     ([],[],[],[],fixedADTs)
                     -- calculate ADTs for all sorts
                     (sortSet caslsign)
                  -- generated predicates (from inductionScheme)
                  gapreds = Hets.inmGetIdNameGaPredSet uniqueidnamemapping
                  -- compact them, stripping their origin
                  gapredadd =
                    Set.fold
                      (\((gapid, gapt), _) m ->
                        Map.insertWith
                          Set.union
                          gapid
                          (Set.singleton gapt)
                          m
                      )
                      Map.empty
                      gapreds
                  -- merge with normal predicates
                  morepreds =
                    Map.union
                      gapredadd
                      (predMap caslsign)
                  -- translate to OMDoc
                  (theoryPreds, pPres) =
                    Map.foldWithKey
                      -- ...for every predicate and its Set of types...
                      (\pid pts (tPr, pP) ->
                        Set.fold
                          -- ...for every single type...
                          (\pt (tPr', pP') ->
                            case 
                              find -- find the unique name for this combination
                                (\( (uid, upt), _) -> uid == pid && upt == pt)
                                (
                                  Set.toList
                                    $
                                    -- combine normal and generated 
                                    -- predicates for lookup (no overlap)
                                    Set.union
                                      (
                                        Hets.inmGetIdNamePredSet
                                          uniqueidnamemapping
                                      )
                                      (
                                        Hets.inmGetIdNameGaPredSet
                                          uniqueidnamemapping
                                      )
                                )
                            of
                              -- silently ignore this (should not happen)
                              Nothing -> (tPr', pP')
                              -- ...with unique name...
                              (Just (_, uname )) ->
                                let
                                  -- create predication
                                  newpred = 
                                    predicationToXmlOM
                                      ln
                                      nn
                                      idnamemapping
                                      uniqueNames
                                      fullNames
                                      (pid, pt)
                                  -- create presentation
                                  newpres =
                                    makePresentationForOM
                                      uname
                                      (Hets.idToString pid)
                                in
                                  -- add new OMDoc-elements
                                  (tPr' ++ [newpred], pP' ++ [newpres])
                          )
                          (tPr, pP)
                          pts
                      )
                      ([],[])
                      morepreds
                  -- translate operators to OMDoc
                  (theoryOps, oPres) =
                    Map.foldWithKey
                      -- ...for every operator and its set of types...
                      (\oid ots (tOp, oP) ->
                        Set.fold
                          -- ...for every single type...
                          (\ot (tOp', oP') ->
                            case 
                              find -- unique name for this combination
                                (\( (uid, uot), _) -> uid == oid && uot == ot)
                                (Set.toList (Hets.inmGetIdNameOpSet uniqueidnamemapping))
                            of
                              -- ignore if not found (should not happen)
                              Nothing -> (tOp', oP')
                              -- with unique name...
                              (Just (_, uname )) ->
                                let
                                  -- create operator
                                  newop =
                                    operatorToXmlOM
                                      ln
                                      nn
                                      idnamemapping
                                      uniqueNames
                                      fullNames
                                      (oid, ot)
                                  -- and presentation
                                  newpres =
                                    makePresentationForOM
                                      uname
                                      (Hets.idToString oid)
                                in
                                  -- add new OMDoc-elements
                                  (tOp' ++ [newop], oP' ++ [newpres])
                          )
                          (tOp, oP)
                          ots
                      )
                      ([],[])
                      (opMap caslsign)
                  -- translate theorem links to OMDoc
                  (theoryThmLinks, theoryDummyImports) =
                    foldl
                      -- ...for every (tagged) theorem link...
                      (\(tTL, tDI) (lnum, edge) ->
                        let
                          -- create OMDoc translation and maybe a Dummy-link
                          (newtTL, mtDI) =
                            createXmlThmLinkOM
                              lnum
                              lenv
                              ln
                              edge
                              uniqueNames
                              fullNames
                        in
                          -- check if there is a Dummy
                          case mtDI of
                            Nothing -> (tTL ++ [newtTL], tDI)
                            (Just newtDI) -> (tTL ++ [newtTL], tDI ++ [newtDI])
                      )
                      ([],[])
                      (zip [1..] (filterThmLinks $ Graph.inn dg nn))
                  -- recognizers are formally references to
                  -- predicates that decide whether their argument
                  -- belongs to the sort defined in
                  -- the sortdef.
                  --
                  -- here the semantic is to signal that this
                  -- sort is a subsort of the sort in the argument
                  -- and that thus all members of this sort are
                  -- also members of the sort in the argument
                  --
                  -- note that the predicates do not exists;
                  -- the Hets-sort-definition-axioms can't be parsed
                  -- easily into the OMDoc-Model (?).
                  omRecognizers =
                    foldl
                      (\oS (lateSort, _, _, insorts, syms) ->
                        if null insorts
                          then
                            oS
                          else
                            oS
                              ++
                              (
                              map
                                (\(is, isSym) ->
                                    let
                                      typeobj =
                                        OMDoc.mkType
                                          (OMDoc.mkOMDocRef "casl")
                                          $
                                          OMDoc.OMOMOBJ
                                            $
                                            OMDoc.mkOMOBJ
                                              $
                                              OMDoc.mkOMA
                                                (
                                                  [
                                                      OMDoc.mkOMSE
                                                        "casl"
                                                        "predication"
                                                    , OMDoc.toElement isSym
                                                  ]
                                                )
                                    in
                                      OMDoc.mkSymbolE
                                        Nothing
                                        (
                                          "recognizer_"
                                            ++ is
                                            ++ "_in_"
                                            ++ lateSort
                                        )
                                        OMDoc.SRObject
                                        (Just typeobj)
                                )
                                (zip insorts syms)
                              )
                      )
                      []
                      theoryLateInsorts
                in
                  do
  --                  omdoc <- xio
                    -- translate formulas (axiom/definition + presentation)                
                    -- (reason for IO)
                    (omAxs, omDefs, omPres) <-
                      wrapFormulasCMPIOOM
                        go
                        lenv
                        ln
                        nn
                        idnamemapping
                        uniqueNames
                        fullNames
                        (Hets.getNodeSentences node)
                    -- is the current node a reference ?
                    if isDGRef node
                      then
                        -- never mind...
                        return (omdoc, adtList)
                      else
                        let
                          -- if there are _any_ dummy imports
                          -- generate a single dummy theory 
                          -- for this theory
                          mDummyTheory =
                            case theoryDummyImports of
                              [] -> Nothing
                              _ ->
                                Just
                                  $
                                  OMDoc.Theory
                                    (theoryXmlId ++ "-dummy")
                                    (map OMDoc.mkCIm theoryDummyImports)
                                    []
                                    dummyTheoryComment
                          -- create new theory with all created elements
                          newtheory =
                            OMDoc.Theory
                              theoryXmlId
                              (
                                (map OMDoc.mkCSy theorySorts)
                                ++
                                (map OMDoc.mkCSy theoryOps)
                                ++
                                (map OMDoc.mkCSy theoryPreds)
                                ++
                                (map OMDoc.mkCAd theoryADTs)
                                ++
                                (map OMDoc.mkCSy omRecognizers)
                                ++
                                (map OMDoc.mkCAx omAxs)
                                ++
                                (map OMDoc.mkCDe omDefs)
                                ++
                                (map OMDoc.mkCIm theoryDefLinks)
                              )
                              (
                                [theoryPresentation]
                                ++
                                theoryPresentations
                                ++
                                omPres
                                ++
                                pPres
                                ++
                                oPres
                              )
                              Nothing
                          -- and finally, if there is a dummy, prepend it to the new theory
                          newTheories =
                            case mDummyTheory of
                              Nothing -> [newtheory]
                              (Just dt) -> [dt, newtheory]
                        in
                          -- insert new theory and new inclusions
                          return
                          (
                              (
                                OMDoc.addInclusions
                                  (
                                    OMDoc.addTheories
                                      omdoc
                                      newTheories
                                  )
                                  theoryThmLinks
                              )
                            , adtList -- the new adt list
                          )
              return res -- so close, so far... ^^
          )
          (return (initialOMDoc, [])) -- start with initial
          (Graph.labNodes dg) -- all nodes
    in
      omdocio >>= \(om, _) -> return om -- strip adtlist

{- |
  alias for 'Hets.inmGetNodeId'
-}
getNodeNameForXml::Hets.IdNameMapping->String
getNodeNameForXml = Hets.inmGetNodeId
  
-- | create an OMDoc-/symbol/ defining a predication.
--
-- Results in something like (/typenameX/ encodes signature):
--
-- @
--   \<symbol role=\"object\" name=\"/predname/\">
--     \<type system=\"casl\">
--       \<OMOBJ>
--         \<OMA>
--           \<OMS cd=\"casl\" name=\"predication\">
--           \<OMS cd=\"/libnameOfType1/\" name=\"/typename1/\">
--           \<OMS cd=\"/libnameOfType2/\" name=\"/typename2/\">
--           /.../
--         \<\/OMA>
--       \<\/OMOBJ>
--     \<\/type>
--   \<\/symbol>
-- @
predicationToXmlOM::
  Hets.LIB_NAME -- ^ library name of predication
  ->Graph.Node -- ^ node of predication
  ->Hets.IdNameMapping -- ^ name mapping for theory
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->(Id.Id, PredType) -- ^ predication to translate
  ->OMDoc.Symbol
predicationToXmlOM 
  ln
  nn
  currentmapping
  {-uniqueNames-}_
  {-fullNames-}_
  (pid, pt)
  =
    let
      e_fname = "OMDoc.OMDocOutput.predicationToXmlOM: "
      pidxmlid =
        Data.Maybe.fromMaybe
          (error (e_fname ++ "No name for \"" ++ show pid ++ "\""))
          (Hets.getNameForPred [currentmapping] (pid, pt))
      argnames =
        map
          (\args ->
            Data.Maybe.fromMaybe
              (error (e_fname ++ "No name for \"" ++ show args ++ "\""))
              (Hets.getNameForSort [currentmapping] args)
          )
          (predArgs pt)
      argorigins =
        map
          (\argxmlid ->
            case Hets.getNameOrigin [currentmapping] ln nn argxmlid of
              [] -> error (e_fname ++ "No origin for Sort " ++ show argxmlid)
              [o] -> getNodeNameForXml o
              (o:_) ->
                Debug.Trace.trace
                  ("More than one origin for \"" ++ show argxmlid ++ "\"")
                  $ 
                  getNodeNameForXml o 
          )
          argnames
      argzip =
        zip
          argnames
          argorigins
      typeobj =
        OMDoc.mkType
          (OMDoc.mkOMDocRef "casl")
          $
          OMDoc.OMOMOBJ
            $
            OMDoc.mkOMOBJ
              $
              OMDoc.mkOMA
                (
                  [
                    OMDoc.mkOMSE "casl" "predication"
                  ]
                  ++
                  (
                    map
                      (\(an, ao) ->
                        OMDoc.mkOMSE ao an
                      )
                      argzip
                  )
                )
    in
      OMDoc.mkSymbolE
        Nothing
        pidxmlid
        OMDoc.SRObject
        (Just typeobj)

-- | create an OMDoc-/symbol/ defining an operator.
--
-- Results in something like 
-- (/typenameX/ encodes signature, /typenameR/ encodes result type) :
--
-- @
--   \<symbol role=\"object\" name=\"/opname/\">
--     \<type system=\"casl\">
--       \<OMOBJ>
--         \<OMA>
--           \<OMS cd=\"casl\" name=\"function\">
--           \<OMS cd=\"/libnameOfType1/\" name=\"/typename1/\">
--           \<OMS cd=\"/libnameOfType2/\" name=\"/typename2/\">
--           /.../
--           \<OMS cd=\"/libnameOfTypeR/\" name=\"/typenameR/\">
--         \<\/OMA>
--       \<\/OMOBJ>
--     \<\/type>
--   \<\/symbol>
-- @
operatorToXmlOM::
  Hets.LIB_NAME -- ^ library name of operator
  ->Graph.Node -- ^ node of operator
  ->Hets.IdNameMapping -- ^ name mapping in library
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->(Id.Id, OpType) -- ^ operator to translate
  ->OMDoc.Symbol
operatorToXmlOM
  ln
  nn
  currentmapping
  {-uniqueNames-}_
  {-fullNames-}_
  (oid, ot)
  =
    let
      e_fname = "OMDoc.OMDocOutput.operatorToXmlOM: "
      oidxmlid =
        Data.Maybe.fromMaybe
          (error (e_fname ++ "No name for \"" ++ show oid ++ "\""))
          (Hets.getNameForOp [currentmapping] (oid, ot))
      argnames =
        map
          (\args ->
            Data.Maybe.fromMaybe
              (error (e_fname ++ "No name for \"" ++ show args ++ "\""))
              (Hets.getNameForSort [currentmapping] args)
          )
          (opArgs ot)
      argorigins =
        map
          (\argxmlid ->
            case Hets.getNameOrigin [currentmapping] ln nn argxmlid of
              [] -> error (e_fname ++ "No origin for Sort " ++ show argxmlid)
              [o] -> getNodeNameForXml o
              (o:_) ->
                Debug.Trace.trace
                  ("More than one origin for \"" ++ show argxmlid ++ "\"")
                  $ 
                  getNodeNameForXml o
          )
          argnames
      argzip =
        zip
          argnames
          argorigins
      resxmlid =
        Data.Maybe.fromMaybe
          (error (e_fname ++ "No name for \"" ++ show (opRes ot) ++ "\""))
          (Hets.getNameForSort [currentmapping] (opRes ot))
      resorigin =
        case Hets.getNameOrigin [currentmapping] ln nn resxmlid of
          [] -> error (e_fname ++ "No origin for Sort " ++ show resxmlid)
          [o] -> getNodeNameForXml o
          (o:_) ->
            Debug.Trace.trace
              ("More than one origin for \"" ++ show resxmlid ++ "\"")
              $ 
              getNodeNameForXml o
      typeobj =
        OMDoc.mkType
          (OMDoc.mkOMDocRef "casl")
          $
          OMDoc.OMOMOBJ
            $
            OMDoc.mkOMOBJ
              $
              OMDoc.mkOMA
                (
                  [
                    OMDoc.mkOMSE
                      "casl"
                      (if (opKind ot) == Total
                        then
                          "function"
                        else
                          "partial-function"
                      )
                  ]
                  ++
                  (
                    map
                      (\(an, ao) ->
                        OMDoc.mkOMSE ao an
                      )
                      argzip
                  )
                  ++
                  [
                    OMDoc.mkOMSE
                      resorigin
                      resxmlid
                  ]
                )
    in
      OMDoc.mkSymbolE
        Nothing
        oidxmlid
        OMDoc.SRObject
        (Just typeobj)

{-
sortToXmlOM::XmlNamed SORT->OMDoc.Symbol
sortToXmlOM xnSort =
  OMDoc.mkSymbol (xnName xnSort) OMDoc.SRSort
-}

-- | create a representation for a generated sort (generated by /ADT/)
genSortToXmlOM::
  String -- ^ generated from attribute
  ->XmlNamed SORT -- ^ sort
  ->OMDoc.Symbol
genSortToXmlOM genFrom xnSort =
  OMDoc.mkSymbolE (Just genFrom) (xnName xnSort) OMDoc.SRSort Nothing

-- | theory name, theory source (local)
data TheoryImport = TI (String, String)

instance Show TheoryImport where
  show (TI (tn, ts)) = ("Import of \"" ++ tn ++ "\" from \"" ++ ts ++ "\".")

-- | source name, source (absolute)
data Source a = S (String, String) a

instance Show (Source a) where
  show (S (sn, sf) _) = ("Source \"" ++ sn ++ "\" File : \"" ++ sf ++ "\".");

-- | create a filename from a library name (without path and extension).
--
-- Used to generate the name (xml:id) for an OMDoc-Document.
createLibName::ASL.LIB_NAME->String
createLibName libname = splitFile . fst . splitPath $ unwrapLinkSource libname

-- | extract the source-component from a library name
unwrapLinkSource::ASL.LIB_NAME->String
unwrapLinkSource
  (ASL.Lib_id lid) = unwrapLID lid
unwrapLinkSource
  (ASL.Lib_version lid _) = unwrapLID lid

-- | extract the source from a library ID
unwrapLID::ASL.LIB_ID->String
unwrapLID (ASL.Indirect_link path _ _) = path
unwrapLID (ASL.Direct_link url _) = url

-- | separates the path and filename part from a filename, first element is the
-- name, second the path (without last delimiter)
splitPath::String->(String, String)
splitPath f = case explode "/" f of
  [x] -> (x,"")
  l -> (last l, joinWith '/' $ init l)

-- | returns the name of a file without extension
splitFile::String->String
splitFile file =
  let
    filenameparts = explode "." file
  in
    case (length filenameparts) of
            1 -> file
            2 -> case head filenameparts of
                            "" -> "."++(last filenameparts)
                            fn -> fn
            _ -> implode "." $ init filenameparts 
        
-- | returns an 'omdoc-version' of a filename (e.g. test.env -> test.omdoc)
asOMDocFile::String->String
asOMDocFile file =
  let
    parts = splitFile' file
    fullfilename = last parts
    filenameparts = explode "." fullfilename
    (filename, mfileext) =
      case (length filenameparts) of
        0 -> ("", Nothing)
        1 -> (head filenameparts, Nothing)
        2 -> case head filenameparts of
          "" -> ("."++(last filenameparts), Nothing)
          fn -> (fn, Just (last filenameparts))
        _ -> ( implode "." $ init filenameparts, Just (last filenameparts)) 
  in
    case mfileext of
      Nothing -> joinFile $ (init parts) ++ [filename ++ ".omdoc"]
      (Just fileext) ->
        case map toLower fileext of
          "omdoc" -> file
          _ -> joinFile $ (init parts) ++ [filename ++ ".omdoc"]
  where
  splitFile' ::String->[String]
  splitFile' = explode "/"
  joinFile::[String]->String
  joinFile = implode "/"

-- | prepend a path to a pathname
fileSandbox::
  String -- ^ path to prepend (may not end on \'\/\')
  ->String -- ^ path
  ->String
fileSandbox [] file = file
fileSandbox sb file =
  sb ++ "/" ++ case head file of
    '/' -> tail file
    _ -> file

-- | used in /CMP/ generation.
--
-- Takes a list of 'Id.Pos'-file-positions and extracts the 
-- corresponding strings into a mapping.
posLines::[Id.Pos]->IO (Map.Map Id.Pos String)
posLines posl =
  do
    (psm, _) <- foldl (\iomaps pos@(Id.SourcePos name' line _) ->
      do
      (strmap, linemap) <- iomaps
      case Map.lookup name' linemap of
        (Just flines) ->
          return (Map.insert pos (headorempty (drop (line-1) flines)) strmap,
           linemap)
        Nothing ->
          do
            fe <- System.Directory.doesFileExist name'
            f <- if fe then readFile name' else (return "")
            flines <- return (lines f)
            return (Map.insert pos (headorempty (drop (line-1) flines)) strmap,
              Map.insert name' flines linemap)
        ) (return (Map.empty, Map.empty)) posl
    return psm

--data QUANTIFIER = Universal | Existential | Unique_existential
-- Quantifier as CASL Symbol
quantName :: QUANTIFIER->String
quantName Universal = caslSymbolQuantUniversalS
quantName Existential = caslSymbolQuantExistentialS
quantName Unique_existential = caslSymbolQuantUnique_existentialS

-- | check if a type t1 is a subtype of a type t2
--
-- Returns 'True' iff the first sort is the same as the second sort
-- or the first sort is a subsort of the second sort.
--
-- Uses 'Rel.path' /first/ /second/ /rel/ to check subsort.
isTypeOrSubType::
  Rel.Rel SORT
  ->SORT
  ->SORT
  ->Bool
isTypeOrSubType sortrel givensort neededsort =
  (givensort == neededsort)
    || (Rel.path givensort neededsort sortrel)

-- | check for type compatibility
-- a type /t1/ is compatible to a type /t2/ if
-- a) /t1 == t2/ or b) /t1/ is a subtype of /t2/
--
-- Each sort in the given lists must be /compatible/ to the sort
-- at the same position in the other list. That is, the sorts in the 
-- first lists must be of the same or of a sub-type of the sort in the
-- second list.
--
-- See 'isTypeOrSubType'
compatibleTypes::
  Rel.Rel SORT
  ->[SORT] -- ^ types to compare (/given/)
  ->[SORT] -- ^ types to compare (/needed/)
  ->Bool
compatibleTypes _ [] [] = True
compatibleTypes _ [] _ = False
compatibleTypes _ _ [] = False
compatibleTypes sortrel (s1:r1) (s2:r2) =
  (isTypeOrSubType sortrel s1 s2) && (compatibleTypes sortrel r1 r2)

-- | check type compatibility for two predicates
compatiblePredicate::Rel.Rel SORT->PredType->PredType->Bool
compatiblePredicate sortrel pt1 pt2 =
  compatibleTypes sortrel (predArgs pt1) (predArgs pt2)

-- | check type compatibility for two operators
compatibleOperator::Rel.Rel SORT->OpType->OpType->Bool
compatibleOperator sortrel ot1 ot2 =
--  (\x -> Debug.Trace.trace ("Comparing " ++ show ot1 ++ " to " ++ show ot2 ++ " -> " ++ show x) x)
--  $
  (isTypeOrSubType sortrel (opRes ot1) (opRes ot2))
  &&
  (compatibleTypes sortrel (opArgs ot1) (opArgs ot2))


-- | transform a list of variable declarations
-- into a list of (Name, Type) (bindings).
makeVarDeclList::
  Hets.LIB_NAME
  ->Graph.Node
  ->[Hets.IdNameMapping]
  ->[Hets.IdNameMapping]
  ->[VAR_DECL] -- ^ variable declarations to transform
  ->[(String, String)]
makeVarDeclList ln _ uN fN vdl =
  process vdl
  where
  process::[VAR_DECL]->[(String, String)]
  process [] = []
  process ( (Var_decl vl s _):vdl' ) =
    let
      msxn = findSortOriginCL ln uN fN s
    in
      (
        case msxn of
          Just (sxid, _) ->
            map
              (\vd ->
                (sxid, adjustStringForXmlName (show vd))
              )
              vl
          Nothing ->
            []
      )
      ++ process vdl'


-- first newline needs pulling up because we have a list of lists...
-- | transform Hets variable declarations to OpenMath variable bindings.
--
-- Results in something like this :
--
-- @
--   \<OMBVAR>
--     \<OMATTR>
--       \<OMATP>
--          \<OMS cd=\"casl\" name=\"type\"\/>
--          \<OMS cd=\"/libnameOfType1/\" name=\"/typename1/\"\/>
--       \<\/OMATP>
--       \<OMV name=\"/varname1/\"\/>
--     \<\/OMATTR>
--     \<OMATTR>
--       \<OMATP>
--          \<OMS cd=\"casl\" name=\"type\"\/>
--          \<OMS cd=\"/libnameOfType2/\" name=\"/typename2/\"\/>
--       \<\/OMATP>
--       \<OMV name=\"/varname2/\"\/>
--     \<\/OMATTR>
--     /.../
--   \<\/OMBVAR>
-- @
processVarDeclOM::
  Hets.LIB_NAME -- ^ libary of variable declaration
  ->Graph.Node -- ^ node 
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->[VAR_DECL] -- ^ variable declarations
  ->OMDoc.OMBindingVariables
processVarDeclOM ln nn uN fN vdl =
  OMDoc.mkOMBVAR
    (processVarDecls vdl)
  
  where
  processVarDecls::
    [VAR_DECL]
    ->[OMDoc.OMVariable]
  processVarDecls [] = []
  processVarDecls ( (Var_decl vl s _):vdl' ) =
    -- <ombattr><omatp><oms>+</omatp><omv></ombattr>
    (
      foldl
        (\decls vd ->
          decls
          ++
          [ OMDoc.toVariable $ createTypedVarOM ln nn uN fN s (adjustStringForXmlName (show vd)) ]
        )
        []
        vl
    )
    ++ (processVarDecls vdl')

-- | create an OMDoc-structure containing type information.
--
-- Results in something like this :
--
-- @
--   \<OMATP>
--     \<OMS cd=\"casl\" name=\"type\"\/>
--     \<OMS cd=\"/libname/\" name=\"/typename/\"\/>
--   \<\/OMATP>
-- @
--
-- See 'createTypedVarOM'
createATPOM::
  Hets.LIB_NAME -- ^ library of sort\/type
  ->Graph.Node -- ^ node
  ->[Hets.IdNameMapping] -- ^ unique name mapping 
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->SORT -- ^ sort\/type
  ->OMDoc.OMAttributionPart
createATPOM ln nn uniqueNames fullNames sort =
  OMDoc.mkOMATP
    [
      (
          OMDoc.mkOMS caslS typeS
        , createSymbolForSortOM ln nn uniqueNames fullNames sort
      )
    ]

-- | create an OMDoc-structure to attach type information to a variable.
--
-- Results in something like this :
--
-- @
--   \<OMATTR>
--     \<OMATP>
--        \<OMS cd=\"casl\" name=\"type\"\/>
--        \<OMS cd=\"/libnameOfType/\" name=\"/typename/\"\/>
--     \<\/OMATP>
--     \<OMV name=\"/varname/\"\/>
--   \<\/OMATTR>
-- @
--
-- See 'createATPOM'
createTypedVarOM::
  Hets.LIB_NAME -- ^ library of variable
  ->Graph.Node -- ^ node of variable
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->SORT -- ^ sort\/type of variable
  ->String -- ^ name of variable
  ->OMDoc.OMAttribution
createTypedVarOM ln nn uniqueNames fullNames sort varname =
  OMDoc.mkOMATTR
    (createATPOM ln nn uniqueNames fullNames sort)
    (OMDoc.mkOMSimpleVar (adjustStringForXmlName varname))

-- | find the XML-name and library name mapping for a sort
findSortOriginCL::
  Hets.LIB_NAME -- ^ library to search in
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->SORT -- ^ sort to find
  ->Maybe (XmlName, Hets.IdNameMapping)
findSortOriginCL
  ln
  uniqueNames
  fullNames
  s
  =
    Hets.findOriginInCurrentLib
      ln
      uniqueNames
      fullNames
      (\cm ->
        case
          find
            (\( (uid), _ ) -> uid == s)
            (Set.toList (Hets.inmGetIdNameSortSet cm))
        of
          Nothing -> Nothing
          Just (_, uname) -> (Just (uname, cm))
      )

-- | create an XML-representation of a 'SORT'.
createSymbolForSortOM::
  Hets.LIB_NAME -- ^ library of sort
  ->Graph.Node -- ^ node of sort
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->SORT -- ^ sort to represent
  ->OMDoc.OMSymbol
createSymbolForSortOM
  ln
  _ -- nn
  uniqueNames
  fullNames
  s
  =
    let
      (sortxmlid, sortorigin) =
        case
          findSortOriginCL
            ln
            uniqueNames
            fullNames
            s
        of
          Nothing ->
            error "OMDoc.OMDocOutput.createSymbolForSortOM: \
              \Cannot find sort origin!"
          (Just (sx, so)) ->
            (
                sx
              , getNodeNameForXml so
            )
    in
      OMDoc.mkOMS sortorigin sortxmlid

-- | Tries to find the XML-name and the library name mapping
-- of a predicate.
--
-- For qualified predicates the given sort-relation is used
-- to find a predicate with a compatible signature (according to
-- the relation).
findPredicateOriginCL::
  Hets.LIB_NAME -- ^ name of library to search in
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->Rel.Rel SORT -- ^ sort relation for compatibility checks
  ->PRED_SYMB -- ^ predication to find
  ->Maybe (XmlName, Hets.IdNameMapping)
findPredicateOriginCL
  ln
  uniqueNames
  fullNames
  _
  (Pred_name pr)
  =
    Hets.findOriginInCurrentLib
      ln
      uniqueNames
      fullNames
      (\cm ->
        case
          find
            (\( (uid, _), _ ) -> uid == pr)
            (Set.toList
              (
                Set.union
                  (Hets.inmGetIdNameGaPredSet cm)
                  (Hets.inmGetIdNamePredSet cm)
              )
            )
        of
          Nothing -> Nothing
          Just (_, uname) -> (Just (uname, cm))
      )
findPredicateOriginCL
  ln
  uniqueNames
  fullNames
  sortrel
  (Qual_pred_name pr pt _)
  =
    Hets.findOriginInCurrentLib
      ln
      uniqueNames
      fullNames
      (\cm ->
        case 
          preferEqualFindCompatible
            (Set.toList
              (
                Set.union
                  (Hets.inmGetIdNameGaPredSet cm)
                  (Hets.inmGetIdNamePredSet cm)
              )
            )
            (\( (uid, upt), _) ->
              uid == pr && upt == (Hets.cv_Pred_typeToPredType pt)
            )
            (\( (uid, upt), _) ->
              uid == pr &&
                compatiblePredicate
                  sortrel
                  upt
                  (Hets.cv_Pred_typeToPredType pt)
            )
        of
          Nothing -> Nothing
          (Just (_, uname)) -> Just (uname, cm)
      )

-- | create an xml-representation for a predication
createSymbolForPredicationOM::
  GlobalOptions -- ^ HetcatsOpts + debuggin information
  ->LibEnv -- ^ library environment
  ->Hets.LIB_NAME -- ^ library name of predication
  ->Graph.Node -- ^ node of predication
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  -> PRED_SYMB -- ^ the predication to process
  ->OMDoc.OMSymbol
createSymbolForPredicationOM _ lenv ln nn uniqueNames fullNames ps =
    let
      e_fname = "OMDoc.OMDocOutput.createSymbolForPredicationOM: "
      currentNode =
        fromMaybe
          (error (e_fname ++ "No such node!"))
          $
          (flip Graph.lab)
            nn
            $
            lookupDGraph ln lenv
      currentSign = Hets.getJustCASLSign $ Hets.getCASLSign (dgn_sign currentNode)
      currentRel = sortRel currentSign
      (predxmlid, predorigin) =
        case
          findPredicateOriginCL
            ln
            uniqueNames
            fullNames
            currentRel
            ps
        of
          Nothing ->
            Debug.Trace.trace
              (e_fname ++ "No origin for predicate! (" ++ (show ps) ++ ")")
              (adjustStringForXmlName (predName ps), "casl")
            
--            error (e_fname ++ "No origin for predicate! (" ++ (show ps) ++ ")")   
          (Just (predx, predo)) ->
            (   
                predx
              , getNodeNameForXml predo
            )
    in
      OMDoc.mkOMS predorigin predxmlid
    where
      predName::PRED_SYMB->String
      predName (Pred_name s) = show s
      predName (Qual_pred_name s _ _) = show s

-- | Tries to find the XML-name and the library name mapping
-- of an operator.
--
-- For qualified operators the given sort-relation is used
-- to find an operator with a compatible signature (according to
-- the relation).
findOperatorOriginCL::
  Hets.LIB_NAME -- ^ name of library to search in
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->Rel.Rel SORT -- ^ sort relation for compatibility checks
  ->OP_SYMB -- ^ operator to find
  ->Maybe (XmlName, Hets.IdNameMapping)
findOperatorOriginCL
  ln
  uniqueNames
  fullNames
  _
  (Op_name op)
  =
    Hets.findOriginInCurrentLib
      ln
      uniqueNames
      fullNames
      (\cm ->
        case
          find
            (\( (uid, _), _ ) -> uid == op)
              (
              (Set.toList (Hets.inmGetIdNameOpSet cm))
              ++
              (Set.toList (Hets.inmGetIdNameConsSetLikeOps cm))
              )
        of
          Nothing -> Nothing
          Just (_, uname) -> (Just (uname, cm))
      )
findOperatorOriginCL
  ln
  uniqueNames
  fullNames
  sortrel
  (Qual_op_name op ot _)
  =
    Hets.findOriginInCurrentLib
      ln
      uniqueNames
      fullNames
      (\cm ->
        case 
          preferEqualFindCompatible
            (
              (Set.toList (Hets.inmGetIdNameOpSet cm))
              ++
              (Set.toList (Hets.inmGetIdNameConsSetLikeOps cm))
            )
            (\( (uid, uot), _) ->
              uid == op && uot == (Hets.cv_Op_typeToOpType ot)
            )
            (\( (uid, uot), _) ->
              uid == op
              && compatibleOperator sortrel uot (Hets.cv_Op_typeToOpType ot)
            )
        of
          Nothing -> Nothing
          (Just (_, uname)) -> Just (uname, cm)
      )

-- | create a xml-representation of an operator
processOperatorOM::
  GlobalOptions -- ^ HetscatsOpts + debug information
  ->LibEnv -- ^ library environment
  ->Hets.LIB_NAME -- ^ library name of operator
  ->Graph.Node -- ^ node of operator
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->OP_SYMB -- ^ the operator to process
  ->OMDoc.OMSymbol
      -- ^ the xml-representation of the operator
processOperatorOM _ lenv ln nn uniqueNames fullNames
    os =
    let
      e_fname = "OMDoc.OMDocOutput.processOperatorOM: "
      currentNode =
        fromMaybe
          (error (e_fname ++ "No such node!"))
          $
          (flip Graph.lab)
            nn
            $
            lookupDGraph ln lenv
      currentSign =
        Hets.getJustCASLSign $ Hets.getCASLSign (dgn_sign currentNode)
      currentRel = sortRel currentSign
      (opxmlid, oporigin) =
        case
          findOperatorOriginCL
            ln
            uniqueNames
            fullNames
            currentRel
            os
        of
          Nothing ->
            error (e_fname ++ "No origin for operator!")
          (Just (opx, opo)) ->
            (   
                opx
              , getNodeNameForXml opo
            )

    in
      OMDoc.mkOMS oporigin opxmlid

-- | Generic function to search for an element where two predicates
-- signal preferred (/equal/) and sufficient (/compatible/) elements
-- respectively.
--
-- If an /equal/ element exists it is returned, else if a /compatible/
-- element exists, it is returned and else 'Nothing' is returned.
preferEqualFindCompatible::
  [a] -- ^ elements to search in
  ->(a->Bool) -- ^ /equality/-predicate
  ->(a->Bool) -- ^ /compatibility/-predicate
  ->Maybe a
preferEqualFindCompatible l isEqual isCompatible =
  case find isEqual l of
    Nothing ->
      find isCompatible l
    x -> x

-- | create a xml-representation from a term (in context of a theory).
--
-- This function is applied recursively to all 'TERM'S inside the given term.
-- 'FORMULA'S inside a 'TERM' are processed by 'processFormulaOM'.
processTermOM::
  forall f .
  (Pretty.Pretty f)
  =>GlobalOptions -- ^ HetcatsOpts + debugging information
  ->LibEnv -- ^ library environment
  ->Hets.LIB_NAME -- ^ library name of term
  ->Graph.Node -- ^ node of term
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->[(String, String)] -- ^ variable bindings (Name, Type)
  -> TERM f -- ^ the term to process
  ->OMDoc.OMElement
-- Simple_id
processTermOM _ _ _ _ _ _ _
  (Simple_id id' ) =
  OMDoc.toElement
    $
    (OMDoc.mkOMSimpleVar (show id'))
-- Qual_var
processTermOM _ _ ln nn uniqueNames fullNames vb
  (Qual_var v s _) =
    if elem (show v) (map snd vb)
      then
        let
          matches = map fst $ filter (\(_, sort) -> (==) (show v) sort) vb
          element =
            case
              findSortOriginCL
                ln
                uniqueNames
                fullNames
                s
            of
              Nothing ->
                error "processTermOM@Qual_var: cannot find sort!"
              (Just (sortxmlid, _)) ->
                if elem sortxmlid matches
                  then
                    OMDoc.toElement
                      $
                      OMDoc.mkOMCommented
                        (
                          (show v) ++ " is qualified for "
                          ++ (implode ", " matches)
                        )
                        (OMDoc.mkOMSimpleVar (show v))
                  else
                    OMDoc.toElement
                      $
                      (
                        OMDoc.mkOMCommented
                          (
                            "Qualification mismatch: Expected one of \"" 
                            ++ (implode ", " matches)
                            ++ "\" but \"" ++ sortxmlid ++ "\" found..."
                            
                          )
                          $
                          (OMDoc.mkOMSimpleVar (show v))
                      )
        in
          element
      else
        OMDoc.toElement
          $
          (createTypedVarOM ln nn uniqueNames fullNames s (show v) )
-- Application
processTermOM go lenv ln nn uniqueNames fullNames vb
  (Application op termlist _) =
    let
      omterms = 
        foldl
          (\ts t ->
            ts ++
              [
                OMDoc.toElement
                  $
                  processTermOM go lenv ln nn uniqueNames fullNames vb t
              ]
          )
          []
          termlist
    in
      if null omterms
        then
          OMDoc.toElement
            $
            (processOperatorOM go lenv ln nn uniqueNames fullNames op)
        else
          OMDoc.toElement
            $
            OMDoc.mkOMA
              (
                [
                  OMDoc.toElement
                    $
                    processOperatorOM go lenv ln nn uniqueNames fullNames op
                ] ++ omterms
              )
-- Cast
processTermOM go lenv ln nn uniqueNames fullNames vb
  (Cast t s _) =
    processTermOM go lenv ln nn uniqueNames fullNames vb
      (Application
        (Op_name $ Hets.stringToId "PROJ")
        [t, (Simple_id $ Id.mkSimpleId (show s))]
        Id.nullRange
      )
-- Conditional
processTermOM go lenv ln nn uniqueNames fullNames vb
  (Conditional t1 f t2 _) =
    OMDoc.toElement
      $
      OMDoc.mkOMA
        [
            OMDoc.toElement $ OMDoc.mkOMS caslS "IfThenElse"
          , OMDoc.toElement $ processFormulaOM go lenv ln nn uniqueNames fullNames vb f
          , OMDoc.toElement $ processTermOM go lenv ln nn uniqueNames fullNames vb t1
          , OMDoc.toElement $ processTermOM go lenv ln nn uniqueNames fullNames vb t2
        ]
-- Sorted_term is to be ignored in OMDoc (but could be modelled...) (Sample/Simple.casl uses it...)
processTermOM go lenv ln nn uniqueNames fullNames vb
  (Sorted_term t _ _) =
    processTermOM go lenv ln nn uniqueNames fullNames vb t
-- Unsupported Terms...
processTermOM _ _ _ _ _ _ _ _ =
  error "OMDoc.OMDocOutput.processTermOM: Unsupported Term encountered..." 


-- | translate a 'FORMULA' into an OMDoc-structure.
--
-- This function is applied recusively on all encountered formulas inside
-- the given formula. 'TERM'S inside the formula are processed by 
-- 'processTermOM'.
processFormulaOM::
  forall f .
  (Pretty.Pretty f)
  =>GlobalOptions -- ^ HetcatsOpts + debugging information
  ->LibEnv  -- ^ library environment
  ->Hets.LIB_NAME -- ^ library name of formula
  ->Graph.Node -- ^ node of formula
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->[(String, String)] -- ^ variable bindings (Name, Type)
  ->FORMULA f  -- ^ formula to translate
  ->OMDoc.OMElement
-- Quantification
processFormulaOM go lenv ln nn uN fN vb
  (Quantification q vl f _) =
    let
      currentVarNames = map snd vb
      varbindings = makeVarDeclList ln nn uN fN vl
      newBindings =
        foldl
          (\nb c@(vtn, vnn) ->
            if elem vnn currentVarNames
              then
                map
                  (\o@(vto, vno) ->
                    if vno == vnn
                      then
                        if vto == vtn
                          then
                            Debug.Trace.trace
                              (
                                "Warning: Variable " ++ vtn ++
                                " has been bound a second time (same type)"
                              )
                              o
                          else
                            Debug.Trace.trace
                              (
                                "Warning: Variable " ++ vtn ++ "::" ++ vtn ++ 
                                " shadows existing variable of type " ++ vto
                              )
                              c
                      else
                        o
                  )
                  nb
              else
                nb ++ [c]
          )
          vb
          varbindings
    in
      OMDoc.mkOMBINDE
        (OMDoc.mkOMS caslS (quantName q))
        (processVarDeclOM ln nn uN fN vl)
        (processFormulaOM go lenv ln nn uN fN newBindings f)

-- Conjunction
processFormulaOM go lenv ln nn uN fN vb
  (Conjunction fl _) =
    OMDoc.mkOMAE
      (
        [ OMDoc.mkOMSE caslS caslConjunctionS ]
        ++
        (
          foldl
            (\fs f ->
              fs ++ [ processFormulaOM go lenv ln nn uN fN vb f ]
            )
            []
            fl
        )
      )

-- Disjunction
processFormulaOM go lenv ln nn uN fN vb
  (Disjunction fl _) =
    OMDoc.mkOMAE
      (
        [ OMDoc.mkOMSE caslS caslDisjunctionS ]
        ++
        (
          foldl
            (\fs f ->
              fs ++ [ processFormulaOM go lenv ln nn uN fN vb f ]
            )
            []
            fl
        )
      )
-- Implication
processFormulaOM go lenv ln nn uN fN vb
  (Implication f1 f2 b _) =
    OMDoc.mkOMAE
      [
          OMDoc.mkOMSE caslS caslImplicationS
        , processFormulaOM go lenv ln nn uN fN vb f1
        , processFormulaOM go lenv ln nn uN fN vb f2
        , processFormulaOM go lenv ln nn uN fN vb 
            ((if b then True_atom Id.nullRange else False_atom Id.nullRange)::(FORMULA f))
      ]

-- Equivalence
processFormulaOM go lenv ln nn uN fN vb
  (Equivalence f1 f2 _) =
    OMDoc.mkOMAE
      [
          OMDoc.mkOMSE caslS caslEquivalenceS
        , processFormulaOM go lenv ln nn uN fN vb f1
        , processFormulaOM go lenv ln nn uN fN vb f2
      ]
-- Negation
processFormulaOM go lenv ln nn uN fN vb
  (Negation f _) =
    OMDoc.mkOMAE
      [
          OMDoc.mkOMSE caslS caslNegationS
        , processFormulaOM go lenv ln nn uN fN vb f
      ]
-- Predication
processFormulaOM go lenv ln nn uN fN vb
  (Predication p tl _) =
    OMDoc.mkOMAE
      (
        [
            OMDoc.mkOMSE caslS caslPredicationS
          , OMDoc.toElement $ createSymbolForPredicationOM go lenv ln nn uN fN p
        ]
        ++
        (
          foldl
            (\ts t ->
              ts ++ [ processTermOM go lenv ln nn uN fN vb t ]
            )
            []
            tl
        )
      )
-- Definedness
processFormulaOM go lenv ln nn uN fN vb
  (Definedness t _ ) =
    OMDoc.mkOMAE
      [
          OMDoc.mkOMSE caslS caslDefinednessS
        , processTermOM go lenv ln nn uN fN vb t
      ]
-- Existl_equation
processFormulaOM go lenv ln nn uN fN vb
  (Existl_equation t1 t2 _) = 
    OMDoc.mkOMAE
      [
          OMDoc.mkOMSE caslS caslExistl_equationS
        , processTermOM go lenv ln nn uN fN vb t1
        , processTermOM go lenv ln nn uN fN vb t2
      ]
-- Strong_equation
processFormulaOM go lenv ln nn uN fN vb
  (Strong_equation t1 t2 _) = 
    OMDoc.mkOMAE
      [
          OMDoc.mkOMSE caslS caslStrong_equationS
        , processTermOM go lenv ln nn uN fN vb t1
        , processTermOM go lenv ln nn uN fN vb t2
      ]
-- Membership
processFormulaOM go lenv ln nn uN fN vb
  (Membership t s _) = 
    OMDoc.mkOMAE
      [
          OMDoc.mkOMSE caslS caslMembershipS
        , processTermOM go lenv ln nn uN fN vb t
        , OMDoc.toElement $ createSymbolForSortOM ln nn uN fN s
      ]
-- False_atom
processFormulaOM _ _ _ _ _ _ _
  (False_atom _) =
    OMDoc.mkOMSE caslS caslSymbolAtomFalseS
-- True_atom
processFormulaOM _ _ _ _ _ _ _
  (True_atom _) =
    OMDoc.mkOMSE caslS caslSymbolAtomTrueS
-- Sort_gen_ax
processFormulaOM go lenv ln nn uN fN vb
  (Sort_gen_ax constraints freetype) =
  let
    soCon = Induction.inductionScheme constraints 
  in
    OMDoc.mkOMAE
      (
      [
        OMDoc.mkOMSE
          caslS
          caslSort_gen_axS
      ]
      ++
      (
        processConstraintsOM
          go
          lenv
          ln
          nn
          uN
          fN
          constraints
      )
      ++
      (
        case Result.resultToMaybe soCon of
          Nothing -> []
          (Just (cf::(FORMULA f))) -> [processFormulaOM go lenv ln nn uN fN vb cf]
      )
      ++
      [
        OMDoc.mkOMSE
          caslS
          (if freetype then caslSymbolAtomTrueS else caslSymbolAtomFalseS)
      ]
      )
-- unsupported formulas
-- Mixfix_formula
processFormulaOM _ _ _ _ _ _ _
  (Mixfix_formula {}) =
    OMDoc.mkOMComment "unsupported : Mixfix_formula"
-- Unparsed_formula
processFormulaOM _ _ _ _ _ _ _
  (Unparsed_formula {}) =
    OMDoc.mkOMComment "unsupported : Unparsed_formula"
-- ExtFORMULA
processFormulaOM _ _ _ _ _ _ _
  (ExtFORMULA {}) =
    OMDoc.mkOMComment "unsupported : ExtFORMULA"

-- | translate constraints to OMDoc by fitting the data into 
--   artificial operator applications.
--
--  This is used by 'processFormula' and will be obsolete
--  when the formulas generated by 'Induction.inductionScheme' can
--  be read back to constraints.
processConstraintsOM::
  GlobalOptions -- ^ HetcatsOpts + debugging information
  ->LibEnv -- ^ library environment
  ->Hets.LIB_NAME -- ^ library of constraints
  ->Graph.Node -- ^ node of constrains
  ->[Hets.IdNameMapping] -- ^ unique name mapping
  ->[Hets.IdNameMapping] -- ^ name mapping
  ->[ABC.Constraint] -- ^ constraints to process
  ->[OMDoc.OMElement] 
processConstraintsOM _ _ _ _ _ _ [] = []
processConstraintsOM go lenv ln nn uN fN constraints
  =
    let
      e_fname = "OMDoc.OMDocOutput.processConstraintsOM: "
      idnamemapping =
        case
          find
            (\inm ->
              (Hets.inmGetLibName inm) == ln
              && (Hets.inmGetNodeNum inm) == nn
            )
            fN
        of
          Nothing -> error (e_fname ++ "No such name...")
          (Just a) -> a
    in
    [
        OMDoc.mkOMAE
          (
            [
              OMDoc.mkOMSE caslS "constraint-definitions"
            ]
            ++
            (
              foldl
                (\celems (ABC.Constraint news ops' origs) ->
                  celems ++
                  [
                    OMDoc.mkOMAE
                      [
                          OMDoc.mkOMSE caslS "constraint-context"
                        , OMDoc.mkOMSE caslS (getSortIdName idnamemapping news)
                        , OMDoc.mkOMSE caslS (getSortIdName idnamemapping origs)
                        , OMDoc.mkOMAE
                            (
                              [
                                  OMDoc.mkOMSE caslS "constraint-list"
                              ]
                              ++
                              (
                                foldl
                                  (\vars (op, il) ->
                                    vars ++
                                    [
                                      OMDoc.mkOMAE
                                        [
                                            OMDoc.mkOMSE caslS "constraint"
                                          , OMDoc.mkOMAE
                                              (
                                                [
                                                    OMDoc.mkOMSE
                                                      caslS
                                                      "constraint-indices"
                                                ]
                                                ++
                                                (
                                                  map OMDoc.mkOMIE il
                                                )
                                              )
                                          , OMDoc.toElement
                                              (
                                              processOperatorOM
                                                go
                                                lenv
                                                ln
                                                nn
                                                uN
                                                fN
                                                op
                                              )
                                        ]
                                    ]
                                  )
                                  []
                                  ops'
                              )
                            )
                      ]
                  ]
                )
                []
                constraints
            )
          )
    ]

-- | translate 'CASLFORMULA's to OMDoc-elements (/axiom|definition|presentation/) 
--  where for each /axiom/- or /definition/-element a /presentation/-element 
--  is generated to preserve the internal (Hets) name.
wrapFormulasCMPIOOM::
  GlobalOptions -- ^ HetcatsOpts + debugging-information
  ->LibEnv -- ^ library environment
  ->Hets.LIB_NAME -- ^ library of formulas
  ->Graph.Node -- ^ node of formulas
  ->Hets.IdNameMapping -- ^ name mapping for this library
  ->[Hets.IdNameMapping] -- ^ mapping of unique names 
  ->[Hets.IdNameMapping] -- ^ mapping of names
  ->[(Ann.Named CASLFORMULA)] -- ^ named formulas 
  ->IO ([OMDoc.Axiom], [OMDoc.Definition], [OMDoc.Presentation])
wrapFormulasCMPIOOM go lenv ln nn cM uN fN fs =
  let
    posLists = concatMap Id.getPosList (map Ann.sentence fs)
  in
  do
    poslinemap <- posLines posLists
    return
      $
      foldl
        (\(wax, wde, wpr) f ->
          let
            (axdef, pr) = wrapFormulaCMPOM go lenv ln nn cM uN fN f poslinemap
          in
            case axdef of
              (Left ax) ->
                (wax++[ax], wde, wpr++[pr])
              (Right def) ->
                (wax, wde++[def], wpr++[pr])
        )
        ([], [], [])
        (zip fs [1..])

-- | translate a single named 'CASLFORMULA' to OMDoc.
-- 
-- This will result in either an /axiom/- or /definition/-element and a 
-- corresponding /presentation/-element preserving the internal (Hets) name.
wrapFormulaCMPOM::
  GlobalOptions -- ^ HetscatsOpts + debuggin-information
  ->LibEnv -- ^ library environment
  ->Hets.LIB_NAME -- ^ library of formula
  ->Graph.Node -- ^ node of formula
  ->Hets.IdNameMapping -- ^ name mapping for library
  ->[Hets.IdNameMapping] -- ^ mapping of unique names 
  ->[Hets.IdNameMapping] -- ^ mapping of names
  ->((Ann.Named CASLFORMULA), Int) -- ^ named formula and integer-tag to 
                                   --   disambiguate formula
  ->(Map.Map Id.Pos String) -- ^ map of original formula input to create /CMP/-elements
  ->(Either OMDoc.Axiom OMDoc.Definition, OMDoc.Presentation)
wrapFormulaCMPOM
  go
  lenv
  ln
  nn
  currentMapping
  uniqueNames
  fullNames
  (ansen, sennum)
  poslinemap =
  let
    senxmlid =
      case
        Hets.getNameForSens
          [currentMapping]
          (Hets.stringToId $ Ann.senName ansen, sennum)
      of
        Nothing ->
          error
            (
              "OMDoc.OMDocOutput.wrapFormulaCMPOM: \
              \No unique name for Sentence \"" ++ Ann.senName ansen ++ "\""
            )
        (Just n) -> n
    sens = Ann.sentence ansen
    sposl = Id.getPosList sens
    omformula = processFormulaOM go lenv ln nn uniqueNames fullNames [] sens
    omobj = OMDoc.mkOMOBJ omformula
    cmptext = 
      foldl
        (\cmpt p ->
          cmpt ++ (Map.findWithDefault "" p poslinemap) ++ "\n"
        )
        ""
        sposl
    cmp = OMDoc.mkCMP (OMDoc.MTextText cmptext)
    cmpl =
      if null $ trimString cmptext
        then
          []
        else
          [cmp]
    fmp = OMDoc.FMP Nothing (Left omobj)
    axiom =
      if Ann.isAxiom ansen
        then
          Left $ OMDoc.mkAxiom senxmlid cmpl [fmp]
        else
          Right $ OMDoc.mkDefinition senxmlid [cmp] [fmp]
    pres = makePresentationForOM senxmlid (Ann.senName ansen)
  in
    (axiom, pres)

