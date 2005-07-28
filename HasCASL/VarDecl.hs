{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

analyse generic var (or type var) decls

-}

module HasCASL.VarDecl where

import Data.Maybe
import Data.List as List
import Control.Monad

import qualified Common.Lib.Map as Map
import Common.Id
import Common.Lib.State
import Common.Result
import Common.PrettyPrint
import Common.Lexer
import Common.AnnoState
import Text.ParserCombinators.Parsec (runParser, eof)

import HasCASL.ParseTerm
import HasCASL.As
import HasCASL.AsUtils
import HasCASL.Le
import HasCASL.ClassAna
import HasCASL.TypeAna
import HasCASL.Unify
import HasCASL.Merge
import HasCASL.Builtin

anaStarType :: Type -> State Env (Maybe Type)
anaStarType t = fmap (fmap snd) $ anaType (Just universe, t) 

anaType :: (Maybe Kind, Type)  -> State Env (Maybe ((RawKind, [Kind]), Type))
anaType p = fromResult $ anaTypeM p

anaInstTypes :: [Type] -> State Env [Type]
anaInstTypes ts = if null ts then return []
   else do mp <- anaType (Nothing, head ts) 
           rs <- anaInstTypes $ tail ts
           return $ case mp of
                   Nothing -> rs
                   Just (_, ty) -> ty:rs

anaTypeScheme :: TypeScheme -> State Env (Maybe TypeScheme)
anaTypeScheme (TypeScheme tArgs ty p) =
    do tvs <- gets localTypeVars    -- save global variables  
       mArgs <- mapM anaddTypeVarDecl tArgs
       let newArgs = catMaybes mArgs  
       mt <- anaStarType ty
       case mt of 
           Nothing -> do putLocalTypeVars tvs       -- forget local variables 
                         return Nothing
           Just newTy -> do 
               let newSc = TypeScheme newArgs newTy p
               gTy <- generalizeS newSc
               putLocalTypeVars tvs       -- forget local variables 
               return $ Just gTy

generalizeS :: TypeScheme -> State Env TypeScheme
generalizeS sc@(TypeScheme tArgs ty p) = do 
    let fvs = leaves (> 0) ty
        svs = sortBy comp fvs
        comp a b = compare (fst a) $ fst b
    tvs <- gets localTypeVars 
    let newArgs = map ( \ (_, (i, _)) -> case Map.lookup i tvs of
                  Nothing -> error "generalizeS" 
                  Just (TypeVarDefn v vk rk c) -> 
                      TypeArg i v vk rk c Other nullRange) svs
        newTy = generalize newArgs ty
    if null tArgs then return $ TypeScheme newArgs newTy p
       else do
         addDiags $ generalizable sc
         return $ TypeScheme newArgs newTy p

addLocalTypeVar :: Bool -> TypeVarDefn -> Id -> State Env ()
addLocalTypeVar warn tvd i = do 
    tvs <- gets localTypeVars
    if warn then do 
         tm <- gets typeMap
         case Map.lookup i tm of 
             Nothing -> case Map.lookup i tvs of 
                 Nothing -> return ()
                 Just _ -> addDiags [mkDiag Hint "rebound type variable" i] 
             Just _ -> addDiags [mkDiag Hint 
                    "type variable shadows type constructor" i]
       else return ()
    putLocalTypeVars $ Map.insert i tvd tvs

-- | store type id and check kind arity (warn on redeclared types)
addTypeId :: Bool -> TypeDefn -> Instance -> RawKind -> Kind -> Id 
          -> State Env Bool
addTypeId warn defn _ rk k i = do 
    tvs <- gets localTypeVars
    case Map.lookup i tvs of
        Just _ -> do 
            if warn then addDiags[mkDiag Warning 
                                  "new type shadows type variable" i]
               else return ()
            putLocalTypeVars $ Map.delete i tvs
        Nothing -> return()
    cm <- gets classMap
    case Map.lookup i cm of 
      Just _ -> do 
          addDiags [mkDiag Error "class name used as type" i]       
          return False
      Nothing -> if placeCount i <= kindArity rk then do
          addTypeKind warn defn i rk k
          return True
          else do addDiags [mkDiag Error "wrong arity of" i]
                  return False

-- | store type as is (warn on redeclared types)
addTypeKind :: Bool -> TypeDefn -> Id -> RawKind -> Kind -> State Env Bool
addTypeKind warn d i rk k = 
    do tm <- gets typeMap
       case Map.lookup i tm of
           Nothing -> do 
               putTypeMap $ Map.insert i (TypeInfo rk [k] [] d) tm
               return True 
           Just (TypeInfo ok oldks sups defn) -> 
               if rk == ok then do 
                   let isKnownInst = k `elem` oldks
                       insts = if isKnownInst then oldks else k : oldks
                       Result ds mDef = mergeTypeDefn defn d
                   if warn && isKnownInst && case (defn, d) of 
                                 (PreDatatype, DatatypeDefn _) -> False
                                 _ -> True then
                       addDiags [mkDiag Hint "redeclared type" i]
                       else return ()
                   case mDef of
                       Just newDefn -> do 
                           putTypeMap $ Map.insert i 
                               (TypeInfo ok insts sups newDefn) tm
                           return True
                       Nothing -> do 
                           addDiags $ map (improveDiag i) ds
                           return False
                else do addDiags $ diffKindDiag i ok rk 
                        return False

nonUniqueKind :: (PosItem a, PrettyPrint a) => [Kind] -> a -> 
                 (Kind -> State Env (Maybe b)) -> State Env (Maybe b)
nonUniqueKind ks a f = case ks of
    [k] -> f k
    _ -> do addDiags [mkDiag Error "non-unique kind for" a]
            return Nothing

-- | analyse a type argument 
anaddTypeVarDecl :: TypeArg -> State Env (Maybe TypeArg)
anaddTypeVarDecl (TypeArg i v vk _ _ s ps) = do
  cm <- gets classMap
  case Map.lookup i cm of 
    Just _ -> do 
        addDiags [mkDiag Error "class used as type variable" i]
        return Nothing         
    Nothing -> do
     c <- toEnvState inc
     case vk of 
      VarKind k ->  
        let Result ds (Just rk) = anaKindM k cm
        in if null ds then do
            addLocalTypeVar True (TypeVarDefn v vk rk c) i
            return $ Just $ TypeArg i v vk rk c s ps
        else do addDiags ds
                return Nothing
      Downset t -> do                 
        mt <- anaType (Nothing, t)
        case mt of 
            Nothing -> return Nothing
            Just ((rk, ks), nt) -> 
                nonUniqueKind ks t $ \ k -> do
                   let nd = Downset (KindedType nt k nullRange)
                   addLocalTypeVar True (TypeVarDefn InVar nd rk c) i
                   return $ Just $ TypeArg i v (Downset nt) rk c s ps
      MissingKind -> do 
        tvs <- gets localTypeVars
        case Map.lookup i tvs of 
            Nothing -> do 
                addDiags [mkDiag Warning "missing kind for type variable " i]
                let dvk = VarKind universe
                addLocalTypeVar True (TypeVarDefn v dvk rStar c) i
                return $ Just $ TypeArg i v dvk rStar c s ps
            Just (TypeVarDefn v0 dvk rk _) -> do 
                addLocalTypeVar True (TypeVarDefn v0 dvk rk c) i
                return $ Just $ TypeArg i v0 dvk rk c s ps

-- | add an analysed type argument (warn on redeclared types)
addTypeVarDecl :: Bool -> TypeArg -> State Env ()
addTypeVarDecl warn (TypeArg i v vk rk c _ _) = 
       addLocalTypeVar warn (TypeVarDefn v vk rk c) i

-- | get matching information of uninstantiated identifier
findOpId :: Env -> UninstOpId -> TypeScheme -> Maybe OpInfo
findOpId e i sc = listToMaybe $ fst $ partitionOpId e i sc

-- | partition information of an uninstantiated identifier
partitionOpId :: Env -> UninstOpId -> TypeScheme -> ([OpInfo], [OpInfo])
partitionOpId e i sc = 
    let l = Map.findWithDefault (OpInfos []) i $ assumps e
    in partition (isUnifiable (typeMap e) (counter e) sc . opType) $ opInfos l

checkUnusedTypevars :: TypeScheme -> State Env TypeScheme
checkUnusedTypevars sc@(TypeScheme tArgs t _) = do
    let ls = map (fst . snd) $ leaves (< 0) t -- generic vars
        rest = map getTypeVar tArgs List.\\ ls
    if null rest then return ()
      else addDiags [mkDiag Warning "unused type variables" rest]
    return sc

-- | storing an operation
addOpId :: UninstOpId -> TypeScheme -> [OpAttr] -> OpDefn 
        -> State Env Bool
addOpId i oldSc attrs defn = 
    do sc <- checkUnusedTypevars oldSc
       e <- get
       let as = assumps e
           tm = typeMap e
           TypeScheme _ ty _ = sc 
           ds = if placeCount i > 1 then case unalias ty of 
                   FunType arg _ _ _ -> case unalias arg of
                       ProductType ts _ -> if placeCount i /= length ts then 
                            [mkDiag Error "wrong number of places in" i]
                            else [] 
                       _ -> [mkDiag Error "expected tuple argument for" i]
                   _ -> [mkDiag Error "expected function type for" i]
                 else []
           (l, r) = partitionOpId e i sc
           oInfo = OpInfo sc attrs defn 
       if null ds then 
               do let Result es mo = foldM (mergeOpInfo tm) oInfo l
                  addDiags $ map (improveDiag i) es
                  if i `elem` map fst bList then addDiags $ [mkDiag Warning
                      "ignoring declaration for builtin identifier" i]
                      else return ()
                  case mo of 
                      Nothing -> return False
                      Just oi -> do putAssumps $ Map.insert i 
                                                   (OpInfos (oi : r)) as
                                    return True
          else do addDiags ds
                  return False

-- | add a local variable with an analysed type (if True then warn)
addLocalVar :: Bool -> VarDecl -> State Env () 
addLocalVar warn (VarDecl v t _ _) = 
    do ass <- gets assumps
       vs <- gets localVars
       if warn then if Map.member v ass then
          addDiags [mkDiag Hint "variable shadows global name(s)" v]
          else if Map.member v vs then 
          addDiags [mkDiag Hint "rebound variable" v]
          else return ()
         else return ()  
       putLocalVars $ Map.insert v (VarDefn t) vs 

-- | add analysed local variable or type variable declaration 
addGenVarDecl :: GenVarDecl -> State Env ()
addGenVarDecl(GenVarDecl v) = addLocalVar True v
addGenVarDecl(GenTypeVarDecl t) = addTypeVarDecl False t 

-- | analyse and add local variable or type variable declaration 
anaddGenVarDecl :: Bool -> GenVarDecl -> State Env (Maybe GenVarDecl)
anaddGenVarDecl warn gv = case gv of 
    GenVarDecl v -> optAnaddVarDecl warn v
    GenTypeVarDecl t -> anaddTypeVarDecl t >>= (return . fmap GenTypeVarDecl)

convertTypeToKind :: Env -> Type -> Result (Variance, Kind)
convertTypeToKind e ty = let s = showPretty ty "" in
    case runParser (extKind << eof) (emptyAnnos ()) "" s of
    Right (v, k) -> let Result ds _ = anaKindM k $ classMap e in
               if null ds then return (v, k) else Result ds Nothing
    Left _ -> fail $ "not a kind '" ++ s ++ "'"

-- | local variable or type variable declaration
optAnaddVarDecl :: Bool -> VarDecl -> State Env (Maybe GenVarDecl)
optAnaddVarDecl warn vd@(VarDecl v t s q) = 
    let varDecl = do mvd <- anaVarDecl vd
                     case mvd of 
                         Nothing -> return Nothing
                         Just nvd -> do 
                             let movd = makeMonomorph nvd 
                             addLocalVar warn movd
                             return $ Just $ GenVarDecl movd
    in if isSimpleId v then
    do e <- get
       let Result ds mk = convertTypeToKind e t
       case mk of 
           Just (vv, k) -> do 
               addDiags [mkDiag Hint "is type variable" v]
               tv <- anaddTypeVarDecl $ TypeArg v vv (VarKind k) rStar 0 s q
               return $ fmap GenTypeVarDecl tv 
           _ -> do addDiags $ map ( \ d -> Diag Hint (diagString d) q) ds  
                   varDecl
    else varDecl

makeMonomorph :: VarDecl -> VarDecl
makeMonomorph (VarDecl v t sk ps) = VarDecl v (monoType t) sk ps

monoType :: Type -> Type
monoType t = subst (Map.fromList $ 
                    map ( \ (v, (i, rk)) -> 
                          (v, TypeName i rk 0)) $ leaves (> 0) t) t

-- | analyse variable declaration
anaVarDecl :: VarDecl -> State Env (Maybe VarDecl)
anaVarDecl(VarDecl v oldT sk ps) = 
    do mt <- anaStarType oldT
       return $ case mt of 
               Nothing -> Nothing
               Just t -> Just $ VarDecl v t sk ps

-- create fresh type vars for unknown ids tagged with type MixfixType []. 
anaPattern :: Pattern -> State Env Pattern
anaPattern pat = 
    case pat of
    QualVar vd -> do newVd <- checkVarDecl vd
                     return $ QualVar newVd
    ResolvedMixTerm i pats ps -> do 
         l <- mapM anaPattern pats
         return $ ResolvedMixTerm i l ps
    ApplTerm p1 p2 ps -> do
         p3 <- anaPattern p1
         p4 <- anaPattern p2
         return $ ApplTerm p3 p4 ps
    TupleTerm pats ps -> do 
         l <- mapM anaPattern pats
         return $ TupleTerm l ps
    TypedTerm p q ty ps -> do 
         mt <- anaStarType ty 
         let newT = case mt of Just t -> t
                               _ -> ty
         case p of 
             QualVar (VarDecl v (MixfixType []) ok qs) ->
                 let newVd = VarDecl v newT ok (qs `appRange` ps) in
                 return $ QualVar newVd
             _ -> do newP <- anaPattern p
                     return $ TypedTerm newP q newT ps
    AsPattern vd p2 ps -> do
         newVd <- checkVarDecl vd
         p4 <- anaPattern p2
         return $ AsPattern newVd p4 ps
    _ -> return pat
    where checkVarDecl vd@(VarDecl v t ok ps) = case t of 
            MixfixType [] -> do
                (tvar, c) <- toEnvState $ freshVar $ posOfId v
                return $ VarDecl v (TypeName tvar rStar c) ok ps
            _ -> do mt <- anaStarType t 
                    case mt of 
                        Just ty -> return $ VarDecl v ty ok ps 
                        _ -> return vd
