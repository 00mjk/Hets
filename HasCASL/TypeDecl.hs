{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

analyse type decls

-}

module HasCASL.TypeDecl where

import Data.Maybe

import Common.Lexer
import Common.Id
import Common.AS_Annotation
import Common.Lib.State
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Map as Map
import Common.Result
import Common.GlobalAnnotations

import HasCASL.As
import HasCASL.AsUtils
import HasCASL.Le
import HasCASL.ClassAna
import HasCASL.TypeAna
import HasCASL.DataAna
import HasCASL.Unify
import HasCASL.VarDecl
import HasCASL.TypeCheck

idsToTypePatterns :: [Maybe (Id, [TypeArg])] -> [TypePattern]
idsToTypePatterns mis = map ( \ (i, tArgs) -> TypePattern i tArgs [] ) 
                         $ catMaybes mis

anaFormula :: GlobalAnnos -> Annoted Term -> State Env (Maybe (Annoted Term))
anaFormula ga at = 
    do mt <- resolveTerm ga (Just unitType) $ item at 
       return $ case mt of Nothing -> Nothing
                           Just e -> Just at { item = e }

anaVars :: Vars -> Type -> Result [VarDecl]
anaVars (Var v) t = return [VarDecl v t Other []]
anaVars (VarTuple vs _) t = 
    case unalias t of 
           ProductType ts _ -> 
               if length ts == length vs then 
                  let lrs = zipWith anaVars vs ts 
                      lms = map maybeResult lrs in
                      if all isJust lms then 
                         return $ concatMap fromJust lms
                         else Result (concatMap diags lrs) Nothing 
               else mkError "wrong arity" t
           _ -> mkError "product type expected" t

mapAnMaybe :: (Monad m) => (a -> m (Maybe b)) -> [Annoted a] -> m [Annoted b]
mapAnMaybe f al = 
    do il <- mapAnM f al
       return $ map ( \ a -> replaceAnnoted (fromJust $ item a) a) $ 
              filter (isJust . item) il 

anaTypeItems :: GlobalAnnos -> GenKind -> Instance -> [Annoted TypeItem] 
            -> State Env [Annoted TypeItem]
anaTypeItems ga gk inst l = do
    ul <- mapAnMaybe ana1TypeItem l
    tys <- mapM ( \ (Datatype d) -> dataPatToType d) $ 
              filter ( \ t -> case t of 
                       Datatype _ -> True
                       _ -> False) $ map item ul
    rl <- mapAnMaybe (anaTypeItem ga gk inst tys) ul
    addDataSen tys
    return rl

addDataSen :: [DataPat] -> State Env ()
addDataSen tys = do 
    tm <- gets typeMap
    let tis = map ( \ (DataPat i _ _ _) -> i) tys
        ds = foldr ( \ i dl -> case Map.lookup i tm of 
                     Nothing -> dl
                     Just ti -> case typeDefn ti of
                                DatatypeDefn dd -> dd : dl
                                _ -> dl) [] tis
        sen = NamedSen ("ga_" ++ showSepList (showString "_") showId tis "") 
              True $ DatatypeSen ds
    if null tys then return () else appendSentences [sen]

ana1TypeItem :: TypeItem -> State Env (Maybe TypeItem)
ana1TypeItem (Datatype d) = 
    do md <- ana1Datatype d
       return $ fmap Datatype md
ana1TypeItem t = return $ Just t 

-- | analyse a 'TypeItem'
anaTypeItem :: GlobalAnnos -> GenKind -> Instance -> [DataPat] -> TypeItem 
            -> State Env (Maybe TypeItem)
anaTypeItem _ _ inst _ (TypeDecl pats kind ps) = 
    do cm <- gets classMap 
       let Result cs (Just rrk) = anaKindM kind cm
           Result ds (Just is) = convertTypePatterns pats
       addDiags $ cs ++ ds
       let (rk, ak) = if null cs then (rrk, kind) else (star, star)
       mis <- mapM (addTypePattern NoTypeDefn inst (rk, [ak])) is
       let newPats = idsToTypePatterns mis
       return $ if null newPats then Nothing else 
              Just $ TypeDecl newPats ak ps

anaTypeItem _ _ inst _ (SubtypeDecl pats t ps) = 
    do let Result ds (Just is) = convertTypePatterns pats
       addDiags ds  
       te <- get
       let Result es mp = anaTypeM (Nothing, t) te
       case mp of 
           Nothing -> do 
               mis <- mapM (addTypePattern NoTypeDefn inst (star, [star])) is
               let newPats = idsToTypePatterns mis
               if null newPats then return Nothing else case t of 
                   TypeToken tt -> do 
                       let tid = simpleIdToId tt
                           newT = TypeName tid star 0
                       addTypeId False NoTypeDefn inst star star tid
                       mapM_ (addSuperType newT) $ map fst is
                       return $ Just $ SubtypeDecl newPats newT ps
                   _ -> do
                       addDiags es
                       return $ Just $ TypeDecl newPats star ps
           Just (ak, newT) -> do 
              mis <- mapM (addTypePattern NoTypeDefn inst ak) is
              let newPats = idsToTypePatterns mis
              mapM_ (addSuperType newT) $ map fst is   
              return $ if null newPats then Nothing else 
                     Just $ SubtypeDecl newPats newT ps

anaTypeItem _ _ inst _ (IsoDecl pats ps) = 
    do let Result ds (Just is) = convertTypePatterns pats
           js = map fst is
       addDiags ds
       mis <- mapM (addTypePattern NoTypeDefn inst (star, [star])) is
       mapM_ ( \ i -> mapM_ (addSuperType (TypeName i star 0)) js) js 
       return $ if null mis then Nothing else 
              Just $ IsoDecl (idsToTypePatterns mis) ps

anaTypeItem ga _ inst _ (SubtypeDefn pat v t f ps) = 
    do let Result ds m = convertTypePattern pat
       addDiags ds
       case m of 
           Nothing -> return Nothing
           Just (i, tArgs) -> do 
               tvs <- gets localTypeVars
               newAs <- mapM anaddTypeVarDecl tArgs
               mt <- anaStarType t
               let nAs = catMaybes newAs
                   newPat = TypePattern i nAs []
               case mt of 
                   Nothing -> do
                       putLocalTypeVars tvs
                       return Nothing
                   Just ty -> do
                       newPty <- generalizeS $ TypeScheme nAs ty []
                       let fullKind = typeArgsListToKind nAs star
                       rk <- anaKind fullKind
                       let Result es mvds = anaVars v $ monoType ty
                           altDecl = Just $ AliasType newPat (Just fullKind)
                                     newPty ps
                           altAct = do 
                               putLocalTypeVars tvs
                               addTypeId True (AliasTypeDefn newPty) inst 
                                    rk fullKind i 
                               return altDecl
                       addDiags es
                       if cyclicType i ty then do 
                           addDiags [mkDiag Error 
                                     "illegal recursive subtype definition" ty]
                           putLocalTypeVars tvs
                           return Nothing
                           else case mvds of 
                           Nothing -> altAct
                           Just vds -> do 
                               checkUniqueVars vds
                               vs <- gets localVars
                               mapM_ (addLocalVar True) vds
                               mf <- anaFormula ga f
                               putLocalVars vs
                               case mf of 
                                   Nothing -> altAct
                                   Just newF -> do 
                                       addTypeId True (Supertype v newPty
                                                      $ item newF)
                                           inst rk fullKind i
                                       addSuperType ty i
                                       putLocalTypeVars tvs
                                       return $ Just $ SubtypeDefn newPat v ty 
                                              newF ps

anaTypeItem _ _ inst _ (AliasType pat mk sc ps) = 
    do let Result ds m = convertTypePattern pat
       addDiags ds
       case m of 
              Nothing -> return Nothing
              Just (i, tArgs) -> do
                  tvs <- gets localTypeVars -- save variables  
                  newAs <- mapM anaddTypeVarDecl tArgs
                  (ik, mt) <- anaPseudoType mk sc
                  let nAs = catMaybes newAs
                  case mt of 
                          Nothing -> do putLocalTypeVars tvs 
                                        return Nothing
                          Just (TypeScheme args ty qs) -> 
                              if cyclicType i ty then 
                                do addDiags [mkDiag Error 
                                       "illegal recursive type synonym" ty]
                                   putLocalTypeVars tvs
                                   return Nothing
                                else do 
                                let allArgs = nAs++args
                                    fullKind = typeArgsListToKind nAs ik
                                    allSc = TypeScheme allArgs ty qs
                                rk <- anaKind fullKind
                                newPty <- generalizeS allSc
                                putLocalTypeVars tvs
                                b <- addTypeId True (AliasTypeDefn newPty) 
                                        inst rk fullKind i 
                                return $ if b then Just $ AliasType 
                                           (TypePattern i [] [])
                                           (Just fullKind) newPty ps
                                         else Nothing  

anaTypeItem _ gk inst tys (Datatype d) = 
    do mD <- anaDatatype gk inst tys d 
       case mD of 
           Nothing -> return Nothing
           Just newD -> return $ Just $ Datatype newD

ana1Datatype :: DatatypeDecl -> State Env (Maybe DatatypeDecl)
ana1Datatype (DatatypeDecl pat kind alts derivs ps) = 
    do cm <- gets classMap 
       let Result cs (Just rk) = anaKindM kind cm
           k = if null cs then kind else star
       addDiags $ checkKinds pat star rk ++ cs
       let rms = map ( \ c -> anaKindM (ClassKind c) cm) derivs
           mcs = map maybeResult rms
           jcs = catMaybes mcs
           newDerivs = map fst $ filter (isJust . snd) $ zip derivs mcs
           Result ds m = convertTypePattern pat
       addDiags (ds ++ concatMap diags rms) 
       addDiags $ concatMap (checkKinds pat star) jcs
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
                  b <- addTypeId False PreDatatype Plain frk fullKind i
                  return $ if b then Just $ DatatypeDecl 
                      (TypePattern i nAs []) k alts newDerivs ps else Nothing

dataPatToType :: DatatypeDecl -> State Env DataPat
dataPatToType (DatatypeDecl (TypePattern i nAs _) k _ _ _) = do
     rk <- anaKind k
     return $ DataPat i nAs rk $ patToType i nAs rk
dataPatToType _ = error "dataPatToType"

-- | add a supertype to a given type id
addSuperType :: Type -> Id -> State Env ()
addSuperType t i =
    do tm <- gets typeMap
       let js = superTypeToId t
       if Set.member i js then return () -- silently ignore
         else if Set.member i $ supIds tm Set.empty js then
            addDiags[mkDiag Error 
                ("subtyping cycle via '" ++ showId i "' and") t]
         else case Map.lookup i tm of
           Nothing -> return () -- previous error
           Just (TypeInfo ok ks sups defn) -> 
               if any (== t) sups then 
                  addDiags[mkDiag Hint "repeated supertype" t]
               else putTypeMap $ Map.insert i 
                        (TypeInfo ok ks (t:sups) defn) tm

addDataSubtype :: DataPat -> Type -> State Env ()
addDataSubtype (DataPat _ _ _ rt) st = 
    case st of 
    TypeName i _ _ -> addSuperType rt i 
    _ -> addDiags [mkDiag Warning "data subtype ignored" st]

-- | analyse a 'DatatypeDecl'
anaDatatype :: GenKind -> Instance -> [DataPat] 
            -> DatatypeDecl -> State Env (Maybe DatatypeDecl)
anaDatatype genKind inst tys
       d@(DatatypeDecl (TypePattern i nAs _) k alts _ _) = 
    do dt@(DataPat _ _ rk rt) <- dataPatToType d
       let fullKind = typeArgsListToKind nAs k
       frk <- anaKind fullKind
       tvs <- gets localTypeVars
       mapM_ (addTypeVarDecl False) nAs
       mNewAlts <- fromResult $ anaAlts tys dt (map item alts) 
       case mNewAlts of 
         Nothing -> do 
             putLocalTypeVars tvs
             return Nothing
         Just newAlts -> do 
           mapM_ (addDataSubtype dt) $ foldr 
             ( \ (Construct mc ts _ _) l -> case mc of
               Nothing -> ts ++ l
               Just _ -> l) [] newAlts
           mapM_ ( \ (Construct mc tc p sels) -> case mc of 
               Nothing -> return ()
               Just c -> do
                   let srt = generalize nAs rt 
                       sc = TypeScheme nAs 
                         (getConstrType srt p tc) []
                   addOpId c sc [] (ConstructData i) 
                   mapM_ ( \ (Select ms ts pa) -> case ms of 
                           Just s -> do 
                               let selSc = TypeScheme nAs 
                                        (getSelType srt pa ts) []
                               addOpId s selSc []
                                       $ SelectData [ConstrInfo c sc] i
                           Nothing -> return False) $ concat sels) newAlts
           let de = DataEntry Map.empty i genKind (genTypeArgs nAs) rk newAlts
           addTypeId True (DatatypeDefn de) inst frk fullKind i
           appendSentences $ makeDataSelEqs de rt
           putLocalTypeVars tvs
           return $ Just d 
anaDatatype _ _ _ _ = error "anaDatatype (not preprocessed)"

-- | analyse a pseudo type (represented as a 'TypeScheme')
anaPseudoType :: Maybe Kind -> TypeScheme -> State Env (Kind, Maybe TypeScheme)
anaPseudoType mk (TypeScheme tArgs ty p) =
    do cm <- gets classMap 
       let k = case mk of 
            Nothing -> Nothing
            Just j -> let Result cs (Just rk) = anaKindM j cm
                      in Just $ if null cs then j else rk 
       nAs <- mapM anaddTypeVarDecl tArgs
       let ntArgs = catMaybes nAs
       mp <- anaType (Nothing, ty)
       case mp of
           Nothing -> return (star, Nothing)
           Just ((_, sks), newTy) -> case sks of 
               [sk] -> do  
                   let newK = typeArgsListToKind ntArgs sk
                   irk <- anaKind newK
                   case k of 
                     Nothing -> return () 
                     Just j -> do grk <- anaKind j 
                                  addDiags $ checkKinds ty grk irk
                   return (newK, Just $ TypeScheme ntArgs newTy p)
               _ -> return (star, Nothing)

-- | add a type pattern 
addTypePattern :: TypeDefn -> Instance -> (RawKind, [Kind]) 
               -> (Id, [TypeArg])  -> State Env (Maybe (Id, [TypeArg]))

addTypePattern defn inst (_, ks) (i, tArgs) = 
    nonUniqueKind ks i $ \ kind -> do
       tvs <- gets localTypeVars
       newAs <- mapM anaddTypeVarDecl tArgs
       let nAs = catMaybes newAs
           fullKind = typeArgsListToKind nAs kind
       putLocalTypeVars tvs
       addDiags $ checkUniqueTypevars nAs
       frk <- anaKind fullKind
       b <- addTypeId True defn inst frk fullKind i
       return $ if b then Just (i, nAs) else Nothing

-- | convert type patterns
convertTypePatterns :: [TypePattern] -> Result [(Id, [TypeArg])]
convertTypePatterns [] = Result [] $ Just []
convertTypePatterns (s:r) =
    let Result d m = convertTypePattern s
        Result ds (Just l) = convertTypePatterns r
        in case m of 
                  Nothing -> Result (d++ds) $ Just l
                  Just i -> Result (d++ds) $ Just (i:l)

illegalTypePattern, illegalTypePatternArg, illegalTypeId 
    :: TypePattern -> Result a 
illegalTypePattern tp = mkError "illegal type pattern" tp
illegalTypePatternArg tp = mkError "illegal type pattern argument" tp
illegalTypeId tp = mkError "illegal type pattern identifier" tp

-- | convert a 'TypePattern'
convertTypePattern :: TypePattern -> Result (Id, [TypeArg])
convertTypePattern (TypePattern t as _) = return (t, as)
convertTypePattern tp@(TypePatternToken t) = 
    if isPlace t then illegalTypePattern tp
       else return (simpleIdToId t, []) 
convertTypePattern tp@(MixfixTypePattern 
                       [ra, ri@(TypePatternToken inTok), rb]) =
    if head (tokStr inTok) `elem` signChars
       then let inId = Id [Token place $ get_pos ra, inTok, 
                           Token place $ get_pos rb] [] [] in
       case (ra, rb) of 
            (TypePatternToken (Token "__" _),
             TypePatternToken (Token "__" _)) -> return (inId, [])
            _ -> do a <- convertToTypeArg ra
                    b <- convertToTypeArg rb
                    return (inId, [a, b])
    else case ra of 
         TypePatternToken t1 -> do 
             a <- convertToTypeArg ri
             b <- convertToTypeArg rb
             return (simpleIdToId t1, [a, b])
         _ -> illegalTypePattern tp
convertTypePattern tp@(MixfixTypePattern (TypePatternToken t1 : rp)) =
    if isPlace t1 then 
       case rp of 
               [TypePatternToken inId, TypePatternToken t2] -> 
                   if isPlace t2 && head (tokStr inId) `elem` signChars
                     then return (Id [t1,inId,t2] [] [], [])
                   else illegalTypePattern tp
               _ -> illegalTypePattern tp
    else case rp of
         [BracketTypePattern Squares as@(_:_) ps] -> do 
             is <- mapM convertToId as 
             return (Id [t1] is ps, [])
         _ -> do as <- mapM convertToTypeArg rp 
                 return (simpleIdToId t1, as)
convertTypePattern (BracketTypePattern bk [ap] ps) =
    case bk of 
    Parens -> convertTypePattern ap
    _ -> let (o, c) = getBrackets bk
             tid = Id [Token o ps, Token place $ get_pos ap, 
                       Token c ps] [] [] in  
         case ap of 
         TypePatternToken t -> if isPlace t then 
             return (tid, [])
             else return (tid, [TypeArg (simpleIdToId t) MissingKind 
                                        star 0 Other []])
         _ -> do a <- convertToTypeArg ap
                 return (tid, [a])
convertTypePattern tp = illegalTypePattern tp

convertToTypeArg :: TypePattern -> Result TypeArg
convertToTypeArg tp@(TypePatternToken t) = 
    if isPlace t then illegalTypePatternArg tp
    else return $ TypeArg (simpleIdToId t) MissingKind star 0 Other []
convertToTypeArg (TypePatternArg a _) =  return a
convertToTypeArg (BracketTypePattern Parens [tp] _) =  convertToTypeArg tp
convertToTypeArg tp = illegalTypePatternArg tp

convertToId :: TypePattern -> Result Id
convertToId tp@(TypePatternToken t) = 
    if isPlace t then illegalTypeId tp
       else return $ Id [t] [] []
convertToId (MixfixTypePattern []) = error "convertToId: MixfixTypePattern []"
convertToId (MixfixTypePattern (hd:tps)) = 
         if null tps then convertToId hd
         else do 
         let (toks, comps) = break ( \ p -> 
                        case p of BracketTypePattern Squares (_:_) _ -> True
                                  _ -> False) tps
         ts <- mapM convertToToks (hd:toks)
         (is, ps) <- if null comps then return ([], []) 
                     else convertToIds $ head comps
         pls <- if null comps then return [] 
                else mapM convertToPlace $ tail comps
         return $ Id (concat ts ++ pls) is ps
convertToId tp = do 
    ts <- convertToToks tp
    return $ Id ts [] []

convertToIds :: TypePattern -> Result ([Id], [Pos])
convertToIds (BracketTypePattern Squares tps@(_:_) ps) = do
    is <- mapM convertToId tps
    return (is, ps)
convertToIds tp = illegalTypeId tp

convertToToks :: TypePattern -> Result [Token]
convertToToks (TypePatternToken t) = return [t]
convertToToks (BracketTypePattern bk [tp] ps) = case bk of 
    Parens -> illegalTypeId tp 
    _ -> do let [o,c] = mkBracketToken bk ps
            ts <- convertToToks tp 
            return (o : ts ++ [c])
convertToToks(MixfixTypePattern tps) = do
    ts <- mapM convertToToks tps
    return $ concat ts
convertToToks tp = illegalTypeId tp

convertToPlace :: TypePattern -> Result Token
convertToPlace tp@(TypePatternToken t) = 
    if isPlace t then return t
       else illegalTypeId tp
convertToPlace tp = illegalTypeId tp
