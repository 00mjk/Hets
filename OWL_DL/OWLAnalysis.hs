{- |
Module      :  $Header$
Copyright   :  Heng Jiang, Uni Bremen 2004-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  jiang@tzi.de
Stability   :  provisional
Portability :  non-portable (inports Logic.Logic)

analyse owl files
-}

module OWL_DL.OWLAnalysis where

import OWL_DL.AS
import OWL_DL.Namespace
import OWL_DL.Logic_OWL_DL
import OWL_DL.StaticAna
import OWL_DL.Sign
import OWL_DL.StructureAna

import Common.ATerm.ReadWrite
import Common.ATerm.Unshared
import System.Cmd(system)
import System.Exit
import System.Environment(getEnv)
import System.Posix.Process
import qualified Data.Map as Map
import qualified Data.List as List
import Data.Graph.Inductive.Graph
import Static.DevGraph
import Common.GlobalAnnotations
import Common.Result
import Common.Utils
import Common.AS_Annotation hiding (isAxiom,isDef)
import Syntax.AS_Library
import Driver.Options
import Common.Id
import Logic.Logic
import Logic.Grothendieck
import Logic.Prover
-- import Data.Graph.Inductive.Query.DFS
-- import Data.Graph.Inductive.Query.BFS
import Data.Maybe(fromJust)
import System.IO
import System.Time

-- | call for owl parser (env. variable $HETS_OWL_PARSER muss be defined)
parseOWL :: FilePath              -- ^ local filepath or uri
         -> IO OntologyMap        -- ^ map: uri -> Ontology
parseOWL filename  =
  do
    pwd <- getEnv "PWD"
    if null filename
       then
         error "empty file name!"
       else do
           pid <- getProcessID
           currTime <- getClockTime
           calend <- toCalendarTime currTime
           let tmpFile = "/tmp/" ++ (basename filename) ++ "-" ++ (show pid)
                         ++ "-" ++ (buildTime calend) ++ ".term"
           if checkUri filename
               then
                 do exitCode <-
                        system ("$HETS_OWL_PARSER/owl_parser " ++ filename ++
                               " " ++ tmpFile)
                    run exitCode tmpFile
               else if (head filename) == '/'
                       then
                         do
                           exitCode <-
                                system ("$HETS_OWL_PARSER/owl_parser file://"
                                        ++ filename ++ " " ++ tmpFile)
                           run exitCode tmpFile
                       else do exitCode <-
                                 system ("$HETS_OWL_PARSER/owl_parser file://"
                                         ++ pwd ++ "/" ++ filename ++
                                        " " ++ tmpFile)
                               run exitCode tmpFile

       where buildTime cTime =
                 (show $ ctYear cTime) ++ (show $ ctMonth cTime) ++
                 (show $ ctDay cTime) ++ (show $ ctHour cTime) ++
                 (show $ ctMin cTime) ++ (show $ ctSec cTime)

             run :: ExitCode -> FilePath -> IO OntologyMap
             run exitCode tmpFile
                 | exitCode == ExitSuccess =
                     do
                       t <- parseProc tmpFile
                       system ("rm -f " ++ tmpFile)
                       return t
                 | otherwise =  error ("process stop! " ++ (show exitCode))

-- | parse the file "output.term" from java-owl-parser
parseProc :: FilePath -> IO OntologyMap
parseProc filename =
    do d <- readFile filename
       let aterm = getATermFull $ readATerm d
       case aterm of
         AList paarList _ ->
             return $ Map.fromList $ parsingAll paarList
         _ -> error ("false file: " ++ show filename ++ ".")

-- | parse an ontology with all imported ontologies
parsingAll :: [ATerm] -> [(String, Ontology)]
parsingAll [] = []
parsingAll (aterm:res) =
             (ontologyParse aterm):(parsingAll res)

-- | ontology parser, this version ignore validation, massages of java-parser.
ontologyParse :: ATerm -> (String, Ontology)
ontologyParse
    (AAppl "UOPaar"
        [AAppl uri _  _,
         AAppl "OWLParserOutput" [_, _, _, onto] _] _)
    = case ontology of
      Ontology _ _ namespace ->
          (if head uri == '"' then read uri::String else uri,
           propagateNspaces namespace $ createAndReduceClassAxiom ontology)
   where ontology = fromATerm onto::Ontology
ontologyParse _ = error "false ontology file."

-- | remove equivalent disjoint class axiom, create equivalentClasses,
-- | subClassOf axioms, and sort directives (definitions of classes and
-- | properties muss be moved to begin of directives)
createAndReduceClassAxiom :: Ontology -> Ontology
createAndReduceClassAxiom (Ontology oid directives ns) =
    let (definition, axiom, other) =
            findAndCreate (List.nub directives) ([], [], [])
        directives' = reverse definition ++ reverse axiom ++ reverse other
    in  Ontology oid directives' ns

   where -- search directives list, sort the define concept and role,
         -- axioms, and rest
         findAndCreate :: [Directive]
                       -> ([Directive], [Directive], [Directive])
                       -> ([Directive], [Directive], [Directive])
         findAndCreate [] res = res
         findAndCreate (h:r) (def, axiom, rest) =
             case h of
             Ax (Class cid _ Complete _ desps) ->
                 -- the original directive must also be saved.
                 findAndCreate r
                    (h:def,(Ax (EquivalentClasses (DC cid) desps)):axiom,rest)
             Ax (Class cid _ Partial _ desps) ->
                 if null desps then
                    findAndCreate r (h:def, axiom, rest)
                    else
                     findAndCreate r (h:def,
                                      (appendSubClassAxiom cid desps) ++ axiom,
                                      rest)
             Ax (EnumeratedClass _ _ _ _) ->
                 findAndCreate r (h:def, axiom, rest)
             Ax (DisjointClasses _ _ _) ->
                             if any (eqClass h) r then
                                findAndCreate r (def, axiom, rest)
                                else findAndCreate r (def,h:axiom, rest)
             Ax (DatatypeProperty _ _ _ _ _ _ _) ->
                 findAndCreate r (h:def, axiom, rest)
             Ax (ObjectProperty _ _ _ _ _ _ _ _ _) ->
                 findAndCreate r (h:def, axiom, rest)
             _ -> findAndCreate r (def, axiom, h:rest)

         -- append single subClassOf axioms from an derective of ontology
         appendSubClassAxiom :: ClassID -> [Description] -> [Directive]
         appendSubClassAxiom _ [] = []
         appendSubClassAxiom cid (hd:rd) =
             (Ax (SubClassOf (DC cid) hd)):(appendSubClassAxiom cid rd)

         -- check if two disjointClasses axiom are equivalent
         -- (a disjointOf b == b disjointOf a)
         eqClass :: Directive -> Directive -> Bool
         eqClass dj1 dj2 =
              case dj1 of
              Ax (DisjointClasses c1 c2 _) ->
                  case dj2 of
                  Ax (DisjointClasses c3 c4 _) ->
                      if (c1 == c4 && c2 == c3)
                         then True
                         else False
                  _ -> False
              _ -> False

-- | structure analysis bases of ontologyMap from owl parser
structureAna :: FilePath
             -> HetcatsOpts
             -> OntologyMap
             -> IO (Maybe (LIB_NAME, -- filename
                    LibEnv           -- DGraphs for imported modules
                   ))
structureAna file opt ontoMap =
    do
       let (newOntoMap, dg) = buildDevGraph ontoMap
       case analysis opt of
         Structured -> do                   -- only structure analysis
            printMsg $ labNodesDG dg
            putStrLn $ show dg
            return (Just (simpleLibName file,
                          simpleLibEnv file $ reverseGraph dg))
         Skip       -> return $ fail ""     -- Nothing is ambiguous
         _          -> staticAna file opt (newOntoMap, dg)
     where -- output Analyzing messages for structured anaylsis
           printMsg :: [LNode DGNodeLab] -> IO()
           printMsg [] = putStrLn ""
           printMsg ((_, node):rest) =
               do putStrLn ("Analyzing ontology " ++
                            (showName $ dgn_name node))
                  printMsg rest

-- simpleLibEnv and simpleLibName builded two simple lib-entities for
-- showGraph
simpleLibEnv :: FilePath -> DGraph -> LibEnv
simpleLibEnv filename dg =
    Map.singleton (simpleLibName filename) emptyGlobalContext
           { globalEnv = Map.singleton (mkSimpleId "")
                         (SpecEntry ((JustNode nodeSig), [], g_sign, nodeSig))
           , devGraph = dg }
       where nodeSig = NodeSig 0 g_sign
             g_sign = G_sign OWL_DL emptySign 0

simpleLibName :: FilePath -> LIB_NAME
simpleLibName s = Lib_id $ Direct_link ("library_" ++ s) nullRange

-- | static analysis if the HetcatesOpts is not only Structured.
-- | sequence call for nodesStaticAna on the basis of topologically
-- | sort of all nodes
staticAna :: FilePath
          -> HetcatsOpts
          -> (OntologyMap, DGraph)
          -> IO (Maybe (LIB_NAME,     -- filename
                        LibEnv        -- DGraphs for imported modules
                       ))
staticAna file opt (ontoMap, dg) =
    do let topNodes = topsortDG dg
       Result diagnoses res <-
           nodesStaticAna (reverse topNodes) Map.empty ontoMap Map.empty dg []
       case res of
           Just (_, dg', _) -> do
            showDiags opt $ List.nub diagnoses
            let dg'' = insEdgesDG (reverseLinks $ labEdgesDG dg')
                           (delEdgesDG (edgesDG dg') dg')
            -- putStrLn $ show dg''
            return (Just (simpleLibName file,
                          simpleLibEnv file dg''))
           _            -> error "no devGraph..."

-- | a map to save which node has been analysed.
type SignMap = Map.Map Node (Sign, [Named Sentence])

-- | call to static analyse of all nodes
nodesStaticAna :: [Node]            -- ^ topologically sort of graph
               -> SignMap           -- ^ an map of analyzed nodes
               -> OntologyMap       -- ^ an map of parsed ontology
               -> Namespace         -- ^ global namespaces
               -> DGraph            -- ^ current graph
               -> [Diagnosis]       -- ^ diagnosis of result
               -> IO (Result (SignMap, DGraph, Namespace))
                      -- ^ result is tuple of new map of signs and sentences,
                      -- ^ new grpah, and new global namespace map.
nodesStaticAna [] signMap _ ns dg diag =
    return $ Result diag (Just (signMap, dg, ns))
nodesStaticAna (h:r) signMap ontoMap globalNs dg diag = do
    Result digs res <-
        -- Each node must be analyzed with the associated imported nodes.
        -- Those search for imported nodes is by bfs accomplished.
        nodeStaticAna (reverse $ map (matchNode dg) (bfsDG h dg))
                          (emptySign, diag)
                          signMap ontoMap globalNs dg
    case res of
        Just (newSignMap, newDg, newGlobalNs) ->
            nodesStaticAna r newSignMap ontoMap newGlobalNs newDg (diag++digs)
        Prelude.Nothing ->
               -- Warning or Error message
            nodesStaticAna r signMap ontoMap globalNs dg (diag++digs)

-- | call to static analyse of single nodes
nodeStaticAna :: [LNode DGNodeLab]   -- ^ imported nodes of one node
                                     -- ^ (incl. itself)
              -> (Sign, [Diagnosis]) -- ^ here saved incoming sign, diagnoses
              -> SignMap             -- ^ an map of analyzed nodes
              -> OntologyMap         -- ^ an map of parsed ontology
              -> Namespace           -- ^ global namespaces
              -> DGraph              -- ^ current graph
              -> IO (Result (SignMap, DGraph, Namespace))
nodeStaticAna [] _ _ _ _ _ =
    do return initResult           -- remove warning
-- the last node in list is current top node.
nodeStaticAna
    ((n,topNode):[]) (inSig, oldDiags) signMap ontoMap globalNs dg =
  do
    let nn@(nodeName, _, _) = dgn_name topNode
    putStrLn ("Analyzing ontology " ++ (show nodeName))
    case Map.lookup n signMap of
     Just _ ->
        return $ Result oldDiags (Just (signMap, dg, globalNs))
     _   ->
      do
        let ontology@(Ontology mid _ _) = fromJust $
                   Map.lookup (getNameFromNode nn) ontoMap
            Result diag res =
                 -- static analysis of current ontology with all sign of
                 -- imported ontology.
                 basicOWL_DLAnalysis (ontology, inSig, emptyGlobalAnnos)
        case res of
	  Just (_, accSig, sent) ->
            do
	     let (newGlobalNs, tMap) =
                     integrateNamespaces globalNs (namespaceMap accSig)
                 newSent = map (renameNamespace tMap) sent
                 difSig = diffSig accSig inSig
                 newDifSig = renameNamespace tMap difSig
                 newSig  = renameNamespace tMap accSig
                 -- the new node (with sign and sentence) has the sign of
                 -- accumulated sign with imported signs, but the sentences
                 -- is only of current ontology, because all sentences of
                 -- imported ontoloies can be automatically outputed by
                 -- showTheory (see GUI)
                 newLNode =
               	     (n, topNode {dgn_theory =
				  G_theory OWL_DL newSig 0 (toThSens newSent)
				 0})
                 -- by remove of an node all associated edges are also deleted
                 -- so the deges must be saved before remove the node, then
                 -- appended again.
                 -- The out edges (after reverse are inn edges) must
                 -- also with new signature be changed.
		 ledges = (innDG dg n) ++ (map (changeGMorOfEdges newSig) (outDG dg n))
                 newG = insEdgesDG ledges (insNodeDG newLNode (delNodeDG n dg))

 	     return $ Result (oldDiags ++ diag)
	             (Just ((Map.insert n (newDifSig, newSent) signMap),
                            newG, newGlobalNs))
	  _   -> do let actDiag = mkDiag Error
				    ("error by analysing of " ++ (show mid)) ()
                    return $ Result (actDiag:oldDiags) Prelude.Nothing
            -- The GMorphism of edge should also with new Signature be changed,
            -- since with "show theory" the edges also with Sign one links
            -- (see Static.DevGraph.joinG_sentences).
      where changeGMorOfEdges :: Sign -> LEdge DGLinkLab -> LEdge DGLinkLab
            changeGMorOfEdges newSign (n1, n2, edge) =
                let newCMor = idComorphism (Logic OWL_DL)
                    Result _ newGMor = gEmbedComorphism newCMor
                                       (G_sign OWL_DL newSign 0)
                in  (n1, n2, edge {dgl_morphism = fromJust newGMor})

-- The other nodes in list are examined whether they were already analyzed.
-- if yes then signs of it for further analysis are taken out; otherwise they
-- are first analyzed (with complete part tree of this node).
nodeStaticAna ((n, _):r) (inSig, oldDiags) signMap ontoMap globalNs dg
 =
  do
   case Map.lookup n signMap of
     Just (sig, _) ->
        nodeStaticAna r ((integSign sig inSig), oldDiags)
                             signMap ontoMap globalNs dg
     Prelude.Nothing ->
       do
         Result digs' res' <-
                 nodeStaticAna (reverse $ map (matchNode dg) (bfsDG n dg))
                                   (emptySign, [])
                                   signMap ontoMap globalNs dg
         case res' of
          Just (signMap', dg', globalNs') ->
            do
             let (sig', _) = fromJust $ Map.lookup n signMap'
             nodeStaticAna r
                  ((integSign sig' inSig), (oldDiags ++ digs'))
                  signMap' ontoMap globalNs' dg'
          _  -> do error "Error by analysis : nodeStaticAna"
                   nodeStaticAna r (inSig, oldDiags)
                                         signMap ontoMap globalNs dg

-- | build up two sign
integSign :: Sign -> Sign -> Sign
integSign inSig totalSig =
    let (newNamespace, transMap) =
            integrateNamespaces (namespaceMap totalSig) (namespaceMap inSig)
    in  addSign (renameNamespace transMap inSig)
                (totalSig {namespaceMap = newNamespace})

-- | turn edges over
reverseLinks :: [LEdge DGLinkLab] -> [LEdge DGLinkLab]
reverseLinks [] = []
reverseLinks ((source, target, edge):r) =
    (target, source, edge):(reverseLinks r)

-- | turn all edges over of graph
reverseGraph :: DGraph -> DGraph
reverseGraph dg =
    let newLinks = reverseLinks $ labEdgesDG dg
    in insEdgesDG newLinks (delEdgesDG (edgesDG dg) dg)

-- | find a node in DevGraph
matchNode :: DGraph -> Node -> LNode DGNodeLab
matchNode dgraph node =
             let (mcontext, _ ) = matchDG node dgraph
                 (_, _, dgNode, _) = fromJust mcontext
             in (node, dgNode)

