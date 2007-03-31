{- |
Module      :  $Header$
Copyright   :  (c) Hendrik Iben, Uni Bremen 2005-2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  hiben@tzi.de
Stability   :  provisional
Portability :  non-portable(Logic)

  Input-methods for reading OMDoc
-}
module OMDoc.OMDocInput
  (
    mLibEnvFromOMDocFile
  ) 
  where

import qualified OMDoc.HetsDefs as Hets
import CASL.Sign
import CASL.Morphism
import CASL.Logic_CASL
import CASL.AS_Basic_CASL
import qualified Common.Id as Id
import qualified Syntax.AS_Library as ASL
import qualified CASL.AS_Basic_CASL as ABC

import Static.DevGraph
import qualified Data.Graph.Inductive.Graph as Graph
import qualified Common.Lib.Graph as CLGraph

-- Often used symbols from HXT
import Text.XML.HXT.Parser
  (
      (.>), xshow, isTag, getChildren, getValue
    , emptyRoot, v_1, v_0, a_issue_errors, a_source, a_validate
    , a_check_namespaces
  )
        
import qualified Text.XML.HXT.Parser as HXT hiding (run, trace, when)

import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Common.Lib.Rel as Rel

import qualified Common.AS_Annotation as Ann

import qualified Logic.Prover as Prover

import Data.Maybe (fromMaybe)
import Data.List (find)

import qualified Common.GlobalAnnotations as GA

import Debug.Trace (trace)

import qualified System.IO.Error as System.IO.Error

import Driver.Options

import Control.Monad
import Control.Exception as Control.Exception

import qualified Network.URI as URI

import OMDoc.Util
import OMDoc.Container
import OMDoc.XmlHandling

import OMDoc.OMDocDefs

import qualified OMDoc.OMDocInterface as OMDoc
import qualified OMDoc.OMDocXml as OMDocXML

import qualified OMDoc.Util as Util

import qualified System.Directory as System.Directory

{- |
  A wrapper-function for Hets.
  Tries to load an OMDoc file and to create a LibEnv.
  Uses library-path specified in HetcatsOpts to search for imported files.
  On (IO-)error Nothing is returned
-}
mLibEnvFromOMDocFile::
  HetcatsOpts -- ^ setup libdir to search for files
  ->FilePath -- ^ the file to load
  ->IO (Maybe (ASL.LIB_NAME, LibEnv))
mLibEnvFromOMDocFile hco file =
  Control.Exception.catch
    (
      do
        (ln, _, lenv) <- libEnvFromOMDocFile
          (emptyGlobalOptions { hetsOpts = hco })
          file
        return (Just (ln, lenv))
    )
    (\_ -> putIfVerbose hco 0 "Error loading OMDoc!" >> return Nothing)

{- |
  Tries to load an OMDoc file an to create a LibEnv.
  Uses @dGraphGToLibEnvOMDocId@ to create library names.
-}
libEnvFromOMDocFile::
  GlobalOptions -- ^ library path setup with hetsOpts + debugging options
  ->String -- ^ URI \/ File to load
  ->IO (ASL.LIB_NAME, DGraph, LibEnv)
libEnvFromOMDocFile go f =
  makeImportGraphOMDoc go f >>=
    return . importGraphToLibEnvOM go
--    return . dGraphGToLibEnvOMDocId go . hybridGToDGraphG go . processImportGraphXN go


{- -- debug
  loads an OMDoc file and returns it even if there are errors
  fatal errors lead to IOError
loadOMDoc ::
  String -- ^ URI \/ File to load
  ->(IO HXT.XmlTrees)
loadOMDoc f =
  do
    tree <- (
      HXT.run' $
      HXT.parseDocument
        [
           (a_source, f)
          ,(a_validate, v_0) -- validation is nice, but HXT does not give back
                             -- even a partial document then...
          ,(a_check_namespaces,v_1) -- needed,really...
          ,(a_issue_errors, v_0)
        ]
        emptyRoot
      )
    status <- return ( (
      read $
      xshow $
      applyXmlFilter (getValue "status") tree
      ) :: Int )
    if status <= HXT.c_err
      then
        return $ applyXmlFilter (getChildren .> isTag "omdoc") tree
      else
        ioError $ userError ("Error loading \"" ++ f ++ "\"")
-}

{- |
  extracts constructors from adt-structures
-}
-- i need a back-reference to the theory to get presentations for adt-constructors...
extractConsXNWONFromOMADT::
  FFXInput -- ^ current input settings
  ->(Graph.Node, OMDoc.Theory) -- ^ theory of adt
  ->OMDoc.ADT -- ^ adt
  ->(XmlNamedWONId, [(XmlNamedWONId, OpTypeXNWON)])
extractConsXNWONFromOMADT ffxi (origin, theory) adt =
  let
    e_fname = "OMDoc.OMDocInput.extractConsXNWONFromOMADT: "
    sortdef =
      case OMDoc.adtSortDefs adt of
        [] -> error (e_fname ++ "Empty SortDefs!")
        (sd:_) -> sd
    sorts' = OMDoc.sortDefName sortdef
    sortid =
      case findByNameAndOrigin
            sorts'
            origin
            (mapSetToSet $ xnSortsMap ffxi)
              of
                Nothing -> error (e_fname ++ "No sort for ADT!")
                (Just si) -> si
    cons = OMDoc.sortDefConstructors sortdef
  in
    (sortid, map (\n -> extractConXNWON n sortid) cons)
  where
    extractConXNWON::
        OMDoc.Constructor
      ->XmlNamedWONId
      ->(XmlNamedWONId, OpTypeXNWON) -- empty list on error
    extractConXNWON con sortid =
      let
        e_fname =
          "OMDoc.OMDocInput.extractConsXNWONFromOMADT#extractConXNWON: "
        conxname = OMDoc.constructorName con
        conid =
          case
            find
              (\p ->
                OMDoc.presentationForId p == conxname
              )
              (OMDoc.theoryPresentations theory)
          of
            Nothing -> Hets.stringToId conxname
            (Just p) ->
              case
                find
                  (\u -> OMDoc.useFormat u == "Hets")
                  (OMDoc.presentationUses p)
              of
                Nothing -> Hets.stringToId conxname
                (Just u) -> read $ (OMDoc.useValue u)
        conxnwonid = XmlNamed (Hets.mkWON conid origin) conxname
        args =
          map
            (\at ->
              case OMDoc.typeOMDocMathObject at of
                (OMDoc.OMOMOBJ (OMDoc.OMObject ome)) ->
                  case ome of
                    (OMDoc.OMES oms) ->
                      OMDoc.omsName oms
                    _ -> error (e_fname ++ "Invalid Element for SortDefArgs!")
                _ -> error (e_fname ++ "Can't handle Argument of non-OMOBJ type!")
            )
            (OMDoc.constructorArguments con)
        argsxn =
          map
            (\n -> 
              case findByNameAndOrigin
                    n
                    origin
                    (mapSetToSet $ xnSortsMap ffxi)
                      of
                        Nothing -> error (e_fname ++ "Unknown sort in constructor...")
                        (Just x) -> x
            )
            args
      in
        (conxnwonid, OpTypeXNWON Total argsxn sortid)

{- |
  creates sentences from adt-constructors
-}
consToSensXN::
  XmlNamedWONId -- ^ name of the constructed sort
  ->[(XmlNamedWONId, OpTypeXNWON)] -- ^ constructors
  ->XmlNamed Hets.SentenceWO
consToSensXN sortid conlist =
  XmlNamed 
    (Hets.mkWON
      (Ann.NamedSen {
        Ann.senName    = "ga_generated_" ++ show (xnWOaToa sortid),
        Ann.isAxiom    = True,
        Ann.isDef      = False,
        Ann.wasTheorem = False,
        Ann.sentence   = (Sort_gen_ax
          (
          foldl (\constraints (id' , ot) ->
              constraints ++
              [ Constraint
                  (xnWOaToa sortid)
                  [(Qual_op_name
                      (xnWOaToa id' )
                      (Hets.cv_OpTypeToOp_type $ opTypeXNWONToOpType ot)
                      Id.nullRange , [0])] 
                  (xnWOaToa sortid)
              ]
            ) [] conlist
          )
          True
        )})
      (xnWOaToO sortid)
    )
    ("ga_generated_" ++ (xnName sortid))


{- |
  extracts symbols used in a OMDoc-Morphism storing a mapping
  of symbols and a list of hidden symbols
-}
fetchOMRequationSymbols::OMDoc.Morphism->([String], Hets.RequationList)
fetchOMRequationSymbols morph =
  let
    hides = OMDoc.morphismHiding morph
    reqlist =
      foldl
        (\rl req ->
          case req of
            (
                (OMDoc.MTextOM (OMDoc.OMObject (OMDoc.OMES oms1)))
              , (OMDoc.MTextOM (OMDoc.OMObject (OMDoc.OMES oms2)))) ->
              rl ++
                [
                  (
                      (OMDoc.omsCD oms1, OMDoc.omsName oms1)
                    , (OMDoc.omsCD oms2, OMDoc.omsName oms2)
                  )
                ]
            _ ->
              rl
        )
        []
        (OMDoc.morphismRequations morph)
  in
    (hides, reqlist)

defaultDGLinkType::DGLinkType
defaultDGLinkType = GlobalDef

defaultDGOrigin::DGOrigin
defaultDGOrigin = DGExtension

defaultDGLinkLab::DGLinkLab
defaultDGLinkLab =
  DGLink Hets.emptyCASLGMorphism defaultDGLinkType defaultDGOrigin defaultEdgeID


-- remove keys from a map (will result in removing double entries when merging sets)
mapSetToSet::(Ord b)=>Map.Map a (Set.Set b)->Set.Set b
mapSetToSet mapping =
  foldl (\set (_, s) ->
      Set.union set s
    ) Set.empty (Map.toList mapping)
                

{- |
  An annotated theory set is a set of (Graph.Node, Theory) where
  each element in the set contains one theory-tree and is annotated by the
  number of the theory (appearance in file) (pseudo-graph-nodes)
-}
buildAOMTheorySet::OMDoc.OMDoc->Set.Set (Graph.Node, OMDoc.Theory)
buildAOMTheorySet omdoc =
  Set.fromList
    $
    zip [1..] (OMDoc.omdocTheories omdoc)

{- |
  creates a set of theory names by examining the name of the theory and
  searching for presentation elements.
-}
nodeNamesXNFromOM::Set.Set (Graph.Node, OMDoc.Theory)->TheoryXNSet
nodeNamesXNFromOM aomset =
  Set.fromList
    $
    Set.fold
      (\(gn, omt) l ->
        let
          theoid = stripFragment $ OMDoc.theoryId omt
          theoname =
            case
              omPresentationFor omt theoid "Hets"
            of
              Nothing -> idToNodeName $ read ("["++theoid++",,0]")
              (Just x) -> idToNodeName $ read x
        in
          l ++ [XmlNamed (gn, theoname) theoid]
      )
      []
      aomset
                

omPresentationFor::OMDoc.Theory->String->String->Maybe String
omPresentationFor theory pid format =
  case
    find
      (\p -> OMDoc.presentationForId p == pid)
      (OMDoc.theoryPresentations theory)
  of
    Nothing -> Nothing
    (Just p) ->
      case
        find
          (\u -> OMDoc.useFormat u == format)
          (OMDoc.presentationUses p)
      of
        Nothing -> Nothing
        (Just u) -> Just (OMDoc.useValue u)


sortsXNWONFromOMTheory::(Graph.Node, OMDoc.Theory)->(Set.Set XmlNamedWONSORT)
sortsXNWONFromOMTheory (origin, theory) =
  foldl
    (\ss con ->
      case con of
        (OMDoc.CSy symbol) ->
          if OMDoc.symbolRole symbol == OMDoc.SRSort
            then
              let
                sid = OMDoc.symbolId symbol
                sname =
                  case 
                    omPresentationFor theory sid "Hets"
                  of
                    Nothing -> Hets.stringToId sid
                    (Just x) -> read x
              in
                Set.insert (XmlNamed (Hets.mkWON sname origin) sid) ss
            else
              ss
        _ ->
          ss
    )
    Set.empty
    (OMDoc.theoryConstitutives theory)

findByName::(Container b (XmlNamed a))=>String->b->Maybe (XmlNamed a)
findByName iname icon =
  find (\i -> (xnName i) == iname) (getItems icon)
        
findAllByNameWithAnd::(Container b a)=>(a->d)->(a->XmlNamed c)->String->b->[d]
findAllByNameWithAnd proc trans iname icon =
  map proc $ filter (\i -> xnName (trans i) == iname) $ getItems icon
  

-- search for a certainly named item and prefer items of specified origin
-- check result for origin if important
findByNameAndOrigin::(Eq b, Container c (XmlNamedWO a b))=>String->b->c->Maybe (XmlNamedWO a b)
findByNameAndOrigin iname iorig icon =
  let
    candidates = filter (\i -> (xnName i) == iname) (getItems icon)
  in
    case find (\i -> (xnWOaToO i) == iorig) candidates of
      Nothing ->
        case candidates of
          (i:_) -> (Just i)
          _ -> Nothing
      i -> i


relsXNWONFromOMTheory
  ::Set.Set XmlNamedWONSORT
  ->(Graph.Node, OMDoc.Theory)
  ->(Rel.Rel XmlNamedWONSORT, Set.Set ((String, String), [(String, String)]))
relsXNWONFromOMTheory xnsortset (origin, theory) =
  foldl
    (\prev@(r, l) con ->
      case con of
        (OMDoc.CAx ax) ->
          case OMDoc.axiomFMPs ax of
            ((OMDoc.FMP { OMDoc.fmpContent = Left omobj } ):_) ->
              case omobj of
                (OMDoc.OMObject (OMDoc.OMEA seapp)) ->
                  case OMDoc.omaElements seapp of
                    ((OMDoc.OMES sesym):t1:_) ->
                      if OMDoc.omsName sesym == "strong-equation"
                        then
                          case t1 of
                            (OMDoc.OMEA liapp) ->
                              case OMDoc.omaElements liapp of
                                ((OMDoc.OMES lisym):(OMDoc.OMEATTR base):isorts) ->
                                  if OMDoc.omsName lisym == "late-insort" 
                                    then
                                      let
                                        basetype =
                                          case OMDoc.omattrATP base of
                                            OMDoc.OMATP
                                              {
                                                OMDoc.omatpAttribs = (_, OMDoc.OMES ssym):_
                                              } ->
                                                ssym
                                                --OMDoc.omsName ssym
                                            _ ->
                                              error "Malformed late-insort!"
                                        xnbase = (OMDoc.omsCD basetype, OMDoc.omsName basetype)
{-                                        case
                                            findByNameAndOrigin
                                              basetype
                                              origin
                                              xnsortset
                                          of
                                            Nothing ->
                                              XmlNamed
                                                (Hets.mkWON (Hets.stringToId basetype) (-1))
                                                basetype
                                            (Just xnsort') -> xnsort'
-}
                                        rinsorts =
                                          foldl
                                            (\ri s ->
                                              case s of
                                                (OMDoc.OMEATTR s') ->
                                                  let
                                                    stype =
                                                      case OMDoc.omattrATP s' of
                                                        OMDoc.OMATP
                                                          {
                                                            OMDoc.omatpAttribs = (_, OMDoc.OMES ssym):_
                                                          } ->
                                                            ssym
                                                        _ ->
                                                          error "Malformed late-insort!"
                                                  in
                                                    ri ++ [(OMDoc.omsCD stype, OMDoc.omsName stype)]
                                                _ ->
                                                  ri
                                            )
                                            []
                                            isorts
{-                                          foldl
                                            (\ri s ->
                                              case s of
                                                (OMDoc.OMEATTR s') ->
                                                  let
                                                    stype =
                                                      case OMDoc.omattrATP s' of
                                                        OMDoc.OMATP
                                                          {
                                                            OMDoc.omatpAttribs = (_, OMDoc.OMES ssym):_
                                                          } ->
                                                          OMDoc.omsName ssym
                                                        _ ->
                                                          error "Malformed late-insort!"
                                                  in
                                                    case
                                                      findByNameAndOrigin
                                                        stype
                                                        origin
                                                        xnsortset
                                                    of
                                                      Nothing ->
                                                        ri
                                                        ++
                                                        [
                                                        XmlNamed
                                                          (Hets.mkWON (Hets.stringToId stype) (-1))
                                                          stype
                                                        ]
                                                      (Just xnsort') -> ri ++ [xnsort']
                                                _ ->
                                                  ri
                                            )
                                            []
                                            isorts
-}                                          
                                      in
                                        (r, Set.insert (xnbase, rinsorts) l)
{-                                      foldl
                                          (\(r'' i ->
                                            Debug.Trace.trace
                                              ("Reverse-Insort " ++ (show xnbase) ++ " in " ++ (show i))                                            
                                              Rel.insert xnbase i r''
                                          )
                                          prev
                                          rinsorts-}
                                    else
                                      prev
                                _ ->
                                  prev
                            _ ->
                              prev
                        else
                          prev
                    _ ->
                      prev
                _ ->
                  prev
            _ ->
              prev
        (OMDoc.CAd adt) ->
          foldl
            (\(r', l') sd ->
              let
                sortname = OMDoc.sortDefName sd
                insortnames =
                  foldl
                    (\innames ins ->
                      let
                        insortForName =
                          case URI.uriFragment $ OMDoc.insortFor ins of
                            [] -> OMDoc.showURI (OMDoc.insortFor ins)
                            ('#':n) -> n
                            x ->
                              Debug.Trace.trace
                                (
                                  "relsXNWONFromOMTheory: unexpected insort : "
                                  ++ "\"" ++ x ++ "\""
                                )
                                x
                      in
                        innames ++ [insortForName]
                    )
                    []
                    (OMDoc.sortDefInsorts sd)
                xnsort = case findByNameAndOrigin sortname origin xnsortset of
                  Nothing -> (XmlNamed (Hets.mkWON (Hets.stringToId sortname) (-1)) sortname)
                  (Just xnsort' ) -> xnsort'
                xninsorts =
                  map
                    (\s ->
                      case
                        findByNameAndOrigin
                          s
                          origin
                          xnsortset
                      of
                        Nothing ->
                          (XmlNamed (Hets.mkWON (Hets.stringToId s) (-1)) s)
                        (Just xs' ) -> xs'
                    )
                    insortnames
              in
                (
                    foldl
                      (\r'' i ->
                        Rel.insert i xnsort r''
                      )
                      r'
                      xninsorts
                  , l'
                )
            )
            prev
            (OMDoc.adtSortDefs adt)
        _ ->
          prev
    )
    (Rel.empty, Set.empty)
    (OMDoc.theoryConstitutives theory)

  
opsXNWONFromOMTheory
  ::Map.Map XmlName FFXInput
  ->TheoryXNSet
  ->Set.Set XmlNamedWONSORT
  ->(Graph.Node, OMDoc.Theory)
  ->[(XmlNamedWONId, OpTypeXNWON)]
opsXNWONFromOMTheory
  cdmap
  xntheoryset
  xnsortset
  (origin, theory)
  =
  foldl
    (\s' con ->
      case con of
        (OMDoc.CSy symbol) ->
          if OMDoc.symbolRole symbol == OMDoc.SRObject
            then
              case OMDoc.symbolType symbol of
                (Just t) ->
                  case OMDoc.typeOMDocMathObject t of
                    (OMDoc.OMOMOBJ (OMDoc.OMObject e)) ->
                      case e of
                        (OMDoc.OMEA oma) ->
                          case OMDoc.omaElements oma of
                            ((OMDoc.OMES oms):_) ->
                              if
                                elem
                                  (OMDoc.omsName oms) 
                                  ["function", "partial-function"]
                                then
                                  s' ++ [ makeOp (OMDoc.symbolId symbol) oma ]
                                else
                                  s'
                            _ -> s'
                        _ -> s'
                    _ -> s'
                Nothing -> s'
            else
              s'
        _ -> s'
    )
    []
    (OMDoc.theoryConstitutives theory)
  where
    makeOp::OMDoc.XmlId->OMDoc.OMApply->(XmlNamedWONId, OpTypeXNWON)
    makeOp oidxname oma =
      let
        oid =
          case omPresentationFor theory oidxname "Hets" of
            Nothing -> Hets.stringToId oidxname
            (Just x) -> read x
        isTotal =
          case (OMDoc.omaElements oma) of
            ((OMDoc.OMES oms):_) -> OMDoc.omsName oms == "function"
            _ -> error "OMDoc.OMDocInput.opsXNWONFromOMTheory: invalid argument!"
        args =
          drop
            1
            $
            filter
              (\e ->
                case e of
                  (OMDoc.OMES {}) -> True
                  _ -> False
              )
              $
              OMDoc.omaElements oma
        xnargsall =
          map
            (\(OMDoc.OMES oms) ->
              let
                axname = OMDoc.omsName oms
                acd = OMDoc.omsCD oms
                theonode = case getNodeForTheoryName xntheoryset (stripFragment acd) of
                  Nothing ->
                    Debug.Trace.trace
                      ("No Theory for Argument! " ++ (stripFragment acd) ++ "#" ++ axname)
                      (-1)
                  (Just n) -> n
              in
                case findByNameAndOrigin axname theonode xnsortset of
                  Nothing ->
                    let
                      allffxis = Map.elems cdmap
                      allsortmaps = map xnSortsMap allffxis
                      allsortsets = concat (map Map.elems allsortmaps)
                      allsorts = concat (map Set.toList allsortsets)
                    in
                      case
                        find
                          (\x -> (xnName x) == axname)
                          allsorts
                      of
                        Nothing ->
                          XmlNamed
                            (Hets.mkWON (Hets.stringToId axname) (-1))
                            axname
                        (Just s) ->
                          s
                  (Just xnarg) -> if (xnWOaToO xnarg) /= theonode
                    then
                      Debug.Trace.trace
                        (
                          "Found Argument (" ++ show xnarg
                          ++ ") but in wrong Theory! (not in theory #"
                          ++ show theonode
                          ++ ") while processing operator " ++ oidxname
                        )
                        xnarg
                    else
                      xnarg
            )
            args
        xnargs = take (length(xnargsall)-1) xnargsall
        xnres = last (xnargsall)
      in
        (
          XmlNamed (Hets.mkWON oid origin) oidxname,
            OpTypeXNWON
                    (if isTotal then Total else Partial)
                    xnargs
                    xnres
        )


predsXNWONFromOMTheory
  ::Map.Map XmlName FFXInput
  ->TheoryXNSet
  ->Set.Set XmlNamedWONSORT
  ->(Graph.Node, OMDoc.Theory)
  ->[(XmlNamedWONId, PredTypeXNWON)]
predsXNWONFromOMTheory
  cdmap
  xntheoryset
  xnsortset
  (origin, theory)
  =
  foldl
    (\s' con ->
      case con of
        (OMDoc.CSy symbol) ->
          if OMDoc.symbolRole symbol == OMDoc.SRObject
            then
              case OMDoc.symbolType symbol of
                (Just t) ->
                  case OMDoc.typeOMDocMathObject t of
                    (OMDoc.OMOMOBJ (OMDoc.OMObject e)) ->
                      case e of
                        (OMDoc.OMEA oma) ->
                          case OMDoc.omaElements oma of
                            ((OMDoc.OMES oms):_) ->
                              if OMDoc.omsName oms == "predication"
                                then
                                  s' ++ [ makePred (OMDoc.symbolId symbol) oma ]
                                else
                                  s'
                            _ -> s'
                        _ -> s'
                    _ -> s'
                Nothing -> s'
            else
              s'
        _ -> s'
    )
    []
    (OMDoc.theoryConstitutives theory)
  where
    makePred::OMDoc.XmlId->OMDoc.OMApply->(XmlNamedWONId, PredTypeXNWON)
    makePred pidxname oma =
      let
        pid =
          case omPresentationFor theory pidxname "Hets" of
            Nothing -> Hets.stringToId pidxname
            (Just x) -> read x
        args =
          drop
            1
            $
            filter
              (\e ->
                case e of
                  (OMDoc.OMES {}) -> True
                  _ -> False
              )
              $
              OMDoc.omaElements oma
        xnargsall =
          map
            (\(OMDoc.OMES oms) ->
              let
                axname = OMDoc.omsName oms
                acd = OMDoc.omsCD oms
                theonode = case getNodeForTheoryName xntheoryset (stripFragment acd) of
                  Nothing ->
                    Debug.Trace.trace
                      ("No Theory for Argument! " ++ (stripFragment acd) ++ "#" ++ axname)
                      (-1)
                  (Just n) -> n
              in
                case findByNameAndOrigin axname theonode xnsortset of
                  Nothing ->
                    let
                      allffxis = Map.elems cdmap
                      allsortmaps = map xnSortsMap allffxis
                      allsortsets = concat (map Map.elems allsortmaps)
                      allsorts = concat (map Set.toList allsortsets)
                    in
                      case
                        find
                          (\x -> (xnName x) == axname)
                          allsorts
                      of
                        Nothing ->
                          XmlNamed
                            (Hets.mkWON (Hets.stringToId axname) (-1))
                            axname
                        (Just s) ->
                          s
                  (Just xnarg) -> if (xnWOaToO xnarg) /= theonode
                    then
                      Debug.Trace.trace
                        (
                          "Found Argument (" ++ show xnarg
                            ++ ") but in wrong Theory! (not in theory #"
                            ++ show theonode ++ ") while processing predicate "
                            ++ pidxname
                        )
                        xnarg
                    else
                      xnarg
            )
            args
      in
        (
            XmlNamed (Hets.mkWON pid origin) pidxname
          , PredTypeXNWON xnargsall
        )

-- | imports lead to edges but if the information is not stored in the
-- document there is no clue on what type of edge to create...
data ImportHint = FromStructure (String, DGLinkLab) | FromData (String, DGLinkLab)
  deriving (Eq, Show)

-- simple ord-relation to make Set happy...     
instance Ord ImportHint where
  (FromStructure _) <= (FromStructure _) = True
  (FromStructure _) <= (FromData _) = True
  (FromData _) <= (FromData _) = True
  (FromData _) <= (FromStructure _) = False


glThmsFromOMIncs
  ::[OMDoc.Imports]
  ->OMDoc.OMDoc
  ->[(Int, XmlName, (XmlName, Hets.HidingAndRequationList, Conservativity, Bool))]
glThmsFromOMIncs
  omimports
  omdoc
  =
  foldl
    (\glts (inum, incl) ->
      let
        isLocal =
          case incl of
            (OMDoc.AxiomInclusion {}) -> True
            _ -> False
        hreq =
          case OMDoc.inclusionMorphism incl of
            Nothing -> ([],[])
            (Just m) -> fetchOMRequationSymbols m
        fromid =
          case URI.uriFragment $ OMDoc.inclusionFrom incl of
            [] -> OMDoc.showURI $ OMDoc.inclusionFrom incl
            f -> stripFragment f
        toid =
          case URI.uriFragment $ OMDoc.inclusionTo incl of
            [] -> OMDoc.showURI $ OMDoc.inclusionTo incl
            f -> stripFragment f
        conservativity =
          case OMDoc.inclusionMorphism incl of
            Nothing -> None
            (Just m) ->
              case OMDoc.morphismBase m of
                [] -> None
                baselist ->
                  let
                    baseid = last baselist
                  in
                    case
                      filter
                        (\omimp ->
                          case OMDoc.importsMorphism omimp of
                            Nothing -> False
                            (Just im) ->
                              case OMDoc.morphismId im of
                                Nothing -> False
                                (Just mid) -> mid == baseid
                        )
                        omimports
                    of
                      [] -> None
                      [bmorphimp] ->
                        convCons $ OMDoc.importsConservativity bmorphimp
                      (bmorphimp):_ ->
                        Debug.Trace.trace
                          ("More than one matching reference for Morphism-base...")
                          convCons $ OMDoc.importsConservativity bmorphimp
      in
        glts ++
          [
            (
                inum
              , toid
              , (
                    fromid
                  , hreq
                  , conservativity
                  , (not isLocal)
                )
            )
          ]
    )
    []
    $
    zip
      [1..]
      $
      OMDoc.omdocInclusions omdoc
  where
  convCons::OMDoc.Conservativity->Conservativity
  convCons OMDoc.CNone = None
  convCons OMDoc.CMonomorphism = Mono
  convCons OMDoc.CConservative = Cons
  convCons OMDoc.CDefinitional = Def

omdocImportsMapFromAOMSet
  ::TheoryXNSet
  ->Set.Set (Graph.Node, OMDoc.Theory)
  ->Map.Map String [(Int, OMDoc.Imports)]
omdocImportsMapFromAOMSet
  txns aomset =
  Set.fold
    (\(gm, omt) i ->
      let
        name =
          case getTheoryXmlName txns gm of
            Nothing ->
              error "OMDoc.OMDocInput.omdocImportsFromAOMSet: Theory has no name!"
            (Just x) -> x
        imports =
          zip
            [1..]
            $
            foldl
              (\il con ->
                case con of
                  (OMDoc.CIm im) ->
                    il ++ [im]
                  _ -> il
              )
              []
              (OMDoc.theoryConstitutives omt)
      in
        Map.insert name imports i
    )
    Map.empty
    aomset

omdocImportsToHetsImports
  ::[(Int, OMDoc.Imports)]
  ->Hets.Imports
omdocImportsToHetsImports
  omimports =
  foldl
    (\imps (c, i) ->
      let
        fromname =
          case URI.uriFragment $ OMDoc.importsFrom i of
            [] -> OMDoc.showURI $ OMDoc.importsFrom i
            f -> stripFragment f
        hreq =
          case OMDoc.importsMorphism i of
            Nothing -> ([],[])
            (Just m) -> fetchOMRequationSymbols m
      in
        Set.insert (c, (fromname, Nothing, hreq, True)) imps
    )
    Set.empty
    omimports

omdocImportsMapToHetsImportsMap
  ::Map.Map String [(Int, OMDoc.Imports)]
  ->Hets.ImportsMap
omdocImportsMapToHetsImportsMap
  omimportsmap =
  Map.map
    omdocImportsToHetsImports
    omimportsmap
        
sensXNWONFromOMTheory::FFXInput->(Graph.Node, OMDoc.Theory)->(Set.Set (XmlNamed Hets.SentenceWO))
sensXNWONFromOMTheory ffxi (origin, theory) =
  Set.fromList $ unwrapFormulasOM ffxi (origin, theory)


conSensXNWONFromOMTheory::FFXInput->(Graph.Node, OMDoc.Theory)->Set.Set (XmlNamed Hets.SentenceWO) 
conSensXNWONFromOMTheory ffxi (anxml@(_, theory)) =
  let
    adts =
      filter
        (\c ->
          case c of
            (OMDoc.CAd {}) -> True
            _ -> False
        )
        (OMDoc.theoryConstitutives theory)
  in
    Set.fromList $ foldl
      (\list adt' ->
        case adt' of
          OMDoc.CAd adt ->
            let
              (excon, exconlist) =
                extractConsXNWONFromOMADT ffxi anxml adt
            in
              if (length exconlist) == 0 -- if only the relation is expressed,
                                         -- no constructors are specified
                then
                  list
                else
                  list ++ [consToSensXN excon exconlist] 
          _ -> list
      )
      []
      adts 


consXNWONFromOMTheory::FFXInput->(Graph.Node, OMDoc.Theory)->[(XmlNamedWONId, [(XmlNamedWONId, OpTypeXNWON)])]
consXNWONFromOMTheory ffxi (origin, theory) =
  let
    adts =
      filter
        (\c ->
          case c of
            (OMDoc.CAd {}) -> True
            _ -> False
        )
        (OMDoc.theoryConstitutives theory)
  in
    foldl
      (\list adt' ->
        case adt' of
          (OMDoc.CAd adt) ->
            let
              (excon, exconlist) =
                extractConsXNWONFromOMADT ffxi (origin, theory) adt
            in
              if (length exconlist) == 0 -- if only the relation is expressed,
                                         -- no constructors are specified
                then
                  list
                else
                  list ++ [(excon, exconlist)]
          _ -> error "OMDoc.OMDocInput.consXNWONFromOMTheory: This should not happen!"
      ) [] adts 


createTheorySpecificationsOM
  ::TheoryXNSet
  ->String
  ->Set.Set (Graph.Node, OMDoc.Theory)
  ->[TheorySpecification]
createTheorySpecificationsOM
  xntheoryset
  sourcename
  aomset 
  =
  Set.fold
    (\(aom@(origin, theory)) tsl ->
      let
        theoid = OMDoc.theoryId theory
        theonodename =
          case omPresentationFor theory theoid "Hets" of
            Nothing -> idToNodeName $ read ("[" ++ theoid ++ ",,0]")
            (Just x) -> idToNodeName $ read x
        sorts = sortsXNWONFromOMTheory aom
        (rels, late) = relsXNWONFromOMTheory sorts aom
        ops = Set.fromList $ opsXNWONFromOMTheory Map.empty xntheoryset sorts aom
        preds = Set.fromList $ predsXNWONFromOMTheory Map.empty xntheoryset sorts aom
      in
        if Util.isPrefix "ymmud-" (reverse theoid)
          then
            tsl
          else
            tsl ++
              [
                TheorySpecification
                  {
                      ts_name = (stripFragment theoid)
                    , ts_source = sourcename
                    , ts_nodename = theonodename
                    , ts_nodenum = origin
                    , ts_sorts = sorts
                    , ts_sortrelation = rels
                    , ts_predicates = preds
                    , ts_operators = ops
                    , ts_constructors = Set.empty
                    , ts_late_insorts = late
                  }
              ]
    )
    []
    aomset


importGraphToSpecsOM::
  GlobalOptions
  ->(ImportGraph OMDoc.OMDoc)
  ->Graph.Node
  ->([TheorySpecification], [LinkSpecification], TheoryXNSet, Set.Set (Graph.Node, OMDoc.Theory))
importGraphToSpecsOM
  go
  ig
  n
  =
  let
    e_fname = "OMDoc.OMDocInput.importGraphToSpecsOM: "
    node =
      case
        Graph.lab ig n
      of
        Nothing -> error (e_fname ++ "node error!")
        (Just n') -> n'
    (sourcename, omdoc) = (\(S (sn, _) o) -> (sn, o)) node
    refimports = (\x ->
      debugGO go "iGTDGNXN" ("Refimports : " ++ show x) x) $
        filter ( \(_,from,_) -> from /= n) $ Graph.out ig n
    axtheoryset = buildAOMTheorySet omdoc
    xntheoryset = 
      nodeNamesXNFromOM
        (debugGO go "pX" "at nodeNamedXNFromXml" axtheoryset)
    theoryspecs = createTheorySpecificationsOM xntheoryset sourcename axtheoryset
    maxUsedNodeNum =
      foldl
        (\mUNN n' ->
          if n' > mUNN
            then
              n'
            else
              mUNN
        )
        0
        (map ts_nodenum theoryspecs)
    refspecs =
      map
        (\(rn, (_, from, (TI (theoname, _)))) ->
          let
            moriginnode = Graph.lab ig from
            (S (slibname, _) _) = case moriginnode of
              Nothing ->
                error
                  (
                    e_fname
                    ++ "node error (Import of "
                    ++ theoname ++ " from " ++ (show from) ++ " )!"
                  )
              (Just n' ) -> n'
          in
            ReferenceSpecification
              {
                  ts_name = (stripFragment theoname)
                , ts_nodename = (Hets.stringToSimpleId (stripFragment theoname), "", 0)
                , ts_source = slibname
                , ts_nodenum = rn
                , ts_realnodenum = -1
                , ts_sorts = Set.empty
                , ts_sortrelation = Rel.empty
                , ts_predicates = Set.empty
                , ts_operators = Set.empty
                , ts_constructors = Set.empty
              }
        )
        (zip [(maxUsedNodeNum + 1)..] refimports)
    refxnnames =
      Set.fromList
        $
        map
          (\ts -> XmlNamed (ts_nodenum ts, ts_nodename ts) (ts_name ts))
          refspecs
    allXNNames = Set.union xntheoryset refxnnames
    linkspecs = createLinkSpecificationsOM go omdoc allXNNames axtheoryset
  in
    (theoryspecs ++ refspecs, linkspecs, allXNNames, axtheoryset)


createSpecMapOM::
  GlobalOptions
  ->(ImportGraph OMDoc.OMDoc)
  ->Map.Map
      String
      (
          [TheorySpecification]
        , [LinkSpecification]
        , TheoryXNSet
        , Set.Set (Graph.Node, OMDoc.Theory)
      )
createSpecMapOM
  go
  ig
  =
    foldl
      (\sm (nn, (S (sourcename, _) _)) ->
        Map.insert sourcename (importGraphToSpecsOM go ig nn) sm
      )
      Map.empty
      (Graph.labNodes ig)


processSpecMapOM::
  Map.Map
    String
    (
        [TheorySpecification]
      , [LinkSpecification]
      , TheoryXNSet
      , Set.Set (Graph.Node, OMDoc.Theory)
    )
  ->Map.Map
      String
      (
          [TheorySpecification]
        , [LinkSpecification]
        , TheoryXNSet
        , Set.Set (Graph.Node, OMDoc.Theory)
      )
processSpecMapOM
  sm
  =
  let
    e_fname = "OMDoc.OMDocInput.processSpecMapOM: "
    importsFromMap =
      Map.foldWithKey
        (\sourcename (ts, _ , _, _) iFM ->
          let
            references = filter isRefSpec ts
            refed = map ts_source references
          in
            Map.insert sourcename refed iFM
        )
        Map.empty
        sm
    maxNoAction = Map.size sm
    (processedMap, _, _) =
      until
        (\(_, unprocessedMap, _) -> Map.null unprocessedMap)
        (\(pM, uM, noActionSince) ->
          let
            unkeys = Map.keys uM
            unimports =
              map
                (\uk ->
                  (
                      uk
                    , Map.findWithDefault
                        (error (e_fname ++ "No Imports for Key!"))
                        uk
                        importsFromMap
                  )
                )
                unkeys
            freeun =
              filter (\(_, i) -> all (flip elem (Map.keys pM)) i) unimports
          in
            if length freeun == 0 && noActionSince <= maxNoAction
              then
                (pM, uM, noActionSince + 1)
              else
                let
                  currentSource =
                    fst $ ehead (e_fname ++ "currentSource") freeun
                  (ctslist, clslist, cxntheoryset, caxmlset) =
                    Map.findWithDefault
                      (error (e_fname ++ "No Entry for currentSource!"))
                      currentSource
                      uM
                  resolvedrefs =
                    map
                      (\ts ->
                       if isRefSpec ts
                        then
                          let
                            refsource = ts_source ts
                            (rtslist, _, _, _) =
                              Map.findWithDefault
                                (
                                  Debug.Trace.trace
                                    (
                                      "referenced source has not been finished... ("
                                      ++ refsource ++ ")"
                                    )
                                    (
                                      Map.findWithDefault
                                        (
                                            []
                                          , error (e_fname ++ "ref-lookup")
                                          , error (e_fname ++ "ref-lookup")
                                          , error (e_fname ++ "ref-lookup")
                                        )
                                        refsource
                                        uM
                                    )
                                )
                                refsource
                                pM
                            realspec =
                              case
                                find
                                  (\ts' -> ts_name ts' == (ts_name ts))
                                  rtslist
                              of
                                Nothing ->
                                  Debug.Trace.trace
                                    (
                                      "ohoh... no source for reference to "
                                      ++ (ts_name ts)
                                    )
                                    ts
                                (Just x) -> x
                          in
                            adjustOriginsToRef
                              ts
                                {
                                    ts_realnodenum = ts_nodenum realspec
                                  , ts_nodename = ts_nodename realspec
                                  , ts_sorts = ts_sorts realspec
                                  , ts_sortrelation = ts_sortrelation realspec
                                  , ts_predicates = ts_predicates realspec
                                  , ts_operators  = ts_operators realspec
                                  , ts_constructors = ts_constructors realspec
                                }
                        else
                          ts
                      )
                      ctslist
                  processedSpecs =
                    processAllDefLinks
                      resolvedrefs
                      clslist
                in
                  (\x ->
                    if noActionSince > maxNoAction
                      then
                        Debug.Trace.trace
                          ("forced processing of " ++ currentSource)
                          x
                      else
                        x
                  )
                  (
                      Map.insert
                        currentSource
                        (processedSpecs, clslist, cxntheoryset, caxmlset)
                        pM
                    , Map.delete
                        currentSource
                        uM
                    , 0
                  )
        )
        (Map.empty, sm, 0)
  in
    processedMap

  where
    
    adjustOriginsToRef::
        TheorySpecification
      ->TheorySpecification
    adjustOriginsToRef
      ts
      =
      let
        tso = ts_nodenum ts
      in
        ts
          {
              ts_sorts =
                Set.map (setOrigin tso) (ts_sorts ts)
            , ts_sortrelation =
                Rel.fromList
                  $
                  map
                    (\(a, b) -> (setOrigin tso a, setOrigin tso b))
                    (Rel.toList (ts_sortrelation ts))
            , ts_predicates =
                Set.map
                  (\(xnpid, xnpt) ->
                    (
                        xnpid
                      , xnpt
                        {
                          predArgsXNWON =
                            map (setOrigin tso) (predArgsXNWON xnpt) 
                        }
                    )
                  )
                  (ts_predicates ts)
            , ts_operators =
                Set.map
                  (\(xnoid, xnot) ->
                    (
                        xnoid
                      , xnot
                        {
                            opArgsXNWON =
                              map (setOrigin tso) (opArgsXNWON xnot) 
                          , opResXNWON = setOrigin tso (opResXNWON xnot)
                        }
                    )
                  )
                  (ts_operators ts)
            , ts_constructors =
                Set.map
                  (\(xnforsort, conset) ->
                    (
                        setOrigin tso xnforsort
                      , Set.map
                          (\(xncid, xnct) ->
                            (
                                xncid
                              , xnct
                                {
                                    opArgsXNWON = map (setOrigin tso) (opArgsXNWON xnct)
                                  , opResXNWON = setOrigin tso (opResXNWON xnct)
                                }
                            )
                          )
                          conset
                    )
                  )
                  (ts_constructors ts)
          }

    setOrigin::Graph.Node->XmlNamedWONSORT->XmlNamedWONSORT
    setOrigin n xns = XmlNamed (Hets.mkWON (xnWOaToa xns) n) (xnName xns)   

createNodeFromSpecOM::
    FFXInput
  ->(Graph.Node, OMDoc.Theory)
  ->TheorySpecification
  ->Graph.LNode DGNodeLab
createNodeFromSpecOM
  ffxi
  axml
  ts
  =
  let
    theorysens = sensXNWONFromOMTheory ffxi axml
    -- filter out late-insort kludges
    (tsens, _) =
      Set.partition
        (\senwon ->
          case Ann.sentence $ xnWOaToa senwon of
            (Strong_equation t1 _ _) ->
              case t1 of
                (Application op _ _) ->
                  if opName op == "late-insort"
                    then
                      False
                    else
                      True
                _ -> True
            _ -> True
        )
        theorysens
    {-
    lateinrel =
      Set.fold
        (\lif lir ->
          case Ann.sentence $ xnWOaToa lif of
            (Strong_equation (Application _ syms _) _ _) ->
              case syms of
                (base:rest) ->
                  let
                    sbase = 
                      case base of
                        (Qual_var _ s _) ->
                          s
                        _ ->
                          error "Malformed late-insort!"
                    isorts =
                      foldl
                        (\is' fs ->
                          case fs of
                            (Qual_var _ s _) ->
                              is' ++ [s]
                            _ -> is'
                        )
                        []
                        rest
                  in
                    Rel.union
                      lir
                      $
                      Rel.fromList
                        (map (\s -> (sbase, s)) isorts)
                _ ->
                  Debug.Trace.trace
                    ("late-insort: Wrong Form... " ++ (show syms))
                    lir
            _ ->
              Debug.Trace.trace
                ("late-insort: Not a Strong_equation...")
                lir
        )
        Rel.empty
        lateinaxs
      -}
    theorycons = conSensXNWONFromOMTheory ffxi axml
    caslsign =
      Sign
        {
            sortSet = Set.map xnWOaToa (ts_sorts ts)
          , sortRel =
              Rel.fromList
                $
                map
                  (\(a, b) -> (xnWOaToa a, xnWOaToa b))
                  $
                  (Rel.toList (ts_sortrelation ts))
          , opMap =
              implodeSetToMap
                opTypeXNWONToOpType
                (ts_operators ts)
          , predMap =
              implodeSetToMap
                predTypeXNWONToPredType
                (ts_predicates ts)
          , assocOps = Map.empty
          , varMap = Map.empty
          , envDiags = []
          , annoMap = Map.empty
          , globAnnos = Hets.emptyGlobalAnnos
          , extendedInfo = ()
          , sentences = []
                
        }
    theory =
      G_theory
        CASL
        caslsign 0
        (
          Prover.toThSens
            $
            map
              xnWOaToa
              (
                (Set.toList tsens)
                ++ (Set.toList theorycons)
              )
        ) 0
    reftheory = G_theory CASL caslsign 0 (Prover.toThSens []) 0
    node =
      if isRefSpec ts
        then
          DGRef
            {
                dgn_name = ts_nodename ts
              , dgn_libname =
                  ASL.Lib_id
                    (ASL.Indirect_link (ts_source ts) Id.nullRange "")
              , dgn_node = ts_realnodenum ts
              , dgn_theory = reftheory
              , dgn_nf = Nothing
              , dgn_sigma = Nothing
            }
        else
          DGNode
            {
                dgn_name = ts_nodename ts
              , dgn_theory = theory
              , dgn_sigma = Nothing
              , dgn_origin = DGBasic
              , dgn_cons = None
              , dgn_cons_status = LeftOpen
              , dgn_nf = Nothing
            }
  in
    (ts_nodenum ts, node)

  where
    
    implodeSetToMap::
      (Eq a, Ord a, Eq b, Ord b, Eq c, Ord c)=>
        (b->c)
      ->Set.Set (XmlNamedWON a, b)
      ->Map.Map a (Set.Set c)
    implodeSetToMap
      convert
      theset
      =
      Set.fold
        (\(xa, b) m ->
          Map.insertWith
            Set.union
            (xnWOaToa xa)
            (Set.singleton (convert b))
            m
        )
        Map.empty
        theset

-- | Each of these items represents information from
-- a link that has *not* yet been processed (due to error, or
-- because there was ne processing at all)
data UnprocessedItem = UISorts | UIPreds | UIOps
  deriving (Show, Eq)

-- Debug-Info of what was done when processing links
data Did =
    DidForce String String -- link made, even with problems
  | DidLink String String -- link made, no problems
  -- link made partially (or not at all), last parameter appropriate msg
  | DidPartly String String String

-- ANSI-coloured output to aid debugging (the lists get large)
instance Show Did where
  show (DidForce s1 s2) =
    "\ESC[1;34m" ++ s1 ++ "\ESC[1;31m -force-> \ESC[1;34m" ++ s2 ++ "\ESC[0;30m"
  show (DidLink s1 s2) =
    "\ESC[1;34m" ++ s1 ++ "\ESC[1;32m -link-> \ESC[1;34m" ++ s2 ++ "\ESC[0;30m"
  show (DidPartly s1 s2 p) =
    "\ESC[1;34m" ++ s1 ++ "\ESC[1;35m -" ++ p ++ "-> \ESC[1;34m" ++ s2 ++ "\ESC[0;30m"

processAllDefLinks::
    [TheorySpecification]
  ->[LinkSpecification]
  ->[TheorySpecification]
processAllDefLinks
  tslist
  lslist
  =
  let
    numberOfDefLinks =
      foldl
        (\ndl ls ->
          if isDefLink ls
            then
              ndl + 1
            else
              ndl
        )
        (0::Int)
        lslist
--    maxNoAction = length lslist
    ((processed, _), (final_pdl, _), didlist) =
      until
        (\(_, (processedDefLinks, _), _) ->
          processedDefLinks == numberOfDefLinks
        )
        (\((pts, (lsui@(ls, uil)):r), (pdl, nas), didl) ->
          if isDefLink ls
            then
              let
                maxNoAction = (length r)+1
                toname = ls_toname ls
                unprocessedPrevious =
                  filter
                    (\(ls', _) ->
                      isDefLink ls'
                      && ls_toname ls' == (ls_fromname ls)
                    )
                    r
              in
                if (length unprocessedPrevious == 0) || nas > maxNoAction
                  then
                    let
                      totspec = ehead ("processAllDefLink, totspec : " ++ toname) $ filter (\ts -> ts_name ts == toname) pts
                      fromtspec = ehead "processAllDefLinks, fromtspec" $ filter (\ts -> ts_name ts == (ls_fromname ls)) pts
                      ((newtotspec, unprocessedItems), wasForced) =
                        (\x ->
                          if nas > maxNoAction
                            then
                              Debug.Trace.trace
                                (
                                  "\ESC[1;31mForcing link:\ESC[1;34m "
                                  ++ (ls_fromname ls)
                                  ++ "\ESC[0;30m -> \ESC[1;34m"
                                  ++ toname ++ "\ESC[0;30m"
                                )
                                (x, True)
                            else
                              (x, False)
                        )
                        (
                        performDefLinkSpecification
                          uil
                          fromtspec
                          ls
                          totspec
                        )
                      unforcedResult =
                        newtotspec
                          {
                              ts_sorts =
                                if UISorts `elem` unprocessedItems
                                  then
                                    ts_sorts totspec
                                  else
                                    ts_sorts newtotspec
                            , ts_predicates =
                                if UIPreds `elem` unprocessedItems
                                  then
                                    ts_predicates totspec
                                  else
                                    ts_predicates newtotspec
                            , ts_operators =
                                if UIOps `elem` unprocessedItems
                                  then
                                    ts_operators totspec
                                  else
                                    ts_operators newtotspec
                          }
                      resspec =
                        if wasForced
                          then
                            newtotspec
                          else
                            unforcedResult
                      newpts =
                        map
                          (\ts ->
                            if ts_name ts == ts_name resspec
                              then
                                if ts_nodenum ts /= ts_nodenum resspec
                                  then
                                    Debug.Trace.trace
                                      (
                                        "\ESC[1;31mWarning:\ESC[0;30m Same names found ! "
                                        ++ (show (ts_nodenum ts, ts_name ts))
                                        ++ " and "
                                        ++ (show (ts_nodenum newtotspec, ts_name newtotspec))
                                      )
                                      ts
                                  else
                                    resspec
                              else
                                ts
                          )
                          pts
                    in
                      if null unprocessedItems || wasForced
                        then
                          (
                              (newpts, r)
                            , (pdl + 1, 0)
                            , didl ++ [if wasForced
                                then
                                  Debug.Trace.trace
                                    ("")
                                  DidForce (ts_name fromtspec) (ts_name totspec)
                                else
                                  DidLink (ts_name fromtspec) (ts_name totspec)]
                          )
                        else
                          debugEnv
                            "devLinksMorphism"
                            (
                              "\ESC[1;31m!\ESC[0;30mMorphism in \ESC[1;34m"
                              ++ (show (ts_name fromtspec)) ++ "\ESC[0;30m -> \ESC[1;34m"
                              ++ (show (ts_name totspec))
                              ++ "\ESC[0;30m failed " ++ (show unprocessedItems)
                              ++ ", processing later..."
                            )
                            (
                                (pts, r++[(ls, unprocessedItems)])
                                  -- honor reducement
                              , (pdl, nas+(if length unprocessedItems < length uil then 0 else 1))
                              , didl
                                  ++ [
                                        DidPartly
                                          (ts_name fromtspec)
                                          (ts_name totspec)
                                          (show unprocessedItems)
                                    ]
                            )
                  else
                    ( (pts, r++[lsui]), (pdl, nas+1), didl )
            else
              ((pts, r), (pdl, nas), didl) -- don't count as no action if not def link
        )
        ((tslist, map (\l -> (l, [UISorts, UIPreds, UIOps])) lslist), (0::Int,0::Int), [])
  in
    if final_pdl /= numberOfDefLinks
      then
        Debug.Trace.trace
          (
            "Error while processing. Stopped after " ++ show final_pdl ++ " of "
            ++ show numberOfDefLinks ++ " links were processed..."
          )
          processed
      else
        debugEnv
          "devLinksDid"
          ("Did: " ++ show didlist)
          processed
  where
    
    isDefLink::LinkSpecification->Bool
    isDefLink ls =
      case ls_type ls of
        LocalDef -> True
        GlobalDef -> True
        HidingDef -> True
        _ -> False

performDefLinkSpecification::
    [UnprocessedItem]
  ->TheorySpecification
  ->LinkSpecification
  ->TheorySpecification
  ->(TheorySpecification, [UnprocessedItem])
performDefLinkSpecification
  uilist
  tsFrom
  ls
  tsTo
  =
  let
   r@(_{-newTS-}, _) =
    if isDef (ls_type ls)
      then
        let
          (hidden, req) = ls_hreql ls
          -- Sorts
          fromSorts =
            if isLocal (ls_type ls)
              then
                Set.filter
                  (\xns -> xnWOaToO xns == ts_nodenum tsFrom)
                  (ts_sorts tsFrom)
              else
                (ts_sorts tsFrom)
          availSorts = Set.filter (\xns -> not $ elem (xnName xns) hidden) fromSorts
          (newSorts, sortSuccess) =
            if UISorts `elem` uilist
              then
                Set.fold
                  (\xns same@(nS, s) ->
                    case
                      find
                        (\((_, oldName),_) -> oldName == xnName xns)
                        req
                    of
                      Nothing -> (nS ++ [xns], s)
                      (Just (_, (_, newName))) ->
                        case
                          find
                            (\to_xns -> xnName to_xns == newName)
                            (Set.toList (ts_sorts tsTo))
                        of
                          Nothing ->
                            {-
                            Debug.Trace.trace
                              (
                                "\ESC[1;31mWarning:\ESC[0;30m " ++ (show count) ++ " "
                                ++ "In Morphism from " ++ (ts_name tsFrom)
                                ++ "(" ++ (ts_source tsFrom) ++ ")"
                                ++ " to " ++ (ts_name tsTo)
                                ++ "(" ++ (ts_source tsTo) ++ ")"
                                ++ ": Sort morphism not possible for "
                                ++ (xnName xns) ++ " -> " ++ newName
                                ++ " because there is no such sort in the target!"
                                ++ " sorts in target : " 
                                ++ (Set.fold (\se s' -> s' ++ " " ++ (show se)) "" (ts_sorts tsTo))
                              )
                            -}
                            (nS, False)
                          (Just _) -> same
                  )
                  ([], True)
                  availSorts
              else
                ([], True) -- fast merge...
          mergedSorts =
            Set.union
              (ts_sorts tsTo)
              (Set.fromList newSorts)
          -- Predicates
          fromPreds = 
            if isLocal (ls_type ls)
              then
                Set.filter
                  (\(xnpid, _) -> xnWOaToO xnpid == ts_nodenum tsFrom)
                  (ts_predicates tsFrom)
              else
                (ts_predicates tsFrom)
          availPreds = Set.filter (\(xnpid, _) -> not $ elem (xnName xnpid) hidden) fromPreds
          (newPreds, predSuccess) =
            if UIPreds `elem` uilist
              then
                Set.fold
                  (\(xnp@(xnpid, _)) same@(nP,s) ->
                    case
                      find
                        (\((_, oldName),_) -> oldName == xnName xnpid)
                        req
                    of
                      Nothing -> (nP ++ [xnp], s)
                      (Just (_,(_,newName))) ->
                        case
                          find
                            (\(to_xnpid, _) -> xnName to_xnpid == newName)
                            (Set.toList (ts_predicates tsTo))
                        of
                          Nothing ->
                            {-
                            Debug.Trace.trace
                              (
                                "\ESC[1;31mWarning:\ESC[0;30m Predicate morphism not possible for "
                                ++ (xnName xnpid) ++ " -> " ++ newName
                              )
                            -}
                            (nP, False)
                          (Just _) -> same
                  )
                  ([], True)
                  availPreds
              else
                ([], True) -- will be fast on merge...
          mergedPreds =
            Set.union
              (ts_predicates tsTo)
              (Set.fromList newPreds)
          -- Operators
          fromOps = 
            if isLocal (ls_type ls)
              then
                Set.filter
                  (\(xnoid, _) -> xnWOaToO xnoid == ts_nodenum tsFrom)
                  (ts_operators tsFrom)
              else
                (ts_operators tsFrom)
          availOps = Set.filter (\(xnoid, _) -> not $ elem (xnName xnoid) hidden) fromOps
          (newOps, opSuccess) =
            if UIOps `elem` uilist
              then
                Set.fold
                  (\(xno@(xnoid, _)) same@(nO,s) ->
                    case
                      find
                        (\((_, oldName),_) -> oldName == xnName xnoid)
                        req
                    of
                      Nothing -> (nO ++ [xno], s)
                      (Just (_,(_,newName))) ->
                        case
                          find
                            (\(to_xnoid, _) -> xnName to_xnoid == newName)
                            (Set.toList (ts_operators tsTo))
                        of
                          Nothing ->
                            {-
                            Debug.Trace.trace
                              (
                                "\ESC[1;31mWarning:\ESC[0;30m Operator morphism not possible for "
                                ++ (xnName xnoid) ++ " -> " ++ newName
                              )
                            -}
                            (nO, False)
                          (Just _) -> same
                  )
                  ([], True)
                  availOps
              else
                ([], True) -- superfast merging...
          mergedOps =
            Set.union
              (ts_operators tsTo)
              (Set.fromList newOps)
          -- checks
          -- why did I omit the from relation here first ?
          checkedRels =
            Rel.fromList
              $
              map
                (\(s1, s2) ->
                  (findRealSort mergedSorts s1, findRealSort mergedSorts s2)
                )
                $
                Rel.toList
                  (Rel.union
                    (ts_sortrelation tsFrom)
                    (
                      Rel.union
                        (ts_sortrelation tsTo)
                        (
                          (\x ->
                            if Set.null $ ts_late_insorts tsTo 
                              then
                                x
                              else
                                Debug.Trace.trace
                                ("Late-insort: merging " ++ (show $ ts_late_insorts tsTo))
                                x
                          )
                          Rel.fromList
                            (
                              foldl
                                (\l ((_, a), bl) ->
                                  l
                                  ++
                                  (
                                  map
                                    (\(_, b) ->
                                      (
                                          XmlNamed
                                            (Hets.mkWON (Hets.stringToId a) (-1))
                                            a
                                        , XmlNamed
                                            (Hets.mkWON (Hets.stringToId b) (-1))
                                            b
                                      )
                                    )
                                    bl
                                  )
                                )
                                []
                                (Set.toList $ ts_late_insorts tsTo)
                            )
                        )
                    )
                  )
          checkedPreds =
            Set.map
              (\(xnpid, xnpt) ->
                (
                    xnpid
                  , xnpt
                    {
                      predArgsXNWON =
                        map (findRealSort mergedSorts) (predArgsXNWON xnpt) 
                    }
                )
              )
              mergedPreds
          checkedOps =
            Set.map
              (\(xnoid, xnot) ->
                (
                    xnoid
                  , xnot
                    {
                        opArgsXNWON =
                          map (findRealSort mergedSorts) (opArgsXNWON xnot) 
                      , opResXNWON = findRealSort mergedSorts (opResXNWON xnot)
                    }
                )
              )
              mergedOps
        in
          (
              tsTo
                {
                    ts_sorts = mergedSorts
                  , ts_sortrelation = checkedRels
                  , ts_predicates = checkedPreds
                  , ts_operators = checkedOps
                }
            ,
              (
                (if sortSuccess then [] else [UISorts])
                ++
                (if predSuccess then [] else [UIPreds])
                ++
                (if opSuccess then [] else [UIOps])
              )
          )
      else -- Thms only affect morphisms
        (tsTo, [])
  in
    if (ls_fromname ls) /= (ts_name tsFrom) || (ls_toname ls) /= (ts_name tsTo)
      then
        error "OMDoc.OMDocInput.performDefLinkSpecification: Wrong application!"
      else
      {-
        Debug.Trace.trace
          (
            "\ESC[1;32mSortMerge\ESC[0;30m " ++ (show count) ++ " "
            ++ (ts_name tsFrom) ++ " -> " ++ (ts_name tsTo)
            ++ " : " ++ (Set.fold (\se s -> s ++ " " ++ (show se)) "" (ts_sorts newTS))
          )
      -}
          r

  where

    findRealSort::Set.Set XmlNamedWONSORT->XmlNamedWONSORT->XmlNamedWONSORT
    findRealSort sorts s =
      if xnWOaToO s == -1
        then
          let
            tssorts = Set.toList sorts
          in
            case
              find
                (\s' -> xnName s' == xnName s)
                tssorts                
            of
              Nothing -> s
              (Just s') -> s'
        else
          s

    isLocal::DGLinkType->Bool
    isLocal LocalDef = True
    isLocal (LocalThm {}) = True
    isLocal _ = False

    isDef::DGLinkType->Bool
    isDef LocalDef = True
    isDef GlobalDef = True
    isDef HidingDef = True
    isDef _ = False

createDGLinkFromLinkSpecification::
    TheorySpecification
  ->LinkSpecification
  ->TheorySpecification
  ->Graph.LEdge DGLinkLab
createDGLinkFromLinkSpecification
  tsFrom
  ls
  tsTo
  =
  let
   caslmorph =
        let
          (hidden, req) = ls_hreql ls
          -- Sorts
          fromSorts =
            if isLocal (ls_type ls)
              then
                Set.filter
                  (\xns -> xnWOaToO xns == ts_nodenum tsFrom)
                  (ts_sorts tsFrom)
              else
                (ts_sorts tsFrom)
          availSorts = Set.filter (\xns -> not $ elem (xnName xns) hidden) fromSorts
          remappedSorts =
            Set.fold
              (\xns rS ->
                case
                  find
                    (\((_, oldName),_) -> oldName == xnName xns)
                    req
                of
                  Nothing -> rS
                  (Just (_, (_, newName))) ->
                    case
                      find
                        (\to_xns -> xnName to_xns == newName)
                        (Set.toList (ts_sorts tsTo))
                    of
                      Nothing ->
                        Debug.Trace.trace
                          (
                            "Warning: Predicate morphism not possible for "
                            ++ (xnName xns) ++ " -> " ++ newName
                          )
                          rS
                      (Just to_xns) -> rS ++ [(xns, to_xns)]
              )
              []
              availSorts
          sortmap =
            Map.fromList
              $
              map
                (\(oxns, nxns) -> (xnWOaToa oxns, xnWOaToa nxns))
                remappedSorts
          -- Predicates
          fromPreds = 
            if isLocal (ls_type ls)
              then
                Set.filter
                  (\(xnpid, _) -> xnWOaToO xnpid == ts_nodenum tsFrom)
                  (ts_predicates tsFrom)
              else
                (ts_predicates tsFrom)
          availPreds = Set.filter (\(xnpid, _) -> not $ elem (xnName xnpid) hidden) fromPreds
          remappedPreds =
            Set.fold
              (\(xnp@(xnpid, _)) rP ->
                case
                  find
                    (\((_, oldName),_) -> oldName == xnName xnpid)
                    req
                of
                  Nothing -> rP
                  (Just (_,(_,newName))) ->
                    case
                      find
                        (\(to_xnpid, _) -> xnName to_xnpid == newName)
                        (Set.toList (ts_predicates tsTo))
                    of
                      Nothing ->
                        Debug.Trace.trace
                          (
                            "Warning: Predicate morphism not possible for "
                            ++ (xnName xnpid) ++ " -> " ++ newName
                          )
                          rP
                      (Just to_xnp) -> rP ++ [(xnp, to_xnp)]
              )
              []
              availPreds
          predmap =
            Map.fromList
              $
              map
                (\( (oxnpid, oxnpt), (nxnpid, _) ) ->
                  ((xnWOaToa oxnpid, predTypeXNWONToPredType oxnpt), xnWOaToa nxnpid)
                )
                remappedPreds
          -- Operators
          fromOps = 
            if isLocal (ls_type ls)
              then
                Set.filter
                  (\(xnoid, _) -> xnWOaToO xnoid == ts_nodenum tsFrom)
                  (ts_operators tsFrom)
              else
                (ts_operators tsFrom)
          availOps = Set.filter (\(xnoid, _) -> not $ elem (xnName xnoid) hidden) fromOps
          remappedOps =
            Set.fold
              (\(xno@(xnoid, _)) rO ->
                case
                  find
                    (\((_, oldName),_) -> oldName == xnName xnoid)
                    req
                of
                  Nothing -> rO
                  (Just (_,(_,newName))) ->
                    case
                      find
                        (\(to_xnoid, _) -> xnName to_xnoid == newName)
                        (Set.toList (ts_operators tsTo))
                    of
                      Nothing ->
                        Debug.Trace.trace
                          (
                            "Warning: Operator morphism not possible for "
                            ++ (xnName xnoid) ++ " -> " ++ newName
                          )
                          rO
                      (Just to_xno) -> rO ++ [(xno, to_xno)]
              )
              []
              availOps
          opmap =
            Map.fromList
              $
              map
                (\( (oxnoid, oxnot), (nxnoid, nxnot) ) ->
                  ((xnWOaToa oxnoid, opTypeXNWONToOpType oxnot), (xnWOaToa nxnoid, opKindX nxnot))
                )
                remappedOps
        in
          Morphism
            {
                msource = Hets.emptyCASLSign
              , mtarget = Hets.emptyCASLSign
              , sort_map = sortmap
              , pred_map = predmap
              , fun_map = opmap
              , extended_map = ()
            }
  in
    if (ls_fromname ls) /= (ts_name tsFrom) || (ls_toname ls) /= (ts_name tsTo)
      then
        error "OMDoc.OMDocInput.createDGLinkFromLinkSpecification: Wrong application!"
      else
        (
            ts_nodenum tsFrom
          , ts_nodenum tsTo
          , DGLink
              {
                  dgl_morphism = Hets.makeCASLGMorphism caslmorph
                , dgl_type = ls_type ls
                , dgl_origin = ls_origin ls
		, dgl_id = defaultEdgeID
              }
        )
  where

    isLocal::DGLinkType->Bool
    isLocal LocalDef = True
    isLocal (LocalThm {}) = True
    isLocal _ = False

ffxiFromTheorySpecifications::
    GlobalOptions
  -> TheoryXNSet
  ->[TheorySpecification]
  ->FFXInput
ffxiFromTheorySpecifications
  go
  theoryxnnames
  tslist
  =
    foldl
      (\ffxi ts ->
        ffxi
          {
              xnSortsMap =
                Map.insert (ts_name ts) (ts_sorts ts) (xnSortsMap ffxi)
            , xnRelsMap =
                Map.insert (ts_name ts) (ts_sortrelation ts) (xnRelsMap ffxi)
            , xnPredsMap =
                Map.insert (ts_name ts) (ts_predicates ts) (xnPredsMap ffxi)
            , xnOpsMap =
                Map.insert
                  (ts_name ts)
                  (
                    Set.union
                      (ts_operators ts)
                      (
                        Set.fold
                          (\s1 s2 ->
                            Set.union s1 s2
                          )
                          Set.empty
                          (
                            Set.map
                              snd
                              (ts_constructors ts)
                          )
                      )
                  )
                  (xnOpsMap ffxi)
          }
      )
      emptyFFXInput { xnTheorySet = theoryxnnames, ffxiGO = go }
      tslist

createFFXIMap::
    GlobalOptions
  ->Map.Map String ([TheorySpecification], TheoryXNSet)
  ->Map.Map String FFXInput
createFFXIMap
  go
  tsmap
  =
  Map.foldWithKey
    (\sn (tslist, txns) m ->
      Map.insert sn (ffxiFromTheorySpecifications go txns tslist) m
    )
    Map.empty
    tsmap

createFinalDGraph::
  [Graph.LNode DGNodeLab]
  ->[Graph.LEdge DGLinkLab]
  ->DGraph
createFinalDGraph
  nodes
  edges
  =
  let
    e_fname = "OMDoc.OMDocInput.createFinalDGraph: "
    newedges =
      map
        (\(from, to, edge) ->
          let
            fromnode = 
              case
                filter (\(n, _) -> n == from) nodes
              of
                [] -> error (e_fname ++ "Cannot make link from #" ++ (show from))
                ((_, n):_) -> n
            tonode =
              case
                filter (\(n, _) -> n == to) nodes
              of
                [] -> error (e_fname ++ "Cannot make link to #" ++ (show to))
                ((_, n):_) -> n
            fromcaslsign =
              Data.Maybe.fromMaybe
                (error (e_fname ++ "Unable to get CASL-Sign from node (from)!"))
                (Hets.getCASLSign (dgn_sign fromnode))
            tocaslsign =
              Data.Maybe.fromMaybe
                (error (e_fname ++ "Unable to get CASL-Sign from node (to)!"))
                (Hets.getCASLSign (dgn_sign tonode))
            currentmorph = Hets.getCASLMorphLL edge
            newmorph =
              if
                case dgl_type edge of
                  HidingDef -> True
                  HidingThm {} -> True
                  _ -> False
                then
                  currentmorph
                    {
                        mtarget = fromcaslsign
                      , msource = tocaslsign
                    }
                else
                  currentmorph
                    {
                        mtarget = tocaslsign
                      , msource = fromcaslsign
                    }
          in
            (
                from
              , to
              , edge
                {
                  dgl_morphism = Hets.makeCASLGMorphism newmorph 
                }
            )
        )
        edges
  in
    Graph.mkGraph nodes newedges
   

addConstructorsTheorySpecificationOM::
  TheorySpecification
  ->FFXInput
  ->(Graph.Node, OMDoc.Theory)
  ->TheorySpecification
addConstructorsTheorySpecificationOM
  ts
  ffxi
  (origin, theory)
  =
  let
    theorycons = consXNWONFromOMTheory ffxi (origin, theory)
    tcset =
      foldl
        (\s (x, xl) ->
          Set.insert (x, Set.fromList xl) s
        )
        Set.empty
        theorycons
  in
    ts
      {
        ts_constructors = tcset
      }


processConstructorsOM::
  Map.Map String ([TheorySpecification], b, c, Set.Set (Graph.Node, OMDoc.Theory))
  ->Map.Map String FFXInput
  ->Map.Map String ([TheorySpecification], b, c, Set.Set (Graph.Node, OMDoc.Theory))
processConstructorsOM
  tsmap
  ffximap
  =
  Map.mapWithKey
    (\k (tslist, b, c, tos) ->
      let
        e_fname = "OMDoc.OMDocInput.processConstructorsOM: "
        thisffxi =
          Map.findWithDefault
            (error (e_fname ++ "error finding ffxi!"))
            k
            ffximap
        mappedspecs =
          map
            (\ts ->
              let
                (thisorigin, thistheory) =
                  case
                    find (\(nn, _) -> nn == (ts_nodenum ts)) (Set.toList tos)
                  of
                    Nothing -> error (e_fname ++ "no xml for " ++ ts_name ts)
                    (Just x) -> x
              in
                if isRefSpec ts
                  then
                    ts
                  else
                    addConstructorsTheorySpecificationOM ts thisffxi (thisorigin, thistheory)
            )
            tslist
      in
        (mappedspecs, b, c, tos)
    )
    tsmap


createGraphPartsOM::
  Map.Map String ([TheorySpecification], [LinkSpecification], c, Set.Set (Graph.Node, OMDoc.Theory))
  ->Map.Map String FFXInput
  ->Map.Map String ([Graph.LNode DGNodeLab], [Graph.LEdge DGLinkLab])
createGraphPartsOM
  tsmap
  ffximap
  =
  Map.mapWithKey
    (\k (tslist, lslist, _, axmls) ->
      let
        e_fname = "OMDoc.OMDocInput.createGraphPartsOM: "
        thisffxi =
          Map.findWithDefault
            (error (e_fname ++ "error finding ffxi!"))
            k
            ffximap
        nodes =
          map
            (\ts ->
              let
                thisaxml =
                  case
                    find (\(origin, _) -> origin == (ts_nodenum ts)) (Set.toList axmls)
                  of
                    Nothing -> error (e_fname ++ "no xml for " ++ ts_name ts)
                    (Just x) -> x
              in
                createNodeFromSpecOM
                  thisffxi
                  thisaxml
                  ts
            )
            tslist
        edges =
          map
            (\ls ->
              let
                fromts =
                  case
                    filter (\ts -> ts_name ts == ls_fromname ls) tslist
                  of
                    [] -> error (e_fname ++ "Unable to find source node " ++ (ls_fromname ls))
                    (n:_) -> n
                tots =
                  case
                    filter (\ts -> ts_name ts == ls_toname ls) tslist
                  of
                    [] ->
                      error
                        (
                          e_fname
                          ++ "Unable to find target node " ++ (ls_toname ls)
                          ++ " known names : " ++
                          (show (map ts_name tslist))
                        )
                    (n:_) -> n
              in
                createDGLinkFromLinkSpecification
                  fromts
                  ls
                  tots
            )
            lslist
        -------------------------------------------------------
	---------------- add IDs into edges -------------------
	-------------------------------------------------------
	edgesWithIDs = 
            zipWith (\(src,tgt,lab) n -> (src, tgt, lab{dgl_id=[n]}))
		    edges
		    [0..(length edges)]    
      in
	(nodes, edgesWithIDs)
        --(nodes, edges)
    )
    tsmap


importGraphToLibEnvOM::
    GlobalOptions
  ->ImportGraph OMDoc.OMDoc
  ->(ASL.LIB_NAME, DGraph, LibEnv)
importGraphToLibEnvOM
  go
  ig
  =
  let
    specMap = createSpecMapOM go ig
    processedSpecMap =
      processSpecMapOM specMap
    ffxiMap =
      createFFXIMap
        go
        (Map.map (\(a, _, c, _) -> (a, c)) processedSpecMap)
    conProcSpecMap = processConstructorsOM processedSpecMap ffxiMap
    ffxiWithConsMap =
      createFFXIMap
        go
        (Map.map (\(a, _, c, _) -> (a, c)) conProcSpecMap)
    partMap = createGraphPartsOM conProcSpecMap ffxiWithConsMap 
    graphMap =
      Map.map
        (\(nodes, edges) ->
          createFinalDGraph nodes edges
        )
        partMap
    libenv =
      Map.fromList
        $
        map
          (\(sn, dg) ->
            ( ASL.Lib_id (ASL.Indirect_link sn Id.nullRange "") 
            , emptyGlobalContext { devGraph = dg }
            )
          )
          (Map.toList graphMap)
    firstSourceNode =
      Data.Maybe.fromMaybe
        (error "OMDoc.OMDocInput.importGraphToLibEnvOM: No first node!")
        $
        Graph.lab ig 1
    firstSource = (\(S (sn, _) _) -> sn) firstSourceNode
    asKey = (ASL.Lib_id (ASL.Indirect_link firstSource Id.nullRange "")) 
    firstDG = lookupDGraph asKey libenv
  in
    (asKey, firstDG, libenv)

data LinkSpecification =
  LinkSpecification 
    {
        ls_type :: DGLinkType
      , ls_origin :: DGOrigin
      , ls_fromname :: XmlName
      , ls_toname :: XmlName
      --, ls_id :: Maybe XmlName
      , ls_hreql :: Hets.HidingAndRequationList
    }
  deriving (Show, Eq)

data TheorySpecification =
  TheorySpecification
    {
        ts_name :: XmlName
      , ts_source :: String
      , ts_nodename :: NODE_NAME
      , ts_nodenum :: Graph.Node
      , ts_sorts :: Set.Set XmlNamedWONSORT
      , ts_sortrelation :: Rel.Rel XmlNamedWONSORT
      , ts_predicates :: Set.Set (XmlNamedWONId, PredTypeXNWON)
      , ts_operators :: Set.Set (XmlNamedWONId, OpTypeXNWON)
      , ts_constructors :: Set.Set (XmlNamedWONId, Set.Set (XmlNamedWONId, OpTypeXNWON)) -- made from sentences on writeout to OMDoc
      , ts_late_insorts :: Set.Set ((String, String), [(String, String)])
    }
  | ReferenceSpecification
    {
        ts_name :: XmlName
      , ts_source :: String
      , ts_nodename :: NODE_NAME
      , ts_nodenum :: Graph.Node
      , ts_realnodenum :: Graph.Node
      , ts_sorts :: Set.Set XmlNamedWONSORT
      , ts_sortrelation :: Rel.Rel XmlNamedWONSORT
      , ts_predicates :: Set.Set (XmlNamedWONId, PredTypeXNWON)
      , ts_operators :: Set.Set (XmlNamedWONId, OpTypeXNWON)
      , ts_constructors :: Set.Set (XmlNamedWONId, Set.Set (XmlNamedWONId, OpTypeXNWON)) -- made from sentences on writeout to OMDoc
    }
  deriving (Show, Eq)

isRefSpec::TheorySpecification->Bool
isRefSpec (ReferenceSpecification {}) = True
isRefSpec _ = False


createLinkSpecificationsOM::
  GlobalOptions
  ->OMDoc.OMDoc
  ->TheoryXNSet
  ->Set.Set (Graph.Node, OMDoc.Theory)
  ->[LinkSpecification]
createLinkSpecificationsOM {-go-}_ omdoc theoryxnset aomset =
  let
    omimportsmap = omdocImportsMapFromAOMSet theoryxnset aomset
    noDummyMap =
      Map.filterWithKey
        (\k _ ->
          not $ Util.isPrefix "ymmud-" (reverse k)
        )
        omimportsmap
    imports' = omdocImportsMapToHetsImportsMap noDummyMap
    flatOMDocImports = map snd $ concat $ Map.elems omimportsmap
    -- filter out uninteresting imports (for performance)
    flatOMDocImportsWithMorphCons =
      filter
        (\omimp ->
          case OMDoc.importsConservativity omimp of
            OMDoc.CNone -> False
            _ ->
              case OMDoc.importsMorphism omimp of
                Nothing -> False
                (Just im) ->
                  case OMDoc.morphismId im of
                    Nothing -> False
                    _ -> True
        )
        flatOMDocImports
    glTheoIncs = glThmsFromOMIncs flatOMDocImportsWithMorphCons omdoc
    lsedges =
      foldl
        (\lsle (nodename, nodeimports) ->
          (foldl (\lsle' ({-tagnum-}_, (ni, {-mmm-}_, hreq, isGlobal)) ->
            let
              hreqmorph = Hets.emptyCASLMorphism
              hreqgmorph = 
                Hets.makeCASLGMorphism hreqmorph 
              isHiding = not $ Hets.isNonHidingHidAndReqL hreq
              ddgl =
                (if isGlobal
                  then 
                    if isHiding
                      then
                        defaultDGLinkLab { dgl_type = Static.DevGraph.HidingDef }
                      else
                        defaultDGLinkLab
                  else
                    defaultDGLinkLab { dgl_type = Static.DevGraph.LocalDef }
                ) {
                      dgl_morphism = hreqgmorph
                    , dgl_origin =
                      if Hets.isEmptyHidAndReqL hreq
                        then
                          dgl_origin defaultDGLinkLab
                        else
                          DGTranslation
                  }
            in
              lsle' ++
                  [
                    LinkSpecification
                      {
                          ls_type = dgl_type ddgl
                        , ls_fromname = ni
                        , ls_toname = nodename
                        , ls_hreql = hreq
                        , ls_origin = dgl_origin ddgl
                      }
                  ]
                
            ) lsle $ Set.toList nodeimports)
        ) -- ledges fold end
        []
        $
        Map.toList imports'
    gledges =
      foldl
        (\lsle (_, nodename, (from, hreq, cons, isGlobal)) ->
          let
            hreqmorph = Hets.emptyCASLMorphism
            hreqgmorph = 
              Hets.makeCASLGMorphism hreqmorph 
            isHiding = not $ Hets.isNonHidingHidAndReqL hreq
            ddgl =
              (if isGlobal
                then 
                  if isHiding
                    then
                      defaultDGLinkLab
                        {
                          dgl_type =
                            Static.DevGraph.HidingThm
                              Hets.emptyCASLGMorphism
                              Static.DevGraph.LeftOpen
                        }
                    else
                      defaultDGLinkLab
                        {
                          dgl_type =
                            Static.DevGraph.GlobalThm
                              Static.DevGraph.LeftOpen
                              cons
                              Static.DevGraph.LeftOpen
                        }
                else
                  defaultDGLinkLab
                    {
                      dgl_type =
                        Static.DevGraph.LocalThm
                          Static.DevGraph.LeftOpen
                          cons
                          Static.DevGraph.LeftOpen
                    }
              ) {
                    dgl_morphism = hreqgmorph
                  , dgl_origin =
                    if Hets.isEmptyHidAndReqL hreq
                      then
                        dgl_origin defaultDGLinkLab
                      else
                        DGTranslation
                }
          in
            lsle ++
                [
                  LinkSpecification
                    {
                        ls_type = dgl_type ddgl
                      , ls_fromname = from
                      , ls_toname = nodename
                      , ls_hreql = hreq
                      , ls_origin = dgl_origin ddgl
                    }
                ]
                
        ) -- ledges fold end
        []
        $
        glTheoIncs
  in
    (lsedges ++ gledges)


-- | theory name, theory source (local)
data TheoryImport = TI (String, String)

instance Show TheoryImport where
  show (TI (tn, ts)) = ("Import of \"" ++ tn ++ "\" from \"" ++ ts ++ "\".")

-- | source name, source (absolute)
--data Source a = S { nameAndURI::(String, String), sContent::a } 
data Source a = S (String, String) a

instance Show (Source a) where
  show (S (sn, sf) _) = ("Source \"" ++ sn ++ "\" File : \"" ++ sf ++ "\".");

type ImportGraph a = CLGraph.Gr (Source a) TheoryImport 


maybeGetXml::String->IO (Maybe HXT.XmlTrees)
maybeGetXml source =
  do
    xml <- HXT.run' $
      HXT.parseDocument
        [
            (HXT.a_source, source)
          , (HXT.a_issue_errors, HXT.v_0)
          , (HXT.a_check_namespaces, HXT.v_1)
          , (HXT.a_validate, HXT.v_0)
        ]
        HXT.emptyRoot
    return
      (let
        status = (read $ HXT.xshow $ getValue "status" (ehead "maybeGetXml" xml))::Int
        result = if status < HXT.c_err then (Just xml) else Nothing
      in
        result)
                                
maybeFindXml::String->[String]->IO (Maybe HXT.XmlTrees)
maybeFindXml source includes =
  let
    e_fname = "OMDoc.OMDocInput.maybeFindXml: "
    muri = URI.parseURIReference source
    uri = fromMaybe (error (e_fname ++ "cannot parse URIReference")) muri
    isFile = (length (URI.uriScheme $ uri)) == 0
    filePath = URI.uriPath uri
    isAbsolute =
        (isFile && ( (ehead (e_fname ++ "maybeFindXml") filePath) == '/'))
      ||
        (URI.isAbsoluteURI source)
    possibilities = source:(if not isAbsolute then map (++"/"++source) includes else [])
  in
    do
      case muri of
        Nothing -> return Nothing
        _ -> firstSuccess (map maybeGetXml possibilities)
  where
    firstSuccess::(Monad m)=>[(m (Maybe a))]->(m (Maybe a))
    firstSuccess [] = return Nothing
    firstSuccess (l:r) =
      do
        res <- l
        case res of
          Nothing -> firstSuccess r
          _ -> return res
                                  

getImportedTheoriesOMDoc::OMDoc.OMDoc->Map.Map String String
getImportedTheoriesOMDoc omdoc =
  let
    timports =
      foldl
        (\ti tc ->
          case tc of
            (OMDoc.CIm imports) ->
              ti ++ [OMDoc.importsFrom imports]
            _ -> ti
        )
        []
        (concat (map OMDoc.theoryConstitutives (OMDoc.omdocTheories omdoc)))
    cimports =
      map OMDoc.inclusionFrom (OMDoc.omdocInclusions omdoc)
    cexports =
      map OMDoc.inclusionTo (OMDoc.omdocInclusions omdoc)
  in
    Map.fromList
      $
      foldl
        (\l uri ->
          let
            path = URI.uriPath uri
            fragment = drop 1 $ URI.uriFragment uri
          in
            if (length path) > 0 && (length fragment) > 0
              then
                l ++ [(fragment, path)]
              else
                l
        )
        []
        (timports ++ cimports ++ cexports)
      

makeImportGraphOMDoc::GlobalOptions->String->(IO (ImportGraph OMDoc.OMDoc))
makeImportGraphOMDoc go source =
  do
    e_fname <- return "OMDoc.OMDocInput.makeImportGraphOMDoc: "
    curdirs <- System.Directory.getCurrentDirectory
    -- trick the uri parser into faking a document to make a relative path later
    mcduri <- return $ URI.parseURIReference ("file://"++curdirs++"/a")
    alibdir <- return $ case mcduri of
      Nothing -> (fixLibDir (libdir (hetsOpts go)))
      (Just cduri) -> relativeSource cduri (fixLibDir (libdir (hetsOpts go)))
    putIfVerbose (hetsOpts go) 0 ("Loading " ++ source ++ "...") 
    mdoc <- maybeFindXml source [alibdir]
    case mdoc of
      Nothing -> ioError $ userError ("Unable to find \"" ++ source ++ "\"")
      (Just doc) ->
        (let
          omdocxml = applyXmlFilter (getChildren .> isTag "omdoc") doc
          omdoc =
            case omdocxml of
              [] -> error (e_fname ++ "Not OMDoc!")
              (o:_) ->
                case OMDocXML.fromXml o of
                  Nothing -> error (e_fname ++ "Unable to read OMDoc!")
                  (Just om) -> om
          omdocid = OMDoc.omdocId omdoc
          mturi =
            URI.parseURIReference
              $
              xshow
                $
                getValue "transfer-URI" (ehead "makeImportGraphOMDoc" doc)
          turi =
            fromMaybe (error (e_fname ++ "Cannot parse URIReference...")) mturi
          muriwithoutdoc =
            URI.parseURIReference
              $
              (reverse $ dropWhile (/='/') $ reverse (show turi))
          uriwithoutdoc =
            fromMaybe
              (error (e_fname ++ "Cannot create path to document..."))
              muriwithoutdoc
          docmap = getImportedTheoriesOMDoc omdoc
          rdocmap = Map.toList docmap -- Map.toList $ Map.map (\s -> relativeSource turi s) docmap
          initialgraph = Graph.mkGraph [(1, S (omdocid, (show turi)) omdoc)] []
        in
          foldl
            (\gio (itname, ituri)  ->
              gio >>= \g -> buildGraph g 1 uriwithoutdoc (TI (itname, ituri)) alibdir
            ) (return initialgraph) rdocmap
        )
  where

  fixLibDir::FilePath->FilePath
  fixLibDir fp =
    case fp of 
      [] -> fp
      _ ->
        if last fp == '/'
          then
            init fp
          else
            fp

  buildGraph::
    ImportGraph OMDoc.OMDoc
    ->Graph.Node
    ->URI.URI
    ->TheoryImport
    ->String
    ->IO (ImportGraph OMDoc.OMDoc)
  buildGraph ig n frompath ti@(TI (theoname, theouri)) alibdir =
    let
      e_fname= "OMDoc.OMDocInput.makeImportGraphOMDoc#buildGraph: "
      includes = [alibdir, (show frompath)]
      possources =
        theouri:(
          map
            (\s -> s ++ (if (last s)=='/' then "" else "/") ++ theouri)
            includes
          )
      mimportsource =
        find
          (\(_, (S (_, suri) _)) -> any (\s -> suri == s) possources)
          (Graph.labNodes ig)
      (S (curid, _) _) =
        case Graph.lab ig n of
          Nothing -> error (e_fname ++ "No such node!")
          (Just x) -> x
    in
    do
      case mimportsource of
        (Just (inum, (S (isn,_) _))) ->
            do
              putIfVerbose
                (hetsOpts go)
                0
                ("Loading " ++ theoname ++ " from "
                  ++ theouri ++ " (cached) for " ++ curid ++ "..." 
                )
              return 
                (if inum == n then
                   debugGO
                    go
                    "mIGFXbG"
                    ("Back-reference in " ++ isn ++ " to " ++ theoname)
                    ig
                 else
                   (Graph.insEdge (n, inum, ti) ig)
                )
        Nothing ->
          do
            putIfVerbose
              (hetsOpts go)
              0
              ("Loading " ++ theoname ++ " from " ++ theouri ++ " for " ++ curid ++ "...")
            mdocR <- maybeFindXml theouri includes
            mdoc <- case mdocR of
              Nothing ->
                do
                  putIfVerbose
                    (hetsOpts go)
                    0
                    ("error at loading " ++ theouri ++ " from " ++ (show includes))
                  ioError
                    $
                    userError
                      ("Unable to find \"" ++ theouri
                        ++ "\" (looked in " ++ (show includes) ++ ")"
                      )
              _ -> return mdocR
            (newgraph, nn, importimports, newbase) <-
              return $
                (
                  let
                    doc =
                      fromMaybe
                        (error
                          (
                            e_fname
                            ++ "Unable to import \""++ theoname 
                            ++ "\"from \"" ++ theouri ++ "\""
                          )
                        )
                        mdoc
                    omdocxml = applyXmlFilter (getChildren .> isTag "omdoc") doc
                    omdoc =
                      case omdocxml of
                        [] -> error (e_fname ++ "No OMDoc!")
                        (o:_) ->
                          case OMDocXML.fromXml o of
                            Nothing -> error (e_fname ++ "Unable to read OMDoc!")
                            (Just om) -> om
                    omdocid = OMDoc.omdocId omdoc
                    imturi =
                      URI.parseURIReference
                        $
                        xshow $ getValue "transfer-URI" (ehead "buildGraph" doc)
                    ituri =
                      fromMaybe
                        (error (e_fname ++ "Cannot parse URIReference..."))
                        imturi
                    miuriwithoutdoc =
                      URI.parseURIReference
                        $
                        (reverse $ dropWhile (/='/') $ reverse (show ituri))
                    iuriwithoutdoc =
                      fromMaybe
                        (error (e_fname ++ "Cannot create path to document..."))
                        miuriwithoutdoc
                    iimports = getImportedTheoriesOMDoc omdoc
                    irimports = Map.toList iimports
                    newnodenum = (Graph.noNodes ig) + 1
                    newsource = S (omdocid, (show ituri)) omdoc
                    newgraph =
                      Graph.insEdge
                        (n, newnodenum, ti)
                        $
                        Graph.insNode (newnodenum, newsource) ig
                  in
                    (newgraph, newnodenum, irimports, iuriwithoutdoc)
                )
            foldl
              (\nigio (itheoname, itheouri) ->
                nigio >>= \nig ->
                  buildGraph nig nn newbase (TI (itheoname, itheouri)) alibdir
              )
              (return newgraph)
              importimports
  relativeSource::URI.URI->String->String
  relativeSource uri s =
    let
      e_fname= "OMDoc.OMDocInput.makeImportGraphOMDoc#relativeSource: "
      msuri = URI.parseURIReference s
      suri = fromMaybe (error (e_fname ++ "Cannot parse URIReference")) msuri
      mreluri = URI.relativeTo suri uri
      reluri =
        fromMaybe (error (e_fname ++ "Cannot create relative URI...")) mreluri
    in
      case msuri of
        Nothing -> s
        _ -> case mreluri of
          Nothing -> s
          _ -> URI.uriToString id reluri ""
                                                
{- |
  After merging all sentences for a target-node, the morphisms still
  point to the old signature. This function updates the target-
  signatures of all morphisms.
-}
{-
fixMorphisms::DGraph->DGraph
fixMorphisms dg =
  let
    labnodes = Graph.labNodes dg
    labedges = Graph.labEdges dg
    newedges =
      foldl
        (\ne (from, to, dgl) ->
          let
            caslmorph = Hets.getCASLMorphLL dgl
            tonode =
              fromMaybe
                (error "!")
                $
                Graph.lab dg to
            fromnode =
              fromMaybe
                (error "!")
                $
                Graph.lab dg from
            tonodesign =
              Hets.getJustCASLSign $ Hets.getCASLSign (dgn_sign tonode)
            fromnodesign =
              Hets.getJustCASLSign $ Hets.getCASLSign (dgn_sign fromnode)
            newmorph =
              if
                case dgl_type dgl of
                  HidingDef -> True
                  HidingThm {} -> True
                  _ -> False
                then
                  -- swap source and target for hiding...
                  caslmorph
                    {
                        msource = tonodesign
                      , mtarget = fromnodesign
                    }
                else
                  caslmorph
                    {
                        msource = fromnodesign
                      , mtarget = tonodesign
                    }
          in
            ne ++
              [
                (
                  from
                  , to
                  , dgl { dgl_morphism = Hets.makeCASLGMorphism newmorph }
                )
              ]
        )
        []
        labedges
  in
    Graph.mkGraph labnodes newedges
-}

createQuasiMappedLists::Eq a=>[(a,a)]->[(a,[a])]
createQuasiMappedLists = foldl (\i x -> insert x i) []
  where 
  insert::(Eq a, Eq b)=>(a,b)->[(a,[b])]->[(a,[b])]
  insert (a,b) [] = [(a,[b])]
  insert (a,b) ((a' ,l):r) =
    if a == a'
      then
        (a' , l++[b]):r
      else
        (a', l) : insert (a,b) r
        
isTrueAtom::(FORMULA ())->Bool
isTrueAtom (True_atom _) = True
isTrueAtom _ = False

-- OMDoc -> FORMULA

unwrapFormulasOM::FFXInput->(Graph.Node, OMDoc.Theory)->[(XmlNamed Hets.SentenceWO)]
unwrapFormulasOM ffxi (origin, theory) =
  let
    axioms =
      filter
        (\c ->
          case c of
            (OMDoc.CAx {}) -> True
            (OMDoc.CDe {}) -> True
            _ -> False
        )
        (OMDoc.theoryConstitutives theory)
  in
    map
      (\ax ->
        case ax of
          (con@(OMDoc.CAx {})) ->
            processAxDef con
          (con@(OMDoc.CDe {})) ->
            processAxDef con
          _ ->
            error "OMDoc.OMDocInput.unwrapFormulasOM: This should not happen!"
      )
      axioms
  where
    processAxDef::OMDoc.Constitutive->XmlNamed Hets.SentenceWO
    processAxDef con =
      let
        presentations = OMDoc.theoryPresentations theory
        axdefname =
          case con of
            (OMDoc.CAx axiom) ->
              OMDoc.axiomName axiom
            (OMDoc.CDe definition) ->
              OMDoc.definitionId definition
            _ -> error "OMDoc.OMDocInput.unwrapFormulasOM#processAxDef: \
                       \This should not happen!"
        name =
          case
            find
              (\p -> OMDoc.presentationForId p == axdefname)
              presentations
          of
            Nothing -> axdefname
            (Just p) ->
              case
                find
                  (\u -> OMDoc.useFormat u == "Hets") 
                  (OMDoc.presentationUses p)
              of
                Nothing -> axdefname
                (Just u) -> OMDoc.useValue u
        formula = unwrapFormulaOM ffxi origin con
      in
        XmlNamed
          (Hets.mkWON (formula { Ann.senName = name }) origin)
          axdefname



unwrapFormulaOM::FFXInput->Graph.Node->OMDoc.Constitutive->(Ann.Named CASLFORMULA)
unwrapFormulaOM ffxi origin con =
  let
    e_fname = "OMDoc.OMDocInput.unwrapFormulaOM: "
    (axdefname, fmps) =
      case con of
        (OMDoc.CAx axiom) ->
          (OMDoc.axiomName axiom, OMDoc.axiomFMPs axiom)
        (OMDoc.CDe definition) ->
          (OMDoc.definitionId definition, OMDoc.definitionFMPs definition)
        _ -> error (e_fname ++ "This should not happen!")
    formula =
      case fmps of
        [] -> error (e_fname ++ "No Formula!")
        (fmp@(OMDoc.FMP {}):_) ->
          case OMDoc.fmpContent fmp of
            (Left (OMDoc.OMObject ome)) ->
              formulaFromOM ffxi origin [] ome
            _ -> error (e_fname ++ "Can only create Formula from OMOBJ!")
  in
    Ann.NamedSen
      {
          Ann.senName = axdefname
        , Ann.isAxiom = (case con of OMDoc.CAx {} -> True; _ -> False)
        , Ann.isDef = (case con of OMDoc.CDe {} -> True; _ -> False)
        , Ann.sentence = formula
      }

data FFXInput = FFXInput {
         ffxiGO :: GlobalOptions
        ,xnTheorySet :: TheoryXNSet -- set of theorys (xmlnames + origin in graph)
        ,xnSortsMap :: Map.Map XmlName (Set.Set XmlNamedWONSORT) -- theory -> sorts mapping
        ,xnRelsMap :: Map.Map XmlName (Rel.Rel XmlNamedWONSORT) -- theory -> rels
        ,xnPredsMap :: Map.Map XmlName (Set.Set (XmlNamedWONId, PredTypeXNWON)) -- theory -> preds
        ,xnOpsMap :: Map.Map XmlName (Set.Set (XmlNamedWONId, OpTypeXNWON)) -- theory -> ops
        }
  deriving Show
        
        
emptyFFXInput::FFXInput
emptyFFXInput =
        FFXInput
                emptyGlobalOptions
                Set.empty
                Map.empty
                Map.empty
                Map.empty
                Map.empty


stripFragment::String->String
stripFragment s =
  let
    (file, theo) = span (/='#') s
  in
    case theo of
      [] -> file
      _ -> drop 1 theo
                

omToSort_gen_ax::FFXInput->OMDoc.OMElement->FORMULA ()
omToSort_gen_ax ffxi (OMDoc.OMEA oma') =
  let
    e_fname = "OMDoc.OMDocInput.omToConstraints: "
    (result, _) =
      case OMDoc.omaElements oma' of
        ( (OMDoc.OMES omssga):(OMDoc.OMEA oma):_:(OMDoc.OMES omsft):_) ->
          if OMDoc.omsName omssga == "sort-gen-ax"
            then
              let
                freetype =
                  if OMDoc.omsName omsft == caslSymbolAtomFalseS
                    then
                      False
                    else
                      True
                constraints = fetchConstraints oma
              in
                (
                    Sort_gen_ax
                      (
                        map
                          (\(ns, os, cons') ->
                            ABC.Constraint ns cons' os
                          )
                          constraints
                      )
                      freetype
                  , constraints
                )
            else
              error (e_fname ++ "Input is no sort-gen-ax! " ++ (show oma'))
        _ ->
          error (e_fname ++ "Malformed sort-gen-ax! : " ++ (show oma'))
  in
    result
  where
    fetchConstraints::OMDoc.OMApply->[(SORT, SORT, [(OP_SYMB, [Int])])]
    fetchConstraints oma =
      let
        e_fname = "OMDoc.OMDocInput.omToConstraints#fetchConstraints: "
      in
      case OMDoc.omaElements oma of
        ( (OMDoc.OMES omsConDef):contextsE ) ->
          if OMDoc.omsName omsConDef == "constraint-definitions"
            then
              let
                omaCCs =
                  foldl
                    (\omaCCs' e ->
                      case e of
                        (OMDoc.OMEA ccoma) ->
                          omaCCs' ++ [ccoma]
                        _ -> omaCCs'
                    )
                    []
                    contextsE
                contexts = fetchContexts omaCCs
              in
                contexts
            else
              error (e_fname ++ "Malformed sort-gen-ax")
        _ ->
          error (e_fname ++ "Malformed sort-gen-ax")
    fetchContexts::[OMDoc.OMApply]->[(SORT, SORT, [(OP_SYMB, [Int])])]
    fetchContexts omaCCs =
      let
        e_fname = "OMDoc.OMDocInput.omToConstraints#fetchContexts: "
      in
        foldl
          (\contexts' ccoma ->
            case OMDoc.omaElements ccoma of
              ((OMDoc.OMES omsConCon)
               :(OMDoc.OMES omsNS)
               :(OMDoc.OMES omsOS)
               :(OMDoc.OMEA omaConLis)
               :_) ->
                if OMDoc.omsName omsConCon == "constraint-context"
                  then
                    let
                      (ns, os) =
                        (
                            Hets.stringToId $ OMDoc.omsName omsNS
                          , Hets.stringToId $ OMDoc.omsName omsOS
                        )
                      conlist =
                        case OMDoc.omaElements omaConLis of
                          ((OMDoc.OMES omsConLis):cons') ->
                            if OMDoc.omsName omsConLis == "constraint-list"
                              then
                                processConstraintList cons'
                              else
                                []
                          _ ->
                            []
                    in
                      contexts' ++ [(ns, os, conlist)]
                  else
                    contexts'
              _ ->
                Debug.Trace.trace
                  (
                    e_fname
                    ++ "Ignoring unexpected elements in constraint-\
                    \definition"
                  )
                  contexts'
          )
          []
          omaCCs
    processConstraintList::[OMDoc.OMElement]->[(OP_SYMB, [Int])]
    processConstraintList cons' =
      let
        e_fname = "OMDoc.OMDocInput.omToConstraints#processConstraintList: "
      in
        foldl
          (\conlist' e ->
            case e of
              (OMDoc.OMEA omaCon) ->
                case OMDoc.omaElements omaCon of
                  ((OMDoc.OMES omsCon):(OMDoc.OMEA omaConInd):ope:_) ->
                    if OMDoc.omsName omsCon == "constraint"
                      then
                        let
                          op = operatorFromOM ffxi ope
                          indices =
                            case OMDoc.omaElements omaConInd of
                              ((OMDoc.OMES omsConInd):il) ->
                                if
                                  (==)
                                    (OMDoc.omsName omsConInd)
                                    "constraint-indices"
                                  then
                                    foldl
                                      (\il' e' ->
                                        case e' of
                                          (OMDoc.OMEI omi) ->
                                            il' ++ [OMDoc.omiInt omi]
                                          _ -> il'
                                      )
                                      []
                                      il
                                  else
                                    []
                              _ ->
                                []
                        in 
                          conlist' ++ [(op, indices)]
                      else
                        Debug.Trace.trace
                          (
                            e_fname
                            ++ "Ignoring unexpected OMS in constraint-list :"
                            ++ " \"" ++ (show omsCon) ++ "\""
                          )
                          conlist'
                  _ ->
                    conlist'
              x ->
                Debug.Trace.trace
                  (
                    e_fname
                    ++ "Ignoring unexpected element in constraint-list :"
                    ++ " \"" ++ (show x) ++ "\""
                  )
                  conlist'
          )
          []
          cons'
omToSort_gen_ax _ _ = error "Wrong application!"

predicationFromOM::FFXInput->OMDoc.OMElement->PRED_SYMB
predicationFromOM ffxi (OMDoc.OMES oms) = 
  let
    e_fname = "OMDoc.OMDocInput.predicationFromOM: "
    sxname = OMDoc.omsName oms
    sxcd = OMDoc.omsCD oms
    mtheoxn = findByName sxcd (xnTheorySet ffxi)
    theoxn = case mtheoxn of
            Nothing ->
              error
                (
                  e_fname
                  ++ "No Theory (" ++ sxcd ++ ") for used predicate (Name) !"
                  ++ sxname ++ " in " ++ (take 1000 $ show (xnPredsMap ffxi))
                )
            (Just theoxn' ) -> theoxn'
    theopreds = Map.findWithDefault Set.empty (xnName theoxn) (xnPredsMap ffxi)
    mpredxnid = findByName sxname (map fst $ Set.toList theopreds)
    predxnid = case mpredxnid of
            Nothing ->
              error
                ( 
                  e_fname
                  ++ "No such predicate in Theory! (" ++ show sxname 
                  ++ " in " ++ (take 1000 $ (show theopreds)) ++ ")"
                ) 
            (Just predxnid' ) -> predxnid'
    predXNWON = case lookup predxnid $ Set.toList theopreds of
            Nothing -> error (e_fname ++ "Predicate not found!")
            (Just pxnwon) -> pxnwon
    doFake =
      (
          (
            case mtheoxn of
              Nothing ->
                Debug.Trace.trace
                  ("Faking Predicate for " ++ show oms ++ " (not found, unknown theory)")
                  True
              _ -> False
          )
        ||
          (
            case mpredxnid of
              Nothing ->
                Debug.Trace.trace
                  ("Faking Predicate for " ++ show oms ++ " (not found)")
                  True
              _ -> False
          )
      )
  in
    if doFake
      then
        Qual_pred_name
          (Hets.stringToId sxname)
          (Pred_type [] Id.nullRange)
          Id.nullRange
      else
        Qual_pred_name
          (xnWOaToa predxnid)
          (Hets.cv_PredTypeToPred_type $ predTypeXNWONToPredType predXNWON)
          Id.nullRange
predicationFromOM _ _ =
  let
    e_fname = "OMDoc.OMDocInput.predicationFromOM: "
  in
    error (e_fname ++ "Invalid OMDoc.OMElement")
                
-- String to Quantifier...
quantFromName::String->QUANTIFIER
quantFromName s
        | (s == caslSymbolQuantUniversalS) = Universal
        | (s == caslSymbolQuantExistentialS) = Existential
        | (s == caslSymbolQuantUnique_existentialS) = Unique_existential
        | otherwise =
          error
            (
              "OMDoc.OMDocInput.quantFromName: "
              ++ s ++": no such quantifier..."
            )


getVarDeclsOM::OMDoc.OMBindingVariables->[(String, String)]
getVarDeclsOM ombvar =
  map
    (\(OMDoc.OMVA omattr) ->
      let
        e_fname = "OMDoc.OMDocInput.getVarDeclsOM: "
        typename =
          case
            filter
              (\e ->
                case e of
                  (omst, OMDoc.OMES _) ->
                    OMDoc.omsName omst == typeS
                  _ -> False
              )
              $
              OMDoc.omatpAttribs $ OMDoc.omattrATP omattr
          of
            [] -> error (e_fname ++ "No Type!")
            ((_, OMDoc.OMES oms):_) -> OMDoc.omsName oms
            _ -> error (e_fname ++ "Unexpected!")
        varname =
          case OMDoc.omattrElem omattr of
            (OMDoc.OMEV omv) ->
              OMDoc.omvName omv
            _ -> error (e_fname ++ "Not a simple Variable!")
      in
      (
          typename
        , varname
      )
    )
    (
      filter
        (\v -> case v of OMDoc.OMVA {} -> True; _ -> False)
        $
        OMDoc.ombvarVars ombvar
    )


isTermOM::OMDoc.OMElement->Bool
isTermOM (OMDoc.OMEV _) = True
isTermOM (OMDoc.OMEATTR _) = True
isTermOM (OMDoc.OMEA _) = True
isTermOM (OMDoc.OMES _) = True
isTermOM _ = False


isOperatorOM::OMDoc.OMElement->Bool
isOperatorOM (OMDoc.OMEATTR _) = True
isOperatorOM (OMDoc.OMES _) = True
isOperatorOM _ = False

{-
scanForVarTypesF::forall q . Set.Set Id.Id -> FORMULA q -> Map.Map Id.Id (Set.Set Id.Id)
scanForVarTypesF vids (Predication prs terms _) =
  let
    subInfo =
      foldl (\m t -> Map.unionWith Set.union m $ scanForVarTypesT vids t) Map.empty terms
    newInfo =
      case prs of
        (Pred_name {}) -> Map.empty
        (Qual_pred_name _ (Pred_type psorts _) _) ->
          foldl
            (\nI (os, t) ->
              case t of
                (Simple_id id') ->
                  if Set.member (Id.simpleIdToId id') vids
                    then
                      Map.insertWith Set.union (Id.simpleIdToId id') (Set.singleton os) nI
                    else
                      nI
                (Qual_var v s _) ->
                  if Set.member (Id.simpleIdToId v) vids 
                    then
                      let
                        nI' = Map.insertWith Set.union (Id.simpleIdToId v) (Set.singleton os) nI
                      in
{-                        if s /= os
                          then
                            Debug.Trace.trace
                              (
                                "(possible) Sort mismatch : wanted " 
                                ++ (show os) ++ "; got " ++ (show s)
                              )
                              nI'
                          else
                            nI' -}
                        nI'
                    else
                      nI
                otherTerm ->
                  foldl
                    (\nI' oTt ->
                      Map.unionWith Set.union nI' (scanForVarTypesT vids oTt)
                    )
                    nI
                    (getSubterms otherTerm)
            )
            Map.empty
            (zip psorts terms)
  in
    Map.unionWith Set.union subInfo newInfo
scanForVarTypesF  vids otherF = 
  let
    subTerms = getSubtermsF otherF
    subFormulas = getSubformulas otherF
    tInfo =
      foldl
        (\m t ->
          Map.unionWith Set.union m $ scanForVarTypesT vids t
        )
        Map.empty
        subTerms
    fInfo =
      foldl
        (\m f ->
          Map.unionWith Set.union m $ scanForVarTypesF vids f
        )
        tInfo
        subFormulas
  in
    fInfo


getSubtermsF::forall q . FORMULA q->[TERM q]
getSubtermsF (Definedness t _) = [t]
getSubtermsF (Existl_equation t1 t2 _) = [t1, t2] 
getSubtermsF (Strong_equation t1 t2 _) = [t1, t2] 
getSubtermsF (Membership t _ _) = [t]
getSubtermsF (Mixfix_formula t) = [t]
getSubtermsF _ = []

getSubformulas::forall q . FORMULA q->[FORMULA q]
getSubformulas (Quantification _ _ f _) = [f]
getSubformulas (Conjunction ts _) = ts
getSubformulas (Disjunction ts _) = ts
getSubformulas (Implication f1 f2 _ _) = [f1, f2]
getSubformulas (Equivalence f1 f2 _) = [f1, f2]
getSubformulas (Negation f _) = [f]
getSubformulas _ = []

scanForVarTypesT::forall f . Set.Set Id.Id -> TERM f -> Map.Map Id.Id (Set.Set Id.Id)
scanForVarTypesT vids (Qual_var v s _) =
  if Set.member (Id.simpleIdToId v) vids
    then
      Map.fromList [(Id.simpleIdToId v, Set.singleton s)]
    else
      Map.empty
scanForVarTypesT vids (Application ops terms _) =
  let
    subInfo =
      foldl (\m t -> Map.unionWith Set.union m $ scanForVarTypesT vids t) Map.empty terms
    newInfo =
      case ops of
        (Op_name {}) -> Map.empty
        (Qual_op_name _ otype _) ->
          foldl
            (\nI (os, t) ->
              case t of
                (Simple_id id') ->
                  if Set.member (Id.simpleIdToId id') vids
                    then
                      Map.insertWith Set.union (Id.simpleIdToId id') (Set.singleton os) nI
                    else
                      nI
                (Qual_var v s _) ->
                  if Set.member (Id.simpleIdToId v) vids 
                    then
                      let
                        nI' = Map.insertWith Set.union (Id.simpleIdToId v) (Set.singleton os) nI
                      in
{-                        if s /= os
                          then
                            Debug.Trace.trace
                              (
                                "(possible) Sort mismatch : wanted " 
                                ++ (show os) ++ "; got " ++ (show s)
                              )
                              nI'
                          else -}
                            nI'
                    else
                      nI
                otherTerm ->
                  foldl
                    (\nI' oTt ->
                      Map.unionWith Set.union nI' (scanForVarTypesT vids oTt)
                    )
                    nI
                    (getSubterms otherTerm)
            )
            Map.empty
            (zip (args_OP_TYPE otype) terms)
  in
    Map.unionWith Set.union subInfo newInfo
scanForVarTypesT vids otherT =
  let
    subTerms = getSubterms otherT
    subFormulas = getSubformulasT otherT
    tInfo =
      foldl
        (\m t ->
          Map.unionWith Set.union m $ scanForVarTypesT vids t
        )
        Map.empty
        subTerms
    fInfo =
      foldl
        (\m f ->
          Map.unionWith Set.union m $ scanForVarTypesF vids f
        )
        tInfo
        subFormulas
  in
    fInfo

getSubterms::forall q . TERM q -> [TERM q]
getSubterms (Sorted_term t _ _) = [t]
getSubterms (Cast t _ _) = [t]
getSubterms (Conditional t1 _ t2 _) = [t1, t2]
getSubterms (Application _ terms' _) = terms'
getSubterms _ = []

getSubformulasT::forall q . TERM q -> [FORMULA q]
getSubformulasT (Conditional _ f _ _) = [f]
getSubformulasT _ = []

unifyWithRelation::(Ord a)=>Rel.Rel a->[a]->[a]->Maybe a
unifyWithRelation _ [x] [] = Just x
unifyWithRelation _ [] _ = Nothing
unifyWithRelation rel (x:r) q =
  if all (\y -> Rel.path x y rel) (r++q)
    then
      Just x
    else
      unifyWithRelation rel r (x:q)
-}

formulaFromOM::FFXInput->Graph.Node->[(String, String)]->OMDoc.OMElement->(FORMULA ())
formulaFromOM ffxi origin varbindings (OMDoc.OMEBIND ombind) =
  let
    e_fname = "OMDoc.OMDocInput.formulaFromOM: @ombind : "
    quant =
      case OMDoc.ombindBinder ombind of
        (OMDoc.OMES oms) ->
          if OMDoc.omsCD oms == caslS
            then
              quantFromName $ OMDoc.omsName oms
            else
              error (e_fname ++ "Wrong CD!")
        _ -> error (e_fname ++ "Quantifier must be an OMS!")
    -- first element is the quantification-OMS
    formula =
      formulaFromOM
        ffxi
        origin
        newBindings
        (OMDoc.ombindExpression ombind)
    vardeclS =
      getVarDeclsOM
        (OMDoc.ombindVariables ombind)
    currentVarNames = map snd varbindings
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
        varbindings
        vardeclS
  {-
    scanShadow =
      foldl
        (\vb (vt, vn) ->
          let
            mprevious =
              case
                filter (\(_, ovn) -> ovn == vn) varbindings
              of
                [] -> Nothing
                (o:_) -> Just o
          in
            case mprevious of
              Nothing -> vb ++ [(vt, vn)]
              (Just (ovt, _)) ->
                if ovt == vt
                  then
                    vb
                  else
                    Debug.Trace.trace
                      (
                        "Warning: Variable \"" ++ vn ++ "\" of type \"" ++ vt ++ "\"\
                         \ shadows existing variable of type \"" ++ ovt ++ "\""
                      )
                      (
                        map
                          (\(old@(_, ovn)) ->
                            if ovn == vn 
                              then
                                (vt, vn)
                              else
                                old
                          )
                          vb
                      )
        )
        varbindings
        vardeclS
    -}
    {-
    varInfo = scanForVarTypesF (Set.fromList (map (Id.stringToId . snd) vardeclS)) formula
    unifiedVars =
      Map.map
        (\sortset ->
          let
            candidates = (Map.elems $ xnRelsMap ffxi)
--              filter
--               (\rel ->
--                  Set.isSubsetOf sortset (Rel.nodes (Rel.map xnWOaToa rel))
--                )
--                (Map.elems $ xnRelsMap ffxi)
            muni =
              if Set.size sortset < 2
                then
                  Just $ head $ Set.toList sortset
                else
                  Util.anything
                    (
                      map
                        (\r ->
                          unifyWithRelation
                            (Rel.map xnWOaToa r)
                            (Set.toList sortset)
                            []
                        )
                        candidates
                    )
          in
            case muni of
              Nothing ->
{-                Debug.Trace.trace
                  (
                    "Cannot unify... please yourself... (" ++ (show sortset) ++ ") "
                    ++ (show candidates)
                  ) -}
                  (head $ Set.toList sortset)
              (Just u) -> u
        )
        varInfo 
    -}
    vardeclS2 = createQuasiMappedLists vardeclS
  in
{-    Debug.Trace.trace
      (
        "Varinfo : " ++ (show vardeclS)
        ++ " raw : " ++ (show varInfo)
        ++ " : unified " ++ (show unifiedVars)
      )
      $ -}
      Quantification
        quant
        (map
          (\(s, vl) ->
            Var_decl
              (map Hets.stringToSimpleId vl)
              (case findByNameAndOrigin
                      (stripFragment s)
                      origin
                      (mapSetToSet $ xnSortsMap ffxi) of
                 Nothing -> error (e_fname ++ "No Sort for " ++ s)
                 (Just x) -> xnWOaToa x
              )
              --(Hets.stringToId s)
              Id.nullRange
          )
          vardeclS2
        )
        formula
        Id.nullRange
formulaFromOM ffxi origin varbindings (OMDoc.OMEA oma) =
  let
    e_fname = "OMDoc.OMDocInput.formulaFromOM: @oma : "
    applySym =
      case OMDoc.omaElements oma of
        ((OMDoc.OMES oms):_) ->
          OMDoc.omsName oms
        _ -> error (e_fname ++ "No OMS First!")
    ftr =
      readsPrec
        (error (e_fname ++ "this argument is not used!"))
        applySym
    formulas =
      map
        (formulaFromOM ffxi origin varbindings)
        $
        filter
          (\e ->
            case e of
              (OMDoc.OMEA {}) -> True
              (OMDoc.OMEATTR {}) -> True
              (OMDoc.OMEBIND {}) -> True
              _ -> False
          )
          (OMDoc.omaElements oma)
    terms =
      map
        (\termc ->
          case termc of
            (Simple_id {}) ->
              Debug.Trace.trace
                (
                  "Created Simple_id : " ++ (show oma)
                )
                termc
            _ -> termc
        )
        $
        map
          (termFromOM ffxi origin varbindings)
          $
          drop
            1
            $
            filter
              (\e ->
                case e of
                  (OMDoc.OMEA {}) -> True
                  (OMDoc.OMEATTR {}) -> True
                  (OMDoc.OMEV {}) -> True
                  (OMDoc.OMES {}) -> True
                  _ -> False
              )
              (OMDoc.omaElements oma)
  in
    case ftr of
      ((ft, _):_) ->
        case ft of
          FTConjunction ->
            Conjunction formulas Id.nullRange
          FTDisjunction ->
            Disjunction formulas Id.nullRange
          FTImplication ->
            makeImplication formulas
          FTEquivalence ->
            makeEquivalence formulas
          FTNegation ->
            makeNegation formulas
          FTPredication ->
            makePredication
          FTDefinedness ->
            makeDefinedness
          FTExistl_equation ->
            makeExistl_equation terms
          FTStrong_equation ->
            makeStrong_equation terms
          FTMembership ->
            makeMembership terms
          FTSort_gen_ax ->
            makeSort_gen_ax
      _ ->
        let
          predterms =
            map
              (termFromOM ffxi origin varbindings)
              $
              filter
                (\e ->
                  case e of
                    (OMDoc.OMEA {}) -> True
                    (OMDoc.OMEATTR {}) -> True
                    _ -> False
                )
                (OMDoc.omaElements oma)
          possibilities =
            findAllByNameWithAnd
              id
              fst
              applySym
              (mapSetToSet (xnPredsMap ffxi))
          withThisOrigin =
            filter
              (\i -> (xnWOaToO $ fst i) == origin)
              possibilities
        in
          if applySym /= []
            then
              case
                case withThisOrigin of
                  [] -> possibilities
                  _ -> withThisOrigin
              of
                (i:_) ->
                  Predication
                    (
                      Qual_pred_name (xnWOaToa (fst i))
                        (
                          Hets.cv_PredTypeToPred_type
                            $ predTypeXNWONToPredType (snd i)
                        )
                        Id.nullRange
                    )
                    predterms
                    Id.nullRange
                [] ->
                  Debug.Trace.trace
                    (
                      "Faking Predicate for \"" ++ applySym ++ "\" : "
                      ++ (take 1000 $ (show oma))
                    )
                    (
                      Predication
                        (
                          Qual_pred_name
                            (Hets.stringToId applySym)
                            (
                              Pred_type [] Id.nullRange
                            )
                            Id.nullRange
                        )
                        predterms
                        Id.nullRange
                    )
--                  error ("Could not find predicate for \"" ++ applySym ++ "\"")
            else
              error (e_fname ++ "Empty application...")
  where


    makeImplication::[FORMULA ()]->FORMULA ()
    makeImplication formulas =
      let
        e_fname = "OMDoc.OMDocInput.formulaFromOM#makeImplication: "
        boolF =
          formulaFromOM
            ffxi
            origin
            varbindings
            $
            case
              filter
                (\e -> 
                  case e of
                    (OMDoc.OMES {}) -> True
                    _ -> False
                )
                (OMDoc.omaElements oma)
            of
              [] -> error (e_fname ++ "No OMS!")
              (_:second:_) -> second
              _ -> error (e_fname ++ "No second OMS!")
      in
        if length formulas < 2
          then
            error (e_fname ++ "Not enough formulas for implication!")
          else
            Implication
              (formulas!!0)
              (formulas!!1)
              (isTrueAtom boolF)
              Id.nullRange

    makeEquivalence::[FORMULA ()]->FORMULA ()
    makeEquivalence formulas =
      if length formulas < 2
        then
          error
            "OMDoc.OMDocInput.formulaFromOM#makeEquivalence: \
            \Not enough formulas for equivalence!"
        else
          Equivalence
            (formulas!!0)
            (formulas!!1)
            Id.nullRange
          
    makeNegation::[FORMULA ()]->FORMULA ()
    makeNegation formulas =
      if length formulas < 1
        then
          error
            "OMDoc.OMDocInput.formulaFromOM#makeNegation: \
            \Empty formulas for negation!"
        else
          Negation (formulas!!0) Id.nullRange

    makePredication::FORMULA ()
    makePredication =
      let
        e_fname = "OMDoc.OMDocInput.formulaFromOM#makePredication: "
        pred' =
          case
            filter
              (\e -> 
                case e of
                  (OMDoc.OMES {}) -> True
                  (OMDoc.OMEATTR {}) -> True
                  _ -> False
              )
              (OMDoc.omaElements oma)
          of
            [] ->
              error (e_fname ++ "No Elements for Predication!")
            (_:second:_) ->
              predicationFromOM ffxi second
            _ ->
              error (e_fname ++ "No second matching element for Predication!")
        predterms =
          map
            (termFromOM ffxi origin varbindings)
            $
            drop
              2
              $
              filter
                (\e ->
                  case e of
                    (OMDoc.OMEA {}) -> True
                    (OMDoc.OMEATTR {}) -> True
                    (OMDoc.OMES {}) -> True
                    _ -> False
                )
                (OMDoc.omaElements oma)
      in
        Predication
          pred'
          predterms
          Id.nullRange

    makeDefinedness::FORMULA ()
    makeDefinedness =
      let
        defterm =
          case
            drop
              1
              $
              filter
                (\e ->
                  case e of
                    (OMDoc.OMEA {}) -> True
                    (OMDoc.OMEATTR {}) -> True
                    (OMDoc.OMES {}) -> True
                    (OMDoc.OMEV {}) -> True
                    _ -> False
                )
                (OMDoc.omaElements oma)
          of
            [] -> error "No Term for Definedness!"
            (t:_) -> termFromOM ffxi origin varbindings t
      in
        Definedness defterm Id.nullRange

    makeExistl_equation::[TERM ()]->FORMULA ()
    makeExistl_equation terms =
      if length terms < 2
        then
          error
            "OMDoc.OMDocInput.formulaFromOM#makeExistl_equation: \
            \Not enough terms for Existl_equation!"
        else
          Existl_equation 
            (terms!!0)
            (terms!!1)
            Id.nullRange
    
    makeStrong_equation::[TERM ()]->FORMULA ()
    makeStrong_equation terms =
      if length terms < 2
        then
          error
            (
              "OMDoc.OMDocInput.formulaFromOM#makeStrong_equation: \
              \Not enough terms for Strong_equation! ("
                ++ show (length terms) ++ ") : "
                ++ (take 1000 (show oma))
            )
        else
          Strong_equation 
            (terms!!0)
            (terms!!1)
            Id.nullRange

    makeMembership::[TERM ()]->FORMULA ()
    makeMembership terms =
      let
        e_fname = "OMDoc.OMDocInput.formulaFromOM#makeMembership: "
      in
        if length terms < 1
          then
            error (e_fname ++ "Not enought terms for Membership!")
          else
            let
              lastoms =
                lastorempty
                  $
                  filter
                    (\e ->
                      case e of
                        (OMDoc.OMES {}) -> True
                        _ -> False
                    )
                    (OMDoc.omaElements oma)

            in
              case lastoms of
                [(OMDoc.OMES oms)] ->
                  let
                    sort = OMDoc.omsName oms
                    sortcd = OMDoc.omsCD oms
                    theosorts =
                      Map.findWithDefault
                        Set.empty
                        sortcd
                        (xnSortsMap ffxi) 
                    sortxn =
                      case findByName sort theosorts of
                        Nothing ->
                          error
                            (
                              e_fname
                              ++ "Sort not found in theory!"
                              ++ "(" ++ sort ++ ", "
                              ++ (take 1000 $ (show theosorts)) ++ ")" 
                            )
                        (Just x) -> x
                  in
                    Membership
                      (ehead (e_fname ++ "Membership") terms)
                      (xnWOaToa sortxn)
                      Id.nullRange
                _ -> error (e_fname ++ "No OMS for Membership-Sort!")
    
    makeSort_gen_ax::FORMULA ()
    makeSort_gen_ax =
      omToSort_gen_ax ffxi (OMDoc.OMEA oma)

formulaFromOM _ _ _ (OMDoc.OMES oms) =
  if OMDoc.omsName oms == caslSymbolAtomFalseS
    then
      False_atom Id.nullRange
    else
      if OMDoc.omsName oms == caslSymbolAtomTrueS
        then
          True_atom Id.nullRange
        else
          error
            "OMDoc.OMDocInput.formulaFromOM: @oms : Expected true or false..."

formulaFromOM _ _ _ _ =
  error "OMDoc.OMDocInput.formulaFromOM: @_ : Not implemented"

termFromOM::FFXInput->Graph.Node->[(String, String)]->OMDoc.OMElement->(TERM ())
termFromOM ffxi origin vb (OMDoc.OMEV omv) =
  let
    e_fname = "OMDoc.OMDocInput.termFromOM: @omv : "
    varname = OMDoc.omvName omv
    mvartypexn =
      case
        filter
          (\(_, vn) -> vn == varname)
          vb
      of
        [] ->
          Nothing
        ((vt,_):_) ->
          Just vt
  in
    case mvartypexn of
      Nothing ->
        Debug.Trace.trace
          (
            "Warning: Untyped variable (TERM) from \"" 
            ++ (show omv) ++ " Bindings " ++ (show vb)
          ) 
          $
          Simple_id 
            $
            Hets.stringToSimpleId (OMDoc.omvName omv)
      (Just varxnsort) ->
        Qual_var
          (Hets.stringToSimpleId varname)
          (
            let
              varsort =
                case
                  findByNameAndOrigin
                    varxnsort
                    origin
                    (mapSetToSet $ xnSortsMap ffxi)
                of
                  Nothing ->
                    error
                      (
                        e_fname
                        ++ "Cannot find defined sort for \""
                        ++ varxnsort ++"\"" 
                      )
                  (Just x) -> xnWOaToa x
            in
               varsort
          )
          Id.nullRange
      

termFromOM ffxi origin vb (ome@(OMDoc.OMEATTR omattr)) =
  let
    e_fname = "OMDoc.OMDocInput.termFromOM: @omattr : "
  in
    if
      (/=)
        (
        filter
          (\(oms, _) ->
            OMDoc.omsName oms == "funtype"
          )
          (OMDoc.omatpAttribs $ OMDoc.omattrATP omattr)
        )
        []
      then
        Application (operatorFromOM ffxi ome) [] Id.nullRange
      else
        let
          varname =
            case (OMDoc.omattrElem omattr) of
              (OMDoc.OMEV omv) ->
                (OMDoc.omvName omv)
              _ ->
                error (e_fname ++ "Expected OMV in OMATTR!")
          varxnsort =
            case
              filter
                (\(oms, _) ->
                  OMDoc.omsName oms == typeS
                )
                (OMDoc.omatpAttribs $ OMDoc.omattrATP omattr)
            of
              [] -> error (e_fname ++ "No Name! : " ++ show ome)
              ((_,(OMDoc.OMES typeoms)):_) -> OMDoc.omsName typeoms
              q -> error (e_fname ++ "Need OMS for Variable-Type... given : " ++ show q)
          shadowCheck =
            filter
              (\(vt, vn) ->
                if vn == varname
                  then
                    if vt /= varxnsort
                      then
                        Debug.Trace.trace
                          (
                            "Warning: " ++ varname ++ "::" ++ varxnsort ++
                            " shadows existing variable of type " ++ vt
                          )
                          False
                      else
                        False
                  else
                    False
              )
              vb
        in
          (
            if null shadowCheck
              then
                id
              else
                id
          )
          Qual_var
            (Hets.stringToSimpleId varname)
            (
              let
                varsort =
                  case
                    findByNameAndOrigin
                      varxnsort
                      origin
                      (mapSetToSet $ xnSortsMap ffxi)
                  of
                    Nothing ->
                      error
                        (
                          e_fname
                          ++ "Cannot find defined sort for \""
                          ++ varxnsort ++"\"" 
                        )
                    (Just x) -> xnWOaToa x
              in
                 varsort
            )
            Id.nullRange
termFromOM ffxi origin vb (OMDoc.OMEA oma) =
  let
    e_fname = "OMDoc.OMDocInput.termFromOM: @oma : "
    operator =
      operatorFromOM
        ffxi
        (
          ehead
            (e_fname ++ "operator")
            $
            (filter isOperatorOM $ OMDoc.omaElements oma)
        )
    terms =
      map
        (termFromOM ffxi origin vb)
        $
        drop 1
          $
          filter
            isTermOM
            $
            OMDoc.omaElements oma
  in
    case (opName operator) of
    "PROJ" ->
        Cast
          (ehead (e_fname ++ "PROJ") terms)
          (Hets.stringToId $ show (ehead (e_fname ++ "PROJ, tail") $ tail terms))
          Id.nullRange
    "IfThenElse" ->
      let
        iteChildsX =
          filter
            (\ome ->
              case ome of
                (OMDoc.OMES _) -> True
                (OMDoc.OMEBIND _) -> True
                (OMDoc.OMEATTR _) -> True
                (OMDoc.OMEA _) -> True
                (OMDoc.OMEV _) -> True
                _ -> False
            )
            (OMDoc.omaElements oma)
        iteCondX =
          ehead
            (
              e_fname
              ++ "Missing condition in conditional term : "
              ++ (take 1000 (show oma))
            )
            $
            singleitem 2 iteChildsX
        iteThenX =
          ehead
            (
              e_fname
              ++ "Missing 'then'-part in conditional term : "
              ++ (take 1000 (show oma))
            )
            $
            singleitem 3 iteChildsX
        iteElseX =
          ehead
            (
              e_fname 
              ++ "Missing 'else'-part in conditional term : "
              ++ (take 1000 (show oma))
            )
            $
            singleitem 4 iteChildsX
        iteCond =
          formulaFromOM
            ffxi
            origin
            vb
            iteCondX
        iteThen = termFromOM ffxi origin vb (iteThenX)
        iteElse = termFromOM ffxi origin vb (iteElseX)
      in
        Conditional
          iteThen
          iteCond
          iteElse
          Id.nullRange
    _ ->
      Application operator terms Id.nullRange
termFromOM ffxi _ _ (ome@(OMDoc.OMES _)) =
    let
      operator = 
        (\x -> debugGO (ffxiGO ffxi)
          "tFXXNo"
          ("operator : " ++ (show ome))
          x
        )
        $
        operatorFromOM
          ffxi
          ome
    in
      Application operator [] Id.nullRange
termFromOM _ _ _ t =
  error
    (
      "OMDoc.OMDocInput.termFromOM: @_ : \
      \Impossible to create term from \"" 
      ++ show t ++"\""
    ) 

operatorFromOM::FFXInput->OMDoc.OMElement->OP_SYMB
operatorFromOM ffxi (OMDoc.OMES oms) =
  let
    e_fname = "OMDoc.OMDocInput.operatorFromOM: @oms : "
    sxname = OMDoc.omsName oms
    scd = OMDoc.omsCD oms
    stheoid =
      case scd of
        ('#':r) -> r
        _ -> scd
    mtheo = findByName stheoid (xnTheorySet ffxi)
    theoxn =
      case mtheo of
        Nothing ->
          error
            (
              e_fname
              ++ "No Theory for used operator! (\"" 
              ++ sxname ++ "\" in \"" ++ scd ++ "\" Context : \""
              ++ (show oms) ++ "\")"
            )
        (Just theoxn' ) -> theoxn'
    theoops = Map.findWithDefault Set.empty (xnName theoxn) (xnOpsMap ffxi)
    mopxnid = findByName sxname (map fst $ Set.toList theoops)
    opxnid = case mopxnid of
      Nothing ->
        error
          (
            e_fname
            ++ "No such operator in Theory! (" ++ sxname ++ " in "
            ++ (take 1000 (show theoops)) ++ ")"
          )
      (Just opxnid' ) -> opxnid'
    opXNWON = case lookup opxnid $ Set.toList theoops of
      Nothing -> error (e_fname ++ "Operator not found!")
      (Just oxnwon) -> oxnwon
    doFake =
      (
          (stheoid /= caslS)
        &&
          (
            (
              case mtheo of
                Nothing ->
                  Debug.Trace.trace
                    ("Faking Operator for " ++ (show oms) ++ " (not found, unknown theory)")
                    True
                _ -> False
            )
          ||
            (
              case mopxnid of
                Nothing ->
                  Debug.Trace.trace
                    ("Faking Operator for " ++ (show oms) ++ " (not found)")
                    True
                _ -> False
            )
          )
      )
  in
    if
      ( (stheoid==caslS) || doFake )
      then -- eventually there should be an aux. casl-theory while processing...
        if doFake 
          then
            -- faking Op_name's causes errors in MapSentence later
            -- so this clumsy Qual_op_name is constructed...
            Qual_op_name
              (Hets.stringToId sxname)
              (Op_type Total [] (Hets.stringToId "fakeT") Id.nullRange)
              Id.nullRange
          else
            Op_name
              (Hets.stringToId sxname)
      else
        Qual_op_name
          (xnWOaToa opxnid)
          (Hets.cv_OpTypeToOp_type $ opTypeXNWONToOpType opXNWON)
          Id.nullRange
operatorFromOM _ _ =
  error "OMDoc.OMDocInput.operatorFromOM: @_ : wrong parameter!"

opName::OP_SYMB->String
opName (Op_name op) = (show op)
opName (Qual_op_name op _ _) = (show op)

{-
opNameId::OP_SYMB->Id.Id
opNameId (Op_name op) = op
opNameId (Qual_op_name op _ _) = op
-}

-- this reads back an encapsulated node_name
idToNodeName::Id.Id->NODE_NAME
idToNodeName (Id.Id toks _ _) =
  if (length toks) < 3
    then
      error
        (
          "OMDoc.OMDocInput.idToNodeName: Malformed NODE_NAME-Id : "
          ++ (show toks)
        )
    else
      (toks!!0, show (toks!!1), read (show (toks!!2)))



