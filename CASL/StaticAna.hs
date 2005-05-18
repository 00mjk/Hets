
{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2003
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

CASL static analysis for basic specifications
Follows Chaps. III:2 and III:3 of the CASL Reference Manual.
    
-}

module CASL.StaticAna where

import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.MixfixParser
import CASL.Overload
import CASL.Inject
import CASL.Quantification
import CASL.Utils
import Common.Lib.State
import Common.PrettyPrint
import Common.Lib.Pretty
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel
import Common.Id
import Common.AS_Annotation
import Common.GlobalAnnotations
import Common.Result
import Data.Maybe
import Data.List

import Control.Exception (assert)

checkPlaces :: [SORT] -> Id -> [Diagnosis]
checkPlaces args i = 
    if let n = placeCount i in n == 0 || n == length args then []
           else [mkDiag Error "wrong number of places" i]

addOp :: OpType -> Id -> State (Sign f e) ()
addOp ty i = 
    do checkSorts (opRes ty : opArgs ty)
       e <- get
       let m = opMap e
           l = Map.findWithDefault Set.empty i m
           check = addDiags $ checkPlaces (opArgs ty) i
           store = do put e { opMap = addOpTo i ty m }
       if Set.member ty l then 
             addDiags [mkDiag Hint "redeclared op" i] 
          else case opKind ty of 
          Partial -> if Set.member ty {opKind = Total} l then
                     addDiags [mkDiag Warning "partially redeclared" i] 
                     else store >> check
          Total -> do store
                      if Set.member ty {opKind = Partial} l then
                         addDiags [mkDiag Hint "redeclared as total" i] 
                         else check

addAssocOp :: OpType -> Id -> State (Sign f e) ()
addAssocOp ty i = do
       e <- get
       put e { assocOps = addOpTo i ty $ assocOps e }

updateExtInfo :: (e -> Result e) -> State (Sign f e) ()
updateExtInfo upd = do
    s <- get
    let re = upd $ extendedInfo s
    case maybeResult re of
         Nothing -> return ()
         Just e -> put s { extendedInfo = e }
    addDiags $ diags re

addOpTo :: Id -> OpType -> OpMap -> OpMap 
addOpTo k v m = 
    let l = Map.findWithDefault Set.empty k m
        n = Map.insert k (Set.insert v l) m   
    in case opKind v of
     Total -> let vp =  v { opKind = Partial } in 
              if Set.member vp l then
              Map.insert k (Set.insert v $ Set.delete vp l) m
              else n
     _ -> if Set.member v { opKind = Total } l then m
          else n

addPred :: PredType -> Id -> State (Sign f e) ()
addPred ty i = 
    do checkSorts $ predArgs ty
       e <- get
       let m = predMap e
           l = Map.findWithDefault Set.empty i m
       if Set.member ty l then 
          addDiags [mkDiag Hint "redeclared pred" i] 
          else do put e { predMap = Map.insert i (Set.insert ty l) m }
                  addDiags $ checkPlaces (predArgs ty) i

allOpIds :: Sign f e -> Set.Set Id
allOpIds = Rel.keysSet . opMap

addAssocs :: GlobalAnnos -> Sign f e -> GlobalAnnos
addAssocs ga e =
    ga { assoc_annos =  
                foldr ( \ i m -> case Map.lookup i m of
                        Nothing -> Map.insert i ALeft m
                        _ -> m ) (assoc_annos ga) (Map.keys $ assocOps e) } 

formulaIds :: Sign f e -> Set.Set Id
formulaIds e = let ops = allOpIds e in
    Set.fromDistinctAscList (map simpleIdToId $ Map.keys $ varMap e) 
               `Set.union` ops

allPredIds :: Sign f e -> Set.Set Id
allPredIds = Rel.keysSet . predMap

addSentences :: [Named (FORMULA f)] -> State (Sign f e) ()
addSentences ds = 
    do e <- get
       put e { sentences = reverse ds ++ sentences e }

-- * traversing all data types of the abstract syntax

ana_BASIC_SPEC :: Resolver f => Min f e 
               -> Ana b f e -> Ana s f e -> GlobalAnnos
               -> BASIC_SPEC b s f -> State (Sign f e) (BASIC_SPEC b s f)
ana_BASIC_SPEC mef ab as ga (Basic_spec al) = fmap Basic_spec $
      mapAnM (ana_BASIC_ITEMS mef ab as ga) al

-- looseness of a datatype
data GenKind = Free | Generated | Loose deriving (Show, Eq, Ord)

mkForall :: [VAR_DECL] -> FORMULA f -> [Pos] -> FORMULA f
mkForall vl f ps = if null vl then f else 
                   Quantification Universal vl f ps

unionGenAx :: [GenAx] -> GenAx
unionGenAx = foldr ( \ (s1, r1, f1) (s2, r2, f2) -> 
                        (Set.union s1 s2,
                         Rel.union r1 r2,
                         Set.union f1 f2)) emptyGenAx

ana_BASIC_ITEMS :: Resolver f => Min f e  
                -> Ana b f e -> Ana s f e -> GlobalAnnos 
                -> BASIC_ITEMS b s f -> State (Sign f e) (BASIC_ITEMS b s f)
ana_BASIC_ITEMS mef ab as ga bi = 
    case bi of 
    Sig_items sis -> fmap Sig_items $ 
                     ana_SIG_ITEMS mef as ga Loose sis 
    Free_datatype al ps -> 
        do let sorts = map (( \ (Datatype_decl s _ _) -> s) . item) al
           mapM_ addSort sorts
           mapAnM (ana_DATATYPE_DECL Free) al 
           toSortGenAx ps True $ getDataGenSig al
           closeSubsortRel 
           return bi
    Sort_gen al ps ->
        do (gs,ul) <- ana_Generated mef as ga al
           toSortGenAx ps False $ unionGenAx gs
           return $ Sort_gen ul ps
    Var_items il _ -> 
        do mapM_ addVars il
           return bi
    Local_var_axioms il afs ps -> 
        do e <- get -- save
           mapM_ addVars il
           vds <- gets envDiags
           sign <- get
           put e { envDiags = vds } -- restore with shadowing warnings 
           let preds = allPredIds sign
               ops = formulaIds sign
               newGa = addAssocs ga sign
               (es, resFs, anaFs) = foldr ( \ f (dss, ress, anas) -> 
                      let Result ds m = anaForm mef newGa ops preds sign 
                                        $ item f
                      in case m of
                         Nothing -> (ds ++ dss, ress, anas)
                         Just (resF, anaF) -> 
                             (ds ++ dss, f {item = resF} : ress, 
                                 f {item = anaF} : anas))
                     ([], [], []) afs
               fufs = map (mapAn (\ f -> let 
                                 vs = map ( \ (v, s) -> 
                                            Var_decl [v] s ps)
                                      $ Set.toList $ freeVars f 
                                 in stripQuant $ mkForall (vs ++ il) f ps)) 
                      anaFs 
               sens = map ( \ a -> NamedSen (getRLabel a) True $ item a) fufs
           addDiags es
           addSentences sens                        
           return $ Local_var_axioms il resFs ps
    Axiom_items afs ps ->                   
        do sign <- get
           ops <- gets formulaIds
           preds <- gets allPredIds
           newGa <- gets $ addAssocs ga
           let (es, resFs, anaFs) = foldr ( \ f (dss, ress, anas) -> 
                      let Result ds m = anaForm mef newGa ops preds sign 
                                        $ item f
                      in case m of
                         Nothing -> (ds ++ dss, ress, anas)
                         Just (resF, anaF) -> 
                             (ds ++ dss, f {item = resF} : ress, 
                                 f {item = anaF} : anas))
                     ([], [], []) afs
               fufs = map (mapAn (\ f -> let
                                 vs = map ( \ (v, s) -> 
                                            Var_decl [v] s ps)
                                      $ Set.toList $ freeVars f 
                                 in stripQuant $ mkForall vs f ps)) anaFs
               sens = map ( \ a -> NamedSen (getRLabel a) True $ item a) fufs
           addDiags es
           addSentences sens                        
           return $ Axiom_items resFs ps
    Ext_BASIC_ITEMS b -> fmap Ext_BASIC_ITEMS $ ab ga b

mapAn :: (a -> b) -> Annoted a -> Annoted b
mapAn f an = replaceAnnoted (f $ item an) an

type GenAx = (Set.Set SORT, Rel.Rel SORT, Set.Set Component)

emptyGenAx :: GenAx
emptyGenAx = (Set.empty, Rel.empty, Set.empty)

toSortGenAx :: [Pos] -> Bool -> GenAx -> State (Sign f e) ()
toSortGenAx ps isFree (sorts, rel, ops) = do
    let sortList = Set.toList sorts
        opSyms = map ( \ c -> let ide = compId c in Qual_op_name ide  
                      (toOP_TYPE $ compType c) $ posOfId ide) $ Set.toList ops
        injSyms = map ( \ (s, t) -> let p = posOfId s in 
                        Qual_op_name injName 
                        (Op_type Total [s] t p) p) $ Rel.toList 
                  $ Rel.irreflex rel
        resType _ (Op_name _) = False
        resType s (Qual_op_name _ t _) = res_OP_TYPE t ==s
        getIndex s = maybe (-1) id $ findIndex (==s) sortList
        addIndices (Op_name _) = 
          error "CASL/StaticAna: Internal error in function addIndices"
        addIndices os@(Qual_op_name _ t _) = 
            (os,map getIndex $ args_OP_TYPE t)
        collectOps s = 
          Constraint s (map addIndices $ filter (resType s) 
                            (opSyms ++ injSyms)) s
        constrs = map collectOps sortList
        f =  Sort_gen_ax constrs isFree
    if null sortList then 
       addDiags[Diag Error "missing generated sort" ps]
       else return ()
    addSentences [NamedSen 
                  ("ga_generated_" ++ 
                   showSepList (showString "_") showId sortList "")
                  True f]

ana_SIG_ITEMS :: Resolver f => Min f e  
                -> Ana s f e -> GlobalAnnos -> GenKind 
                -> SIG_ITEMS s f -> State (Sign f e) (SIG_ITEMS s f)
ana_SIG_ITEMS mef as ga gk si = 
    case si of 
    Sort_items al ps -> 
        do ul <- mapM (ana_SORT_ITEM mef ga) al 
           closeSubsortRel
           return $ Sort_items ul ps
    Op_items al ps -> 
        do ul <- mapM (ana_OP_ITEM mef ga) al 
           return $ Op_items ul ps
    Pred_items al ps -> 
        do ul <- mapM (ana_PRED_ITEM mef ga) al 
           return $ Pred_items ul ps
    Datatype_items al _ -> 
        do let sorts = map (( \ (Datatype_decl s _ _) -> s) . item) al
           mapM_ addSort sorts
           mapAnM (ana_DATATYPE_DECL gk) al 
           closeSubsortRel
           return si
    Ext_SIG_ITEMS s -> fmap Ext_SIG_ITEMS $ as ga s

-- helper
ana_Generated :: Resolver f => Min f e 
              -> Ana s f e -> GlobalAnnos -> [Annoted (SIG_ITEMS s f)]     
              -> State (Sign f e) ([GenAx], [Annoted (SIG_ITEMS s f)])
ana_Generated mef as ga  al = do
   ul <- mapAnM (ana_SIG_ITEMS mef as ga Generated) al
   return (map (getGenSig . item) ul, ul)
   
getGenSig :: SIG_ITEMS s f -> GenAx
getGenSig si = case si of 
      Sort_items al _ -> unionGenAx $ map (getGenSorts . item) al
      Op_items al _ -> (Set.empty, Rel.empty, 
                           Set.unions (map (getOps . item) al))
      Datatype_items dl _ -> getDataGenSig dl
      _ -> emptyGenAx

isConsAlt :: ALTERNATIVE -> Bool
isConsAlt a = case a of 
              Subsorts _ _ -> False
              _ -> True

getDataGenSig :: [Annoted DATATYPE_DECL] -> GenAx
getDataGenSig dl = 
    let alts = concatMap (( \ (Datatype_decl s al _) -> 
                          map ( \ a -> (s, item a)) al) . item) dl
        sorts = map fst alts
        (realAlts, subs) = partition (isConsAlt . snd) alts 
        cs = map ( \ (s, a) ->
               let (i, ty, _) = getConsType s a
               in Component i ty) realAlts
        rel = foldr ( \ (t, a) r ->
                  foldr ( \ s -> 
                          Rel.insert s t)
                  r $ getAltSubsorts a)
               Rel.empty subs   
        in (Set.fromList sorts, rel, Set.fromList cs)

getGenSorts :: SORT_ITEM f -> GenAx
getGenSorts si = 
    let (sorts, rel) = case si of 
           Sort_decl il _ -> (Set.fromList il, Rel.empty)
           Subsort_decl il i _ -> (Set.fromList (i:il)
                                  , foldr (flip Rel.insert i) Rel.empty il)
           Subsort_defn sub _ super _ _ -> (Set.singleton sub
                                           , Rel.insert sub super Rel.empty)
           Iso_decl il _ -> (Set.fromList il
                            , foldr ( \ s r -> foldr ( \ t -> 
                              Rel.insert s t) r il) Rel.empty il)
        in (sorts, rel, Set.empty)
           

getOps :: OP_ITEM f -> Set.Set Component
getOps oi = case oi of 
    Op_decl is ty _ _ -> 
        Set.fromList $ map ( \ i -> Component i $ toOpType ty) is
    Op_defn i par _ _ -> Set.singleton $ Component i $ toOpType $ headToType par

ana_SORT_ITEM :: Resolver f => Min f e 
              -> GlobalAnnos -> Annoted (SORT_ITEM  f) 
              -> State (Sign f e) (Annoted (SORT_ITEM f))
ana_SORT_ITEM mef ga asi =
    case item asi of 
    Sort_decl il _ ->
        do mapM_ addSort il
           return asi
    Subsort_decl il i _ -> 
        do mapM_ addSort (i:il)
           mapM_ (addSubsort i) il
           return asi
    Subsort_defn sub v super af ps -> 
        do e <- get -- save
           put e { varMap = Map.empty }
           addVars (Var_decl [v] super ps) 
           sign <- get
           ops <- gets formulaIds 
           preds <- gets allPredIds
           newGa <- gets $ addAssocs ga
           put e -- restore 
           let Result ds mf = anaForm mef newGa ops preds sign $ item af
               lb = getRLabel af
               lab = if null lb then getRLabel asi else lb
           addDiags ds 
           addSort sub
           addSubsort super sub
           case mf of 
             Nothing -> return asi { item = Subsort_decl [sub] super ps}
             Just (resF, anaF) -> do 
               let p = posOfId sub
                   pv = tokPos v
               addSentences[NamedSen lab True $
                             mkForall [Var_decl [v] super pv] 
                             (Equivalence 
                              (Membership (Qual_var v super pv) sub p)
                              anaF p) p]
               return asi { item = Subsort_defn sub v super 
                                   af { item = resF } ps}
    Iso_decl il _ ->
        do mapM_ addSort il
           mapM_ ( \ i -> mapM_ (addSubsort i) il) il
           return asi

ana_OP_ITEM :: Resolver f => Min f e -> GlobalAnnos -> Annoted (OP_ITEM f) 
            -> State (Sign f e) (Annoted (OP_ITEM f))
ana_OP_ITEM mef ga aoi = 
    case item aoi of 
    Op_decl ops ty il ps -> 
        do let oty = toOpType ty
           mapM_ (addOp oty) ops
           ul <- mapM (ana_OP_ATTR mef ga oty ops) il
           if null $ filter ( \ i -> case i of 
                                   Assoc_op_attr -> True
                                   _ -> False) il 
              then return ()
              else mapM_ (addAssocOp oty) ops
           return aoi {item = Op_decl ops ty (catMaybes ul) ps}
    Op_defn i ohd at ps -> 
        do let ty = headToType ohd
               lb = getRLabel at
               lab = if null lb then getRLabel aoi else lb
               args = case ohd of 
                      Op_head _ as _ _ -> as
               vs = map (\ (Arg_decl v s qs) -> (Var_decl v s qs)) args
               arg = concatMap ( \ (Var_decl v s qs) ->
                                 map ( \ j -> Qual_var j s qs) v) vs
           addOp (toOpType ty) i
           e <- get -- save
           put e { varMap = Map.empty }
           mapM_ addVars vs
           sign <- get
           ops <- gets formulaIds
           preds <- gets allPredIds 
           newGa <- gets $ addAssocs ga
           put e -- restore
           let Result ds mt = anaTerm mef newGa ops preds sign 
                              (res_OP_TYPE ty) ps $ item at
           addDiags ds
           case mt of 
             Nothing -> return aoi { item = Op_decl [i] ty [] ps }
             Just (resT, anaT) -> do 
                 let p = posOfId i
                 addSentences [NamedSen lab True $ mkForall vs 
                     (Strong_equation 
                      (Application (Qual_op_name i ty p) arg ps)
                      anaT p) ps]
                 return aoi {item = Op_defn i ohd at { item = resT } ps }

headToType :: OP_HEAD -> OP_TYPE
headToType (Op_head k args r ps) = Op_type k (sortsOfArgs args) r ps

sortsOfArgs :: [ARG_DECL] -> [SORT]
sortsOfArgs = concatMap ( \ (Arg_decl l s _) -> map (const s) l)

ana_OP_ATTR :: Resolver f => Min f e -> GlobalAnnos 
            -> OpType -> [Id] -> (OP_ATTR f)
            -> State (Sign f e) (Maybe (OP_ATTR f))
ana_OP_ATTR mef ga ty ois oa = do
  let   sty = toOP_TYPE ty
        rty = opRes ty 
        atys = opArgs ty 
        q = posOfId rty
  case atys of 
         [t1,t2] | t1 == t2 -> case oa of 
              Comm_op_attr -> return ()
              _ -> if t1 == rty then return () 
                   else addDiags [Diag Error 
                             "result sort must be equal to argument sorts" q]
         _ -> addDiags [Diag Error
                        "expecting two arguments of equal sort" q] 
  case oa of 
    Unit_op_attr t ->
        do sign <- get
           ops <- gets allOpIds
           preds <- gets allPredIds 
           newGa <- gets $ addAssocs ga
           let Result ds mt = anaTerm mef newGa ops preds 
                              sign { varMap = Map.empty } rty q t
           addDiags ds
           case mt of 
             Nothing -> return Nothing
             Just (resT, anaT)  -> do 
               addSentences $ map (makeUnit True anaT ty) ois
               addSentences $ map (makeUnit False anaT ty) ois
               return $ Just $ Unit_op_attr resT
    Assoc_op_attr -> do
      let ns = map mkSimpleId ["x", "y", "z"]
          vs = map ( \ v -> Var_decl [v] rty q) ns
          [v1, v2, v3] = map ( \ v -> Qual_var v rty q) ns
          makeAssoc i = let p = posOfId i 
                            qi = Qual_op_name i sty p in 
            NamedSen ("ga_assoc_" ++ showId i "") True $
            mkForall vs
            (Strong_equation 
             (Application qi [v1, Application qi [v2, v3] p] p)
             (Application qi [Application qi [v1, v2] p, v3] p) p) p
      addSentences $ map makeAssoc ois
      return $ Just oa
    Comm_op_attr -> do 
      let ns = map mkSimpleId ["x", "y"]
          vs = zipWith ( \ v t -> Var_decl [v] t 
                         $ concatMap posOfId atys) ns atys
          args = map toQualVar vs
          makeComm i = let p = posOfId i
                           qi = Qual_op_name i sty p in
            NamedSen ("ga_comm_" ++ showId i "") True $
            mkForall vs
            (Strong_equation  
             (Application qi args p)
             (Application qi (reverse args) p) p) p
      addSentences $ map makeComm ois      
      return $ Just oa
    Idem_op_attr -> do 
      let v = mkSimpleId "x"
          vd = Var_decl [v] rty q
          qv = toQualVar vd
          makeIdem i = let p = posOfId i in 
            NamedSen ("ga_idem_" ++ showId i "") True $
            mkForall [vd]
            (Strong_equation  
             (Application (Qual_op_name i sty p) [qv, qv] p)
             qv p) p
      addSentences $ map makeIdem ois
      return $ Just oa

makeUnit :: Bool -> TERM f -> OpType -> Id -> Named (FORMULA f)
makeUnit b t ty i =
    let lab = "ga_" ++ (if b then "right" else "left") ++ "_unit_"
              ++ showId i ""
        v = mkSimpleId "x"
        vty = opRes ty
        q = posOfId vty
        p = posOfId i
        qv = Qual_var v vty q
        args = [qv, t] 
        rargs = if b then args else reverse args
    in NamedSen lab True $ mkForall [Var_decl [v] vty q]
                     (Strong_equation 
                      (Application (Qual_op_name i (toOP_TYPE ty) p) rargs p)
                      qv p) p

ana_PRED_ITEM :: Resolver f => Min f e 
              -> GlobalAnnos -> Annoted (PRED_ITEM f)
              -> State (Sign f e) (Annoted (PRED_ITEM f))
ana_PRED_ITEM mef ga ap = 
    case item ap of 
    Pred_decl preds ty _ -> 
        do mapM (addPred $ toPredType ty) preds
           return ap
    Pred_defn i phd@(Pred_head args rs) at ps ->
        do let lb = getRLabel at
               lab = if null lb then getRLabel ap else lb
               ty = Pred_type (sortsOfArgs args) rs
               vs = map (\ (Arg_decl v s qs) -> (Var_decl v s qs)) args
               arg = concatMap ( \ (Var_decl v s qs) ->
                                 map ( \ j -> Qual_var j s qs) v) vs
           addPred (toPredType ty) i
           e <- get -- save
           put e { varMap = Map.empty }
           mapM_ addVars vs          
           sign <- get
           ops <- gets formulaIds
           preds <- gets allPredIds 
           newGa <- gets $ addAssocs ga
           put e -- restore
           let Result ds mt = anaForm mef newGa ops preds sign $ item at
           addDiags ds
           case mt of 
             Nothing -> return ap {item = Pred_decl [i] ty ps}
             Just (resF, anaF) -> do 
               let p = posOfId i
               addSentences [NamedSen lab True $
                             mkForall vs 
                             (Equivalence (Predication (Qual_pred_name i ty p)
                                           arg p) anaF p) p]
               return ap {item = Pred_defn i phd at { item = resF } ps}

-- full function type of a selector (result sort is component sort)
data Component = Component { compId :: Id, compType :: OpType }
                 deriving (Show)

instance Eq Component where
    Component i1 t1 == Component i2 t2 = 
        (i1, opArgs t1, opRes t1) == (i2, opArgs t2, opRes t2)

instance Ord Component where
    Component i1 t1 <=  Component i2 t2 = 
        (i1, opArgs t1, opRes t1) <= (i2, opArgs t2, opRes t2)

instance PrettyPrint Component where
    printText0 ga (Component i ty) =
        printText0 ga i <+> colon <> printText0 ga ty

instance PosItem Component where
    get_pos = get_pos . compId

-- | return list of constructors 
ana_DATATYPE_DECL :: GenKind -> DATATYPE_DECL -> State (Sign f e) [Component]
ana_DATATYPE_DECL gk (Datatype_decl s al _) = 
    do ul <- mapM (ana_ALTERNATIVE s . item) al
       let constr = catMaybes ul
           cs = map fst constr              
       if null constr then return ()
          else do addDiags $ checkUniqueness cs
                  let totalSels = Set.unions $ map snd constr
                      wrongConstr = filter ((totalSels /=) . snd) constr
                  addDiags $ map ( \ (c, _) -> mkDiag Error 
                      ("total selectors '" ++ showSepList (showString ",")
                       showPretty (Set.toList totalSels) 
                       "'\n  must appear in alternative") c) wrongConstr
       case gk of 
         Free -> do 
           let allts = map item al
               (alts, subs) = partition isConsAlt allts
               sbs = concatMap getAltSubsorts subs
               comps = map (getConsType s) alts
               ttrips = map (( \ (a, vs, t, ses) -> (a, vs, t, catSels ses))
                               . selForms1 "X" ) comps 
               sels = concatMap ( \ (_, _, _, ses) -> ses) ttrips
           addSentences $ map makeInjective 
                            $ filter ( \ (_, _, ces) -> not $ null ces) 
                              comps
           addSentences $ makeDisjSubsorts s sbs
           addSentences $ concatMap ( \ c -> map (makeDisjToSort c) sbs)
                        comps 
           addSentences $ makeDisjoint comps 
           addSentences $ catMaybes $ concatMap 
                             ( \ ses -> 
                               map (makeUndefForm ses) ttrips) sels
         _ -> return ()
       return cs

makeDisjSubsorts :: SORT -> [SORT] -> [Named (FORMULA f)]
makeDisjSubsorts d subs = case subs of
    [] -> []
    s : rs -> map (makeDisjSubsort s) rs ++ makeDisjSubsorts d rs
  where
  makeDisjSubsort :: SORT -> SORT -> Named (FORMULA f)
  makeDisjSubsort s1 s2 = let
     n = mkSimpleId "x"
     pd = posOfId d
     p1 = posOfId s1
     p2 = posOfId s2
     p = concat [pd, p1, p2]
     v = Var_decl [n] d pd
     qv = toQualVar v
     in NamedSen ("ga_disjoint_sorts_" ++ showId s1 "_" 
                  ++ showId s2 "") True $
     mkForall [v] (Negation (Conjunction [
              Membership qv s1 p1, Membership qv s2 p2] p) p) p

makeDisjToSort :: (Id, OpType, [COMPONENTS]) -> SORT -> Named (FORMULA f)
makeDisjToSort a s = 
    let (c, v, t, _) = selForms1 "X" a 
        p = posOfId s in
        NamedSen ("ga_disjoint_" ++ showId c "_sort_" 
                  ++ showId s "") True $
        mkForall v (Negation (Membership t s p) p) p

makeInjective :: (Id, OpType, [COMPONENTS]) -> Named (FORMULA f)
makeInjective a = 
    let (c, v1, t1, _) = selForms1 "X" a
        (_, v2, t2, _) = selForms1 "Y" a
        p = posOfId c
    in NamedSen ("ga_injective_" ++ showId c "") True $
       mkForall (v1 ++ v2) 
       (Equivalence (Strong_equation t1 t2 p)
        (let ces = zipWith ( \ w1 w2 -> Strong_equation 
                             (toQualVar w1) (toQualVar w2) p) v1 v2
         in if isSingle ces then head ces else Conjunction ces p)
        p) p

makeDisjoint :: [(Id, OpType, [COMPONENTS])] -> [Named (FORMULA f)]
makeDisjoint l = case l of
    [] -> []
    c : cs -> map (makeDisj c) cs ++ makeDisjoint cs
  where
  makeDisj :: (Id, OpType, [COMPONENTS]) -> (Id, OpType, [COMPONENTS])
           -> Named (FORMULA f)
  makeDisj a1 a2 = 
    let (c1, v1, t1, _) = selForms1 "X" a1
        (c2, v2, t2, _) = selForms1 "Y" a2
        p = posOfId c1 ++ posOfId c2
    in NamedSen ("ga_disjoint_" ++ showId c1 "_" ++ showId c2 "") True
           $ mkForall (v1 ++ v2) 
                 (Negation (Strong_equation t1 t2 p) p) p

catSels :: [(Maybe Id, OpType)] -> [(Id, OpType)]
catSels =  map ( \ (m, t) -> (fromJust m, t)) . 
                 filter ( \ (m, _) -> isJust m)

makeUndefForm :: (Id, OpType) -> (Id, [VAR_DECL], TERM f, [(Id, OpType)])
              -> Maybe (Named (FORMULA f))
makeUndefForm (s, ty) (i, vs, t, sels) = 
    let p = posOfId s in
    if any ( \ (se, ts) -> s == se && opRes ts == opRes ty ) sels
    then Nothing else
       Just $ NamedSen ("ga_selector_undef_" ++ showId s "_" 
                        ++ showId i "") True $
              mkForall vs 
              (Negation 
               (Definedness
                (Application (Qual_op_name s (toOP_TYPE ty) p) [t] p)
                p) p) p

getAltSubsorts :: ALTERNATIVE -> [SORT]
getAltSubsorts c = case c of
    Subsorts cs _ -> cs
    _ -> []

getConsType :: SORT -> ALTERNATIVE -> (Id, OpType, [COMPONENTS])
getConsType s c = 
    let getConsTypeAux (part, i, il) = 
          (i, OpType part (concatMap 
                            (map (opRes . snd) . getCompType s) il) s, il)
     in case c of 
        Subsorts _ _ -> error "getConsType"
        Alt_construct k a l _ -> getConsTypeAux (k, a, l)

getCompType :: SORT -> COMPONENTS -> [(Maybe Id, OpType)]
getCompType s (Cons_select k l cs _) = 
    map (\ i -> (Just i, OpType k [s] cs)) l
getCompType s (Sort cs) = [(Nothing, OpType Partial [s] cs)]

genSelVars :: String -> Int -> [OpType] -> [VAR_DECL]
genSelVars _ _ [] = []
genSelVars str n (ty:rs)  = 
    Var_decl [mkSelVar str n] (opRes ty) [] : genSelVars str (n+1) rs

mkSelVar :: String -> Int -> Token
mkSelVar str n = mkSimpleId (str ++ show n)

makeSelForms :: Int -> (Id, [VAR_DECL], TERM f, [(Maybe Id, OpType)])
             -> [Named (FORMULA f)]
makeSelForms _ (_, _, _, []) = []
makeSelForms n (i, vs, t, (mi, ty):rs) =
    (case mi of 
            Nothing -> []
            Just j -> let p = posOfId j 
                          rty = opRes ty
                          q = posOfId rty in 
              [NamedSen ("ga_selector_" ++ showId j "") True 
                     $ mkForall vs 
                      (Strong_equation 
                       (Application (Qual_op_name j (toOP_TYPE ty) p) [t] p)
                       (Qual_var (mkSelVar "X" n) rty q) p) p]
    )  ++ makeSelForms (n+1) (i, vs, t, rs)

selForms1 :: String -> (Id, OpType, [COMPONENTS]) 
          -> (Id, [VAR_DECL], TERM f, [(Maybe Id, OpType)])
selForms1 str (i, ty, il) =
    let cs = concatMap (getCompType (opRes ty)) il
        vs = genSelVars str 1 $ map snd cs 
    in (i, vs, Application (Qual_op_name i (toOP_TYPE ty) [])
            (map toQualVar vs) [], cs)

toQualVar :: VAR_DECL -> TERM f
toQualVar (Var_decl v s ps) = 
    if isSingle v then Qual_var (head v) s ps else error "toQualVar"

selForms :: (Id, OpType, [COMPONENTS]) -> [Named (FORMULA f)]
selForms = makeSelForms 1 . selForms1 "X"
 
-- | return the constructor and the set of total selectors 
ana_ALTERNATIVE :: SORT -> ALTERNATIVE 
                -> State (Sign f e) (Maybe (Component, Set.Set Component))
ana_ALTERNATIVE s c = 
    case c of 
    Subsorts ss _ ->
        do mapM_ (addSubsort s) ss
           return Nothing
    _ -> do let cons@(i, ty, il) = getConsType s c
            addOp ty i
            ul <- mapM (ana_COMPONENTS s) il
            let ts = concatMap fst ul
            addDiags $ checkUniqueness (ts ++ concatMap snd ul)
            addSentences $ selForms cons
            return $ Just (Component i ty, Set.fromList ts) 

 
-- | return total and partial selectors
ana_COMPONENTS :: SORT -> COMPONENTS 
               -> State (Sign f e) ([Component], [Component])
ana_COMPONENTS s c = do
    let cs = getCompType s c
    sels <- mapM ( \ (mi, ty) -> 
            case mi of 
            Nothing -> return Nothing
            Just i -> do addOp ty i
                         return $ Just $ Component i ty) cs 
    return $ partition ((==Total) . opKind . compType) $ catMaybes sels 

-- | utility
resultToState :: (a -> Result a) -> a -> State (Sign f e) a
resultToState f a = do 
    let r =  f a 
    addDiags $ diags r
    case maybeResult r of
        Nothing -> return a
        Just b -> return b

-- wrap it all up for a logic

type Ana b f e = GlobalAnnos -> b -> State (Sign f e) b

class (PrettyPrint f, PosItem f) => Resolver f where
   putParen :: f -> f -- ^ put parenthesis around mixfix terms
   mixResolve :: MixResolve f -- ^ resolve mixfix terms 
   checkMix :: (f -> Bool) -- ^ check if a formula extension has been 
                             -- analysed completely by mixfix resolution
   putInj :: f -> f -- ^ insert injections 

anaForm :: Resolver f => Min f e -> GlobalAnnos -> Set.Set Id -> Set.Set Id 
        -> Sign f e -> (FORMULA f) -> Result (FORMULA f, FORMULA f)
anaForm mef ga ops preds sign f = do 
    resF <- resolveFormula putParen mixResolve ga ops preds f
    anaF <- minExpFORMULA mef ga sign 
         $ assert (noMixfixF checkMix resF) resF
    return (resF, anaF)

anaTerm :: Resolver f => Min f e -> GlobalAnnos -> Set.Set Id -> Set.Set Id 
        -> Sign f e -> SORT -> [Pos] -> (TERM f) -> Result (TERM f, TERM f)
anaTerm mef ga ops preds sign srt pos t = do 
    resT <- resolveMixfix putParen mixResolve ga ops preds t
    anaT <- oneExpTerm mef ga sign 
         $ assert (noMixfixT checkMix resT) $ Sorted_term resT srt pos
    return (resT, anaT)

basicAnalysis :: Resolver f
              => Min f e -- ^ type analysis of f
              -> Ana b f e  -- ^ static analysis of basic item b
              -> Ana s f e  -- ^ static analysis of signature item s  
              -> (e -> e -> e) -- ^ difference of signature extension e
              -> (BASIC_SPEC b s f, Sign f e, GlobalAnnos)
         -> Result (BASIC_SPEC b s f, Sign f e, Sign f e, [Named (FORMULA f)])
basicAnalysis mef anab anas dif (bs, inSig, ga) = 
    let (newBs, accSig) = runState (ana_BASIC_SPEC mef anab anas ga bs) 
                          inSig
        ds = reverse $ envDiags accSig
        sents = reverse $ sentences accSig
        cleanSig = accSig { envDiags = [], sentences = [], varMap = Map.empty }
        diff = diffSig cleanSig inSig 
            { extendedInfo = dif (extendedInfo accSig) $ extendedInfo inSig }
    in Result ds $ Just (newBs, diff, cleanSig, sents) 

basicCASLAnalysis :: (BASIC_SPEC () () (), Sign () (), GlobalAnnos)
                  -> Result (BASIC_SPEC () () (), Sign () (), 
                             Sign () (), [Named (FORMULA ())])
basicCASLAnalysis = 
    basicAnalysis (const $ const return) (const return) (const return) const

instance Resolver () where
    putParen = id
    mixResolve = const $ const return
    checkMix = const True
    putInj = id
