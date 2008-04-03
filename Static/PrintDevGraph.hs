{- |
Module      :  $Header$
Description :  pretty printing (parts of) a LibEnv
Copyright   :  (c) C. Maeder, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  non-portable(DevGraph)

pretty printing (parts of) a LibEnv
-}

module Static.PrintDevGraph
    ( printLibrary
    , prettyLibEnv
    , printTh
    , prettyHistElem
    , prettyHistory
    , showLEdge
    ) where

import Static.GTheory
import Static.DevGraph
import Static.DGToSpec

import Syntax.AS_Library (LIB_NAME, getLIB_ID)
import Syntax.Print_AS_Library ()

import Common.GlobalAnnotations
import Common.Id
import Common.Doc as Doc
import Common.DocUtils
import Common.Result
import Common.Keywords
import Common.ConvertGlobalAnnos
import Common.AnalyseAnnos
import qualified Common.Lib.Rel as Rel
import qualified Common.Lib.Graph as Tree

import Data.Graph.Inductive.Graph as Graph
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.List
import Data.Char (isAlpha)

printLibrary :: LibEnv -> (LIB_NAME, DGraph) -> Doc
printLibrary le (ln, DGraph { globalAnnos = ga, globalEnv = ge }) =
    keyword libraryS <+> pretty ln $+$
         foldr ($++$) Doc.empty
                   (map (uncurry $ printTheory le ln ga) $ Map.toList ge)

printTheory :: LibEnv -> LIB_NAME -> GlobalAnnos
            -> SIMPLE_ID -> GlobalEntry -> Doc
printTheory le ln ga sn ge = case ge of
    SpecEntry (ExtGenSig _ _ _ (NodeSig n _)) ->
        case maybeResult $ computeTheory le ln n of
            Nothing -> Doc.empty
            Just g -> printTh ga sn g
    _ -> Doc.empty

printTh :: GlobalAnnos -> SIMPLE_ID -> G_theory -> Doc
printTh oga sn g =
    let ga = removeProblematicListAnnos oga in
    useGlobalAnnos ga $ pretty ga $+$ prettyGTheorySL g $+$
    sep [keyword specS <+> sidDoc sn <+> equals, prettyGTheory g]

removeProblematicListAnnos :: GlobalAnnos -> GlobalAnnos
removeProblematicListAnnos ga = let
    is = Map.keysSet $ Rel.toMap $ prec_annos ga
    la = literal_annos ga
    nla = la { list_lit = Map.filterWithKey ( \ li _ ->
        let (op, cl, cs) = getListBrackets li in
          Set.null $ Set.filter ( \ (Id ts ics _) ->
              cs == ics && isPrefixOf op ts && isSuffixOf cl ts) is)
        $ list_lit la }
    Result _ (Just lm) = store_literal_map Map.empty $ c_lit_an nla
    in ga { literal_annos = nla
          , literal_map = lm }

-- * pretty instances

showNodeId :: Node -> String
showNodeId i = "node " ++ show i

instance Pretty NodeSig where
  pretty (NodeSig n sig) = fsep [ text (showNodeId n) <> colon, pretty sig ]

dgOriginSpec :: DGOrigin -> Maybe SIMPLE_ID
dgOriginSpec o = case o of
    DGSpecInst n -> Just n
    DGFitView n -> Just n
    DGFitViewA n -> Just n
    _ -> Nothing

dgOriginHeder :: DGOrigin -> String
dgOriginHeder o = case o of
    DGEmpty -> "empty-spec"
    DGBasic -> "basic-spec"
    DGExtension -> "extension"
    DGTranslation -> "translation"
    DGUnion -> "union"
    DGHiding -> "hiding"
    DGRevealing -> "revealing"
    DGRevealTranslation -> "translation part of a revealing"
    DGFree -> "free-spec"
    DGCofree -> "cofree-spec"
    DGLocal -> "local-spec"
    DGClosed -> "closed-spec"
    DGLogicQual -> "spec with logic qualifier"
    DGData -> "data-spec"
    DGFormalParams -> "formal parameters"
    DGImports -> "arch import"
    DGSpecInst _ -> "instantiation"
    DGFitSpec -> "fitting-spec"
    DGFitView _ -> "fitting-view"
    DGFitViewA _ -> "fitting view (actual parameters)"
    DGProof -> "proof-construct"
    DGintegratedSCC -> "OWL spec with integrated strongly connected components"

instance Pretty DGOrigin where
  pretty o = text (dgOriginHeder o) <+> pretty (dgOriginSpec o)

instance Pretty DGNodeInfo where
  pretty c = case c of
    DGNode {} -> pretty $ node_origin c
    DGRef {} ->
      pretty (getLIB_ID $ ref_libname c) <+> text (showNodeId $ ref_node c)

prettyDGNodeLab :: DGNodeLab -> Doc
prettyDGNodeLab l = sep [ text $ getDGNodeName l, pretty $ nodeInfo l]

instance Pretty DGNodeLab where
  pretty l = vcat
    [ text "Origin:" <+> pretty (nodeInfo l)
    , text $ if hasOpenGoals l then "locally empty" else "has open goals"
    , case dgn_nf l of
        Nothing -> Doc.empty
        Just n -> text "normal form:" <+> text (showNodeId n)
    , case dgn_sigma l of
        Nothing -> Doc.empty
        Just gm -> text "normal form inclusion:" $+$ pretty gm
    , case dgn_lock l of
        Nothing -> Doc.empty
        Just _ -> text "currently locked."
    , text "Local Theory:"
    , pretty $ dgn_theory l]

showEdgeId :: EdgeId -> String
showEdgeId (EdgeId i) = "edge " ++ show i

instance Pretty EdgeId where
   pretty (EdgeId i) = text $ show i

dgLinkOriginSpec :: DGLinkOrigin -> Maybe SIMPLE_ID
dgLinkOriginSpec o = case o of
    DGLinkSpecInst n -> Just n
    DGLinkView n -> Just n
    DGLinkFitView n -> Just n
    DGLinkFitViewImp n -> Just n
    DGLinkFitViewAImp n -> Just n
    _ -> Nothing

dgLinkOriginHeder :: DGLinkOrigin -> String
dgLinkOriginHeder o = case o of
    SeeTarget -> "see target"
    SeeSource -> "see source"
    DGLinkExtension -> "extension"
    DGLinkTranslation -> "OMDoc translation"
    DGLinkClosedLenv -> "closed spec (inclusion of local environment)"
    DGLinkImports -> "OWL import"
    DGLinkSpecInst _ -> "instantiation-link"
    DGLinkFitSpec -> "fitting-spec-link"
    DGLinkView _ -> "view"
    DGLinkFitView _ -> "fitting view to"
    DGLinkFitViewImp _ -> "fitting view (imports)"
    DGLinkFitViewAImp _ -> "fitting view (imports and actual parameters)"
    DGLinkProof -> "proof-link"

instance Pretty DGLinkOrigin where
  pretty o = text (dgLinkOriginHeder o) <+> pretty (dgLinkOriginSpec o)

-- | only shows the edge and node ids
showLEdge :: LEdge DGLinkLab -> String
showLEdge (s, t, l) = showEdgeId (dgl_id l)
  ++ " (" ++ showNodeId s ++ " --> " ++ show t ++ ")"

-- | only print the origin and some notion of the tye of the label
prettyDGLinkLab :: (DGLinkLab -> Doc) -> DGLinkLab -> Doc
prettyDGLinkLab f l = fsep
  [ case dgl_origin l of
      SeeTarget -> Doc.empty
      o -> pretty o
  , f l ]

-- | print short edge information
prettyLEdge :: LEdge DGLinkLab -> Doc
prettyLEdge e@(_, _, l) = fsep
  [ text $ showLEdge e
  , prettyDGLinkLab (text . getDGLinkType) l
  , prettyThmLinkStatus $ dgl_type l ]

dgRuleEdges :: DGRule -> [LEdge DGLinkLab]
dgRuleEdges r = case r of
    HideTheoremShift l -> [l]
    GlobDecomp l -> [l]
    LocDecomp l -> [l]
    LocInference l -> [l]
    GlobSubsumption l -> [l]
    Composition ls -> ls
    _ -> []

dgRuleHeader :: DGRule -> String
dgRuleHeader r = case r of
    GlobDecomp _ -> "Global-Decomposition"
    LocDecomp _ -> "Local-Decomposition"
    LocInference _ -> "Local-Inference"
    GlobSubsumption _ -> "Global-Subsumption"
    BasicInference _ _ -> "Basic-Inference"
    BasicConsInference _ _ -> "Basic-Cons-Inference"
    _ -> takeWhile isAlpha $ show r

instance Pretty DGRule where
  pretty r = let es = dgRuleEdges r in fsep
    [ text (dgRuleHeader r) <> if null es then Doc.empty else colon, case r of
    BasicInference c bp -> fsep
      [ text $ "using comorphism '" ++ show c ++ "' with proof tree:"
      , text $ show bp]
    BasicConsInference c bp -> fsep
      [ text $ "using comorphism '" ++ show c ++ "' with proof tree:"
      , text $ show bp]
    _ -> case es of
      [] -> Doc.empty
      [(_, _, l)] -> prettyDGLinkLab (const Doc.empty) l
      _ -> pretty $ Set.fromList $ map (\ (_, _, l) -> dgl_id l) es]

instance Pretty ThmLinkStatus where
  pretty tls = case tls of
        LeftOpen -> Doc.empty
        Proven r ls -> let s = proofBasis ls in
          fcat [parens (pretty r), if Set.null s then Doc.empty else pretty s]

dgLinkTypeHeader :: DGLinkType -> String
dgLinkTypeHeader = takeWhile isAlpha . show

prettyThmLinkStatus :: DGLinkType -> Doc
prettyThmLinkStatus = maybe Doc.empty pretty . thmLinkStatus

instance Pretty DGLinkType where
    pretty t = text (dgLinkTypeHeader t) <> prettyThmLinkStatus t

instance Pretty DGLinkLab where
  pretty l = vcat
    [ text "Origin:" <+> pretty (dgl_origin l)
    , text "Type:" <+> pretty (dgl_type l)
    , text "Signature Morphism:"
    , pretty $ dgl_morphism l]

-- | pretty print a labelled node
prettyGenLNode :: (a -> Doc) -> LNode a -> Doc
prettyGenLNode f (n, l) = fsep [text (showNodeId n) <> colon, f l]

prettyLNode :: LNode DGNodeLab -> Doc
prettyLNode = prettyGenLNode prettyDGNodeLab

dgChangeType :: DGChange -> String
dgChangeType c = case c of
    InsertNode _ -> "insert"
    DeleteNode _ -> "delete"
    InsertEdge _ -> "insert"
    DeleteEdge _ -> "delete"
    SetNodeLab _ _ -> "change"

instance Pretty DGChange where
  pretty c = text (dgChangeType c) <+> case c of
    InsertNode n -> prettyLNode n
    DeleteNode n -> prettyLNode n
    InsertEdge e -> prettyLEdge e
    DeleteEdge e -> prettyLEdge e
    SetNodeLab _ n -> prettyLNode n

prettyGr :: Tree.Gr DGNodeLab DGLinkLab -> Doc
prettyGr g = vcat (map (prettyLNode) $ labNodes g)
  $+$ vcat (map prettyLEdge $ labEdges g)

instance Pretty DGraph where
  pretty dg = vcat
    [ prettyGr $ dgBody dg
    , text "History"
    , prettyHistory $ proofHistory dg
    , text "Redoable History"
    , prettyHistory $ redoHistory dg
    , text "next edge:" <+> pretty (getNewEdgeId dg) ]

prettyHistElem :: ([DGRule], [DGChange]) -> Doc
prettyHistElem (rs, cs) =
  vcat $ (text "rules: " <+> ppWithCommas rs) : map pretty cs

prettyHistory :: ProofHistory -> Doc
prettyHistory = vcat . map prettyHistElem

prettyLibEnv :: LibEnv -> Doc
prettyLibEnv = printMap id vsep ($+$)
