{- |
Module      :  $Header$
Copyright   :  (c) Maciek Makowski, Warsaw University 2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

  Amalgamability analysis for CASL. 

  Follows the algorithm outlined in MFCS 2001 (LNCS 2136, pp. 451-463, 
  Springer 2001) paper.


TODO:

* optimisations in congruenceClosure (Nelson-Oppen algorithm?)
* optimisation in colimitIsThin (fixUpdRule)
* optimisations in the whole algorithm

-}

-- keep within 80 chars per line!

module CASL.Amalgamability(-- * Types
                           CASLSign, CASLMor, 
                           -- * Functions
                           ensuresAmalgamability) where


import CASL.AS_Basic_CASL
import Common.Id
import Common.Lib.Graph
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Rel as Rel
import qualified Common.Lib.Set as Set
import Common.PrettyPrint
import Common.Lib.Pretty
import Common.Result
import Common.Amalgamate
import CASL.Sign
import CASL.Morphism
import Data.List

-- Exported types
type CASLSign = Sign () ()
type CASLMor = Morphism () () ()

-- Miscellaneous types
type CASLDiag = Diagram CASLSign CASLMor
type DiagSort = (Node, SORT) 
type DiagOp = (Node, (Id, OpType))
type DiagPred = (Node, (Id, PredType))
type DiagEmb = (Node, SORT, SORT)
type DiagEmbWord = [DiagEmb]
-- | equivalence classes are represented as lists of elements
type EquivClass a = [a]
-- | equivalence relations are represented as lists of equivalence classes
type EquivRel a = [EquivClass a]
-- | or, sometimes, as lists of pairs (element, equiv. class tag)
type EquivRelTagged a b = [(a, b)]

-- PrettyPrint instance (for diagnostic output)
instance (PrettyPrint a,  PrettyPrint b) => PrettyPrint (Diagram a b) where
    printText0 ga diag = 
        ptext "nodes: " 
        <+> (printText0 ga (labNodes diag))
        <+> ptext "\nedges: "
        <+> (printText0 ga (labEdges diag))


-- | Compute the Sorts set -- a disjoint union of all the sorts
-- in the diagram.
sorts :: CASLDiag        -- ^ the diagram to get the sorts from
      -> [DiagSort]
sorts diag = 
    let mkNodeSortPair n srt = (n, srt)
        appendSorts sl (n, Sign { sortSet = s }) =
            sl ++ (map (mkNodeSortPair n) (Set.toList s))
    in foldl appendSorts [] (labNodes diag)


-- | Compute the Ops set -- a disjoint union of all the operation symbols
-- in the diagram.
ops :: CASLDiag        -- ^ the diagram to get the ops from
    -> [DiagOp]
ops diag = 
    let mkNodeOp n opId opType ol = ol ++ [(n, (opId, opType))]
        mkNodeOps n opId opTypes ol = 
            ol ++ Set.fold (mkNodeOp n opId) [] opTypes
        appendOps ol (n, Sign { opMap = m }) =
            ol ++ Map.foldWithKey (mkNodeOps n) [] m 
    in foldl appendOps [] (labNodes diag)


-- | Compute the Preds set -- a disjoint union of all the predicate symbols
-- in the diagram.
preds :: CASLDiag        -- ^ the diagram to get the preds from
      -> [DiagPred]
preds diag = 
    let mkNodePred n predId predType pl = pl ++ [(n, (predId, predType))]
        mkNodePreds n predId predTypes pl = 
            pl ++ Set.fold (mkNodePred n predId) [] predTypes
        appendPreds pl (n, Sign { predMap = m }) =
            pl ++ Map.foldWithKey (mkNodePreds n) [] m 
    in foldl appendPreds [] (labNodes diag)


-- | Convert the relation representation from list of pairs 
-- (val, equiv. class tag) to a list of equivalence classes.
taggedValsToEquivClasses :: Ord b
                         => EquivRelTagged a b -- ^ a list of (value, tag) pairs
                         -> EquivRel a
taggedValsToEquivClasses [] = []
taggedValsToEquivClasses rel =
    let -- prepMap: create a map with all the equivalence class tags mapped to
        -- empty lists
        prepMap rel = 
            foldl (\m -> \k -> Map.insert (snd k) [] m) Map.empty rel
        -- conv: perform actual conversion
        convert [] m = map snd (Map.toAscList m)
        convert ((ds, ect) : dsps) m =
            let m' = Map.update (\ec -> Just (ds : ec)) ect m
            in convert dsps m'
    in convert rel (prepMap rel)


-- | Convert the relation representation from list of 
-- equivalence classes to list of (value, tag) pairs.
equivClassesToTaggedVals :: Ord a
                         => EquivRel a
                         -> EquivRelTagged a a
equivClassesToTaggedVals rel =
    let eqClToList [] = []
        eqClToList eqcl@(fst : _) = map (\x -> (x, fst)) eqcl
    in foldl (\vtl -> \eqcl -> vtl ++ (eqClToList eqcl)) [] rel

{- the old, n^3 version of mergeEquivClassesBy:
-- | Merge the equivalence classes for elements fulfilling given condition.
mergeEquivClassesBy :: Eq b 
                    => (a -> a -> Bool)   -- ^ the condition stating when two elements are in relation
                    -> EquivRelTagged a b -- ^ the input relation
                    -> EquivRelTagged a b
-- ^ returns the input relation with equivalence classes merged according to
-- the condition.
mergeEquivClassesBy cond rel =
    -- Starting with the first element in the list an element (elem, tag) is taken
    -- and cond is subsequently applied to it and all the elements
    -- following it in the list. Whenever an element (elem', tag') 
    -- that is in relation with the chosen one is found, all the equivalence 
    -- class tags in the list that are equal to tag' are updated to tag.

    let merge rel pos | pos >= length rel = rel
        merge rel pos | otherwise = 
            let mergeWith cmpl _ [] = cmpl
                mergeWith cmpl vtp@(elem, ec) toCmpl@((elem', ec') : _) =
                    let (cmpl', toCmpl') = if ec /= ec' && (cond elem elem') 
                                             then let upd (elem'', ec'') = 
                                                          if ec'' == ec' 
                                                             then (elem'', ec) 
                                                             else (elem'', ec'')
                                                  in (map upd cmpl, map upd toCmpl)
                                             else (cmpl, toCmpl)
                    in mergeWith (cmpl' ++ [head toCmpl']) vtp (tail toCmpl')
                (cmpl, (vtp : vtps)) = splitAt pos rel
                rel' = mergeWith (cmpl ++ [vtp]) vtp vtps
            in merge rel' (pos + 1)
    in merge rel 0
-}

data TagEqcl a b = Eqcl [a] | TagRef b
                   deriving Show

-- | Merge the equivalence classes for elements fulfilling given condition.
mergeEquivClassesBy :: (Ord b)
                    => (a -> a -> Bool)   -- ^ the condition stating when two elements are in relation
                    -> EquivRelTagged a b -- ^ the input relation
                    -> EquivRelTagged a b
-- ^ returns the input relation with equivalence classes merged according to
-- the condition.
mergeEquivClassesBy cond rel =
    -- Starting with the first element in the list an element (elem, tag) is taken
    -- and cond is subsequently applied to it and all the elements
    -- following it in the list. Whenever an element (elem', tag') 
    -- that is in relation with the chosen one is found, the equivalence classes
    -- in tagMap for tag and tag' are merged: tag in tagMap points to the merged
    -- equivalence class and tag' in tagMap is a reference to tag.

    let -- create the initial map mapping tags to equivalence classes        
        initialTagMap = 
            let insEl tagMap (val, tag) =
                    case Map.member tag tagMap of
                                               True -> Map.update (\(Eqcl eqcl) -> Just (Eqcl (val : eqcl))) tag tagMap
                                               False -> Map.insert tag (Eqcl [val]) tagMap
            in foldl insEl Map.empty rel

        -- merge equivalence classes tagged with t1 and t2
        mergeInMap tagMap t1 t2 = 
            let -- find the tag and equivalence class that corresponds to the given tag
                -- performing path compression while traversing the referneces.
                findEqcl t tagMap = 
                    case Map.find t tagMap of 
                                           Eqcl eqcl -> (t, eqcl, tagMap)
                                           TagRef t' -> 
                                               let (rt, eqcl, tagMap') = findEqcl t' tagMap
                                                   tagMap'' = if rt == t' then tagMap'
                                                         else Map.update (\_ -> Just (TagRef rt)) t tagMap'
                                               in (rt, eqcl, tagMap'')

                (rt1, eqcl1, tagMap') = findEqcl t1 tagMap
                (rt2, eqcl2, tagMap'') = findEqcl t2 tagMap'
            in if rt1 == rt2 then tagMap''
                  else let (nrt1, nrt2) = if rt1 > rt2 then (rt2, rt1) else (rt1, rt2)
                           tagMap3 = Map.update (\_ -> Just (Eqcl (eqcl1 ++ eqcl2))) rt1 tagMap''
                           tagMap4 = Map.update (\_ -> Just (TagRef rt1)) rt2 tagMap3
                       in tagMap4

        -- iterate through the relation merging equivalence classes of appropriate elements
        merge tagMap rel pos | pos >= length rel = tagMap
        merge tagMap rel pos | otherwise = 
            let mergeWith tagMap _ [] = tagMap
                mergeWith tagMap vtp@(elem, ec) toCmpl@((elem', ec') : _) =
                    let tagMap' = if ec /= ec' && (cond elem elem') 
                                     then mergeInMap tagMap ec ec'
                                     else tagMap
                    in mergeWith tagMap' vtp (tail toCmpl)
                (_, (vtp : vtps)) = splitAt pos rel
                tagMap' = mergeWith tagMap vtp vtps
            in merge tagMap' rel (pos + 1)

        -- append given equivalence class to the list of (value, tag) pairs
        tagMapToRel rel (_, TagRef _) = rel
        tagMapToRel rel (tag, Eqcl eqcl) =
            foldl (\l -> \v -> (v, tag) : l) rel eqcl

        tagMap = merge initialTagMap rel 0

    in foldl tagMapToRel [] (Map.toAscList tagMap)



-- | Merge the equivalence classes for given tags.
mergeEquivClasses :: Eq b
                  => EquivRelTagged a b
                  -> b                -- ^ tag 1
                  -> b                -- ^ tag 2
                  -> EquivRelTagged a b
mergeEquivClasses rel tag1 tag2 | tag1 == tag2 = rel
                                | otherwise =
    let upd (el, tag) | tag == tag2 = (el, tag1)
                      | otherwise = (el, tag)
    in map upd rel
    

-- | Return true if there is an edge between srcNode and targetNode
-- and the morphism with which it's labelled maps srcSort to targetSort
isMorphSort :: CASLDiag
            -> DiagSort
            -> DiagSort
            -> Bool
isMorphSort diag (srcNode, srcSort) (targetNode, targetSort) = 
    let checkEdges [] = False
        checkEdges ((sn, tn, Morphism { sort_map = sm }) : edges) =
            if sn == srcNode && 
               tn == targetNode &&
               mapSort sm srcSort == targetSort 
               then True else checkEdges edges
    in checkEdges (out diag srcNode)


-- | Return true if there is an edge between srcNode and targetNode
-- and the morphism with which it's labelled maps srcOp to targetOp
isMorphOp :: CASLDiag
          -> DiagOp
          -> DiagOp
          -> Bool
isMorphOp diag (srcNode, srcOp) (targetNode, targetOp) = 
    let checkEdges [] = False
        checkEdges ((sn, tn, Morphism { sort_map = sm, fun_map = fm }) : edges) =
            if sn == srcNode && 
               tn == targetNode &&
               mapOpSym sm fm srcOp == targetOp
               then True else checkEdges edges
    in checkEdges (out diag srcNode)


-- | Return true if there is an edge between srcNode and targetNode
-- and the morphism with which it's labelled maps srcPred to targetPred
isMorphPred :: CASLDiag
            -> DiagPred
            -> DiagPred
            -> Bool
isMorphPred diag (srcNode, srcPred) (targetNode, targetPred) = 
    let checkEdges [] = False
        checkEdges ((sn, tn, Morphism { sort_map = sm, pred_map = pm }) : edges) =
            if sn == srcNode && 
               tn == targetNode &&
               mapPredSym sm pm srcPred == targetPred
               then True else checkEdges edges
    in checkEdges (out diag srcNode)


-- | Compute the simeq relation for given diagram.
simeq :: CASLDiag  -- ^ the diagram for which the relation should be created
      -> EquivRel DiagSort
-- ^ returns the relation represented as a list of equivalence
-- classes (each represented as a list of diagram ops)
simeq diag =
    -- During the computations the relation is represented as a list of pairs
    -- (DiagSort, DiagSort). The first element is a diagram sort and the second
    -- denotes the equivalence class to which it belongs. All the pairs with
    -- equal second element denote elements of one equivalence class.

    let mergeCond ds ds' = isMorphSort diag ds ds' || isMorphSort diag ds' ds

        -- compute the relation
        rel = map (\ds -> (ds, ds)) (sorts diag)
        rel' = mergeEquivClassesBy mergeCond rel
    in taggedValsToEquivClasses rel'


-- | Compute the simeq^op relation for given diagram.
simeqOp :: CASLDiag  -- ^ the diagram for which the relation should be created
         -> EquivRel DiagOp
-- ^ returns the relation represented as a list of equivalence
-- classes (each represented as a list of diagram ops)
simeqOp diag =
    -- During the computations the relation is represented as a list of pairs
    -- (DiagOp, DiagOp). The first element is a diagram op and the second
    -- denotes the equivalence class to which it belongs. All the pairs with
    -- equal second element denote elements of one equivalence class.

    let mergeCond ds ds' = isMorphOp diag ds ds' || isMorphOp diag ds' ds

        -- compute the relation
        rel = map (\ds -> (ds, ds)) (ops diag)
        rel' = mergeEquivClassesBy mergeCond rel
    in taggedValsToEquivClasses rel'


-- | Compute the simeq^pred relation for given diagram.
simeqPred :: CASLDiag  -- ^ the diagram for which the relation should be created
         -> EquivRel DiagPred
-- ^ returns the relation represented as a list of equivalence
-- classes (each represented as a list of diagram preds)
simeqPred diag =
    -- During the computations the relation is represented as a list of pairs
    -- (DiagPred, DiagPred). The first element is a diagram pred and the second
    -- denotes the equivalence class to which it belongs. All the pairs with
    -- equal second element denote elements of one equivalence class.

    let mergeCond ds ds' = isMorphPred diag ds ds' || isMorphPred diag ds' ds

        -- compute the relation
        rel = map (\ds -> (ds, ds)) (preds diag)
        rel' = mergeEquivClassesBy mergeCond rel
    in taggedValsToEquivClasses rel'


-- | Compute the simeq_tau relation for given diagram.
simeq_tau :: [(Node, CASLMor)]
          -> EquivRel DiagSort
simeq_tau sink = 
    let -- tagEdge: for given morphism m create a list of pairs 
        -- (a, b) where a is DiagSort from the source signature that
        -- is mapped by m to b
        tagEdge (sn, Morphism { sort_map = sm }) = 
            map (\(ss, ts) -> ((sn, ss), ts)) (Map.toList sm)
        rel = foldl (\l -> \e -> l ++ (tagEdge e)) [] sink
    in taggedValsToEquivClasses rel


-- | Compute the simeq^op_tau relation for given diagram.
simeqOp_tau :: [(Node, CASLMor)]
            -> EquivRel DiagOp
simeqOp_tau sink = 
    let -- tagEdge: for given morphism m create a list of pairs 
        -- (a, b) where a is DiagOp from the source signature that
        -- is mapped by m to b
        tagEdge (sn, Morphism { sort_map = sm, fun_map = fm }) = 
            map (\srcOp -> ((sn, srcOp), mapOpSym sm fm srcOp)) (Map.keys fm)
        rel = foldl (\l -> \e -> l ++ (tagEdge e)) [] sink
    in taggedValsToEquivClasses rel


-- | Compute the simeq^pred_tau relation for given diagram.
simeqPred_tau :: [(Node, CASLMor)]
              -> EquivRel DiagPred
simeqPred_tau sink = 
    let -- tagEdge: for given morphism m create a list of pairs 
        -- (a, b) where a is DiagPred from the source signature that
        -- is mapped by m to b
        tagEdge (sn, Morphism { sort_map = sm, pred_map = pm }) = 
            map (\srcPred -> ((sn, srcPred), mapPredSym sm pm srcPred)) (Map.keys pm)
        rel = foldl (\l -> \e -> l ++ (tagEdge e)) [] sink
    in taggedValsToEquivClasses rel


-- | Check that one equivalence relation is a subset of another.
-- The relations are represented as a lists of equivalence classes,
-- where equivalence classes are lists of elements.
subRelation :: Eq a
            => EquivRel a  -- ^ the relation that is supposed to be a subset
            -> EquivRel a  -- ^ the relation that is supposed to be a superset
            -> Maybe (a, a)
-- ^ returns a pair of elements that are in the same equivalence class of the 
-- first relation but are not in the same equivalence class of the second 
-- relation or Nothing the first relation is a subset of the second one.
subRelation [] _ = Nothing
subRelation ([] : eqcls) sup = subRelation eqcls sup -- this should never be the case
subRelation (elts@(elt : _) : eqcls) sup =
    let findEqCl _ [] = [] 
        findEqCl elt (eqcl : eqcls) =
            if elem elt eqcl then eqcl else findEqCl elt eqcls
        checkEqCl [] _ = Nothing
        checkEqCl (elt : elts) supEqCl =
            if elem elt supEqCl 
               then checkEqCl elts supEqCl
               else Just elt
        curFail = checkEqCl elts (findEqCl elt sup)
    in case curFail of 
            Nothing -> subRelation eqcls sup
            Just elt2 -> Just (elt, elt2)


-- | Compute the set of sort embeddings defined in the diagram.
embs :: CASLDiag
     -> [DiagEmb]
embs diag =
    let embs' [] = []
        embs' ((n, Sign {sortRel = sr}) : lNodes) = 
            (map (\(s1, s2) -> (n, s1, s2)) (Rel.toList sr)) ++ (embs' lNodes)
    in embs' (labNodes diag)


-- | Compute the set of sort embeddings (relations on sorts) defined
-- in the source nodes of the sink.
sinkEmbs :: CASLDiag          -- ^ the diagram
         -> [(Node, CASLMor)] -- ^ the sink
         -> [DiagEmb]
sinkEmbs _ [] = []
sinkEmbs diag ((srcNode, _) : edges) = 
    let (_, _, Sign {sortRel = sr}, _) = context srcNode diag
    in (map (\(s1, s2) -> (srcNode, s1, s2)) (Rel.toList sr)) 
           ++ (sinkEmbs diag edges)
    

-- | Check if the two given elements are in the given relation.
inRel :: Eq a 
      => EquivRel a -- ^ the relation
      -> a          -- ^ the first element
      -> a          -- ^ the second element
      -> Bool
inRel [] _ _ = False
inRel (eqc : eqcs) a b | a == b = True
                       | otherwise =
    case find (\x -> x == a) eqc of
         Nothing -> inRel eqcs a b
         Just _ -> case find (\x -> x == b) eqc of
                        Nothing -> False
                        Just _ -> True


-- | Check if two embeddings can occur subsequently in a word
-- given the simeq relation on sorts.
admissible :: EquivRel DiagSort -- ^ the \simeq relation
           -> DiagEmb           -- ^ the first embedding
           -> DiagEmb           -- ^ the second embedding
           -> Bool
admissible simeq (n1, s1, _) (n2, _, s2) = 
    inRel simeq (n1, s1) (n2, s2)


-- | Compute the set of all the loopless, admissible
-- words over given set of embeddings.
looplessWords :: [DiagEmb]         -- ^ the embeddings
         -> EquivRel DiagSort -- ^ the \simeq relation that defines admissibility
         -> [DiagEmbWord]
looplessWords embs simeq =
    let -- generate the list of all loopless words over given alphabet
        -- with given suffix
        looplessWords' suff@(e : _) embs pos | pos >= length embs = [suff]
                                             | otherwise = 
            let emb = embs !! pos
                embs' = embs \\ [emb]
                ws = if admissible simeq emb e
                       then looplessWords' (emb : suff) embs' 0
                       else []
            in ws ++ (looplessWords' suff embs (pos + 1))
        looplessWords' [] embs pos | pos >= length embs = []
                                   | otherwise = 
            let emb = embs !! pos
                embs' = embs \\ [emb]
            in (looplessWords' [emb] embs' 0) ++ (looplessWords' [] embs (pos + 1))
    in looplessWords' [] embs 0


-- | Return the codomain of an embedding path.
wordCod :: DiagEmbWord 
        -> DiagSort
wordCod ((n, _, s2) : _) = (n, s2)


-- | Return the domain of an embedding path.
wordDom :: DiagEmbWord
        -> DiagSort
wordDom w = let (n, s1, _) = last w in (n, s1)


-- | Find an equivalence class tag for given element.
findTag :: Eq a
        => EquivRelTagged a b
        -> a
        -> Maybe b
findTag [] _ = Nothing 
findTag ((w', t) : wtps) w = 
    if w == w' then Just t else findTag wtps w


-- | Compute the left-cancellable closure of a relation on words.
leftCancellableClosure :: EquivRelTagged DiagEmbWord DiagEmbWord
                       -> EquivRelTagged DiagEmbWord DiagEmbWord
leftCancellableClosure rel = 
    let -- checkPrefixes: for each common prefix of two given words
        -- merge the equivalence classes of the suffixes
        checkPrefixes [] _ rel = rel
        checkPrefixes _ [] rel = rel
        checkPrefixes w1@(l1 : suf1) w2@(l2 : suf2) rel | w1 == w2 = rel
                                                        | l1 /= l2 = rel
                                                        | otherwise =
            let Just tag1 = findTag rel suf1
                Just tag2 = findTag rel suf2
                rel' = if tag1 == tag2 then rel
                          else let upd (w, t) | t == tag2 = (w, tag1)
                                              | otherwise = (w, t)
                               in map upd rel
            in checkPrefixes suf1 suf2 rel'

        -- iterateWord1: for each pair of related words call checkPrefixes
        iterateWord1 rel pos | pos >= length rel = rel
                             | otherwise =
            let iterateWord2 wtp1@(w1, t1) rel pos | pos >= length rel = rel
                                                   | otherwise =
                    let wtp2@(w2, t2) = rel !! pos
                        rel' = if t1 == t2 then checkPrefixes w1 w2 rel else rel
                    in iterateWord2 wtp1 rel' (pos + 1)
                wtp = rel !! pos
                rel' = iterateWord2 wtp rel 0
            in iterateWord1 rel' (pos + 1)
    in {-trace ("leftCancellableClosure " ++ show rel) $-} iterateWord1 rel 0


-- | Compute the congruence closure of an equivalence R: two pairs of elements (1, 3) and 
-- (2, 4) are chosen such that 1 R 2 and 3 R 4. It is then checked that elements 1, 3 and 
-- 2, 4 are in relation supplied and if so equivalence classes for (op 1 3) and (op 1 4) 
-- in R are merged.
-- This function should be applied to the relation until a fixpoint is reached.
congruenceClosure :: (Eq a, Eq b)
                  => (a -> a -> Bool) -- ^ the check to be performed on elements 1, 3 and 2, 4
                  -> (a -> a -> a)    -- ^ the operation to be performed on elements 1, 3 and 2, 4
                  -> EquivRelTagged a b
                  -> EquivRelTagged a b
congruenceClosure check op rel =
    let -- iterateWord1 
        iterateWord1 rel pos | pos >= length rel = rel
                             | otherwise =
            let -- iterateWord2
                iterateWord2 wtp1@(_, t1) rel pos | pos >= length rel = rel
                                                  | otherwise =
                    let -- iterateWord3
                        iterateWord3 wtp1@(w1, _) wtp2 rel pos | pos >= length rel = rel
                                                               | otherwise =
                            let -- iterateWord4
                                iterateWord4 wtp1@(w1, _) wtp2@(w2, _) wtp3@(w3, t3) rel pos | pos >= length rel = rel
                                                                                             | otherwise =
                                    let (w4, t4) = rel !! pos
                                        rel' = if t3 /= t4 || not (check w2 w4) then rel
                                                  else let mct1 = findTag rel (op w1 w3)
                                                           mct2 = findTag rel (op w2 w4)
                                                       in case (mct1, mct2) of 
                                                                            (Nothing, _) -> rel -- w3w1 is not in the domain of rel
                                                                            (_, Nothing) -> rel -- w4w2 is not in the domain of rel
                                                                            (Just ct1, Just ct2) -> mergeEquivClasses rel ct1 ct2
                                    in iterateWord4 wtp1 wtp2 wtp3 rel' (pos + 1)

                                wtp3@(w3, _) = rel !! pos
                                rel' = if check w1 w3
                                          -- inRel here is usually much more efficient 
                                          -- than findTag rel (w3 ++ w1)
                                          then iterateWord4 wtp1 wtp2 wtp3 rel 0
                                          else rel
                            in iterateWord3 wtp1 wtp2 rel' (pos + 1)

                        wtp2@(_, t2) = rel !! pos
                        rel' = if t1 /= t2 then rel
                                  else iterateWord3 wtp1 wtp2 rel 0 
                    in iterateWord2 wtp1 rel' (pos + 1)

                wtp = rel !! pos
                rel' = iterateWord2 wtp rel 0
            in iterateWord1 rel' (pos + 1)

    in{- trace ("congruenceClosure " ++ show rel) $-} iterateWord1 rel 0 


-- | Compute the cong_tau relation for given diagram and sink.
cong_tau :: CASLDiag          -- ^ the diagram
         -> [(Node, CASLMor)] -- ^ the sink
         -> EquivRel DiagSort -- ^ the \simeq_tau relation
         -> EquivRel DiagEmbWord
cong_tau diag sink st = 
    let -- domCodSimeq: check that domains and codomains of given words are related
        domCodSimeq w1 w2 = 
            inRel st (wordDom w1) (wordDom w2) && inRel st (wordCod w1) (wordCod w2)

        embs = sinkEmbs diag sink
        words = looplessWords embs st
        rel = map (\w -> (w, w)) words
        rel' = mergeEquivClassesBy domCodSimeq rel
    in taggedValsToEquivClasses rel'


-- | Compute the finite representation of cong_0 relation for given diagram.
-- The representation consists only of equivalence classes that
-- contain more than one element.
cong_0 :: CASLDiag
       -> EquivRel DiagSort -- ^ the \simeq relation
       -> EquivRel DiagEmbWord
cong_0 diag simeq = 
    let -- diagRule: the Diag rule
        diagRule [(n1, s11, s12)] [(n2, s21, s22)] =
            isMorphSort diag (n1, s11) (n2, s21) && isMorphSort diag (n1, s12) (n2, s22) || 
            isMorphSort diag (n2, s21) (n1, s11) && isMorphSort diag (n2, s22) (n1, s12)
        diagRule _ _ = False

        -- addToRel: add given word to given relation
        addToRel [] _ = []
        addToRel (eqcl@(refw : _) : eqcls) w =
            if wordDom w == wordDom refw && wordCod w == wordCod refw
               then ((w : eqcl) : eqcls) 
               else (eqcl : (addToRel eqcls w))

        -- words2: generate all the admissible 2-letter words over given alphabet
        words2 _ [] _ = []
        words2 alph (_ : embs) [] = words2 alph embs alph
        words2 alph embs1@(emb1 : _) (emb2 : embs2) =
            let ws = words2 alph embs1 embs2
            in if admissible simeq emb1 emb2 
               then ([emb1, emb2] : ws) else ws

        -- compute the relation
        em = embs diag
        rel = map (\e -> ([e], [e])) em
        rel' = mergeEquivClassesBy diagRule rel
        rel'' = taggedValsToEquivClasses rel'
        w2s = words2 em em em
        rel''' = foldl addToRel rel'' w2s
    in rel'''


-- | Compute the set Adm_\simeq if it's finite.
finiteAdm_simeq :: [DiagEmb]         -- ^ the embeddings
                -> EquivRel DiagSort -- ^ the \simeq relation that defines admissibility
                -> Maybe [DiagEmbWord]
-- ^ returns the computed set or Nothing if it's infinite
finiteAdm_simeq embs simeq =
    let -- generate the list of the words over given alphabet
        -- with given suffix
        embWords' suff@(e : _) embs pos | pos >= length embs = Just [suff]
                                        | otherwise = 
            let emb = embs !! pos
                mws1 = if admissible simeq emb e
                         then if any (\emb' -> emb' == emb) suff
                                then Nothing
                                else embWords' (emb : suff) embs 0
                         else Just []
                mws2 = case mws1 of
                            Nothing -> Nothing
                            Just _ -> embWords' suff embs (pos + 1)
            in case mws1 of 
                    Nothing -> Nothing
                    Just ws1 -> case mws2 of 
                                     Nothing -> Nothing
                                     Just ws2 -> Just (ws1 ++ ws2)
        embWords' [] embs pos | pos >= length embs = Just []
        embWords' [] embs pos | otherwise = 
            let emb = embs !! pos
                mws1 = embWords' [emb] embs 0
                mws2 = case mws1 of
                            Nothing -> Nothing
                            Just _ -> embWords' [] embs (pos + 1)
            in case mws1 of
                    Nothing -> Nothing
                    Just ws1 -> case mws2 of 
                                     Nothing -> Nothing
                                     Just ws2 -> Just (ws1 ++ ws2)
    in embWords' [] embs 0


-- | Check if the colimit is thin.
colimitIsThin :: EquivRel DiagSort    -- ^ the simeq relation
              -> [DiagEmb]            -- ^ the set of diagram embeddings
              -> EquivRel DiagEmbWord -- ^ the cong_0 relation
              -> Bool
colimitIsThin simeq embs c0 = 
    let -- sortsC: a list of colimit sorts
        sortsC = foldl (\s -> \eqcl -> (head eqcl : s)) [] simeq
        simeqT = equivClassesToTaggedVals simeq

        -- ordMap: map representing the topological order on sorts in the colimit
        ordMap = 
            let sortClasses' m [] = m
                sortClasses' m ((n, s1, s2) : embs) =
                    let Just c1 = findTag simeqT (n, s1)
                        Just c2 = findTag simeqT (n, s2)
                    in sortClasses' (Map.update (\s -> Just (Set.insert c2 s)) c1 m) embs
                ordMap' = foldl (\m -> \cl -> Map.insert cl Set.empty m) Map.empty sortsC
            in sortClasses' ordMap' embs

        -- larger: return a list of colimit sorts larger than given sort
        larger s = 
            let dl = Set.toList (Map.find s ordMap)
            in (s : (foldl (\l -> \s -> l ++ (larger s)) [] dl))

        -- s: the map representing sets S_{\geq s1,s2}
        s = let compS m (s1, s2) = 
                    let ls1 = Set.fromList (larger s1)
                        ls2 = Set.fromList (larger s2)
                    in Map.insert (s1, s2) (Set.intersection ls1 ls2) m
            in foldl compS Map.empty [(s1, s2) | s1 <- sortsC, s2 <- sortsC]

        -- b: the map representing sets B_{s1,s2}
        b = let compB m sp =
                    let sim s' s'' = not (Set.isEmpty (Map.find (s', s'') s))
                        rel = map (\x -> (x, x)) (Set.toList (Map.find sp s))
                        rel' = mergeEquivClassesBy sim rel
                    in Map.insert sp (taggedValsToEquivClasses rel') m
            in foldl compB Map.empty [(s1, s2) | s1 <- sortsC, s2 <- sortsC]

        embDomS (n, dom, _) = let Just s = findTag simeqT (n, dom) in s
        embCodS (n, _, cod) = let Just s = findTag simeqT (n, cod) in s

        -- checkAllSorts: check the C = B condition for all colimit sorts
        checkAllSorts m | Map.isEmpty m = {-trace "CT: Yes"-} True
                        | otherwise =
            let -- checkSort: check if for given colimit sort C = B
                checkSort cs =
                    let embsCs = filter (\e -> embDomS e == cs) embs
                        c = foldl (\m -> \ep -> Map.insert ep [] m) Map.empty
                                  [(d, e) | d <- embsCs, e <- embsCs]
                        c' = let updC c (d, e) =
                                     let s1 = embCodS d
                                         s2 = embCodS e
                                     in Map.update (\_ -> Just (Map.find (s1, s2) b)) (d, e) c
                             in foldl updC c [(d, e) | d <- embsCs, e <- embsCs, inRel c0 [d] [e]]
                        c'' = let updC c (d@(n1, _, cod1), e@(n2, _, cod2)) =
                                      let s1 = embCodS d
                                          s2 = embCodS e
                                      in if (filter (\(n, dom, cod) -> (n, dom) == (n1, cod1) && (n, cod) == (n2, cod2)) embs) == []
                                            then c
                                            else let [absCls] = filter (\ac -> any (s2==) ac) (Map.find (s1, s2) b)
                                                 in foldl (\c -> \k -> Map.update (\l -> Just (l ++ [absCls])) k c) c [(d, e), (e, d)]
                              in foldl updC c' [(d, e) | d <- embsCs, e <- embsCs, wordDom [d] == wordDom [e]]
                        fixUpdRule c = 
                            let updC c (e1, e2, e3) =
                                    let updC' c (b12, b23, b13) =
                                            let sb12 = Set.fromList b12
                                                sb23 = Set.fromList b23
                                                sb13 = Set.fromList b13
                                                comm = Set.intersection sb12 (Set.intersection sb23 sb13)
                                            in if Set.isEmpty comm then c
                                                  else let c' = if any (\l -> l == b13) (Map.find (e1, e3) c) 
                                                                   then c 
                                                                   else Map.update (\l -> Just (l ++ [b13])) (e1, e3) c
                                                       in if any (\l -> l == b13) (Map.find (e1, e3) c') 
                                                             then c' 
                                                             else Map.update (\l -> Just (l ++ [b13])) (e3, e1) c'
                                        s1 = embCodS e1
                                        s3 = embCodS e3
                                    in foldl updC' c [(b12, b23, b13) |
                                                      b12 <- (Map.find (e1, e2) c),
                                                      b23 <- (Map.find (e2, e3) c),
                                                      b13 <- (Map.find (s1, s3) b)]
                                c' = foldl updC c [(e1, e2, e3) | 
                                                   e1 <- embsCs, e2 <- embsCs, e3 <- embsCs]
                            in if c' == c then c else fixUpdRule c'
                        c3 = fixUpdRule c''
                        checkIncl [] = True
                        checkIncl ((e1, e2) : embprs) =
                            let s1 = embCodS e1
                                s2 = embCodS e2
                                res = if subRelation (Map.find (s1, s2) b) (Map.find (e1, e2) c3) == Nothing
                                         then checkIncl embprs
                                         else False
                            in {-trace ("B[" ++ (show s1) ++ ", " ++ (show s2) ++ ":\n" ++ (show (Map.find (s1, s2) b)) ++ "\n" ++
                                      "C[" ++ (show e1) ++ ", " ++ (show e2) ++ ":\n" ++ (show (Map.find (e1, e2) c3)) ++ "\n\n")-}
                                     res
                    in checkIncl [(e1, e2) | e1 <- embsCs, e2 <- embsCs]

                -- cs: next colimit sort to process     
                -- m': the order map with cs removed
                (cs, m') = let [(cs, _)] = take 1 (filter (\(_, lt) -> Set.isEmpty lt) 
                                                          (Map.toList m))
                               m' = Map.delete cs m
                               m'' = foldl (\m -> \k -> Map.update (\lt -> Just (Set.delete cs lt)) k m)
                                           m' (Map.keys m')
                           in (cs, m'')
            in if checkSort cs then checkAllSorts m' else {-trace "CT: No"-} False

    in {-trace ("\\simeq: " ++ (show simeq) ++ "\nEmbs: " ++ (show embs) ++ "\n\\cong_0: " ++ show c0)-} 
         checkAllSorts ordMap

{- the old, unoptimised version of cong:
-- | Compute the \cong relation given its (finite) domain
cong :: CASLDiag
     -> [DiagEmbWord]     -- ^ the Adm_\simeq set (the domain of \cong relation)
     -> EquivRel DiagSort -- ^ the \simeq relation
     -> EquivRel DiagEmbWord
cong diag adm simeq =
    let -- domCodEqual: check that domains and codomains of given words are equal
        domCodEqual w1 w2 = 
               wordDom w1 == wordDom w2 && wordCod w1 == wordCod w2

        -- diagRule: the Diag rule
        diagRule [(n1, s11, s12)] [(n2, s21, s22)] =
            isMorphSort diag (n1, s11) (n2, s21) && isMorphSort diag (n1, s12) (n2, s22) ||
            isMorphSort diag (n2, s21) (n1, s11) && isMorphSort diag (n2, s22) (n1, s12) 
        diagRule _ _ = False

        -- compRule: the Comp rule works for words 1 and 2-letter long
        -- with equal domains and codomains
        compRule w1@[_] w2@[_, _] = domCodEqual w1 w2
        compRule w1@[_, _] w2@[_] = domCodEqual w1 w2
        compRule _ _ = False

        -- fixCongLc: apply Cong and Lc rules until a fixpoint is reached
        fixCongLc rel =
            let rel' = (leftCancellableClosure . congruenceClosure simeq) rel
            in if rel == rel' then rel else fixCongLc rel'

        -- compute the relation
        rel = map (\w -> (w, w)) adm
        rel' = mergeEquivClassesBy diagRule rel
        rel'' = mergeEquivClassesBy compRule rel'
        rel''' = fixCongLc rel''
    in taggedValsToEquivClasses rel'''
-}

-- | Compute the (optimised) \cong relation given its (finite) domain and \sim relation.
-- Optimised \cong is supposed to contain only words composed of canonical embeddings; 
-- we also use a (CompDiag) rule instead of (Comp) and (Diag) rules.
cong :: CASLDiag
     -> [DiagEmbWord]     -- ^ the Adm_\simeq set (the domain of \cong relation)
     -> EquivRel DiagSort -- ^ the \simeq relation
     -> EquivRel DiagEmb  -- ^ the \sim relation
     -> EquivRel DiagEmbWord
cong diag adm simeq sim =
    let -- domCodEqual: check that domains and codomains of given words are equal
        domCodEqual w1 w2 = 
               wordDom w1 == wordDom w2 && wordCod w1 == wordCod w2

        -- diagRule: the Diag rule
        diagRule [(n1, s11, s12)] [(n2, s21, s22)] =
            isMorphSort diag (n1, s11) (n2, s21) && isMorphSort diag (n1, s12) (n2, s22) ||
            isMorphSort diag (n2, s21) (n1, s11) && isMorphSort diag (n2, s22) (n1, s12) 
        diagRule _ _ = False

        -- compDiagRule: the combination of Comp and Diag rules
        compDiagRule w1@[_] w2@[_, _] = compDiagRule w2 w1
        compDiagRule [e1, e2] [d] = 
            let [ec1] = filter (\(e : _) -> e == e1) sim
                [ec2] = filter (\(e : _) -> e == e2) sim
                matches [] = False
                matches (((n1, _, s12), (n2, s21, _)) : eps) = 
                    if n1 == n2 && inRel sim d (n1, s21, s12)
                       then True
                       else matches eps
            in matches [(me1, me2) | me1 <- ec1, me2 <- ec2]
        compDiagRule _ _ = False

        -- fixCongLc: apply Cong and Lc rules until a fixpoint is reached
        fixCongLc rel =
            let rel' = (leftCancellableClosure . 
                        congruenceClosure (\w1 -> \w2 -> inRel simeq (wordCod w1) (wordDom w2)) 
                                          (\w1 -> \w2 -> w2 ++ w1)) rel
            in if rel == rel' then rel else fixCongLc rel'

        -- compute the relation
        rel = map (\w -> (w, w)) adm
        rel' = mergeEquivClassesBy compDiagRule rel
        rel'' = fixCongLc rel'
    in taggedValsToEquivClasses rel''


-- | Compute the \cong^R relation
congR :: CASLDiag
      -> EquivRel DiagSort -- ^ the \simeq relation
      -> EquivRel DiagEmb  -- ^ the \sim relation
      -> EquivRel DiagEmbWord
congR diag simeq sim =
    --cong diag (looplessWords (embs diag) simeq) simeq
    cong diag (looplessWords (canonicalEmbs sim) simeq) simeq sim


-- | Compute the \sim relation
sim :: CASLDiag
    -> [DiagEmb]
    -> EquivRel DiagEmb
sim diag embs =
    let -- diagRule: the Diag rule
        diagRule (n1, s11, s12) (n2, s21, s22) =
            isMorphSort diag (n1, s11) (n2, s21) && isMorphSort diag (n1, s12) (n2, s22) ||
            isMorphSort diag (n2, s21) (n1, s11) && isMorphSort diag (n2, s22) (n1, s12) 

        -- the check for congruenceClosure
        check (p, s11, s12) (q, s21, s22) =
            if p /= q || s12 /= s21 then False
            else any (\(n, s1, s2) -> n == p && s1 == s11 && s2 == s22) embs

        -- the op for congruence closure
        op (p, s1, _) (_, _, s2) = (p, s1, s2)

        -- fixCong: apply Cong rule until a fixpoint is reached
        fixCong rel =
            let rel' = congruenceClosure check op rel
            in if rel == rel' then rel else fixCong rel'
                       
        rel = map (\e -> (e, e)) embs
        rel' =  fixCong rel
        rel'' = mergeEquivClassesBy diagRule rel'
    in taggedValsToEquivClasses rel''


-- | Compute the CanonicalEmbs(D) set given \sim relation
canonicalEmbs :: EquivRel DiagEmb
              -> [DiagEmb]
canonicalEmbs sim =
    foldl (\l -> \(e : _) -> (e : l)) [] sim


-- | Convert given \cong_\tau relation to the canonical form
-- w.r.t. given \sim relation
canonicalCong_tau :: EquivRel DiagEmbWord
                  -> EquivRel DiagEmb
                  -> EquivRel DiagEmbWord
canonicalCong_tau ct sim =
    let mapEmb e = let Just (ce : _) = find (elem e) sim
                   in ce
        mapWord w = map mapEmb w
        mapEqcl ec = map mapWord ec
    in map mapEqcl ct


-- | Convert a word to a list of sorts that are embedded 
wordToEmbPath :: DiagEmbWord
              -> [SORT]
wordToEmbPath [] = []
wordToEmbPath ((_, s1, s2) : embs) = 
    let rest [] = []
        rest ((_, s, _) : embs) = (rest embs) ++ [s]
    in (rest embs) ++ [s1, s2]


hasCellCaslAmalgOpt :: [CASLAmalgOpt] -> Bool
hasCellCaslAmalgOpt = any ( \ o -> case o of
                            Cell -> True
                            _ -> False)

hasColimitThinnessOpt :: [CASLAmalgOpt] -> Bool
hasColimitThinnessOpt = any ( \ o -> case o of
                            ColimitThinness -> True
                            _ -> False)
    
-- | The amalgamability checking function for CASL. 
ensuresAmalgamability :: [CASLAmalgOpt]        -- ^ program options
                      -> CASLDiag              -- ^ the diagram to be checked
                      -> [(Node, CASLMor)]     -- ^ the sink
                      -> Diagram String String -- ^ the diagram containing descriptions of nodes and edges
                      -> Result Amalgamates
ensuresAmalgamability opts diag sink desc = 
    do if null opts 
         then return (DontKnow "Skipping amalgamability check")
         else       
          do let -- aux. functions that help printing out diagnostics
              getNodeSig _ [] = emptySign () -- this should never be the case
              getNodeSig n ((n1, sig) : nss) = if n == n1 then sig else getNodeSig n nss
              lns = labNodes diag
              formatOp (id, t) = renderText Nothing (printText id) ++ " :" ++ renderText Nothing (printText t)
              formatPred (id, t) = renderText Nothing (printText id) ++ " : " ++ renderText Nothing (printText t)
              formatSig n = case find (\(n', d) -> n' == n && d /= "") (labNodes desc) of
                              Just (_, d) -> d 
                              Nothing -> renderText Nothing (printText (getNodeSig n lns))
              -- and now the relevant stuff
              s = {-trace ("Diagram: " ++ showPretty diag "\n Sink: " ++ showPretty sink "")-} simeq diag
              st = simeq_tau sink
             -- 1. Check the inclusion (*). If it doesn't hold, the specification is
             -- incorrect.
             case subRelation st s of
              Just (ns1, ns2) -> let sortString1 = renderText Nothing (printText (snd ns1)) ++
                                             " in\n\n" ++ formatSig (fst ns1) ++ "\n\n"
                                     sortString2 = renderText Nothing (printText (snd ns2)) ++
                                             " in\n\n" ++ formatSig (fst ns2) ++ "\n\n"
                                 in do return (NoAmalgamation ("\nsorts " ++ sortString1 ++ "and " ++ sortString2 ++ "might be different"))
              Nothing -> 
               do let sop = simeqOp diag
                      sopt = simeqOp_tau sink
                 -- 2. Check sharing of operations. If the check fails, the specification is
                 -- incorrect
                  case subRelation sopt sop of
                      Just (nop1, nop2) -> let opString1 = formatOp (snd nop1) ++
                                                           " in\n\n" ++ formatSig (fst nop1) ++ "\n\n"
                                               opString2 = formatOp (snd nop2) ++
                                                           " in\n\n" ++ formatSig (fst nop2) ++ "\n\n"
                               in do return (NoAmalgamation ("\noperations " ++ opString1 ++ "and " ++ opString2 ++ "might be different"))
                      Nothing ->
                        do let spred = simeqPred diag
                               spredt = simeqPred_tau sink
                           -- 3. Check sharing of predicates. If the check fails, the specification is
                           -- incorrect
                           case subRelation spredt spred of
                                Just (np1, np2) -> let pString1 = formatPred (snd np1) ++
                                                                  " in\n\n" ++ formatSig (fst np1) ++ "\n\n"
                                                       pString2 = formatPred (snd np2) ++
                                                                  " in\n\n" ++ formatSig (fst np2) ++ "\n\n"
                                                   in do return (NoAmalgamation ("\npredicates " ++ pString1 ++ "and " ++ pString2 ++ "might be different"))
                                Nothing ->
                                 if not (hasCellCaslAmalgOpt opts || hasColimitThinnessOpt opts)
                                  then return defaultDontKnow
                                  else
                                   do 
                                     let ct = cong_tau diag sink st
                                         -- As we will be using a finite representation of \cong_0
                                         -- that may not contain some of the equivalence classes with
                                         -- only one element it's sufficient to check that the subrelation
                                         -- ct0 of ct that has only non-reflexive elements is a subrelation
                                         -- of \cong_0.
                                         ct0 = filter (\l -> length l > 1) ct
                                         c0 = cong_0 diag s
                                     -- 2. Check the simple case: \cong_0 \in \cong, so if \cong_\tau \in \cong_0 the
                                     -- specification is correct.
                                     case subRelation ct0 c0 of
                                          Nothing -> do return Amalgamates
                                          Just _ -> 
                                            do let em = embs diag
                                                   cem = canonicalEmbs si
                                                   mas = finiteAdm_simeq cem s
                                                   si = sim diag em
                                                   cct = canonicalCong_tau ct si
                                               -- 3. Check if the set Adm_\simeq is finite.
                                               case mas of 
                                                    Just cas -> 
                                                      do -- 4. check the colimit thinness. If the colimit is thing then
                                                         -- the specification is correct.
                                                         if hasColimitThinnessOpt opts && 
                                                            colimitIsThin s em c0 then return Amalgamates
                                                            else do let c = cong diag cas s si
                                                                        --c = cong diag as s
                                                                    -- 5. Check the cell condition in its full generality.
                                                                    if hasCellCaslAmalgOpt opts
                                                                       then case subRelation cct c of
                                                                               Just (w1, w2) -> let rendEmbPath [] = []
                                                                                                    rendEmbPath (h : w) = 
                                                                                                        foldl (\t -> \s -> t ++ " < " ++ renderText Nothing (printText s)) 
                                                                                                              (renderText Nothing (printText h)) w
                                                                                                    word1 = rendEmbPath (wordToEmbPath w1)
                                                                                                    word2 = rendEmbPath (wordToEmbPath w2)
                                                                                                in do return (NoAmalgamation ("embedding paths \n    " ++ word1 ++
                                                                                                                  "\nand\n    " ++ word2 ++ "\nmight be different"))
                                                                               Nothing -> do return Amalgamates 
                                                                       else return defaultDontKnow
                                                    Nothing -> do let cR = congR diag s si
                                                               -- 6. Check the restricted cell condition. If it holds then the
                                                               -- specification is correct. Otherwise proof obligations need to 
                                                               -- be generated.
                                                                  if hasCellCaslAmalgOpt opts
                                                                     then case subRelation cct cR of 
                                                                            Just _ -> do return defaultDontKnow -- TODO: generate proof obligations
                                                                            Nothing -> do return Amalgamates
                                                                     else return defaultDontKnow

