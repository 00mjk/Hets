{- | 
   Module      :  $Header$
   Copyright   :  (c) Maciek Makowski, Warsaw University 2004
   License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

   Maintainer  :  till@tzi.de
   Stability   :  provisional
   Portability :  non-portable (Logic)

   Data types and functions for architectural diagrams.
   Follows the CASL Reference Manual, section III.5.6.
-}

module Static.ArchDiagram 
where

import Logic.Comorphism
import Logic.Logic
import Logic.Grothendieck

import Data.Graph.Inductive.Graph as Graph
import qualified Data.Graph.Inductive.Tree as Tree

import qualified Common.Lib.Map as Map
import Common.Lib.Pretty
import Common.PrettyPrint
import Common.Result
import Common.Id

import Static.DevGraph

-- * Types
-- (as defined for extended static semantics in Chap. III:5.6.1)

data DiagNodeLab = DiagNode { dn_sig :: NodeSig,
			      dn_desc :: String } 
		   deriving Show
emptyDiagNodeLab :: AnyLogic -> DiagNodeLab
emptyDiagNodeLab l = DiagNode { dn_sig = EmptyNode l, dn_desc = "" }

data DiagLinkLab = DiagLink { dl_morphism :: GMorphism }
		   deriving (Eq, Show)

type BasedParUnitSig = (DiagNodeSig, ParUnitSig)

type Diag = Tree.Gr DiagNodeLab DiagLinkLab
emptyDiag :: Diag
emptyDiag = Graph.empty

data DiagNodeSig = Diag_node_sig Node NodeSig
		 | Empty_node AnyLogic
		   deriving Show
emptyDiagNodeSig :: AnyLogic -> DiagNodeSig
emptyDiagNodeSig l = Empty_node l

-- | Return a signature stored within given diagram node sig
getSigFromDiag :: DiagNodeSig -> NodeSig
getSigFromDiag (Diag_node_sig _ ns) = ns
getSigFromDiag (Empty_node l) = EmptyNode l

data BasedUnitSig = Based_unit_sig DiagNodeSig 
		  | Based_par_unit_sig BasedParUnitSig
		    deriving Show

type StBasedUnitCtx = Map.Map SIMPLE_ID BasedUnitSig
emptyStBasedUnitCtx :: StBasedUnitCtx
emptyStBasedUnitCtx = Map.empty

-- Since Ps and Bs in the definition of ExtStUnitCtx have disjoint domains
-- we can merge them into a single mapping represented by StBasedUnitCtx.
type ExtStUnitCtx = (StBasedUnitCtx, Diag)
emptyExtStUnitCtx :: ExtStUnitCtx
emptyExtStUnitCtx = (emptyStBasedUnitCtx, emptyDiag)


-- * Instances

-- PrettyPrint
instance PrettyPrint Diag where
    printText0 ga diag = 
	let gs (n, DiagNode {dn_sig = nsig}) = 
		(n, getSig nsig)
        in ptext "nodes: " 
	   <+> (printText0 ga (map gs (labNodes diag)))
	   <+> ptext "\nedges: "
	   <+> (printText0 ga (edges diag))


-- * Functions

-- | Pretty print the diagram
printDiag :: a -> String -> Diag -> Result a
--printDiag res t diag = warning res (showPretty diag t) nullPos
printDiag res _ _ = do return res

-- | A mapping from extended to basic static unit context
ctx :: ExtStUnitCtx -> StUnitCtx
ctx (buc, _) = 
    let ctx' [] _ = emptyStUnitCtx
	ctx' (id : ids) buc =
	    let uctx = ctx' ids buc
	    in case Map.lookup id buc of
	            Just (Based_unit_sig (Diag_node_sig _ nsig)) 
			-> Map.insert id (Sig nsig) uctx
     		    Just (Based_par_unit_sig ((Diag_node_sig _ nsig), usig)) 
			-> Map.insert id (Imp_unit_sig (nsig, Par_unit_sig usig)) uctx
		    _ -> uctx -- this should never be the case
    in ctx' (Map.keys buc) buc



-- | Insert the edges from given source nodes to given target node
-- into the given diagram. The edges are labelled with inclusions.
insInclusionEdges :: LogicGraph
		  -> Diag          -- ^ the diagram to which the edges should be inserted
		  -> [DiagNodeSig] -- ^ the source nodes
		  -> DiagNodeSig   -- ^ the target node
		  -> Result Diag
-- ^ returns the diagram with edges inserted
insInclusionEdges lgraph diag srcNodes (Diag_node_sig tn tnsig) =
    do let inslink diag dns = do d <- diag
				 case dns of
			            Empty_node _ -> return d
				    Diag_node_sig n nsig -> 
					do incl <- ginclusion lgraph (getSig nsig) (getSig tnsig)
					   return (insEdge (n, tn, DiagLink { dl_morphism = incl }) d)
       diag' <- foldl inslink (return diag) srcNodes
       return diag'


-- | Insert the edges from given source node to given target nodes
-- into the given diagram. The edges are labelled with inclusions.
insInclusionEdgesRev :: LogicGraph
		     -> Diag          -- ^ the diagram to which the edges should be inserted
		     -> DiagNodeSig   -- ^ the source node
		     -> [DiagNodeSig] -- ^ the target nodes
		     -> Result Diag
-- ^ returns the diagram with edges inserted
insInclusionEdgesRev lgraph diag (Diag_node_sig sn snsig) targetNodes =
    do let inslink diag dns = do d <- diag
				 case dns of
			            Empty_node _ -> return d
				    Diag_node_sig n nsig -> 
					do incl <- ginclusion lgraph (getSig snsig) (getSig nsig)
					   return (insEdge (sn, n, DiagLink { dl_morphism = incl }) d)
       diag' <- foldl inslink (return diag) targetNodes
       return diag'


-- | Build a diagram that extends given diagram with a node containing
-- given signature and with edges from given set of nodes to the new node.
-- The new edges are labelled with sigature inclusions.
extendDiagramIncl :: LogicGraph
		  -> Diag          -- ^ the diagram to be extended
		  -> [DiagNodeSig] -- ^ the nodes which should be linked to the new node
		  -> NodeSig       -- ^ the signature with which the new node should be labelled
		  -> String        -- ^ the node description (for diagnostics)
		  -> Result (DiagNodeSig, Diag)
-- ^ returns the new node and the extended diagram
extendDiagramIncl lgraph diag srcNodes newNodeSig desc = 
  do let nodeContents = DiagNode {dn_sig = newNodeSig, dn_desc = desc}
	 node = getNewNode diag
	 diag' = insNode (node, nodeContents) diag
	 newDiagNode = Diag_node_sig node newNodeSig
     diag'' <- insInclusionEdges lgraph diag' srcNodes newDiagNode
     printDiag (newDiagNode, diag'') "extendDiagramIncl" diag''
     return (newDiagNode, diag'') 


-- | Build a diagram that extends given diagram with a node and an
-- edge to that node. The edge is labelled with given signature morphism and
-- the node contains the target of this morphism. Extends the development graph 
-- with given morphis as well.
extendDiagramWithMorphism :: [Pos]         -- ^ the position (for diagnostics)
			  -> LogicGraph
			  -> Diag          -- ^ the diagram to be extended
			  -> DGraph        -- ^ the development graph
			  -> DiagNodeSig   -- ^ the node from which the edge should originate
			  -> GMorphism     -- ^ the morphism with which the new edge should be labelled
			  -> String        -- ^ the node description (for diagnostics)
			  -> DGOrigin      -- ^ the origin of the new node
			  -> Result (DiagNodeSig, Diag, DGraph)
-- ^ returns the new node, the extended diagram and extended development graph
extendDiagramWithMorphism pos _ diag dg (Diag_node_sig n nsig) morph desc orig =
  if (getSig nsig) == (dom Grothendieck morph) then
     do (targetSig, dg') <- extendDGraph dg nsig morph orig
	let nodeContents = DiagNode {dn_sig = targetSig, dn_desc = desc}
	    node = getNewNode diag
 	    diag' = insNode (node, nodeContents) diag
	    diag'' = insEdge (n, node, DiagLink { dl_morphism = morph }) diag'
        printDiag (Diag_node_sig node targetSig, diag'', dg') "extendDiagramWithMorphism" diag''
        return (Diag_node_sig node targetSig, diag'', dg') 
     else do fatal_error ("Internal error: Static.AnalysisArchitecture.extendDiagramWithMorphism: the morphism domain differs from the signature in given source node")
			 pos


-- | Build a diagram that extends given diagram with a node and an
-- edge from that node. The edge is labelled with given signature morphism and
-- the node contains the source of this morphism. Extends the development graph 
-- with given morphis as well.
extendDiagramWithMorphismRev :: [Pos]         -- ^ the position (for diagnostics)
			     -> LogicGraph
			     -> Diag          -- ^ the diagram to be extended
			     -> DGraph        -- ^ the development graph
			     -> DiagNodeSig   -- ^ the node to which the edge should point
			     -> GMorphism     -- ^ the morphism with which the new edge should be labelled
			     -> String        -- ^ the node description (for diagnostics)
			     -> DGOrigin      -- ^ the origin of the new node
			     -> Result (DiagNodeSig, Diag, DGraph)
-- ^ returns the new node, the extended diagram and extended development graph
extendDiagramWithMorphismRev pos _ diag dg (Diag_node_sig n nsig) morph desc orig =
  if (getSig nsig) == (cod Grothendieck morph) then
     do (sourceSig, dg') <- extendDGraphRev dg nsig morph orig
	let nodeContents = DiagNode {dn_sig = sourceSig, dn_desc = desc}
	    node = getNewNode diag
 	    diag' = insNode (node, nodeContents) diag
	    diag'' = insEdge (node, n, DiagLink { dl_morphism = morph }) diag'
        printDiag (Diag_node_sig node sourceSig, diag'', dg') "extendDiagramWithMorphismRev" diag''
        return (Diag_node_sig node sourceSig, diag'', dg') 
     else do fatal_error ("Internal error: Static.AnalysisArchitecture.extendDiagramWithMorphismRev: the morphism codomain differs from the signature in given target node")
			 pos


-- | Build a diagram that extends given diagram with a node containing
-- given signature and with edge from given nodes to the new node.
-- The new edge is labelled with given signature morphism.
extendDiagram :: Diag          -- ^ the diagram to be extended
	      -> DiagNodeSig   -- ^ the node from which morphism originates
	      -> GMorphism     -- ^ the morphism with which new edge should be labelled
	      -> NodeSig       -- ^ the signature with which the new node should be labelled
	      -> String        -- ^ the node description (for diagnostics)
	      -> Result (DiagNodeSig, Diag)
-- ^ returns the new node and the extended diagram
extendDiagram diag (Diag_node_sig n _) edgeMorph newNodeSig desc = 
  do let nodeContents = DiagNode {dn_sig = newNodeSig, dn_desc = desc}
	 node = getNewNode diag
	 diag' = insNode (node, nodeContents) diag
	 diag'' = insEdge (n, node, DiagLink { dl_morphism = edgeMorph }) diag'
	 newDiagNode = Diag_node_sig node newNodeSig
     printDiag (newDiagNode, diag'') "extendDiagram" diag''
     return (newDiagNode, diag'') 


-- | Convert a homogeneous diagram to a simple diagram where
-- all the signatures in nodes and morphism on the edges are 
-- coerced to a common logic.
homogeniseDiagram :: Logic lid sublogics
		           basic_spec sentence symb_items symb_map_items
			   sign morphism symbol raw_symbol proof_tree
		  => lid     -- ^ the target logic to which signatures and morphisms will be coerced
		  -> Diag    -- ^ the diagram to be homogenised
		  -> Result (Tree.Gr sign morphism)
homogeniseDiagram targetLid diag = 
    -- The implementation relies on the representation of graph nodes as
    -- integers. We can therefore just obtain a list of all the labelled nodes
    -- from diag, convert all the nodes and insert them to a new diagram; then
    -- copy all the edges from the original to new diagram (coercing the morphisms).
    do let convertNode (n, DiagNode { dn_sig = NodeSig (_, G_sign srcLid sig) }) =
	       do sig' <- rcoerce targetLid srcLid nullPos sig
		  return (n, sig')
           convertEdge (n1, n2, DiagLink { dl_morphism = GMorphism cid _ mor }) =
	       let srcLid = sourceLogic cid
	       in if isIdComorphism (Comorphism cid) then
		     do mor' <- rcoerce targetLid srcLid nullPos mor
			return (n1, n2, mor')
		     else do fatal_error "Trying to coerce a morphism between different logics. Heterogeneous specifications are not fully supported yet."
					 nullPos
	   convertNodes cDiag [] = do return cDiag
	   convertNodes cDiag (lNode : lNodes) =
	       do convNode <- convertNode lNode
		  let cDiag' = insNode convNode cDiag
		  convertNodes cDiag' lNodes
	   convertEdges cDiag [] = do return cDiag
	   convertEdges cDiag (lEdge : lEdges) = 
	       do convEdge <- convertEdge lEdge
		  let cDiag' = insEdge convEdge cDiag
		  convertEdges cDiag' lEdges
	   nodes = labNodes diag
	   edges = labEdges diag
       -- insert converted nodes to an empty diagram
       cDiag <- convertNodes Graph.empty nodes
       -- insert converted edges to the diagram containing only nodes
       cDiag' <- convertEdges cDiag edges
       return cDiag'


-- | Coerce GMorphisms in the list of (diagram node, GMorphism) pairs
-- to morphisms in given logic
homogeniseSink :: Logic lid sublogics
		         basic_spec sentence symb_items symb_map_items
			 sign morphism symbol raw_symbol proof_tree
		=> lid                 -- ^ the target logic to which morphisms will be coerced
		-> [(Node, GMorphism)] -- ^ the list of edges to be homogenised
		-> Result [(Node, morphism)]
homogeniseSink targetLid edges =
    -- See homogeniseDiagram for comments on implementation.
    do let convertMorphism (n, GMorphism cid _ mor) =
	       let srcLid = sourceLogic cid
	       in if isIdComorphism (Comorphism cid) then
		     do mor' <- rcoerce targetLid srcLid nullPos mor
			return (n, mor')
		     else do fatal_error "Trying to coerce a morphism between different logics. Heterogeneous specifications are not fully supported yet."
					 nullPos
	   convEdges [] = do return []
	   convEdges (e : es) = do ce <- convertMorphism e
				   ces <- convEdges es
				   return (ce : ces)
       convEdges edges


-- | Create a graph containing descriptions of nodes and edges.
diagDesc :: Diag 
	 -> Tree.Gr String String
diagDesc diag =
    let insNodeDesc g (n, DiagNode { dn_desc = desc }) =
	    if desc == "" then g else insNode (n, desc) g
    in foldl insNodeDesc Graph.empty (labNodes diag)


-- | Create a sink consisting of incusion morphisms between
-- signatures from given set of nodes and given signature.
inclusionSink :: LogicGraph
	      -> [DiagNodeSig] -- ^ the source nodes
	      -> NodeSig       -- ^ the target signature
	      -> Result [(Node, GMorphism)]
-- ^ returns the diagram with edges inserted
inclusionSink lgraph srcNodes tnsig =
    do let insmorph ls dns = do l <- ls
			        case dns of
			            Empty_node _ -> return l
				    Diag_node_sig n nsig -> 
					do incl <- ginclusion lgraph (getSig nsig) (getSig tnsig)
					   return ((n, incl): l)
       sink <- foldl insmorph (return []) srcNodes
       return sink
