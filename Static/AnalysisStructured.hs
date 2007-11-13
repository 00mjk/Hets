{- |
Module      :  $Header$
Description :  static analysis of heterogeneous structured specifications
Copyright   :  (c) Till Mossakowski and Uni Bremen 2003-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  :  till@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Grothendieck)

Static analysis of CASL (heterogeneous) structured specifications
   Follows the verfication semantic rules in Chap. IV:4.7
   of the CASL Reference Manual.
-}

module Static.AnalysisStructured
    ( ana_SPEC
    , isStructured
    , ana_RENAMING
    , ana_RESTRICTION
    , homogenizeGM
    , insGSig
    , insLink
    , extendMorphism
    ) where

import Driver.Options
import Logic.Logic
import Logic.ExtSign
import Logic.Coerce
import Logic.Comorphism
import Logic.Grothendieck
import Logic.Prover
import Static.DevGraph
import Static.GTheory
import Syntax.AS_Structured
import Common.Result
import Common.Id
import Common.ExtSign
import Common.AS_Annotation hiding (isAxiom, isDef)
import qualified Data.Set as Set
import qualified Data.Map as Map
import qualified Common.Lib.Rel as Rel(image, setInsert)
import Data.Graph.Inductive.Graph as Graph (Node)
import Common.DocUtils
import Data.Maybe
import Data.List (find)
import Control.Monad

insGTheory :: DGraph -> NODE_NAME -> DGOrigin -> G_theory -> (NodeSig, DGraph)
insGTheory dg name orig (G_theory lid sig ind sens tind) =
    let (sgMap, s) = sigMapI dg
        (tMap, t) = thMapI dg
        nind = if ind == 0 then s + 1 else ind
        tb = tind == 0 && not (Map.null sens)
        ntind = if tb then t + 1 else tind
        nsig = G_sign lid sig nind
        nth = G_theory lid sig nind sens ntind
        node_contents = newNodeLab name orig nth
        node = getNewNodeDG dg
    in (NodeSig node nsig,
        (if tb then setThMapDG $ Map.insert (t+1) nth tMap else id) $
        (if ind == 0 then setSigMapDG $ Map.insert (s+1) nsig sgMap else id)
         $ insNodeDG (node, node_contents) dg)

insGSig :: DGraph -> NODE_NAME -> DGOrigin -> G_sign -> (NodeSig, DGraph)
insGSig dg name orig (G_sign lid sig ind) =
    insGTheory dg name orig $ noSensGTheory lid sig ind

insLink :: DGraph -> GMorphism -> DGLinkType -> DGOrigin -> Node -> Node
        -> DGraph
insLink dg (GMorphism cid sign si mor mi) ty orig n t =
    let (sgMap, s) = sigMapI dg
        (mrMap, m) = morMapI dg
        nsi = if si == 0 then s + 1 else si
        nmi = if mi == 0 then m + 1 else mi
        nmor = GMorphism cid sign nsi mor nmi
        link = DGLink
          { dgl_morphism = nmor
          , dgl_type = ty
          , dgl_origin = orig
          , dgl_id = defaultEdgeID }
    in (if mi == 0 then setMorMapDG $ Map.insert (m+1)
         (toG_morphism nmor) mrMap else id) $
       (if si == 0 then setSigMapDG $ Map.insert (s+1)
        (G_sign (sourceLogic cid) sign nsi) sgMap else id)
       $ insLEdgeNubDG (n, t, link) dg

-- | analyze a SPEC
-- first Parameter determines if incoming symbols shall be ignored
-- options: here we need the info: shall only the structure be analysed?
ana_SPEC :: Bool -> LogicGraph -> DGraph -> MaybeNode -> NODE_NAME ->
            HetcatsOpts -> SPEC -> Result (SPEC, NodeSig, DGraph)
ana_SPEC addSyms lg dg nsig name opts sp = case sp of
  Basic_spec (G_basic_spec lid bspec) pos ->
    do G_sign lid' sigma' i1 <- return (getMaybeSig nsig)
       let adj = adjustPos pos
       sigma@(ExtSign sig sys) <-
           adj $ coerceSign lid' lid "Analysis of basic spec" sigma'
       (bspec', ExtSign sigma_complete sysd, ax) <- adj $
          if isStructured opts
           then return (bspec, mkExtSign $ empty_signature lid, [])
           else do b <- maybeToMonad
                          ("no basic analysis for logic "
                                         ++ language_name lid)
                          (basic_analysis lid)
                   b (bspec, sig, globalAnnos dg)
       let (ns@(NodeSig node gsig), dg') = insGTheory dg name DGBasic
             $ G_theory lid (ExtSign sigma_complete
               $ Set.intersection
                     (if addSyms then Set.union sys sysd else sysd)
               $ sym_of lid sigma_complete) 0 (toThSens ax) 0
       incl <- adj $ ginclusion lg (G_sign lid sigma i1) gsig
       return (Basic_spec (G_basic_spec lid bspec') pos, ns, case nsig of
              EmptyNode _ -> dg'
              JustNode (NodeSig n _) ->
                  insLink dg' incl GlobalDef DGExtension n node)
  EmptySpec pos -> case nsig of
      EmptyNode _ -> do
        warning () "empty spec" pos
        let (ns, dg') = insGSig dg name DGEmpty (getMaybeSig nsig)
        return (sp, ns, dg')
        {- ana_SPEC should be changed to return a MaybeNode!
           Then this duplicate dummy node could be avoided.
           Also empty unions could be treated then -}
      JustNode ns -> return (sp, ns ,dg)
  Translation asp ren ->
   do let sp1 = item asp
      (sp1', NodeSig n' gsigma, dg') <-
          ana_SPEC addSyms lg dg nsig (inc name) opts sp1
      mor <- ana_RENAMING lg nsig gsigma opts ren
      -- ??? check that mor is identity on local env
      let (ns@(NodeSig node _), dg'') =
            insGSig dg' name DGTranslation $ cod Grothendieck mor
           -- ??? too simplistic for non-comorphism inter-logic translations
      return (Translation (replaceAnnoted sp1' asp) ren, ns,
              insLink dg'' mor GlobalDef DGTranslation n' node)
  Reduction asp restr ->
   do let sp1 = item asp
      (sp1', NodeSig n' gsigma', dg') <-
          ana_SPEC addSyms lg dg nsig (inc name) opts sp1
      let gsigma = getMaybeSig nsig
      (hmor, tmor) <- ana_RESTRICTION gsigma gsigma' opts restr
      -- we treat hiding and revealing differently
      -- in order to keep the dg as simple as possible
      case tmor of
       Nothing ->
        do let (ns@(NodeSig node _), dg'') =
                   insGSig dg' name DGHiding $ dom Grothendieck hmor
           -- ??? too simplistic for non-comorphism inter-logic reductions
           return (Reduction (replaceAnnoted sp1' asp) restr, ns,
                   insLink dg'' hmor HidingDef DGHiding n' node)
       Just tmor' -> do
        let gsigma1 = dom Grothendieck tmor'
            gsigma'' = cod Grothendieck tmor'
           -- ??? too simplistic for non-comorphism inter-logic reductions
        -- the case with identity translation leads to a simpler dg
        if tmor' == ide Grothendieck (dom Grothendieck tmor')
         then do
           let (ns@(NodeSig node1 _), dg'') =
                   insGSig dg' name DGRevealing gsigma1
           return (Reduction (replaceAnnoted sp1' asp) restr, ns,
                   insLink dg'' hmor HidingDef DGRevealing n' node1)
         else do
           let (NodeSig node1 _, dg'') =
                   insGSig dg' (extName "T" name) DGRevealing gsigma1
               (ns@(NodeSig node2 _), dg3) =
                   insGSig dg'' name DGRevealTranslation gsigma''
               dg4 = insLink dg3 hmor HidingDef DGRevealing n' node1
           return (Reduction (replaceAnnoted sp1' asp) restr, ns,
                   insLink dg4 tmor' GlobalDef DGRevealTranslation node1 node2)
  Union [] pos -> adjustPos pos $ fail $ "empty union"
  Union asps pos ->
   do let sps = map item asps
      (sps', nsigs, dg', _) <-
          let ana (sps1, nsigs, dg', n) sp' = do
                (sp1, nsig', dg1) <- ana_SPEC addSyms lg dg' nsig n opts sp'
                return (sp1 : sps1, nsig' : nsigs, dg1, inc n)
           in foldM ana ([], [], dg, extName "U" name) sps
      let nsigs' = reverse nsigs
          adj = adjustPos pos
      gbigSigma <- adj $ gsigManyUnion lg (map getSig nsigs')
      let (ns@(NodeSig node _), dg2) = insGSig dg' name DGUnion gbigSigma
          insE dgl (NodeSig n gsigma) = do
            incl <- adj $ ginclusion lg gsigma gbigSigma
            return $ insLink dgl incl GlobalDef DGUnion n node
      dg3 <- foldM insE dg2 nsigs'
      return (Union (map (uncurry replaceAnnoted)
                         (zip (reverse sps') asps))
                    pos, ns, dg3)
  Extension asps pos -> do
   (sps', nsig1', dg1, _, _, _, _) <-
       foldM ana_Extension ([], nsig, dg, lg, opts, pos, addSyms) namedSps
   case nsig1' of
       EmptyNode _ -> fail "empty extension"
       JustNode nsig1 -> return (Extension (map (uncurry replaceAnnoted)
                          (zip (reverse sps') asps))
                                 pos, nsig1,dg1)
   where
   namedSps = zip (reverse (name: tail (take (length asps)
                                         (iterate inc (extName "E" name)))))
                   asps
  Free_spec asp poss -> do
      (nasp, nsig', dg') <-
          anaPlainSpec addSyms lg opts dg nsig name DGFree (FreeDef nsig)
          asp poss
      return (Free_spec nasp poss, nsig', dg')
  Cofree_spec asp poss -> do
      (nasp, nsig', dg') <-
          anaPlainSpec addSyms lg opts dg nsig name DGCofree (CofreeDef nsig)
          asp poss
      return (Cofree_spec nasp poss, nsig', dg')
  Local_spec asp asp' poss ->
   do let sp1 = item asp
          sp1' = item asp'
      (sp2, nsig'@(NodeSig _ (G_sign lid' sigma' _)), dg') <-
          ana_SPEC False lg dg nsig (extName "L" name) opts sp1
      (sp2', NodeSig n'' (G_sign lid'' sigma'' _), dg'') <-
          ana_SPEC False lg dg' (JustNode nsig') (inc name) opts sp1'
      let gsigma = getMaybeSig nsig
      G_sign lid sigma _ <- return gsigma
      sigma1 <- coerceSign lid' lid "Analysis of local spec" sigma'
      sigma2 <- coerceSign lid'' lid "Analysis of local spec" sigma''
      let sys = ext_sym_of lid sigma
          sys1 = ext_sym_of lid sigma1
          sys2 = ext_sym_of lid sigma2
      mor3 <- if isStructured opts then return (ext_ide lid sigma2)
               else adjustPos poss $ ext_cogenerated_sign lid
                      (sys1 `Set.difference` sys) sigma2
      let sigma3 = dom lid mor3
          -- gsigma2 = G_sign lid sigma2
          gsigma3 = G_sign lid (makeExtSign lid sigma3) 0
          sys3 = sym_of lid sigma3
      when (not( isStructured opts ||
                 sys2 `Set.difference` sys1 `Set.isSubsetOf` sys3))
        $ plain_error () (
          "illegal use of locally declared symbols: "
          ++ showDoc ((sys2 `Set.intersection` sys1) `Set.difference` sys3) "")
         poss
      let (ns@(NodeSig node _), dg2) = insGSig dg'' name DGLocal gsigma3
      return (Local_spec (replaceAnnoted sp2 asp)
                         (replaceAnnoted sp2' asp')
                         poss, ns,
              insLink dg2 (gEmbed2 gsigma3 $ mkG_morphism lid mor3)
                  HidingDef DGLocal n'' node)
  Closed_spec asp pos ->
   do let sp1 = item asp
          l = getLogic nsig
      -- analyse spec with empty local env
      (sp', NodeSig n' gsigma', dg') <-
          ana_SPEC False lg dg (EmptyNode l) (inc name) opts sp1
      let gsigma = getMaybeSig nsig
          adj = adjustPos pos
      gsigma'' <- adj $ gsigUnion lg gsigma gsigma'
      let (ns@(NodeSig node gsigma2), dg2) = insGSig dg' name DGClosed gsigma''
      incl1 <- adj $ ginclusion lg gsigma gsigma2
      incl2 <- adj $ ginclusion lg gsigma' gsigma2
      let dg3 = insLink dg2 incl2 GlobalDef DGClosed n' node
      return (Closed_spec (replaceAnnoted sp' asp) pos, ns, case nsig of
            EmptyNode _ -> dg3
            JustNode (NodeSig n _) ->
                insLink dg3 incl1 GlobalDef DGClosedLenv n node)
  Qualified_spec lognm@(Logic_name ln _) asp pos -> do
      let newLG = lg { currentLogic = tokStr ln }
      l <- lookupCurrentLogic "Qualified_spec" newLG
      let newNSig = case nsig of
            EmptyNode _ -> EmptyNode l
            _ -> nsig
      (nasp, nsig', dg') <-
          anaPlainSpec addSyms lg opts dg newNSig name DGLogicQual GlobalDef
          asp pos
      return (Qualified_spec lognm nasp pos, nsig', dg')
  Group asp pos -> do
      (sp', nsig', dg') <- ana_SPEC addSyms lg dg nsig name opts (item asp)
      return (Group (replaceAnnoted sp' asp) pos, nsig', dg')
  Spec_inst spname afitargs pos0 -> let
       pos = if null afitargs then tokPos spname else pos0
       adj = adjustPos pos
       spstr = tokStr spname
    in case lookupGlobalEnvDG spname dg of
    Just (SpecEntry gs@(imps, params, _, body@(NodeSig nB gsigmaB))) ->
     case (\ x y -> (x , x - y)) (length afitargs) (length params) of
      -- the case without parameters leads to a simpler dg
      (0, 0) -> do
       gsigma <- adj $ gsigUnion lg (getMaybeSig nsig) gsigmaB
       let (fsig@(NodeSig node gsigma'), dg2) =
               insGSig dg name (DGSpecInst spname) gsigma
       incl <- adj $ ginclusion lg gsigmaB gsigma'
       let dg3 = insLink dg2 incl GlobalDef (DGSpecInst spname) nB node
       case nsig of
         -- the subcase with empty local env leads to an even simpler dg
         EmptyNode _ ->
          -- if the node shall not be named and the logic does not change,
          if isInternal name && langNameSig gsigma' == langNameSig gsigmaB
            -- then just return the body
           then return (sp, body, dg)
            -- otherwise, we need to create a new one
           else return (sp, fsig, dg3)
         -- the subcase with nonempty local env
         JustNode (NodeSig n sigma) -> do
           incl2 <- adj $ ginclusion lg sigma gsigma'
           return (sp, fsig,
                   insLink dg3 incl2 GlobalDef (DGSpecInst spname) n node)
      -- now the case with parameters
      (_, 0) -> do
       let fitargs = map item afitargs
       (fitargs', dg', args, _) <- adj $ foldM (anaFitArg lg opts spname imps)
           ([], dg, [], extName "A" name) (zip params fitargs)
       let actualargs = reverse args
       (gsigma', morDelta) <- adj $ apply_GS lg gs actualargs
       gsigmaRes <- adj $ gsigUnion lg (getMaybeSig nsig) gsigma'
       let (ns@(NodeSig node gsigmaRes'), dg2) =
               insGSig dg' name (DGSpecInst spname) gsigmaRes
       incl1 <- adj $ ginclusion lg (getMaybeSig nsig) gsigmaRes'
       incl2 <- adj $ ginclusion lg gsigma' gsigmaRes'
       morDelta' <- comp Grothendieck (gEmbed morDelta) incl2
       let dg3 = insLink dg2 morDelta' GlobalDef (DGSpecInst spname) nB node
           dg4 = case nsig of
             EmptyNode _ -> dg3
             JustNode (NodeSig n _) ->
                 insLink dg3 incl1 GlobalDef (DGSpecInst spname) n node
       dg5 <- foldM (parLink lg DGFitSpec gsigmaRes' node) dg4
              $ map snd args
       return (Spec_inst spname
                         (map (uncurry replaceAnnoted)
                              (zip (reverse fitargs') afitargs))
                         pos, ns, dg5)
 -- finally the case with conflicting numbers of formal and actual parameters
      _ ->
        fatal_error
          (spstr ++ " expects " ++ show (length params) ++ " arguments"
           ++ " but was given " ++ show (length afitargs)) pos
    _ -> fatal_error
                 ("Structured specification " ++ spstr ++ " not found") pos
  Data (Logic lidD) (Logic lidP) asp1 asp2 pos -> do
      let sp1 = item asp1
          sp2 = item asp2
          adj = adjustPos pos
      Comorphism cid <- adj $ logicInclusion lg (Logic lidD) (Logic lidP)
      let lidD' = sourceLogic cid
          lidP' = targetLogic cid
      (sp1', NodeSig n' (G_sign lid' sigma' _), dg') <-
         ana_SPEC False lg dg (EmptyNode (Logic lidD)) (inc name) opts sp1
      sigmaD <- adj $ coerceSign lid' lidD' "Analysis of data spec" sigma'
      (sigmaD',sensD') <- adj $ ext_map_sign cid sigmaD
      let (nsig2@(NodeSig node _), dg1) = insGTheory dg' name DGData
            $ G_theory lidP' sigmaD' 0 (toThSens sensD') 0
          dg2 = insLink dg1 (GMorphism cid sigmaD 0
                             (ext_ide lidP' sigmaD') 0)
                GlobalDef DGData n' node
      (sp2', nsig3, dg3) <-
          ana_SPEC addSyms lg dg2 (JustNode nsig2) name opts sp2
      return (Data (Logic lidD) (Logic lidP)
                   (replaceAnnoted sp1' asp1)
                   (replaceAnnoted sp2' asp2)
                   pos, nsig3, dg3)

anaPlainSpec :: Bool -> LogicGraph -> HetcatsOpts -> DGraph -> MaybeNode
             -> NODE_NAME -> DGOrigin -> DGLinkType -> Annoted SPEC -> Range
             -> Result (Annoted SPEC, NodeSig, DGraph)
anaPlainSpec addSyms lg opts dg nsig name orig dglType asp pos = do
      (sp', NodeSig n' gsigma, dg') <-
          ana_SPEC addSyms lg dg nsig (inc name) opts $ item asp
      let (ns@(NodeSig node gsigma'), dg2) = insGSig dg' name orig gsigma
      incl <- adjustPos pos $ ginclusion lg (getMaybeSig nsig) gsigma'
      return (replaceAnnoted sp' asp, ns,
              insLink dg2 incl dglType orig n' node)

anaFitArg :: LogicGraph -> HetcatsOpts -> SPEC_NAME -> MaybeNode
          -> ([FIT_ARG], DGraph, [(G_morphism, NodeSig)], NODE_NAME)
          -> (NodeSig, FIT_ARG)
          -> Result ([FIT_ARG], DGraph, [(G_morphism, NodeSig)], NODE_NAME)
anaFitArg lg opts spname imps (fas', dg1, args, name') (nsig', fa) = do
    (fa', dg', arg) <- ana_FIT_ARG lg dg1 spname imps nsig' opts name' fa
    return (fa' : fas', dg', arg : args , inc name')

parLink :: LogicGraph -> DGOrigin -> G_sign -> Node -> DGraph -> NodeSig
        -> Result DGraph
parLink lg orig gsigma' node dg (NodeSig nA_i sigA_i)= do
    incl <- ginclusion lg sigA_i gsigma'
    return $ insLink dg incl GlobalDef orig nA_i node

-- analysis of renamings
ana_ren :: LogicGraph -> HetcatsOpts -> MaybeNode -> Range -> GMorphism
        -> G_mapping -> Result GMorphism
ana_ren lg opts lenv pos gmor@(GMorphism r sigma ind1 mor _) gmap =
  case gmap of
  G_symb_map (G_symb_map_items_list lid sis) ->
    if isStructured opts then return gmor else do
      let lid2 = targetLogic r
      sis1 <- coerceSymbMapItemsList lid lid2 "Analysis of renaming" sis
      rmap <- stat_symb_map_items lid2 sis1
      mor1 <- induced_from_morphism lid2 rmap (cod lid2 mor)
      case lenv of
        EmptyNode _ -> return ()
        JustNode (NodeSig _ (G_sign lidLenv sigmaLenv _)) -> do
          -- needs to be changed for logic translations
          sigmaLenv' <- coerceSign lidLenv lid2
            "Analysis of renaming: logic translations not properly handeled"
            sigmaLenv
          let sysLenv = ext_sym_of lid2 sigmaLenv'
              m = symmap_of lid2 mor1
              isChanged sy = case Map.lookup sy m of
                Just sy' -> sy /= sy'
                Nothing -> False
              forbiddenSys = Set.filter isChanged sysLenv
          when (not $ Set.null forbiddenSys) $ plain_error () (
           "attempt to rename the following symbols from " ++
           "the local environment:\n" ++ showDoc forbiddenSys "") pos
      mor2 <- comp lid2 mor mor1
      return $ GMorphism r sigma ind1 mor2 0
  G_logic_translation (Logic_code tok src tar pos1) -> do
    let adj = adjustPos pos1
    G_sign srcLid srcSig ind<- return (cod Grothendieck gmor)
    c <- adj $ case tok of
            Just ctok -> do
               Comorphism cid <- lookupComorphism (tokStr ctok) lg
               when (isJust src && getLogicStr (fromJust src) /=
                                    language_name (sourceLogic cid))
                    (fail (getLogicStr (fromJust src) ++
                           "is not the source logic of "
                           ++ language_name cid))
               when (isJust tar && getLogicStr (fromJust tar) /=
                                    language_name (targetLogic cid))
                    (fail (getLogicStr (fromJust tar) ++
                           "is not the target logic of "
                           ++ language_name cid))
               return (Comorphism cid)
            Nothing -> case tar of
               Just (Logic_name l _) -> do
                 tarL <- lookupLogic "with logic: " (tokStr l) lg
                 logicInclusion lg (Logic srcLid) tarL
               Nothing -> fail "with logic: cannot determine comorphism"
    mor1 <- adj $ gEmbedComorphism c (G_sign srcLid srcSig ind)
    adj $ comp Grothendieck gmor mor1
    where getLogicStr (Logic_name l _) = tokStr l

ana_RENAMING :: LogicGraph -> MaybeNode -> G_sign -> HetcatsOpts -> RENAMING
             -> Result GMorphism
ana_RENAMING lg lenv gSigma opts (Renaming ren pos) =
      foldM (ana_ren lg opts lenv pos) (ide Grothendieck gSigma) ren

-- analysis of restrictions
ana_restr :: G_sign -> Range -> GMorphism -> G_hiding -> Result GMorphism
ana_restr (G_sign lidLenv sigmaLenv _) pos
              (GMorphism cid (ExtSign sigma1 sys1) _ mor _) gh =
    case gh of
      G_symb_list (G_symb_items_list lid' sis') -> do
        let lid1 = sourceLogic cid
            lid2 = targetLogic cid
        sis1 <- coerceSymbItemsList lid' lid1 "Analysis of restriction" sis'
        rsys <- stat_symb_items lid1 sis1
        let sys = sym_of lid1 sigma1
            sys' = Set.filter (\ sy -> any (matches lid1 sy) rsys) sys
            unmatched = filter ( \ rsy -> Set.null $ Set.filter
                                 ( \ sy -> matches lid1 sy rsy) sys') rsys
        when (not $ null unmatched)
          $ plain_error () ("attempt to hide unknown symbols:\n"
                          ++ showDoc unmatched "") pos
        -- needs to be changed when logic projections are implemented
        sigmaLenv' <- coerceSign lidLenv lid1
          "Analysis of restriction: logic projections not properly handeled"
          sigmaLenv
        let sysLenv = ext_sym_of lid1 sigmaLenv'
            forbiddenSys = sys' `Set.intersection` sysLenv
        when (not $ Set.null forbiddenSys)
          $ plain_error () (
         "attempt to hide the following symbols from the local environment:\n"
         ++ showDoc forbiddenSys "") pos
        mor1 <- cogenerated_sign lid1 sys' sigma1
        mor1' <- map_morphism cid mor1
        mor2 <- comp lid2 mor1' mor
        return $ GMorphism cid (ExtSign (dom lid1 mor1) $ Set.fold (\ sy ->
          case Map.lookup sy $ symmap_of lid1 mor1 of
            Nothing -> id
            Just sy1 -> Set.insert sy1) Set.empty sys1) 0 mor2 0
      G_logic_projection (Logic_code _tok _src _tar pos1) ->
        fatal_error "no analysis of logic projections yet" pos1

ana_RESTRICTION :: G_sign -> G_sign -> HetcatsOpts -> RESTRICTION
       -> Result (GMorphism, Maybe GMorphism)
ana_RESTRICTION gSigma@(G_sign lid sigma _)
    gSigma'@(G_sign lid' sigma' _) opts restr =
  if isStructured opts then return (ide Grothendieck gSigma, Nothing) else
  case restr of
    Hidden rstr pos -> do
      mor <- foldM (ana_restr gSigma pos) (ide Grothendieck gSigma') rstr
      return (mor, Nothing)
    Revealed (G_symb_map_items_list lid1 sis) pos -> do
     let sys = ext_sym_of lid sigma -- local env
         sys' = ext_sym_of lid' sigma' -- "big" signature
         adj = adjustPos pos
     sis' <- adj $ coerceSymbMapItemsList lid1 lid'
            "Analysis of restriction" sis
     rmap <- adj $ stat_symb_map_items lid' sis'
     let sys'' =
          Set.fromList
           [sy | sy <- Set.toList sys', rsy <-
                       Map.keys rmap, matches lid' sy rsy]
          -- domain of rmap intersected with sys'
          -- domain of rmap should be checked to match symbols from sys' ???
     sys1 <- adj $ coerceSymbolSet lid lid' "Analysis of restriction" sys
        -- ??? this is too simple in case that local env is translated
        -- to a different logic
     mor1 <- adj $ ext_generated_sign lid' (sys1 `Set.union` sys'') sigma'
     mor2 <- adj $ induced_from_morphism lid' rmap (dom lid' mor1)
     return (gEmbed (mkG_morphism lid' mor1),
             Just (gEmbed (mkG_morphism lid' mor2)))

ana_FIT_ARG :: LogicGraph -> DGraph -> SPEC_NAME -> MaybeNode
            -> NodeSig -> HetcatsOpts -> NODE_NAME -> FIT_ARG
            -> Result (FIT_ARG, DGraph, (G_morphism,NodeSig))
ana_FIT_ARG lg dg spname nsigI (NodeSig nP gsigmaP@(G_sign lidP sigmaP _))
    opts name fv = case fv of
  Fit_spec asp gsis pos -> do
   let adj = adjustPos pos
   (sp', nsigA@(NodeSig nA (G_sign lidA sigmaA _)), dg') <-
       ana_SPEC False lg dg nsigI name opts (item asp)
   G_symb_map_items_list lid sis <- homogenizeGM (Logic lidP) gsis
   sigmaA' <- adj $ coerceSign lidA lidP "Analysis of fitting argument" sigmaA
   mor <- adj $ if isStructured opts then return (ext_ide lidP sigmaP)
           else do
             rmap <- stat_symb_map_items lid sis
             rmap' <- if null sis then return Map.empty
                      else coerceRawSymbolMap lid lidP
                               "Analysis of fitting argument" rmap
             let noMatch sig r = Set.null $ Set.filter
                   (\ s -> matches lidP s r) $ ext_sym_of lidP sig
                 unknowns = filter (noMatch sigmaP) (Map.keys rmap')
                   ++ filter (noMatch sigmaA') (Map.elems rmap')
             if null unknowns then
               ext_induced_from_to_morphism lidP rmap' sigmaP sigmaA'
               else fatal_error ("unknown symbols " ++ showDoc unknowns "") pos
   {-
   let symI = sym_of lidP sigmaI'
       symmap_mor = symmap_of lidP mor
   -- are symbols of the imports left untouched?
   if Set.all (\sy -> lookupFM symmap_mor sy == Just sy) symI
    then return ()
    else plain_error () "Fitting morphism must not affect import" pos
   -} -- ??? does not work
      -- ??? also output some symbol that is affected
   let gmor = mkG_morphism lidP mor
   return (Fit_spec (replaceAnnoted sp' asp) gsis pos,
          insLink dg' (gEmbed gmor) (GlobalThm LeftOpen None LeftOpen)
             (DGSpecInst spname) nP nA, (gmor, nsigA))
  Fit_view vn afitargs pos -> let
       adj = adjustPos pos
       spstr = tokStr spname
    in case lookupGlobalEnvDG vn dg of
    Just (ViewEntry (src, mor, gs@(imps, params, _, target))) -> do
     let nSrc = getNode src
         nTar = getNode target
         gsigmaS = getSig src
         gsigmaT = getSig target
         gsigmaI = getMaybeSig nsigI
     GMorphism cid _ _ morHom ind <- return mor
     let lid = targetLogic cid
     when (not (language_name (sourceLogic cid) == language_name lid))
          (fatal_error
                 "heterogeneous fitting views not yet implemented"
                 pos)
     case (\ x y -> (x, x - y)) (length afitargs) (length params) of
      -- the case without parameters leads to a simpler dg
      (0, 0) -> case nsigI of
         -- the subcase with empty import leads to a simpler dg
         EmptyNode _ ->
           return (fv, insLink dg (ide Grothendieck gsigmaP)
                  (GlobalThm LeftOpen None LeftOpen) (DGFitView spname)
                   nP nSrc, (G_morphism lid morHom ind, target))
         -- the subcase with nonempty import
         JustNode (NodeSig nI _) -> do
           gsigmaIS <- adj $ gsigUnion lg gsigmaI gsigmaS
           when (not (isSubGsign lg gsigmaP gsigmaIS))
             (plain_error ()
              ("Parameter does not match source of fittig view. "
               ++ "Parameter signature:\n"
               ++ showDoc gsigmaP
               "\nSource signature of fitting view (united with import):\n"
               ++ showDoc gsigmaIS "") pos)
           G_sign lidI sigI1 _<- return gsigmaI
           sigI <- adj $ coerceSign lidI lid
                    "Analysis of instantiation with import" sigI1
           mor_I <- adj $ morphism_union lid morHom $ ext_ide lid sigI
           gsigmaA <- adj $ gsigUnion lg gsigmaI gsigmaT
           incl1 <- adj $ ginclusion lg gsigmaI gsigmaA
           incl2 <- adj $ ginclusion lg gsigmaT gsigmaA
           incl3 <- adj $ ginclusion lg gsigmaI gsigmaP
           incl4 <- adj $ ginclusion lg gsigmaS gsigmaP
           let (ns@(NodeSig nA _), dg1) =
                   insGSig dg name (DGFitViewA spname) gsigmaA
               (NodeSig n' _, dg2) =
                   insGSig dg1 (inc name) (DGFitView spname) gsigmaP
               dg3 = insLink dg2 incl1 GlobalDef (DGFitViewAImp spname) nI nA
               dg4 = insLink dg3 incl3 GlobalDef (DGFitViewImp spname) nI n'
               dg5 = insLink dg4 incl2 GlobalDef (DGFitViewA spname) nTar nA
               dg6 = insLink dg5 incl4 GlobalDef (DGFitView spname) nSrc n'
               dg7 = insLink dg6 (ide Grothendieck gsigmaP)
                 (GlobalThm LeftOpen None LeftOpen) (DGFitView spname) nP n'
           return (fv, dg7, (mkG_morphism lid mor_I, ns))
      -- now the case with parameters
      (_, 0) -> do
       let fitargs = map item afitargs
       (fitargs', dg', args,_) <- foldM (anaFitArg lg opts spname imps)
           ([], dg, [], extName "A" name) (zip params fitargs)
       let actualargs = reverse args
       (gsigmaA,mor_f) <- adj $ apply_GS lg gs actualargs
       let gmor_f = gEmbed mor_f
       gsigmaRes <- adj $ gsigUnion lg gsigmaI gsigmaA
       mor1 <- adj $ comp Grothendieck mor gmor_f
       incl1 <- adj $ ginclusion lg gsigmaA gsigmaRes
       mor' <- adj $ comp Grothendieck gmor_f incl1
       GMorphism cid1 _ _ mor1Hom _<- return mor1
       let lid1 = targetLogic cid1
       when (not (language_name (sourceLogic cid1) == language_name lid1))
            (fatal_error
                   ("heterogeneous fitting views not yet implemented")
                   pos)
       G_sign lidI sigI1 _<- return gsigmaI
       sigI <- adj $ coerceSign lidI lid1
               "Analysis of instantiation with parameters" sigI1
       theta <- adj $ morphism_union lid1 mor1Hom (ext_ide lid1 sigI)
       incl2 <- adj $ ginclusion lg gsigmaI gsigmaRes
       incl3 <- adj $ ginclusion lg gsigmaI gsigmaP
       incl4 <- adj $ ginclusion lg gsigmaS gsigmaP
       let (ns@(NodeSig nA _), dg1) =
                   insGSig dg' name (DGFitViewA spname) gsigmaRes
           (NodeSig n' _, dg2) =
                   insGSig dg1 (extName "V" name) (DGFitView spname) gsigmaP
       dg3 <- foldM (parLink lg (DGFitView spname) gsigmaRes nA) dg2
              $ map snd args
       let dg4 = case nsigI of
              EmptyNode _ -> dg3
              JustNode (NodeSig nI _) -> let
                dg3a = insLink dg3 incl2 GlobalDef (DGFitViewAImp spname) nI nA
                in insLink dg3a incl3 GlobalDef (DGFitViewImp spname) nI n'
           dg5 = insLink dg4 mor' GlobalDef (DGFitViewA spname) nTar nA
           dg6 = insLink dg5 incl4 GlobalDef (DGFitView spname) nSrc n'
           dg7 = insLink dg6 (ide Grothendieck gsigmaP)
             (GlobalThm LeftOpen None LeftOpen) (DGFitView spname) nP n'
       return (Fit_view vn
                        (map (uncurry replaceAnnoted)
                             (zip (reverse fitargs') afitargs))
                        pos, dg7, (mkG_morphism lid1 theta, ns))
-- finally the case with conflicting numbers of formal and actual parameters
      _ ->
        fatal_error
          (spstr ++ " expects " ++ show (length params) ++ " arguments"
           ++ " but was given " ++ show (length afitargs)) pos
    _ -> fatal_error
                 ("View " ++ tokStr vn ++ " not found") pos

-- Extension of signature morphisms (for instantitations)
-- first some auxiliary functions

mapID :: Map.Map Id (Set.Set Id) -> Id -> Result Id
mapID idmap i@(Id toks comps pos1) =
  case Map.lookup i idmap of
    Nothing -> do
      compsnew <- sequence $ map (mapID idmap) comps
      return (Id toks compsnew pos1)
    Just ids -> if Set.null ids then return i else
      if Set.null $ Set.deleteMin ids then return $ Set.findMin ids else
         plain_error i
             ("Identifier component " ++ showId i
              " can be mapped in various ways:\n"
              ++ showDoc ids "") $ getRange i

extID1 :: Map.Map Id (Set.Set Id) -> Id
              -> Result (EndoMap Id) -> Result (EndoMap Id)
extID1 idmap i@(Id toks comps pos1) m = do
  m1 <- m
  compsnew <- sequence $ map (mapID idmap) comps
  if comps==compsnew
   then return m1
   else return (Map.insert i (Id toks compsnew pos1) m1)

extID :: Set.Set Id -> Map.Map Id (Set.Set Id) -> Result (EndoMap Id)
extID ids idmap = Set.fold (extID1 idmap) (return Map.empty) ids

extendMorphism :: G_sign      -- ^ formal parameter
               -> G_sign      -- ^ body
               -> G_sign      -- ^ actual parameter
               -> G_morphism  -- ^ fitting morphism
               -> Result(G_sign,G_morphism)
extendMorphism (G_sign lid sigmaP _) (G_sign lidB sigmaB1 _)
    (G_sign lidA sigmaA1 _) (G_morphism lidM fittingMor1 _) = do
  -- for now, only homogeneous instantiations....
  sigmaB@(ExtSign _ sysB) <-
      coerceSign lidB lid "Extension of symbol map" sigmaB1
  sigmaA <- coerceSign lidA lid "Extension of symbol map" sigmaA1
  fittingMor <- coerceMorphism lidM lid "Extension of symbol map" fittingMor1
  let symsP = ext_sym_of lid sigmaP
      symsB = ext_sym_of lid sigmaB
      idsB = Set.map (sym_name lid) symsB
      h = symmap_of lid fittingMor
      symbMapToRawSymbMap =
          Map.foldWithKey (\sy1 sy2 -> Map.insert (symbol_to_raw lid sy1)
                                                  (symbol_to_raw lid sy2))
                          Map.empty
      rh = symbMapToRawSymbMap h
      idh = Map.foldWithKey
             (\sy1 sy2 -> Rel.setInsert (sym_name lid sy1) (sym_name lid sy2))
             Map.empty h
  idhExt <- extID idsB idh
  let rIdExt = Map.foldWithKey (\id1 id2 -> Map.insert
                                (id_to_raw lid id1) (id_to_raw lid id2))
                Map.empty
                (foldr (\i -> Map.delete i) idhExt $ Map.keys idh)
      r = rh `Map.union` rIdExt
      -- do we need combining function catching the clashes???
  mor <- ext_induced_from_morphism lid r sigmaB
  let hmor = symmap_of lid mor
      sigmaAD = ExtSign (cod lid mor) $ Set.map (\ sy ->
        Map.findWithDefault sy sy $ symmap_of lid mor) sysB
  sigma <- ext_final_union lid sigmaA sigmaAD
  let illShared = (ext_sym_of lid sigmaA `Set.intersection`
                              ext_sym_of lid sigmaAD )
                   Set.\\ Rel.image h symsP
  when (not (Set.null illShared))
   (plain_error () ("Symbols shared between actual parameter and body"
                     ++ "\nmust be in formal parameter:\n"
                     ++ showDoc illShared "") nullRange)
  let myKernel m = Set.fromDistinctAscList $ comb1 $ Map.toList m
      comb1 [] = []
      comb1 (p : qs) =
           comb2 p qs [] ++ comb1 qs
      comb2 _ [] rs = rs
      comb2 p@(a, b) ((c, d) : qs) rs =
          comb2 p qs $ if b == d then (a, c) : rs else rs
      newIdentifications = myKernel hmor Set.\\ myKernel h
  when (not (Set.null newIdentifications))
   (plain_error () (
     "Fitting morphism leads to forbidden identifications:\n"
     ++ showDoc newIdentifications "") nullRange)
  incl <- ext_inclusion lid sigmaAD sigma
  mor1 <- comp lid mor incl
  return (G_sign lid sigma 0, mkG_morphism lid mor1)

apply_GS :: LogicGraph -> ExtGenSig -> [(G_morphism,NodeSig)]
             -> Result(G_sign,G_morphism)
apply_GS lg (nsigI, _, gsigmaP, nsigB) args = do
  let mor_i = map fst args
      gsigmaA_i = map (getSig . snd) args
      gsigmaB = getSig nsigB
      gsigmaI = getMaybeSig nsigI
  G_sign lidI sigmaI _<- return gsigmaI
  let idI = ext_ide lidI sigmaI
  gsigmaA <- gsigManyUnion lg gsigmaA_i
  mor_f <- homogeneousMorManyUnion (mkG_morphism lidI idI : mor_i)
  extendMorphism gsigmaP gsigmaB gsigmaA mor_f

homogenizeGM :: AnyLogic -> [Syntax.AS_Structured.G_mapping]
             -> Result G_symb_map_items_list
homogenizeGM (Logic lid) gsis =
  foldM homogenize1 (G_symb_map_items_list lid []) gsis
  where
  homogenize1 itl2@(G_symb_map_items_list lid2 sis) sm = case sm of
    Syntax.AS_Structured.G_symb_map (G_symb_map_items_list lid1 sis1) -> do
         sis1' <- coerceSymbMapItemsList lid1 lid2 "" sis1
         return $ G_symb_map_items_list lid2 $ sis ++ sis1'
    _ -> return itl2

-- | check if structured analysis should be performed
isStructured :: HetcatsOpts -> Bool
isStructured a = case analysis a of
    Structured -> True
    _ -> False

-- only consider addSyms for the first spec
ana_Extension
    :: ([SPEC], MaybeNode, DGraph, LogicGraph, HetcatsOpts, Range, Bool)
    -> (NODE_NAME, Annoted SPEC)
    -> Result ([SPEC], MaybeNode, DGraph, LogicGraph, HetcatsOpts, Range, Bool)
ana_Extension (sps', nsig', dg', lg, opts, pos, addSyms) (name',asp') = do
  (sp1', nsig1@(NodeSig n1 sig1), dg1) <-
     ana_SPEC addSyms lg dg' nsig' name' opts (item asp')
  let anno = find isSemanticAnno $ l_annos asp'
  -- is the extension going between real nodes?
  dg2 <- case (anno, nsig') of
     (Just anno0@(Semantic_anno anno1 _), JustNode (NodeSig n' sig')) -> do
         -- any other semantic annotation? that's an error
         when (any (\an -> isSemanticAnno an && an/=anno0) $ l_annos asp')
              (plain_error () "Conflicting semantic annotations"
                pos)
         -- %implied should not occur here
         when (anno1==SA_implied)
              (plain_error ()
               "Annotation %implied should come after a BASIC-ITEM"
                pos)
         if anno1==SA_implies then do
           when (not (isHomSubGsign sig1 sig')) (plain_error ()
             "Signature must not be extended in presence of %implies"
             pos)
   -- insert a theorem link according to p. 319 of the CASL Reference Manual
           return $ insLink dg1 (ide Grothendieck sig1)
                  (GlobalThm LeftOpen None LeftOpen) DGExtension n1 n'
          else do
           let anno2 = case anno1 of
                SA_cons -> Cons
                SA_def -> Def
                SA_mono -> Mono
                _ -> error "Static.AnalysisStructured: this cannot happen"
     -- insert a theorem link according to p. 319 of the CASL Reference Manual
     -- the theorem link is trivally proved by the parallel definition link,
           -- but for clarity, we leave it open here
           -- the interesting open proof obligation is anno2, of course
           incl <- ginclusion lg sig' sig1
           return $ insLink dg1 incl (GlobalThm LeftOpen anno2 LeftOpen)
                  DGExtension n' n1
     _ -> return dg1
  return (sp1' : sps', JustNode nsig1, dg2, lg, opts, pos, True)
