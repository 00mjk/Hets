{- |
Module      :  $Header$
Description :  final static analysis
Copyright   :  (c) Christian Maeder and Uni Bremen 2003-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  experimental
Portability :  portable

conversion from As to Le
-}

module HasCASL.AsToLe where

import Common.AS_Annotation
import Common.GlobalAnnotations
import Common.Id
import Common.Result
import Common.Prec
import Common.Lib.State
import qualified Data.Map as Map
import qualified Data.Set as Set

import HasCASL.As
import HasCASL.FoldType
import HasCASL.Le
import HasCASL.TypeAna
import HasCASL.ClassAna
import HasCASL.VarDecl
import HasCASL.Unify
import HasCASL.OpDecl
import HasCASL.TypeDecl
import HasCASL.Builtin
import HasCASL.PrintLe
import HasCASL.Merge
import HasCASL.MapTerm
import HasCASL.FoldTerm
import Data.Maybe

-- * extract predicate ids from As for mixfix analysis

type Ids = Set.Set Id

unite :: [Ids] -> Ids
unite = Set.unions

idsOfBasicSpec :: BasicSpec -> Ids
idsOfBasicSpec (BasicSpec l) = unite $ map (idsOfBasicItem . item) l

idsOfBasicItem :: BasicItem -> Ids
idsOfBasicItem bi = case bi of
    SigItems i -> idsOfSigItems i
    ClassItems _ l _ -> unite $ map (idsOfClassItem . item) l
    GenItems l _ -> unite $ map (idsOfSigItems . item) l
    Internal l _ -> unite $ map (idsOfBasicItem . item) l
    _ -> Set.empty

idsOfClassItem :: ClassItem -> Ids
idsOfClassItem (ClassItem _ l _) = unite $ map (idsOfBasicItem . item) l

idsOfSigItems :: SigItems -> Ids
idsOfSigItems si = case si of
    TypeItems _ _ _ -> Set.empty
    OpItems b l _ -> unite $ map (idsOfOpItem b . item) l

idsOfOpItem :: OpBrand -> OpItem -> Ids
idsOfOpItem b oi = let
    stripCompound (PolyId (Id ts _ ps) _ _) = Id ts [] ps
    getPolyId (PolyId i _ _) = i
    in case oi of
    OpDecl os _ _ _ -> case b of
        Pred -> Set.union (Set.fromList $ map getPolyId os) $ Set.fromList
                $ map stripCompound os
        _ -> Set.empty
    OpDefn p _ _ _ _ -> case b of
        Pred -> Set.fromList [getPolyId p, stripCompound p]
        _ -> Set.empty

-- * basic analysis

-- | basic analysis
basicAnalysis :: (BasicSpec, Env, GlobalAnnos) ->
                 Result (BasicSpec, Env, [Named Sentence])
basicAnalysis (b, e, ga) =
    let (nb, ne) = runState (anaBasicSpec ga b) e
        in Result (reverse $ envDiags ne) $
           Just (nb, cleanEnv ne, reverse $ sentences ne)

-- | is the signature empty?
isEmptyEnv :: Env -> Bool
isEmptyEnv e = Map.null (classMap e)
               && Map.null (typeMap e)
               && Map.null (assumps e)

-- | is the first argument a subsignature of the second?
isSubEnv :: Env -> Env -> Bool
isSubEnv e1 e2 = if e1 == e2 then True else isEmptyEnv $ diffEnv e1 e2

-- | compute difference of signatures
diffEnv :: Env -> Env -> Env
diffEnv e1 e2 = let
    tm = typeMap e2
    cm = Map.differenceWith diffClass (classMap e1) $ classMap e2
    Result _ (Just acm) = mergeMap mergeClassInfo (classMap e1) $ classMap e2
    in initialEnv
       { classMap = cm
       , typeMap = diffTypeMap acm (typeMap e1) tm
       , assumps = Map.differenceWith (diffAss cm (filterAliases tm)
                         $ addUnit cm tm) (assumps e1) $ assumps e2
       }

-- | compute difference of class infos
diffClass :: ClassInfo -> ClassInfo -> Maybe ClassInfo
diffClass _ _ = Nothing

-- | compute difference of overloaded operations
diffAss :: ClassMap -> TypeMap -> TypeMap -> Set.Set OpInfo -> Set.Set OpInfo
        -> Maybe (Set.Set OpInfo)
diffAss cm tAs tm s1 s2 =
    let s3 = diffOps cm tAs tm s1 s2 in
        if Set.null s3 then Nothing else Just s3

diffOps :: ClassMap -> TypeMap -> TypeMap -> Set.Set OpInfo -> Set.Set OpInfo
        -> Set.Set OpInfo
diffOps cm tAs tm s1 s2 = if Set.null s1 then s1 else
    let (o, os) = Set.deleteFindMin s1
        rs = diffOps cm tAs tm os s2
        n = mapOpInfo (id, expandAliases tAs) o
    in if Set.null $ Set.filter
           (instScheme tm 1 (opType n) . expand tAs . opType) s2
       then Set.insert n rs else rs

-- | clean up finally accumulated environment
cleanEnv :: Env -> Env
cleanEnv e = diffEnv initialEnv
             { classMap = classMap e
             , typeMap = typeMap e
             , assumps = assumps e } preEnv

-- | analyse basic spec
anaBasicSpec :: GlobalAnnos -> BasicSpec -> State Env BasicSpec
anaBasicSpec ga b@(BasicSpec l) = do
    e <- get
    let newAs = assumps e
        preds = Map.keysSet $ Map.filter (not . Set.null . Set.filter ( \ oi ->
                                 case opDefn oi of
                                 NoOpDefn Pred -> True
                                 Definition Pred _ -> True
                                 _ -> False)) newAs
        newPreds = idsOfBasicSpec b
        rels = Set.union preds newPreds
        newGa = addBuiltins ga
        precs = mkPrecIntMap $ prec_annos newGa
        Result _ (Just ne) = merge preEnv e
    put ne { preIds = (precs, rels), globAnnos = newGa }
    ul <- mapAnM (anaBasicItem newGa) l
    return $ BasicSpec ul

-- | analyse basic item
anaBasicItem :: GlobalAnnos -> BasicItem -> State Env BasicItem
anaBasicItem ga bi = case bi of
    SigItems i -> fmap SigItems $ anaSigItems ga Loose i
    ClassItems inst l ps -> do
       ul <- mapAnM (anaClassItem ga inst) l
       return $ ClassItems inst ul ps
    GenVarItems l ps -> do
       ul <- mapM (anaddGenVarDecl True) l
       return $ GenVarItems (catMaybes ul) ps
    ProgItems l ps -> do
       ul <- mapAnMaybe (anaProgEq ga) l
       return $ ProgItems ul ps
    FreeDatatype l ps -> do
       al <- mapAnMaybe ana1Datatype l
       tys <- mapM (dataPatToType . item) al
       ul <- mapAnMaybe (anaDatatype Free tys) al
       addDataSen tys
       return $ FreeDatatype ul ps
    GenItems l ps -> do
       ul <- mapAnM (anaSigItems ga Generated) l
       return $ GenItems ul ps
    AxiomItems decls fs ps -> do
       tm <- gets localTypeVars -- save type map
       vs <- gets localVars -- save vars
       ds <- mapM (anaddGenVarDecl True) decls
       ts <- mapM (anaFormula ga) fs
       e <- get
       putLocalVars vs -- restore
       putLocalTypeVars tm -- restore
       let newFs = catMaybes ts
           newDs = catMaybes ds
           sens = map ( \ (_, f) -> makeNamed (getRLabel f) $ Formula
                                $ mkEnvForall e (item f) ps) newFs
       appendSentences sens
       return $ AxiomItems newDs (map fst newFs) ps
    Internal l ps -> do
       ul <- mapAnM (anaBasicItem ga) l
       return $ Internal ul ps

freeVars :: Term -> Set.Set VarDecl
freeVars = foldTerm FoldRec
    { foldQualVar = \ _ t -> Set.singleton t
    , foldQualOp = \ _ _ _ _ _ _ _ -> Set.empty
    , foldApplTerm = \ _ t1 t2 _ -> Set.union t1 t2
    , foldTupleTerm = \ _ tts _ -> Set.unions tts
    , foldTypedTerm = \ _ ts _ _ _ -> ts
    , foldAsPattern = \ _ t ts _ -> Set.insert t ts
    , foldQuantifiedTerm = \ _ _ gvs ts _ -> Set.difference ts $
         foldr ( \ gv -> case gv of
           GenVarDecl t -> Set.insert t
           _ -> id) Set.empty gvs
    , foldLambdaTerm = \ _ pats _ ts _ -> Set.difference ts $ Set.unions pats
    , foldCaseTerm = \ _ ts tts _ -> Set.difference
          (Set.unions $ ts : map snd tts) $ Set.unions $ map fst tts
    , foldLetTerm = \ _ _ tts ts _ -> Set.difference
          (Set.unions $ ts : map snd tts) $ Set.unions $ map fst tts
    , foldResolvedMixTerm = \ _ _ _ tts _ -> Set.unions tts
    , foldTermToken = \ _ _ -> Set.empty
    , foldMixTypeTerm = \ _ _ _ _ -> Set.empty
    , foldMixfixTerm = \ _ tts -> Set.unions tts
    , foldBracketTerm = \ _ _ tts _ -> Set.unions tts
    , foldProgEq = \ _ ps ts _ -> (ps, ts) }

-- | quantify
mkEnvForall :: Env -> Term -> Range -> Term
mkEnvForall e t ps =
  let tys = Set.fromList $ map (fst . snd) $ concatMap (leaves (>= 0))
            $ getAllTypes t
      tyVs = map ( \ (i, TypeVarDefn v vk rk c) -> GenTypeVarDecl $
                   TypeArg i v vk rk c Other ps) $ Map.toList
             $ Map.filterWithKey ( \ i _ -> Set.member i tys) $ localTypeVars e
      vs = tyVs ++ map GenVarDecl (Set.toList $ freeVars t)
  in if null vs then t else QuantifiedTerm Universal vs t ps

-- | analyse sig items
anaSigItems :: GlobalAnnos -> GenKind -> SigItems -> State Env SigItems
anaSigItems ga gk si = case si of
    TypeItems inst l ps -> do
       ul <- anaTypeItems ga gk l
       return $ TypeItems inst ul ps
    OpItems b l ps -> do
       ul <- mapM (anaOpItem ga b) l
       let al = foldr (\ i -> case item i of
                    Nothing -> id
                    Just v -> (replaceAnnoted v i :)) [] ul
       return $ OpItems b al ps

-- | analyse a class item
anaClassItem :: GlobalAnnos -> Instance -> ClassItem
                    -> State Env ClassItem
anaClassItem ga _ (ClassItem d l ps) = do
       cd <- anaClassDecls d
       ul <- mapAnM (anaBasicItem ga) l
       return $ ClassItem cd ul ps
