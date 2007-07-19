{- |
Module      :  $Header$
Description :  analyse type declarations
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

analyse type declarations
-}

module HasCASL.TypeDecl
    ( anaFormula
    , mapAnMaybe
    , anaTypeItems
    , dataPatToType
    , ana1Datatype
    , anaDatatype
    , addDataSen
    ) where

import Data.Maybe
import Data.List(group)

import Common.Id
import Common.AS_Annotation
import Common.Lib.State
import qualified Data.Map as Map
import Common.Result
import Common.GlobalAnnotations

import HasCASL.As
import HasCASL.AsUtils
import HasCASL.Le
import HasCASL.ClassAna
import HasCASL.TypeAna
import HasCASL.ConvertTypePattern
import HasCASL.DataAna
import HasCASL.Unify
import HasCASL.VarDecl
import HasCASL.SubtypeDecl
import HasCASL.MixAna
import HasCASL.TypeCheck

-- | resolve and type check a formula
anaFormula :: GlobalAnnos -> Annoted Term
           -> State Env (Maybe (Annoted Term, Annoted Term))
anaFormula ga at = do
    rt <- resolve ga $ item at
    case rt of
      Nothing -> return Nothing
      Just t -> do
          mt <- typeCheck (Just unitType) t
          return $ case mt of
              Nothing -> Nothing
              Just e -> Just (at { item = t }, at { item = e })

anaVars :: Env -> Vars -> Type -> Result [VarDecl]
anaVars te vv t = case vv of
    Var v -> return [VarDecl v t Other nullRange]
    VarTuple vs _ -> let
        (topTy, ts) = getTypeAppl t
        n = length ts in
        if n > 1 && lesserType te topTy (toProdType n) then
               if n == length vs then
                  let lrs = zipWith (anaVars te) vs ts
                      lms = map maybeResult lrs in
                      if all isJust lms then
                         return $ concatMap fromJust lms
                         else Result (concatMap diags lrs) Nothing
               else mkError "wrong arity" topTy
        else mkError "product type expected" topTy

-- | lift a analysis function to annotated items
mapAnMaybe :: (Monad m) => (a -> m (Maybe b)) -> [Annoted a] -> m [Annoted b]
mapAnMaybe f al = do
    il <- mapAnM f al
    return $ map ( \ a -> replaceAnnoted (fromJust $ item a) a) $
           filter (isJust . item) il

-- | analyse annotated type items
anaTypeItems :: GlobalAnnos -> GenKind -> [Annoted TypeItem]
             -> State Env [Annoted TypeItem]
anaTypeItems ga gk l = do
    ul <- mapAnMaybe ana1TypeItem l
    tys <- mapM ( \ (Datatype d) -> dataPatToType d) $
              filter ( \ t -> case t of
                       Datatype _ -> True
                       _ -> False) $ map item ul
    rl <- mapAnMaybe (anaTypeItem ga gk tys) ul
    addDataSen tys
    return rl

-- | add sentences for data type definitions
addDataSen :: [DataPat] -> State Env ()
addDataSen tys = do
    tm <- gets typeMap
    let tis = map ( \ (DataPat i _ _ _) -> i) tys
        ds = foldr ( \ i dl -> case Map.lookup i tm of
                     Nothing -> dl
                     Just ti -> case typeDefn ti of
                                DatatypeDefn dd -> dd : dl
                                _ -> dl) [] tis
        sen = (makeNamed ("ga_" ++ showSepList (showString "_") showId tis "")
              $ DatatypeSen ds) { isDef = True }
    if null tys then return () else appendSentences [sen]

ana1TypeItem :: TypeItem -> State Env (Maybe TypeItem)
ana1TypeItem t = case t of
    Datatype d -> do
        md <- ana1Datatype d
        return $ fmap Datatype md
    _ -> return $ Just t


anaTypeDecl :: [TypePattern] -> Kind -> Range -> State Env (Maybe TypeItem)
anaTypeDecl pats kind ps = do
    cm <- gets classMap
    let Result cs _ = anaKindM kind cm
        Result ds (Just is) = convertTypePatterns pats
    addDiags $ cs ++ ds
    let ak = if null cs then kind else universe
    mis <- mapM (addTypePattern NoTypeDefn ak) is
    let newPats = map toTypePattern $ catMaybes mis
    return $ if null newPats then Nothing else Just $ TypeDecl newPats ak ps

anaIsoDecl :: [TypePattern] -> Range -> State Env (Maybe TypeItem)
anaIsoDecl pats ps = do
    let Result ds (Just is) = convertTypePatterns pats
    addDiags ds
    mis <- mapM (addTypePattern NoTypeDefn universe) is
    let nis = catMaybes mis
    mapM_ ( \ i -> mapM_ (addSuperType (TypeName i rStar 0)
                                          universe) nis) $ map fst nis
    return $ if null nis then Nothing else
                 Just $ IsoDecl (map toTypePattern nis) ps

setTypePatternVars :: [(Id, [TypeArg])] -> State Env [(Id, [TypeArg])]
setTypePatternVars ol = do
    l <- mapM ( \ (i, tArgs) -> do
            e <- get
            newAs <- mapM anaddTypeVarDecl tArgs
            put e
            return (i, catMaybes newAs)) ol
    let g = group $ map snd l
    case g of
      [_ : _] -> do
         newAs <- mapM anaddTypeVarDecl $ snd $ head l
         return $ map ( \ (i, _) -> (i, catMaybes newAs)) l
      _ -> do
        addDiags [mkDiag Error
            "variables must be identical for all types within one item" l]
        return []

anaSubtypeDecl :: [TypePattern] -> Type -> Range
               -> State Env (Maybe TypeItem)
anaSubtypeDecl pats t ps = do
    let Result ds (Just is) = convertTypePatterns pats
    addDiags ds
    tvs <- gets localTypeVars
    nis <- setTypePatternVars is
    let newPats = map toTypePattern nis
    te <- get
    putLocalTypeVars tvs
    let Result es mp = anaTypeM (Nothing, t) te
    case mp of
      Nothing -> do
        mapM_ (addTypePattern NoTypeDefn universe) is
        if null newPats then return Nothing else case t of
            TypeToken tt -> do
                let tid = simpleIdToId tt
                    newT = TypeName tid rStar 0
                addTypeId False NoTypeDefn rStar universe tid
                mapM_ (addSuperType newT universe) nis
                return $ Just $ SubtypeDecl newPats newT ps
            _ -> do
                addDiags es
                return $ Just $ TypeDecl newPats universe ps
      Just ((rk, ks), newT) -> do
        nonUniqueKind ks t $ \ kind -> do
          mapM_ (addTypePattern NoTypeDefn kind) is
          mapM_ (addSuperType newT $ rawToKind rk) nis
          return $ if null nis then Nothing else
                       Just $ SubtypeDecl newPats newT ps

anaSubtypeDefn :: GlobalAnnos -> TypePattern -> Vars -> Type
               -> (Annoted Term) -> Range -> State Env (Maybe TypeItem)
anaSubtypeDefn ga pat v t f ps = do
    let Result ds m = convertTypePattern pat
    addDiags ds
    case m of
      Nothing -> return Nothing
      Just (i, tArgs) -> do
        tvs <- gets localTypeVars
        newAs <- mapM anaddTypeVarDecl tArgs
        mt <- anaStarType t
        putLocalTypeVars tvs
        case mt of
          Nothing -> return Nothing
          Just ty -> do
            let nAs = catMaybes newAs
                fullKind = typeArgsListToKind nAs universe
            rk <- anaKind fullKind
            e <- get
            let Result es mvds = anaVars e v $ monoType ty
            addDiags es
            if cyclicType i ty then do
                addDiags [mkDiag Error
                          "illegal recursive subtype definition" ty]
                return Nothing
              else case mvds of
                Nothing -> return Nothing
                Just vds -> do
                  checkUniqueVars vds
                  vs <- gets localVars
                  mapM_ (addLocalVar True) vds
                  mf <- anaFormula ga f
                  putLocalVars vs
                  case mf of
                    Nothing -> return Nothing
                    Just (newF, _) -> do
                      addTypeId True NoTypeDefn rk fullKind i
                      addSuperType ty universe (i, nAs)
                      return $ Just $ SubtypeDefn (TypePattern i nAs nullRange)
                                    v ty newF ps

anaAliasType :: TypePattern -> Maybe Kind -> TypeScheme
             -> Range -> State Env (Maybe TypeItem)
anaAliasType pat mk sc ps = do
    let Result ds m = convertTypePattern pat
    addDiags ds
    case m of
      Nothing -> return Nothing
      Just (i, tArgs) -> do
        tvs <- gets localTypeVars -- save variables
        newAs <- mapM anaddTypeVarDecl tArgs
        (ik, mt) <- anaPseudoType mk sc
        putLocalTypeVars tvs
        case mt of
          Nothing -> return Nothing
          Just (TypeScheme args ty qs) ->
            if cyclicType i ty then do
                addDiags [mkDiag Error "illegal recursive type synonym" ty]
                return Nothing
              else do
                let nAs = catMaybes newAs
                    allArgs = nAs ++ args
                    fullKind = typeArgsListToKind nAs ik
                    allSc = TypeScheme allArgs ty qs
                b <- addAliasType True i allSc fullKind
                return $ if b then Just $ AliasType
                    (TypePattern i [] nullRange) (Just fullKind) allSc ps
                         else Nothing

-- | analyse a 'TypeItem'
anaTypeItem :: GlobalAnnos -> GenKind -> [DataPat] -> TypeItem
            -> State Env (Maybe TypeItem)
anaTypeItem ga gk tys itm = case itm of
    TypeDecl pats kind ps -> anaTypeDecl pats kind ps
    SubtypeDecl pats t ps -> anaSubtypeDecl pats t ps
    IsoDecl pats ps -> anaIsoDecl pats ps
    SubtypeDefn pat v t f ps -> anaSubtypeDefn ga pat v t f ps
    AliasType pat mk sc ps -> anaAliasType pat mk sc ps
    Datatype d -> do
        mD <- anaDatatype gk tys d
        case mD of
          Nothing -> return Nothing
          Just newD -> return $ Just $ Datatype newD

-- | pre-analyse a data type for 'anaDatatype'
ana1Datatype :: DatatypeDecl -> State Env (Maybe DatatypeDecl)
ana1Datatype (DatatypeDecl pat kind alts derivs ps) = do
    cm <- gets classMap
    let Result cs (Just rk) = anaKindM kind cm
        k = if null cs then kind else universe
    addDiags $ checkKinds pat rStar rk ++ cs
    let rms = map ( \ c -> anaKindM (ClassKind c) cm) derivs
        mcs = map maybeResult rms
        jcs = catMaybes mcs
        newDerivs = map fst $ filter (isJust . snd) $ zip derivs mcs
        Result ds m = convertTypePattern pat
    addDiags (ds ++ concatMap diags rms)
    addDiags $ concatMap (checkKinds pat rStar) jcs
    case m of
      Nothing -> return Nothing
      Just (i, tArgs) -> do
          tvs <- gets localTypeVars
          newAs <- mapM anaddTypeVarDecl tArgs
          putLocalTypeVars tvs
          let nAs = catMaybes newAs
              fullKind = typeArgsListToKind nAs k
          addDiags $ checkUniqueTypevars nAs
          frk <- anaKind fullKind
          b <- addTypeId False PreDatatype frk fullKind i
          return $ if b then Just $ DatatypeDecl
                     (TypePattern i nAs nullRange) k alts newDerivs ps
                   else Nothing

-- | convert a data type with an analysed type pattern to a data pattern
dataPatToType :: DatatypeDecl -> State Env DataPat
dataPatToType d = case d of
    DatatypeDecl (TypePattern i nAs _) k _ _ _ -> do
      rk <- anaKind k
      return $ DataPat i nAs rk $ patToType i nAs rk
    _ -> error "dataPatToType"

addDataSubtype :: DataPat -> Kind -> Type -> State Env ()
addDataSubtype (DataPat _ nAs _ rt) k st = case st of
    TypeName i _ _ -> addSuperType rt k (i, nAs)
    _ -> addDiags [mkDiag Warning "data subtype ignored" st]

-- | analyse a pre-analysed data type given all data patterns of the type item
anaDatatype :: GenKind -> [DataPat]
            -> DatatypeDecl -> State Env (Maybe DatatypeDecl)
anaDatatype genKind tys d = case d of
    DatatypeDecl (TypePattern i nAs _) k alts _ _ -> do
       dt@(DataPat _ _ rk rt) <- dataPatToType d
       let fullKind = typeArgsListToKind nAs k
       frk <- anaKind fullKind
       tvs <- gets localTypeVars
       mapM_ (addTypeVarDecl False) nAs
       mNewAlts <- fromResult $ anaAlts tys dt (map item alts)
       putLocalTypeVars tvs
       case mNewAlts of
         Nothing -> return Nothing
         Just newAlts -> do
           mapM_ (addDataSubtype dt fullKind) $ foldr
             ( \ (Construct mc ts _ _) l -> case mc of
               Nothing -> ts ++ l
               Just _ -> l) [] newAlts
           let srt = generalize nAs rt
               gArgs = genTypeArgs nAs
           mapM_ ( \ (Construct mc tc p sels) -> case mc of
               Nothing -> return ()
               Just c -> do
                 let sc = TypeScheme gArgs (getFunType srt p tc) nullRange
                 addOpId c sc [] (ConstructData i)
                 mapM_ ( \ (Select ms ts pa) -> case ms of
                   Just s -> do
                     let selSc = TypeScheme gArgs (getSelType srt pa ts)
                                 nullRange
                     addOpId s selSc [] $ SelectData [ConstrInfo c sc] i
                   Nothing -> return False) $ concat sels) newAlts
           let de = DataEntry Map.empty i genKind (genTypeArgs nAs) rk newAlts
           addTypeId True (DatatypeDefn de) frk fullKind i
           appendSentences $ makeDataSelEqs de srt
           return $ Just d
    _ -> error "anaDatatype (not preprocessed)"

-- | analyse a pseudo type (represented as a 'TypeScheme')
anaPseudoType :: Maybe Kind -> TypeScheme -> State Env (Kind, Maybe TypeScheme)
anaPseudoType mk (TypeScheme tArgs ty p) = do
    cm <- gets classMap
    let k = case mk of
              Nothing -> Nothing
              Just j -> let Result cs _ = anaKindM j cm
                        in Just $ if null cs then j else universe
    nAs <- mapM anaddTypeVarDecl tArgs
    let ntArgs = catMaybes nAs
    mp <- anaType (Nothing, ty)
    case mp of
      Nothing -> return (universe, Nothing)
      Just ((_, sks), newTy) -> case sks of
        [sk] -> do
          let newK = typeArgsListToKind ntArgs sk
          irk <- anaKind newK
          case k of
            Nothing -> return ()
            Just j -> do
              grk <- anaKind j
              addDiags $ checkKinds ty grk irk
          return (newK, Just $ TypeScheme ntArgs newTy p)
        _ -> return (universe, Nothing)

-- | add a type pattern
addTypePattern :: TypeDefn -> Kind -> (Id, [TypeArg])
               -> State Env (Maybe (Id, [TypeArg]))
addTypePattern defn kind (i, tArgs) = do
        tvs <- gets localTypeVars
        newAs <- mapM anaddTypeVarDecl tArgs
        putLocalTypeVars tvs
        let nAs = catMaybes newAs
            fullKind = typeArgsListToKind nAs kind
        addDiags $ checkUniqueTypevars nAs
        frk <- anaKind fullKind
        b <- addTypeId True defn frk fullKind i
        return $ if b then Just (i, nAs) else Nothing
