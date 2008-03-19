{- |
Module      :  $Header$
Description :  heterogeneous signatures colimits approximations
Copyright   :  (c) Mihai Codescu, and Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  :  mcodescu@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable

Heterogeneous version of weakly_amalgamable_cocones.
Needs some improvements (see TO DO).

-}

module Static.WACocone(GDiagram,
                       isHomogeneousGDiagram,
                       homogeniseGDiagram,
                       isConnected,
                       isAcyclic,
                       removeIdentities,
                       hetWeakAmalgCocone,
                       initDescList,
                       buildStrMorphisms
                       ) where

import Data.Graph.Inductive.Graph as Graph
import Data.List(nub)
import Common.Lib.Graph
import Common.Result
import Logic.Logic
import Logic.Comorphism
import Logic.Modification
import Logic.Grothendieck
import Logic.Coerce
import Static.GTheory
import Common.ExtSign
import qualified Data.Map as Map
import qualified Data.Set as Set
import Control.Monad
import Common.LogicT
import Comorphisms.LogicGraph

-- | Grothendieck diagrams
type GDiagram = Gr G_theory (Int, GMorphism)

-- | checks whether a connected GDiagram is homogeneous

isHomogeneousGDiagram :: GDiagram -> Bool
isHomogeneousGDiagram diag = foldl (&&) True $ map isHomogeneous $
                             map (\(_,_,(_,phi)) -> phi) $ labEdges diag

-- | homogenise a GDiagram to a targeted logic

homogeniseGDiagram :: Logic lid sublogics
                           basic_spec sentence symb_items symb_map_items
                           sign morphism symbol raw_symbol proof_tree
                  => lid     -- ^ the target logic to be coerced to
                  -> GDiagram    -- ^ the GDiagram to be homogenised
                  -> Result (Gr sign (Int,morphism))

homogeniseGDiagram targetLid diag =  do
  let convertNode (n, gth) = do
       G_sign srcLid extSig _ <- return $ signOf gth
       extSig' <- coerceSign srcLid targetLid "" extSig
       return (n, plainSign extSig')
      convertEdge (n1, n2, (nr,GMorphism cid _ _ mor _ ))
        = if isIdComorphism (Comorphism cid) then
            do mor' <- coerceMorphism (targetLogic cid) targetLid "" mor
               return (n1, n2, (nr,mor'))
          else fail $
               "Trying to coerce a morphism between different logics.\n" ++
               "Heterogeneous specifications are not fully supported yet."
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
      dNodes = labNodes diag
      dEdges = labEdges  diag
       -- insert converted nodes to an empty diagram
  cDiag <- convertNodes Graph.empty dNodes
       -- insert converted edges to the diagram containing only nodes
  cDiag' <- convertEdges cDiag dEdges
  return cDiag'

-- | checks whether a graph is connected

isConnected :: Gr a b -> Bool
isConnected graph = let
  nodeList = nodes graph
  root = head nodeList
  availNodes = Map.fromList $ zip nodeList (repeat True)
  bfs queue avail = case queue of
     [] -> avail
     n:ns -> let
       avail1 = Map.insert n False avail
       nbs = filter ((Map.!) avail) $ neighbors graph n
      in bfs (ns++nbs) avail1
  in filter ((Map.!) (bfs [root] availNodes)) nodeList == []

-- | checks whether a graph is acyclic

isAcyclic :: (Eq b) => Gr a b -> Bool
isAcyclic graph = let
  filterIns gr = filter (\ x -> indeg gr x == 0)
  queue = filterIns graph $ nodes graph
  topologicalSort q gr = case q of
   [] -> null $ edges gr
   n : ns -> let
     oEdges = lsuc gr n
     graph1 = foldl (flip Graph.delLEdge) gr
              $ map (\ (y, label) -> (n, y, label)) oEdges
     succs = filterIns graph1 $ suc gr n
    in topologicalSort (ns ++ succs) graph1
 in topologicalSort queue graph

-- | auxiliary for removing the identity edges from a graph

removeIdentities :: Gr a b -> Gr a b
removeIdentities graph = let
 addEdges gr eList = case eList of
   [] -> gr
   (sn, tn, label):eList1 -> if sn == tn then addEdges gr eList1
                             else addEdges (insEdge (sn, tn, label) gr) eList1
 in (addEdges $ insNodes (labNodes graph) Graph.empty)
        $ labEdges graph

--  assigns to a node all proper descendants
initDescList :: Gr a b -> Map.Map Node [(Node, a)]
initDescList graph =  let
 isProperDescOf gr n x = let
   existsPath diag snode nlist = if snode `elem` nlist then True
                                 else let
      nlist1 = foldl (++) [] $ map (pre diag) nlist
        in if nlist1 == [] then False
           else existsPath diag snode nlist1
     in  if n == x then False
         else existsPath gr x [n]
 descsOf n = filter (\(x,_) -> isProperDescOf graph n x)$ labNodes graph
 in Map.fromList$ map (\node -> (node, descsOf node)) $ nodes graph

commonBounds :: (Eq a) => Map.Map Node [(Node, a)] -> Node -> Node -> [(Node,a)]
commonBounds funDesc n1  n2 = filter
  (\x -> x `elem` ((Map.!) funDesc n1) && x `elem` ((Map.!) funDesc n2) )
  $ nub $ (Map.!) funDesc n1 ++ (Map.!) funDesc n2

--  returns the greatest lower bound of two maximal nodes,if it exists
glb :: (Eq a) =>  Map.Map Node [(Node, a)] -> Node -> Node -> Maybe (Node,a)
glb funDesc n1 n2 = let
 cDescs = commonBounds funDesc n1 n2
 subList [] _ = True
 subList (x:xs) l2 = x `elem` l2 && subList xs l2
 glbList = filter (\(n, x) -> subList
    (filter (\(n0,x0) -> (n,x)/= (n0,x0)) cDescs) (funDesc Map.! n)
           ) cDescs
    -- a node n is glb of n1 and n2 iff
    -- all common bounds of n1 and n2 are also descendants of n
  in case glbList of
     [] -> Nothing
     x:_ -> Just x -- because if it exists, there can be only one

-- if no greatest lower bound exists, compute all maximal bounds of the nodes
maxBounds :: (Eq a) => Map.Map Node [(Node, a)] -> Node -> Node -> [(Node, a)]
maxBounds funDesc n1 n2 = let
  cDescs = commonBounds funDesc n1 n2
  isDesc n0 (n,y) = (n,y) `elem` funDesc Map.! n0
  noDescs (n,y) = filter (\(n0, _) -> isDesc n0 (n,y)) cDescs == []
 in filter noDescs cDescs

--  dijsktra algorithm for finding the the shortest path between two nodes
dijkstra :: GDiagram -> Node -> Node -> Result GMorphism
dijkstra graph source target = let
  dist = Map.insert source 0 $ Map.fromList $
         zip (nodes graph) $ repeat $  2 * (length $ edges graph)
  prev = Map.empty
  q = nodes graph
  com = case lab graph source of
    Nothing -> Map.empty --shouldnt be the case
    Just gt -> Map.insert source (ide $ signOf gt) Map.empty
  (nodeList, com1) = mainloop graph source target q dist prev com
  extractMin queue dMap = let
   u =  head $
     filter (\x -> (Map.!) dMap x == (minimum $ map ((Map.!)dMap) queue)) queue
   in ( Set.toList $ Set.difference (Set.fromList queue) (Set.fromList [u]) , u)
  updateNeighbors d p c u gr = let
    outEdges = out gr u
    upNeighbor dMap pMap cMap uNode edgeList = case edgeList of
     [] -> (dMap, pMap, cMap)
     (_, v, (_, gmor)):edgeL  ->  let
       alt = (Map.!) dMap uNode + 1
      in if (alt >= (Map.!) dMap v) then upNeighbor dMap pMap cMap uNode edgeL
        else let
      d1 = Map.insert v alt dMap
      p1 = Map.insert v uNode pMap
      c1 = Map.insert v gmor cMap
      in upNeighbor d1 p1 c1 uNode edgeL
   in upNeighbor d p c u outEdges
  -- for each neighbor of u, if d(u)+1 < d(v), modify p(v) = u, d(v) = d(u)+1
  mainloop gr sn tn qL d p c = let
   (q1, u) = extractMin qL d
   (d1, p1, c1) = updateNeighbors d p c u gr
   in if (u == tn) then shortPath gr sn p1 c [] tn
     else mainloop gr sn tn q1 d1 p1 c1
  shortPath gr sn p1 c s u  = if (Map.!) p1 u == sn then (u:s, c)
                               else shortPath gr sn p1 c (u:s)  $(Map.!) p1 u
 in foldM comp ((Map.!) com1 source) $ map ((Map.!)com1) nodeList

--  builds the arrows from the nodes of the original graph
--  to the unique maximal node of the obtained graph
-- TO DO:different cases if the new graph is the same as the old one
-- (i.e. a graph with a single maximal node)?

buildStrMorphisms ::  GDiagram -> GDiagram
                    ->Result (G_theory, Map.Map Node GMorphism)
buildStrMorphisms initGraph newGraph = do
 let (maxNode, sigma) = head $ filter (\(node,_) -> outdeg newGraph node == 0) $
                        labNodes newGraph
     buildMor pairList solList = do
      case pairList of
       (n, _):pairs -> do  nMor <- dijkstra newGraph n maxNode
                           buildMor pairs (solList ++ [(n,nMor)])
       [] -> return solList
 morList <- buildMor (labNodes initGraph) []
 return $ (sigma, Map.fromList morList)

--  computes the colimit and inserts it into the graph
addNodeToGraph :: GDiagram -> G_theory -> G_theory -> G_theory -> Int -> Int
               -> Int -> GMorphism -> GMorphism
               -> Map.Map Node [(Node, G_theory)] -> [(Int, G_theory)]
               -> Result (GDiagram, Map.Map Node [(Node, G_theory)])
addNodeToGraph oldGraph
               (G_theory lid extSign _ _ _)
               gt1@(G_theory lid1 extSign1 idx1 _ _)
               gt2@(G_theory lid2 extSign2 idx2 _ _)
               n
               n1
               n2
               (GMorphism cid1 _  _ mor1 _)
               (GMorphism cid2 _  _ mor2 _)
               funDesc maxNodes = do
 let newNode = 1 + (maximum $ nodes oldGraph) --get a new node
 s1 <- coerceSign lid1 lid "addToNodeGraph" extSign1
 s2 <- coerceSign lid2 lid "addToNodeGraph" extSign2
 m1 <- coerceMorphism (targetLogic cid1) lid "addToNodeGraph" mor1
 m2 <- coerceMorphism (targetLogic cid2) lid "addToNodeGraph" mor2
 let spanGr = Graph.mkGraph
       [(n, plainSign extSign), (n1, plainSign s1), (n2, plainSign s2)]
       [(n, n1, (1, m1)), (n, n2, (1, m2))]
 (s, morMap) <- weakly_amalgamable_colimit lid spanGr
 let gtheory = noSensGTheory lid (mkExtSign s) startSigId
      -- must  coerce here
 m11 <- coerceMorphism lid (targetLogic cid1) "addToNodeGraph" $
        morMap Map.! n1
 m22 <- coerceMorphism lid (targetLogic cid2) "addToNodeGraph" $
        morMap Map.! n2
 s11 <- coerceSign lid (sourceLogic cid1) "addToNodeGraph" s1
 s22 <- coerceSign lid (sourceLogic cid2) "addToNodeGraph" s2
 let gmor1 = GMorphism cid1 s11 idx1 m11 startMorId
 let gmor2 = GMorphism cid2 s22 idx2 m22 startMorId
 case maxNodes of
  [] -> do
   let newGraph = insEdges [(n1, newNode,(1, gmor1)),(n2, newNode,(1,gmor2))] $
                  insNode (newNode, gtheory) oldGraph
       funDesc1 = Map.insert newNode
                  (nub $ (Map.!)funDesc n1 ++ (Map.!) funDesc n2 ) funDesc
   return (newGraph, funDesc1)
  _ -> computeCoeqs oldGraph funDesc (n1, gt1) (n2, gt2)
                           (newNode, gtheory) gmor1 gmor2 maxNodes

--  for each node in the list, check whether the coequalizer can be computed
--  if so, modify the maximal node of graph and the edges to it from n1 and n2
computeCoeqs :: GDiagram -> Map.Map Node [(Node, G_theory)]
                   ->  (Node,G_theory) -> (Node,G_theory) -> (Node, G_theory)
                   ->  GMorphism -> GMorphism -> [(Node, G_theory)]->
                       Result (GDiagram, Map.Map Node [(Node, G_theory)])
computeCoeqs oldGraph funDesc (n1,_) (n2,_) (newN, newGt) gmor1 gmor2 [] = do
 let newGraph = insEdges [(n1, newN, (1, gmor1)),(n2, newN, (1, gmor2))] $
                insNode (newN, newGt) oldGraph
     descFun1 = Map.insert newN
                (nub $ (Map.!)funDesc n1 ++ (Map.!) funDesc n2 ) funDesc
 return $ (newGraph, descFun1)
computeCoeqs graph funDesc (n1,gt1) (n2,gt2)
                    (newN, _newGt@(G_theory tlid tsign _ _ _))
                    _gmor1@(GMorphism cid1 sig1 idx1 mor1 _ )
                    _gmor2@(GMorphism cid2 sig2 idx2 mor2 _ ) ((n,gt):descs)= do
 _rho1@(GMorphism cid3 _ _ mor3 _)<- dijkstra graph n n1
 _rho2@(GMorphism cid4 _ _ mor4 _)<- dijkstra graph n n2
 com1 <- compComorphism (Comorphism cid1) (Comorphism cid3)
 com2 <- compComorphism (Comorphism cid1) (Comorphism cid3)
 if com1 /= com2 then  fail "Unable to compute coequalizer" else do
   _gtM@(G_theory lidM signM _idxM _ _)<- mapG_theory com1 gt
   s1 <- coerceSign lidM tlid "coequalizers" signM
   mor3' <- coerceMorphism (targetLogic cid3) (sourceLogic cid1) "coeqs" mor3
   mor4' <- coerceMorphism (targetLogic cid4) (sourceLogic cid2) "coeqs" mor4
   m1 <- map_morphism cid1 mor3'
   m2 <- map_morphism cid2 mor4'
   phi1' <- comp m1 mor1
   phi2' <- comp m2 mor2
   phi1 <- coerceMorphism (targetLogic cid1) tlid "coeqs" phi1'
   phi2 <- coerceMorphism (targetLogic cid2) tlid "coeqs" phi2'
   -- build the double arrow for computing the coequalizers
   let doubleArrow = Graph.mkGraph
         [(n, plainSign s1), (newN, plainSign tsign)]
         [(n, newN, (1, phi1)), (n, newN, (1, phi2))]
   (colS, colM) <- weakly_amalgamable_colimit tlid doubleArrow
   let newGt1 = noSensGTheory tlid (mkExtSign colS) startSigId
   mor11' <- coerceMorphism tlid (targetLogic cid1) "coeqs" $ (Map.!) colM newN
   mor11 <- comp mor1 mor11'
   mor22' <- coerceMorphism tlid (targetLogic cid2) "coeqs" $ (Map.!) colM newN
   mor22 <- comp mor2 mor22'
   let gMor11 = GMorphism cid1 sig1 idx1 mor11 startMorId
   let gMor22 = GMorphism cid2 sig2 idx2 mor22 startMorId
   computeCoeqs graph funDesc (n1, gt1) (n2,gt2) (newN, newGt1)
                       gMor11 gMor22 descs

--  returns a maximal node available
pickMaxNode :: (MonadPlus t) => Gr a b -> t (Node,a)
pickMaxNode graph = msum $ map return $
                    filter (\(node,_) -> outdeg graph node == 0) $
                    labNodes graph

--  returns a list of common descendants of two maximal nodes:
--  one node if a glb exists, or all maximal descendants otherwise
commonDesc ::  Map.Map Node [(Node,G_theory)] -> Node -> Node
            -> [(Node, G_theory)]
commonDesc funDesc n1 n2 = case glb funDesc n1 n2 of
                            Just x -> [x]
                            Nothing -> maxBounds funDesc n1 n2

-- returns a weakly amalgamable square of lax triangles
pickSquare :: (MonadPlus t) => Result GMorphism -> Result GMorphism -> t Square
pickSquare (Result _ (Just phi1@(GMorphism cid1 _ _ _ _)))
           (Result _ (Just phi2@(GMorphism cid2 _ _ _ _))) =
   if (isHomogeneous phi1 && isHomogeneous phi2) then
      return $ mkIdSquare $ Logic $ sourceLogic cid1
    --since they have the same target, both homogeneous implies same logic
   else
    case maybeResult $ lookupSquare_in_LG (Comorphism cid1)(Comorphism cid2) of
     Nothing -> mzero
     Just sqList -> msum $ map return sqList

pickSquare (Result _ Nothing) _ = fail "Error computing comorphisms"
pickSquare _ (Result _ Nothing) = fail "Error computing comorphisms"

--  builds the span for which the colimit is computed
buildSpan :: GDiagram ->
             Map.Map Node [(Node, G_theory)] ->
             AnyComorphism ->
             AnyComorphism ->
             AnyComorphism ->
             AnyComorphism ->
             AnyComorphism ->
             AnyModification ->
             AnyModification ->
             G_theory ->
             G_theory ->
             G_theory ->
             GMorphism ->
             GMorphism ->
             Int -> Int -> Int ->
             [(Int, G_theory)]->
             Result (GDiagram, Map.Map Node [(Node,G_theory)])
buildSpan graph
          funDesc
          d@(Comorphism _cidD)
          e1@(Comorphism cidE1)
          e2@(Comorphism cidE2)
          _d1@(Comorphism _cidD1)
          _d2@(Comorphism _cidD2)
          _m1@(Modification cidM1)
          _m2@(Modification cidM2)
          gt@(G_theory lid sign _ _ _)
          gt1@(G_theory _lid1 _sign1 _ _ _)
          gt2@(G_theory _lid2 _sign2 _ _ _)
          _phi1@(GMorphism cid1 _  _ mor1 _)
          _phi2@(GMorphism cid2 _  _ mor2 _)
          n n1 n2
          maxNodes
           =  do
 sig@(G_theory lid0 sign0 _ _ _)  <- mapG_theory d gt -- phi^d(Sigma)
 sig1 <- mapG_theory e1 gt1 -- phi^e1(Sigma1)
 sig2 <- mapG_theory e2 gt2 -- phi^e2(Sigma2)
 mor1' <- coerceMorphism (targetLogic cid1) (sourceLogic cidE1) "buildSpan" mor1
 eps1 <- map_morphism cidE1 mor1' -- phi^e1(sigma1)
 sign' <- coerceSign lid (sourceLogic$ sourceComorphism cidM1) "buildSpan" sign
 tau1 <- tauSigma cidM1 (plainSign sign') -- I^u1_Sigma
 tau1' <- coerceMorphism (targetLogic$ sourceComorphism cidM1)
                         (targetLogic cidE1) "buildSpan" tau1
 rho1 <- comp tau1' eps1
 mor2' <- coerceMorphism (targetLogic cid2) (sourceLogic cidE2) "buildSpan" mor2
 eps2 <- map_morphism cidE2 mor2' --phi^e2(sigma2)
 sign'' <- coerceSign lid (sourceLogic$ sourceComorphism cidM2) "buildSpan" sign
 tau2 <- tauSigma cidM2 (plainSign sign'') -- I^u2_Sigma
 tau2' <- coerceMorphism (targetLogic$ sourceComorphism cidM2)
                         (targetLogic cidE2) "buildSpan" tau2
 rho2 <- comp tau2' eps2
 signE1 <- coerceSign lid0 (sourceLogic cidE1) " " sign0
 signE2 <- coerceSign lid0 (sourceLogic cidE2) " " sign0
 (graph1, funDesc1) <- addNodeToGraph graph sig sig1 sig2 n n1 n2
     (GMorphism cidE1 signE1 startSigId rho1 startMorId)
     (GMorphism cidE2 signE2 startSigId rho2 startMorId) funDesc maxNodes
 return (graph1, funDesc1)

pickMaximalDesc :: (MonadPlus t) => [(Node, G_theory)] -> t (Node, G_theory)
pickMaximalDesc descList = msum$ map return descList

nrMaxNodes :: Gr a b -> Int
nrMaxNodes graph = length $ filter (\n -> outdeg graph n == 0) $ nodes graph

-- | backtracking function for heterogeneous weak amalgamable cocones
hetWeakAmalgCocone :: (Monad m, LogicT t, MonadPlus (t m)) =>
                     GDiagram -> Map.Map Int [(Int, G_theory)] -> t m GDiagram
hetWeakAmalgCocone graph funDesc =
 if nrMaxNodes graph  == 1 then return graph
 else once $ do
  (n1,gt1) <- pickMaxNode graph
  (n2,gt2) <- pickMaxNode graph
  guard (n1 < n2) -- to consider each pair of maximal nodes only once
  let descList = commonDesc funDesc n1 n2
  case length descList of
    0 -> mzero -- no common descendants for n1 and n2
    _ -> do -- just one common descendant implies greatest lower bound
            --  for several, the tail is not empty and we compute coequalizers
     (n,gt) <- pickMaximalDesc descList
     let phi1 = dijkstra graph n n1
         phi2 = dijkstra graph n n2
     square <- pickSquare phi1 phi2
     let d  = laxTarget $ leftTriangle square
         e1 = laxFst $ leftTriangle square
         d1 = laxSnd $ leftTriangle square
         e2 = laxFst $ rightTriangle square
         d2 = laxSnd $ rightTriangle square
         m1 = laxModif $ leftTriangle square
         m2 = laxModif $ rightTriangle square
     case maybeResult phi1 of
      Nothing -> mzero
      Just phi1' -> case maybeResult phi2 of
       Nothing -> mzero
       Just phi2' -> do
        let mGraph = buildSpan graph funDesc d e1 e2 d1 d2 m1 m2 gt gt1 gt2
                      phi1' phi2' n n1 n2 $ filter (\(nx,_) -> nx /=n) descList
        case  maybeResult mGraph  of
         Nothing -> mzero
         Just (graph1, funDesc1) -> hetWeakAmalgCocone graph1 funDesc1


