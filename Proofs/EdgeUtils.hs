{- |
Module      :  $Header$
Description :  utility functions for edges of development graphs
Copyright   :  (c) Jorina F. Gerken, Till Mossakowski, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  ken@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable(Logic)

utility functions for edges of development graphs
-}

module Proofs.EdgeUtils where

import Logic.Grothendieck
import Static.DevGraph
import Static.DGToSpec
import qualified Common.Lib.Rel as Rel
import qualified Common.Lib.Graph as Tree
import Data.Graph.Inductive.Graph
import Data.Graph.Inductive.Basic (elfilter)
import Data.List
import qualified Data.Set as Set
import qualified Data.Map as Map
import Control.Exception (assert)

{- | change the given DGraph with the given DGChange.
     To notice that, before inserting an edge, the edge ID will be given by
     calling initEdgeId if necessary.
-}
changeDG :: DGraph -> DGChange -> DGraph
changeDG g c = case c of
    InsertNode n -> insLNodeDG n g
    DeleteNode n -> delLNodeDG n g
    InsertEdge e -> insLEdgeDG (initEdgeId e g) g
    DeleteEdge e -> delLEdgeDG e g
    SetNodeLab _ n -> fst $ labelNodeDG n g

{- | initialize the edge id before it's inserted, but if it already contains
     valid id, then do nothing -}
initEdgeId :: LEdge DGLinkLab -> DGraph -> LEdge DGLinkLab
initEdgeId (src, tgt, linklab) g = (src, tgt,
  if dgl_id linklab < startEdgeId
     then linklab { dgl_id = getNewEdgeId g } else linklab)

{- | change the given DGraph with a list of DGChange
-}
changesDG :: DGraph -> [DGChange] -> DGraph
changesDG = foldl' changeDG

{- | change the given DGraph with given DGChange and return a new DGraph and
     the processed DGChange as well.
-}
updateDGAndChange :: DGraph -> DGChange -> (DGraph, DGChange)
updateDGAndChange g c = case c of
    InsertNode n -> (insLNodeDG n g, InsertNode n)
    DeleteNode n -> (delLNodeDG n g, DeleteNode n)
    InsertEdge e -> let newEdge = initEdgeId e g in
                    (insLEdgeDG newEdge g, InsertEdge newEdge)
    DeleteEdge e -> (delLEdgeDG e g, DeleteEdge e)
    SetNodeLab _ n -> let (newG, o) = labelNodeDG n g in (newG, SetNodeLab o n)

{- | change the given DGraph with a list of DGChange, but the processed
DGChanges are kept and in a reverted way for the history element.
-}
updateDGAndChanges :: DGraph -> [DGChange] -> (DGraph, [DGChange])
updateDGAndChanges g [] = (g, [])
updateDGAndChanges g (x : xs) = (auxGraph, newChange : auxChanges)
        where
        (newGraph, newChange) = updateDGAndChange g x
        (auxGraph, auxChanges) = updateDGAndChanges newGraph xs

{- | apply the proof history to the given DGraph to make it go back to
     previous one.
-}
applyProofHistory :: ProofHistory  -> DGraph -> DGraph
applyProofHistory h c =
  setProofHistoryDG h $ changesDG c $ concatMap snd $ reverse h

-- -------------------------------------
-- methods to check the type of an edge
-- -------------------------------------

isProven :: DGLinkType -> Bool
isProven edge = case edge of
    GlobalDef -> True
    LocalDef  -> True
    _ -> case thmLinkStatus edge of
           Just (Proven _ _) -> True
           _ -> False

isDefEdge :: DGLinkType -> Bool
isDefEdge edge = case edge of
    GlobalDef -> True
    LocalDef  -> True
    HidingDef -> True
    _ -> False

isGlobalEdge :: DGLinkType -> Bool
isGlobalEdge edge = case edge of
    GlobalDef -> True
    GlobalThm _ _ _ -> True
    _ -> False

isLocalEdge :: DGLinkType -> Bool
isLocalEdge edge = case edge of
    LocalDef  -> True
    LocalThm _ _ _ -> True
    _ -> False

isGlobalThm :: DGLinkType -> Bool
isGlobalThm edge = case edge of
    GlobalThm _ _ _ -> True
    _ -> False

isLocalThm :: DGLinkType -> Bool
isLocalThm edge = case edge of
    LocalThm _ _ _ -> True
    _ -> False

isUnprovenGlobalThm :: DGLinkType -> Bool
isUnprovenGlobalThm lt = case lt of
    GlobalThm LeftOpen _ _ -> True
    _ -> False

isUnprovenLocalThm :: DGLinkType -> Bool
isUnprovenLocalThm lt = case lt of
    LocalThm LeftOpen _ _ -> True
    _ -> False

isHidingEdge :: DGLinkType -> Bool
isHidingEdge edge = case edge of
    HidingDef -> True
    HidingThm _ _ -> True
    _ -> False

isHidingDef :: DGLinkType -> Bool
isHidingDef lt = case lt of
    HidingDef -> True
    _ -> False

isHidingThm :: DGLinkType -> Bool
isHidingThm edge = case edge of
    HidingThm _ _ -> True
    _ -> False

isUnprovenHidingThm :: DGLinkType -> Bool
isUnprovenHidingThm lt = case lt of
    HidingThm _ LeftOpen -> True
    _ -> False

-- ----------------------------------------------------------------------------
-- other methods on edges
-- ----------------------------------------------------------------------------

eqLEdge :: (DGLinkLab -> DGLinkLab -> Bool) -> LEdge DGLinkLab
          -> LEdge DGLinkLab -> Bool
eqLEdge f (v, w, l) (v2, w2, l2) = v == v2 && w == w2 && f l l2

noPath :: LEdge DGLinkLab -> [LEdge DGLinkLab] -> Bool
noPath e l = case l of
    [e2] -> not $ eqLEdge eqDGLinkLabById e e2
    _ -> True

{- | try to get the given edge from the given DGraph or the given list of
     DGChange to advoid dupplicate inserting of an edge
-}
tryToGetEdge :: LEdge DGLinkLab -> DGraph -> [DGChange]
             -> Maybe (LEdge DGLinkLab)
tryToGetEdge ledge dgraph changes =
    case find (eqLEdge eqDGLinkLabContent ledge) $ getInsertedEdges changes of
      Nothing -> find (eqLEdge eqDGLinkLabContent ledge) $ labEdgesDG dgraph
      e -> e

{- | try to insert an edge into the given dgraph, if the edge exists, the to
be inserted edge's id would be added into the existing edge.-}
insertDGLEdge :: LEdge DGLinkLab -- ^ the to be inserted edge
              -> DGraph -> [DGChange] -> (DGraph, [DGChange])
insertDGLEdge edge dgraph changes =
  case tryToGetEdge edge dgraph changes of
    Nothing -> updateWithChanges [InsertEdge edge] dgraph changes
    Just e@(src, tgt, label) -> let eid = getEdgeId edge in
        if eid == defaultEdgeId
        then (dgraph, changes)
        else let nid = assert (dgl_id label == eid) eid
                 newEdge = (src, tgt,
                   label { dgl_id = nid })
             in
             updateWithChanges [DeleteEdge e, InsertEdge newEdge]
                  dgraph changes

{- | get the edge id out of a given edge -}
getEdgeId :: LEdge DGLinkLab -> EdgeId
getEdgeId (_, _, label) = dgl_id label

-- ----------------------------------------------
-- methods that calculate paths of certain types
-- ----------------------------------------------

getAllPathsOfTypeFromGoalList :: DGraph -> (DGLinkType -> Bool)
                              -> [LEdge DGLinkLab] -> [[LEdge DGLinkLab]]
getAllPathsOfTypeFromGoalList dgraph isType ls = concat
    [concat (map (getAllPathsOfTypeBetween dgraph isType source) targets) |
     source <- sources]
    where
      sources = Set.toList $ Set.fromList $ map (\ (s, _, _) -> s) ls
      targets = Set.toList $ Set.fromList $ map (\ (_, t, _) -> t) ls

{- | returns all paths consisting of edges of the given type in the given
   development graph-}
getAllPathsOfType :: DGraph -> (DGLinkType -> Bool) -> [[LEdge DGLinkLab]]
getAllPathsOfType dgraph isType = getAllPathsOfTypeFromGoalList dgraph isType
           $ filter (liftE isType) (labEdgesDG dgraph)

{- | returns a list of all proven global paths of the given morphism between
   the given source and target node -}
getAllGlobPathsOfMorphismBetween :: DGraph -> GMorphism -> Node -> Node
                                 -> [[LEdge DGLinkLab]]
getAllGlobPathsOfMorphismBetween dgraph morphism src tgt =
  filterPathsByMorphism morphism $ getAllGlobPathsBetween dgraph src tgt

{- | returns all paths from the given list whose morphism is equal to the
   given one -}
filterPathsByMorphism :: GMorphism -> [[LEdge DGLinkLab]]
                      -> [[LEdge DGLinkLab]]
filterPathsByMorphism morphism paths =
  [path | path <- paths, calculateMorphismOfPath path == Just morphism]

{- | returns all paths consisting of global edges only
   or of one local edge followed by any number of global edges -}
getAllLocGlobPathsBetween :: DGraph -> Node -> Node -> [[LEdge DGLinkLab]]
getAllLocGlobPathsBetween dgraph src tgt =
  locGlobPaths ++ globPaths
  where
    outEdges = outDG dgraph src
    locEdges = [(edge, target)
               | edge@(_,target,_) <- filter (liftE isLocalEdge) outEdges]
    locGlobPaths = concat
                   [map ([edge] ++)
                   $ getAllGlobPathsBetween dgraph node tgt
                    | (edge, node) <- locEdges]
    globPaths = getAllGlobPathsBetween dgraph src tgt

{- | returns all paths of globalDef edges or globalThm edges
   between the given source and target node -}
getAllGlobPathsBetween :: DGraph -> Node -> Node -> [[LEdge DGLinkLab]]
getAllGlobPathsBetween dgraph src tgt =
  getAllPathsOfTypeBetween dgraph isGlobalEdge src tgt

{- | returns all cyclic paths consisting of edges of the given type between the
   given two nodes -}
getAllPathsOfTypeBetween :: DGraph -> (DGLinkType -> Bool) -> Node
                         -> Node -> [[LEdge DGLinkLab]]
getAllPathsOfTypeBetween dgraph isType src tgt =
    Tree.getPathsTo [] src tgt
    $ Tree.rmIsolated -- make the graph as small as possible
    $ elfilter (isType . dgl_type)
    $ dgBody dgraph

-- | return all non-cyclic paths starting from the given node
getAllPathsOfTypeFrom :: DGraph -> Node -> [[LEdge DGLinkLab]]
getAllPathsOfTypeFrom dgraph src =
   map reverse $ Tree.getPaths [] src $ dgBody dgraph

-- --------------------------------------------------------------
-- methods to determine the inserted edges in the given dgchange
-- --------------------------------------------------------------

{- | returns all insertions of edges from the given list of changes -}
getInsertedEdges :: [DGChange] -> [LEdge DGLinkLab]
getInsertedEdges [] = []
getInsertedEdges (change : list) = (case change of
    InsertEdge edge -> (edge :)
    _ -> id) $ getInsertedEdges list

-- ----------------------------------------
-- methods to check and select proof basis
-- ----------------------------------------

checkEdgeIds :: DGraph -> Maybe [EdgeId]
checkEdgeIds dg =
    let pBl = map (\ (_, _, l) -> dgl_id l) $ labEdges $ dgBody dg
        pBs = Set.fromList pBl
        pBl2 = Set.toList pBs
    in case pBl \\ pBl2 of
         [] -> if Set.member defaultEdgeId pBs
               then Just [defaultEdgeId] else Nothing
         l -> Just l

{- | determines all proven paths in the given list and tries to select a
   proof basis from these (s. selectProofBasisAux);
   if this fails the same is done for the rest of the given paths, i.e.
   for the unproven ones -}
selectProofBasis :: DGraph -> LEdge DGLinkLab -> [[LEdge DGLinkLab]]
                 -> ProofBasis
selectProofBasis dg ledge paths = let
  (provenPaths, unprovenPaths) = partition (all $ liftE isProven) paths
  pBl = map (\ (_, _, l) ->
               (dgl_id l, proofBasis $ tryToGetProofBasis l))
              $ labEdges $ dgBody dg
  rel = assert (checkEdgeIds dg == Nothing &&
                all (\ (e, pB) -> not (Set.member e pB)) pBl) $
        Rel.toMap $ Rel.transClosure $ Rel.fromDistinctMap
        $ Map.fromList $ filter (not . Set.null . snd) pBl
  in selectProofBasisAux rel ledge $ provenPaths ++ unprovenPaths

{- | selects the first path that does not form a proof cycle with the given
 label (if such a path exits) and returns the labels of its edges -}
selectProofBasisAux :: Map.Map EdgeId (Set.Set EdgeId) -> LEdge DGLinkLab
                    -> [[LEdge DGLinkLab]] -> ProofBasis
selectProofBasisAux _ _ [] = emptyProofBasis
selectProofBasisAux rel ledge (path : list) =
    if roughElem ledge b then selectProofBasisAux rel ledge list
       else b {- OK, no cyclic proof -}
    where b = calculateProofBasis rel path

{- | calculates the proofBasis of the given path,
 i.e. (recursively) close the list of DGLinkLabs under the relation
 'is proved using'. If a DGLinkLab has proof status LeftOpen,
 look up in the development graph for its current status -}
calculateProofBasis :: Map.Map EdgeId (Set.Set EdgeId) -> [LEdge DGLinkLab]
                    -> ProofBasis
calculateProofBasis rel = ProofBasis . foldr
    (\ (_, _, l) -> let eid = dgl_id l in Set.insert eid
     . Set.union (Map.findWithDefault Set.empty eid rel))
    Set.empty

{- | return the proof basis if the given linklab is a proven edge,
     otherwise Nothing. -}
tryToGetProofBasis :: DGLinkLab -> ProofBasis
tryToGetProofBasis label = case dgl_type label of
    GlobalThm (Proven _ pB) _ _ -> pB
    LocalThm (Proven _ pB) _ _ -> pB
    HidingThm _ (Proven _ pB) -> pB
    _ -> emptyProofBasis

invalidateProof :: DGLinkType -> DGLinkType
invalidateProof t = case t of
    GlobalThm _ c _ -> GlobalThm LeftOpen c LeftOpen
    LocalThm _ c _ -> LocalThm LeftOpen c LeftOpen
    HidingThm m _ -> HidingThm m LeftOpen
    FreeThm m _ -> FreeThm m LeftOpen
    _ -> t

{- | adopts the edges of the old node to the new node -}
adoptEdges :: DGraph -> Node -> Node -> (DGraph, [DGChange])
adoptEdges dgraph oldNode newNode =
  if oldNode == newNode then (dgraph, []) else
  let (inEdges', _, _, outEdges') = safeContextDG "adoptEdges" dgraph oldNode
      inEdges = map ( \ (l, v) -> (v, oldNode, l)) inEdges'
      outEdges = map ( \ (l, v) -> (oldNode, v, l)) outEdges'
      newIn = map (adoptEdgesAux newNode True) inEdges
      newOut = map (adoptEdgesAux newNode False) outEdges
      allChanges = map DeleteEdge (inEdges ++ outEdges)
                   ++ map InsertEdge (newIn ++ newOut)
  in (changesDG dgraph allChanges, allChanges)

{- | auxiliary method for adoptEdges -}
adoptEdgesAux :: Node -> Bool -> LEdge DGLinkLab -> LEdge DGLinkLab
adoptEdgesAux node areIngoingEdges (src,tgt,edgelab) =
  let (newSrc, newTgt) = if src == tgt then (node, node) else (src, tgt)
  in if areIngoingEdges then (newSrc, node, edgelab)
     else (node, newTgt, edgelab)

{- | adjusts a node whose label is changed -}
adjustNode :: DGraph -> LNode DGNodeLab -> (DGraph, [DGChange])
adjustNode dgraph newNode =
  updateWithOneChange (SetNodeLab (error "adjustNode") newNode) dgraph []

getAllOpenNodeGoals :: [DGNodeLab] -> [DGNodeLab]
getAllOpenNodeGoals = filter hasOpenGoals

------------------------
-- debug functions
------------------------
{- | similar to a show function of an ledge but only prints the
     necessary parts out. -}
trace_edge :: LEdge DGLinkLab -> String
trace_edge (src, tgt, label) =
    " (" ++ show src ++ "->" ++ show tgt
    ++ " of id " ++ show (dgl_id label)
    ++ " with prove status: "
    ++ trace_edge_status label ++ ") ->"

-- | return a string describing the given path consisting of a list of ledge.
trace_path :: [LEdge DGLinkLab] -> String
trace_path = concat . map trace_edge

{- | return a string containing a simple telling of the status of the
     given linklab. -}
trace_edge_status :: DGLinkLab -> String
trace_edge_status label = case dgl_type label of
    GlobalThm (Proven _ _) _ _ -> "global proven"
    LocalThm (Proven _ _) _ _ -> "local proven"
    HidingThm _ (Proven _ _) -> "hiding proven"
    LocalThm LeftOpen _ _ -> "local unproven"
    GlobalThm LeftOpen _ _ -> "global unproven"
    GlobalDef -> "global def"
    LocalDef  -> "local def"
    HidingDef -> "hiding def"
    _ -> "other unproven or proven"

-- | show the given list of paths.
trace_paths :: [[LEdge DGLinkLab]] -> String
trace_paths =
  unlines . zipWith ( \ n x -> show n ++ trace_path x) [1 :: Int ..]

{- | update both the given devgraph and the changelist with a given change -}
updateWithOneChange :: DGChange -> DGraph -> [DGChange] -> (DGraph, [DGChange])
updateWithOneChange change dgraph changeList =
    (newGraph, newChange : changeList)
        where
          (newGraph, newChange) = updateDGAndChange dgraph change

{- | update both the given devgraph and the changelist with a list of
given changes -}
updateWithChanges :: [DGChange] -> DGraph -> [DGChange] -> (DGraph, [DGChange])
updateWithChanges changes dgraph changeList =
    (newGraph, newChanges ++ changeList)
        where
          (newGraph, newChanges) = updateDGAndChanges dgraph changes

{- | check in the given dgraph if the given node has incoming hiding edges -}
hasIncomingHidingEdge :: DGraph -> Node -> Bool
hasIncomingHidingEdge dgraph node =
    any ( \ (_, tgt, _) -> node == tgt)
      $ filter (liftE isHidingEdge) $ labEdgesDG dgraph

{- | return a warning text if the given node has incoming hiding edge,
     otherwise just an empty string. -}
addHasInHidingWarning :: DGraph -> Node -> String
addHasInHidingWarning dgraph n
     | hasIncomingHidingEdge dgraph n =
           "< Warning: this node has incoming hiding links ! >\n"
     | otherwise = ""

-- | return src node of the given edge.
getLEdgeSrc :: LEdge b -> Node
getLEdgeSrc (n, _, _) = n
