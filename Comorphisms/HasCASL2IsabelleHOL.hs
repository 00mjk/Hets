{- |
Module      :  $Header$
Copyright   :  (c) Uni Bremen 2003 - 2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

   
   The embedding comorphism from HasCASL to Isabelle-HOL.

-}

module Comorphisms.HasCASL2IsabelleHOL where

import Logic.Logic as Logic
import Logic.Comorphism
import Common.Id
import Common.Result
import qualified Common.Lib.Map as Map
import Data.List
import Data.Maybe
import Common.AS_Annotation (Named(..))

-- HasCASL
import HasCASL.Logic_HasCASL
import HasCASL.Sublogic
import HasCASL.Le as Le
import HasCASL.As as As
import HasCASL.Builtin
import HasCASL.Morphism

-- Isabelle
import Isabelle.IsaSign as IsaSign
import Isabelle.IsaConsts
import Isabelle.Logic_Isabelle
import Isabelle.Translate

-- | The identity of the comorphism
data HasCASL2IsabelleHOL = HasCASL2IsabelleHOL deriving (Show)

instance Language HasCASL2IsabelleHOL -- default definition is okay

instance Comorphism HasCASL2IsabelleHOL
               HasCASL HasCASL_Sublogics
               BasicSpec Le.Sentence SymbItems SymbMapItems
               Env Morphism
               Symbol RawSymbol ()
               Isabelle () () IsaSign.Sentence () ()
               IsaSign.Sign 
               IsabelleMorphism () () ()  where
    sourceLogic HasCASL2IsabelleHOL = HasCASL
    sourceSublogic HasCASL2IsabelleHOL = HasCASL_SL
                       { has_sub = False,   -- subsorting
                         has_part = True,   -- partiality
                         has_eq = True,     -- equality
                         has_pred = True,   -- predicates
                         has_ho = True,     -- higher order
                         has_type_classes = False,
                         has_polymorphism = True,
                         has_type_constructors = True,
                         which_logic = HOL
                       }
    targetLogic HasCASL2IsabelleHOL = Isabelle
    targetSublogic HasCASL2IsabelleHOL = ()
    map_theory HasCASL2IsabelleHOL = mkTheoryMapping transSignature 
                   (map_sentence HasCASL2IsabelleHOL)
    map_morphism HasCASL2IsabelleHOL mor = do
       (sig1,_) <- map_sign HasCASL2IsabelleHOL (Logic.dom HasCASL mor)
       (sig2,_) <- map_sign HasCASL2IsabelleHOL (cod HasCASL mor)
       inclusion Isabelle sig1 sig2
    map_sentence HasCASL2IsabelleHOL sign phi =
       case transSentence sign phi of
         Nothing   -> warning (Sentence {senTerm = true}) 
                           "translation of sentence not implemented" nullPos
         Just (ts) -> return $ Sentence {senTerm = ts}
    map_symbol HasCASL2IsabelleHOL _ = error "HasCASL2IsabelleHOL.map_symbol"


-- ============================ Signature ================================== --
baseSign :: BaseSig
baseSign = MainHC_thy

transSignature :: Env
                   -> Result (IsaSign.Sign,[Named IsaSign.Sentence]) 
transSignature sign = 
  return (IsaSign.emptySign {
    baseSig = baseSign,
    -- translation of typeconstructors
    tsig = emptyTypeSig 
             { arities = Map.foldWithKey extractTypeName 
                                        Map.empty 
                                        (typeMap sign) },
    -- translation of operation declarations
    constTab = Map.foldWithKey insertOps 
                               Map.empty 
                               (assumps sign),
    -- translation of datatype declarations
    dataTypeTab = transDatatype (typeMap sign),
    showLemmas = True },
    [] ) 
   where 
    extractTypeName tyId typeInfo m = 
        if isDatatypeDefn typeInfo then m
           else Map.insert (showIsaT tyId baseSign) [(isaTerm, [])] m
                -- translate the kind here!
    isDatatypeDefn t = case typeDefn t of
                         DatatypeDefn _ -> True
                         _              -> False
    insertOps name ops m = 
     let infos = opInfos ops
     in if isSingle infos then
            let transOp = transOpInfo (head infos)
            in case transOp of 
                 Just op -> Map.insert (showIsaT name baseSign) op m
                 Nothing -> m
          else 
            let transOps = map transOpInfo infos
            in  foldl (\ m' (transOp,i) -> 
                           case transOp of
                             Just typ -> Map.insert (showIsaIT name i baseSign)
                                                    typ m'
                             Nothing   -> m')
                      m (zip transOps [1::Int ..])


---------- translation of a type in an operation declaration ----------

-- extract type from OpInfo
-- omit datatype constructors
transOpInfo :: OpInfo -> Maybe Typ
transOpInfo (OpInfo t _ opDef) = 
  case opDef of
    NoOpDefn Pred   -> Just (transPredType t)
    NoOpDefn _      -> Just (transOpType t)
    ConstructData _ -> Nothing
    Definition _ _  -> Just (transOpType t)
    _ -> error "HasCASL2IsabelleHOL.transOpInfo"

-- operation type
transOpType :: TypeScheme -> Typ
transOpType (TypeScheme _ op _) = transType op

-- predicate type
transPredType :: TypeScheme -> Typ
transPredType  (TypeScheme _ pre _) = 
       case pre of
         FunType t _ _ _ -> mkFunType (transType t) boolType
         _  -> error "HasCASL2IsabelleHOL.transPredType"

-- types
transType :: Type -> Typ
-- type name
transType (TypeName tyId _ i) = 
    if i == 0 then Type (showIsaT tyId baseSign) [] [] -- translate kind here!!
       else TFree (showIsaT tyId baseSign) []
-- product type
transType (ProductType ts _) = 
  foldl1 IsaSign.prodType (map transType ts)
-- function type
transType (FunType t arr t' _) = 
  case arr of
    PFunArr -> mkFunType (transType t) (mkOptionType (transType t'))
    FunArr  -> mkFunType (transType t) (transType t')
    _ -> error "HasCASL2IsabelleHOL.transType.FunType"
-- type application
transType (TypeAppl t t') = 
    binTypeAppl (transType t) (transType t')
transType _ = error "HasCASL2IsabelleHOL.transType"


---------- translation of a datatype declaration ----------

transDatatype :: TypeMap -> DataTypeTab
transDatatype tm = map transDataEntry (Map.fold extractDataypes [] tm)
  where extractDataypes ti des = case typeDefn ti of
                                   DatatypeDefn de -> des++[de]
                                   _               -> des

-- datatype with name (tyId) + args (tyArgs) and alternatives
transDataEntry :: DataEntry -> DataTypeTabEntry
transDataEntry (DataEntry _ tyId Le.Free tyArgs alts) = 
                         [((transDName tyId tyArgs), (map transAltDefn alts))]
  where transDName ti ta = Type (showIsaT ti baseSign) [] (map transTypeArg ta)
transDataEntry _ = error "HasCASL2IsabelleHOL.transDataEntry"

-- arguments of datatype's typeconstructor
transTypeArg :: TypeArg -> Typ
transTypeArg (TypeArg tyId _ _ _) = TFree (showIsaT tyId baseSign) []

-- datatype alternatives/constructors
transAltDefn :: AltDefn -> DataTypeAlt
transAltDefn (Construct opId ts Total _) = 
   let ts' = map transType ts
   in case opId of
        Just opId' -> (showIsaT opId' baseSign, ts')
        Nothing  -> ("", ts')
transAltDefn _ = error "HasCASL2IsabelleHOL.transAltDefn"

------------------------------ Formulas ------------------------------

-- simple variables 
transVar :: Var -> String
transVar v = showIsaT v baseSign

transSentence :: Env -> Le.Sentence -> Maybe IsaSign.Term
transSentence sign s = case s of
    Le.Formula t      -> Just (transTerm sign t)
    DatatypeSen _     -> Nothing
    ProgEqSen _ _ _pe -> Nothing

-- disambiguate operation names
transOpId :: Env -> UninstOpId -> TypeScheme -> String
transOpId sign op ts = 
  case (do ops <- Map.lookup op (assumps sign)
           if isSingle (opInfos ops) then return $ showIsaT op baseSign
             else do i <- elemIndex ts (map opType (opInfos ops))
                     return $ showIsaIT op (i+1) baseSign) of
    Just str -> str  
    Nothing  -> showIsaT op baseSign

-- terms
transTerm :: Env -> As.Term -> IsaSign.Term
transTerm _ (QualVar (VarDecl var t _ _)) = 
  let t'  = transType t 
      ot = mkFunType t' $ mkOptionType t'
  in  termAppl (conSomeT ot) (IsaSign.Free (transVar var) t')

transTerm sign (QualOp _ (InstOpId opId _ _) ts _)
  | opId == trueId  =  con "True"
  | opId == falseId = con "False"
  | otherwise       = termAppl conSome (con (transOpId sign opId ts))
-- quantified formulas
transTerm sign (QuantifiedTerm quan varDecls phi _) = 
  foldr (quantify quan) (transTerm sign phi) varDecls
  where
    quantify q gvd phi' = 
      case gvd of
        (GenVarDecl (VarDecl var typ _ _)) ->
          termAppl (con $ qname q) 
               (Abs (con $ transVar var) (transType typ) phi' NotCont)
        (GenTypeVarDecl (TypeArg _ _ _ _)) ->  phi'
    qname Universal   = allS
    qname Existential = exS
    qname Unique      = ex1S
-- strip TypedTerm
transTerm sign (TypedTerm t _ _ _) = 
  case t of ApplTerm _ _ _ -> transApplTerm sign t
            _              -> transTerm sign t
  where
    transApplTerm sig (ApplTerm t' t'' _) = 
      transAppl sig t'
     where  
     -- decides which kind of translation is necessary: formula, predicate, ...
      transAppl s tt =
       case tt of
        QualOp Fun (InstOpId opId _ _) _ _ -> 
        -- logical formulas are translated seperatly (transLog)
          if opId == whenElse then transWhenElse s t''
            else transLog s opId t' t''
        -- predicates
        QualOp Pred _ _ _                  -> 
          termAppl (termAppl (con "pApp") (transTerm s t')) 
                                          (transTerm s t'')
        -- distinguishes between partial and total term application
        QualOp Op _ _ _                    -> transApplOp s t' t''
        -- seeks for determining inner term
        ApplTerm tt' _ _                  -> transAppl s tt'
        -- strips TypedTerm
        TypedTerm tt' _ _ _               -> 
           transAppl s tt'
        _                                  -> mkApp "app" s t' t''
      mkApp s sg tt tt' = termAppl (termAppl (con s) (transTerm sg tt)) 
                         (transTerm sg tt')
      transApplOp s tt tt' =
        case tt of TypedTerm _ _ typ _ ->
                     case typ of FunType _ PFunArr _ _ -> 
                                   mkApp "app" s tt tt'
                                 FunType _ FunArr _ _  -> 
                                   mkApp "apt" s tt tt'
                                 _                     -> 
                                   mkApp "app" s tt tt'
                   _ -> mkApp "app" s tt tt'
    transApplTerm _ _ = error "HasCASL2IsabelleHOL.transApplTerm"

-- lambda abstraction
transTerm sign (LambdaTerm pats p body _) =
  -- distinguishes between partial and total lambda abstraction
  -- total lambda bodies are of type 'a' instead of type 'a option'
  case p of
    Partial -> lambdaAbs transTerm
    Total   -> lambdaAbs transTotalLambda
  where 
   lambdaAbs f =
     if (null pats) then termAppl conSome 
                           (Abs (IsaSign.Free "dummyVar" noType) 
                                    noType (f sign body) NotCont)
--                           (Abs [("dummyVar", noType)] 
--                                      (f sign body) NotCont)
       else termAppl conSome (foldr (abstraction sign) 
                                 (f sign body)
                                 pats)
-- let statement
transTerm sign (LetTerm As.Let peqs body _) = 
  IsaSign.Let (map transProgEq peqs) (transTerm sign body) 
  where
    transProgEq (ProgEq pat t _) = 
      (transPattern sign pat, transPattern sign t)
-- tuple
transTerm sign (TupleTerm ts _) =
  foldl1 (binConst pairC) (map (transTerm sign) ts)
-- case statement
transTerm sign (CaseTerm t peqs _) = 
  -- flatten case alternatives
  let alts = arangeCaseAlts sign peqs
  in
    -- introduces new case statement if case variable is
    -- a term application that may evaluate to 'Some x' or 'None'
    case t of
      QualVar (VarDecl decl _ _ _) -> 
        Case (IsaSign.Free (transVar decl) noType) alts 
      _ -> Case (transTerm sign t)
             ((con "None", con "None"):
               [(App conSome (IsaSign.Free "caseVar" noType) NotCont,
               Case (IsaSign.Free "caseVar" noType) alts)])
transTerm _ _ = error "HasCASL2IsabelleHOL.transTerm"

-- translation formulas with logical connectives
transLog :: Env -> Id -> As.Term -> As.Term -> IsaSign.Term
transLog sign opId opTerm t = case t of
 TupleTerm [l' , r'] _
  | opId == andId  -> binConst conj l r 
  | opId == orId   -> binConst disj l r
  | opId == implId -> binConst impl l r 
  | opId == eqvId  -> binConst eqv  l r
  | opId == exEq   -> binConst conj (binConst eq l r) $ 
                      binConst conj (termAppl defOp l) $ 
                      termAppl defOp r
  | opId == eqId -> binConst eq l r
  where l = transTerm sign l'
        r = transTerm sign r'
 _ | opId == notId  -> termAppl notOp (transTerm sign t)
   | opId == defId  -> termAppl defOp (transTerm sign t)
   | otherwise -> termAppl (transTerm sign opTerm) (transTerm sign t)

-- when else statement
transWhenElse :: Env -> As.Term -> IsaSign.Term
transWhenElse sign t =
    case t of
      TupleTerm terms _ -> 
        let ts = (map (transTerm sign) terms)
        in case ts of
           [i, c, e] -> If c i e NotCont
           _ -> error "HasCASL2IsabelleHOL.transWhenElse.tuple"
      _ -> error "HasCASL2IsabelleHOL.transWhenElse"


--translation of lambda abstractions

-- form Abs(pattern term)
abstraction :: Env -> As.Term -> IsaSign.Term -> IsaSign.Term
abstraction sign pat body = 
    Abs (transPattern sign pat) (getType pat) body NotCont where
--    Abs (transPattern sign pat) body NotCont where
    getType t =
      case t of
        QualVar (VarDecl _ typ _ _) ->  transType typ
        TypedTerm _ _ typ _         -> transType typ
        TupleTerm terms _           -> evalTupleType terms
        _                           -> 
          error "HasCASL2IsabelleHOL.abstraction"
    evalTupleType t = foldr1 IsaSign.prodType (map getType t)

-- translation of lambda patterns 
-- a pattern keeps his type 't', isn't translated to 't option'
transPattern :: Env -> As.Term -> IsaSign.Term
transPattern _ (QualVar (VarDecl var typ _ _)) = 
  IsaSign.Free (transVar var) $ transType typ
transPattern sign (TupleTerm terms _) = 
    foldl1 (binConst isaPair) $ map (transPattern sign) terms
transPattern _ (QualOp _ (InstOpId opId _ _) _ _) = 
    con $ showIsaT opId baseSign
transPattern sign (TypedTerm t _ _ _) = transPattern sign t
transPattern sign (ApplTerm t1 t2 _) = 
    App (transPattern sign t1) (transPattern sign t2) NotCont
transPattern sign t = transTerm sign t

-- translation of total lambda abstraction bodies
transTotalLambda :: Env -> As.Term -> IsaSign.Term
transTotalLambda _ (QualVar (VarDecl var typ _ _)) = 
  IsaSign.Free (transVar var) (transType typ) 
transTotalLambda sign t@(QualOp _ (InstOpId opId _ _) _ _) =
  if opId == trueId || opId == falseId then transTerm sign t
    else con $ showIsaT opId baseSign
transTotalLambda sign (ApplTerm term1 term2 _) =
  termAppl (transTotalLambda sign term1) $ transTotalLambda sign term2
transTotalLambda sign (TypedTerm t _ _ _) = transTotalLambda sign t
transTotalLambda sign (LambdaTerm pats part body _) =
  case part of
    Partial -> lambdaAbs transTerm
    Total   -> lambdaAbs transTotalLambda
  where 
    lambdaAbs f =
      if (null pats) then Abs (IsaSign.Free "dummyVar" noType) 
                               noType (f sign body) NotCont
--      if (null pats) then Abs [("dummyVar", noType)] 
        else foldr (abstraction sign) (f sign body) pats
transTotalLambda sign (TupleTerm terms _) =
  foldl1 (binConst isaPair) $ map (transTotalLambda sign) terms
transTotalLambda sign (CaseTerm t pEqs _) = 
  Case (transTotalLambda sign t) $ map transCaseAltTotal pEqs
  where transCaseAltTotal (ProgEq pat trm _) = 
                (transPat sign pat, transTotalLambda sign trm)
transTotalLambda sign t = transTerm sign t   

----------------- translation of case alternatives ------------------

{- Annotation concerning Patterns:
     Following the HasCASL-Summary and the limits of the encoding
     from HasCASL to Isabelle/HOL patterns may take the form:
        QualVar, QualOp, ApplTerm, TupleTerm and TypedTerm 
-}

-- Input: List of case alternative (one pattern per term)
-- Functionality: Tests wheter pattern is a variable -> case alternative is
--                translated
arangeCaseAlts :: Env -> [ProgEq]-> [(IsaSign.Term, IsaSign.Term)]
arangeCaseAlts sign peqs 
  | and (map patIsVar peqs) = map (transCaseAlt sign) peqs
  | otherwise               =  sortCaseAlts sign peqs
  

{- Input: List of case alternatives, that patterns does consist of
        datatype constructors (with arguments) or tupels
   Functionality: Groups case alternatives by leading
        pattern-constructor each pattern group is flattened 
-}
sortCaseAlts :: Env -> [ProgEq]-> [(IsaSign.Term, IsaSign.Term)]
sortCaseAlts sign peqs = 
  let consList
        | null peqs = error "No case alternatives."
        | otherwise = getCons sign (getName (head peqs))
      groupedByCons = Data.List.nub (map (groupCons peqs) consList)
  in  map (flattenPattern sign) groupedByCons

-- Returns a list of the constructors of the used datatype
getCons :: Env -> TypeId -> [UninstOpId]
getCons sign tyId = 
  extractIds (typeDefn (findInMap tyId (typeMap sign)))
  where extractIds (DatatypeDefn (DataEntry _ _ _ _ altDefns)) =
          catMaybes (map stripConstruct altDefns)
        extractIds _ = error "HasCASL2Isabelle.extractIds"
        stripConstruct (Construct i _ _ _) = i
        findInMap :: Ord k => k -> Map.Map k a -> a 
        findInMap k m = maybe (error "HasCASL2isabelleHOL.findInMap") id $
                Map.lookup k m

-- Extracts the type of the used datatype in case patterns
getName :: ProgEq -> TypeId
getName (ProgEq pat _ _) = (getTypeName pat)

getTypeName :: Pattern -> TypeId
getTypeName p =
   case p of
     QualVar (VarDecl _ typ _ _)       -> name typ
     QualOp _ _ (TypeScheme _ typ _) _ -> name typ
     TypedTerm _ _ typ _               -> name typ
     ApplTerm  t _ _                   -> getTypeName t
     TupleTerm ts _                    -> getTypeName (head ts)
     _  -> error "HasCASL2IsabelleHOL.getTypeName"
   where name tp = case tp of 
                     TypeName tyId _ 0       -> tyId
                     TypeAppl tp' _          -> name tp'
                     FunType _ _ tp' _       -> name tp'
                     ProductType (tp':_) _   -> name tp'
                     _                       -> 
                       error "HasCASL2IsabelleHOL.name (of type)"


-- Input: Case alternatives and name of one constructor
-- Functionality: Filters case alternatives by constructor's name
groupCons :: [ProgEq] -> UninstOpId -> [ProgEq]
groupCons peqs name = filter hasSameName peqs
  where hasSameName (ProgEq pat _ _) = 
           hsn pat
        hsn pat =
          case pat of
            QualOp _ (InstOpId n _ _) _ _ -> n == name
            ApplTerm t1 _ _               -> hsn t1
            TypedTerm t _ _ _             -> hsn t
            TupleTerm _ _                 -> True
            _                             -> False



-- Input: List of case alternatives with same leading constructor
-- Functionality: Tests whether the constructor has no arguments, if so
--                translates case alternatives
flattenPattern :: Env -> [ProgEq] -> (IsaSign.Term, IsaSign.Term)
flattenPattern sign peqs = case peqs of
  [] -> error "Missing constructor alternative in case pattern."
  [h] -> transCaseAlt sign h
  -- at this stage there are patterns left which use 'ApplTerm' or 'TupleTerm'
  -- or the 'TypedTerm' variant of one of them
  _ -> let m = concentrate (matricize peqs) sign in 
              transCaseAlt sign (ProgEq (shrinkPat m) (term m) [])


data CaseMatrix = CaseMatrix { patBrand :: PatBrand,
                               cons     :: Maybe As.Term,
                               args     :: [Pattern],
                               newArgs  :: [Pattern],
                               term     :: As.Term } deriving (Show)

data PatBrand = Appl | Tuple | QuOp | QuVar deriving (Eq, Show)

instance Eq CaseMatrix where
 (==) cmx cmx' = (patBrand cmx   == patBrand cmx') 
                && (args cmx     == args cmx')
                && (term cmx     == term cmx') 
                && (cons cmx     == cons cmx')
                && (newArgs cmx  == newArgs cmx')

{- First of all a matrix is allocated (matriArg) with the arguments of a
 constructor resp.  of a tuple. They're binded with the term, that would
 be executed if the pattern matched.  Then the resulting list of
 matrices is grouped by the leading argument. (groupArgs) Afterwards -
 if a list of grouped arguments has more than one element - the last
 pattern argument (in the list 'patterns') is replaced by a new variable.
 n patterns are reduced to one pattern.
 This procedure is repeated until there's only one case alternative
 for each constructor.
  -}

-- Functionality: turns ProgEq into CaseMatrix
matricize :: [ProgEq] -> [CaseMatrix]
matricize =  map matriPEq


matriPEq :: ProgEq -> CaseMatrix
matriPEq (ProgEq pat altTerm _) = matriArg pat altTerm

matriArg :: Pattern -> As.Term -> CaseMatrix
matriArg pat cTerm =
  case pat of 
    ApplTerm t1 t2 _    -> let (c, p) = stripAppl t1 (Nothing, [])
                           in 
                             CaseMatrix { patBrand = Appl,
                                          cons     =  c,
                                          args     = p ++ [t2],
                                          newArgs  = [],
                                          term     = cTerm }
    TupleTerm ts _      -> CaseMatrix { patBrand = Tuple,
                                        cons     = Nothing,
                                        args     = ts,
                                        newArgs  = [],
                                        term     = cTerm }
    TypedTerm t _ _ _   -> matriArg t cTerm
    qv@(QualVar _)      -> CaseMatrix { patBrand = QuVar,
                                        cons     = Nothing,
                                        args     = [qv],
                                        newArgs  = [],
                                        term     = cTerm }
    qo@(QualOp _ _ _ _) -> CaseMatrix { patBrand = QuOp,
                                        cons     = Nothing,
                                        args     = [qo],
                                        newArgs  = [],
                                        term     = cTerm }
    _                   -> error "HasCASL2IsabelleHOL.matriArg"
-- Assumption: The innermost term of a case-pattern consisting of a ApplTerm
--             is a QualOp, that is a datatype constructor
  where stripAppl ct tp = case ct of
            TypedTerm (ApplTerm q@(QualOp _ _ _ _) t' _) _ _ _ -> 
                (Just q, [t'] ++ snd tp)
            TypedTerm (ApplTerm (TypedTerm 
              q@(QualOp _ _ _ _) _ _ _) t' _) _ _ _ -> (Just q, [t'] ++ snd tp)
            TypedTerm (ApplTerm t' t'' _) _ _ _                -> 
              stripAppl t' (fst tp, [t''] ++ snd tp)
            ApplTerm q@(QualOp _ _ _ _) t' _ -> (Just q, [t'] ++ snd tp)
            ApplTerm (TypedTerm 
              q@(QualOp _ _ _ _) _ _ _) t' _ -> (Just q, [t'])
            ApplTerm t' t'' _                -> 
              stripAppl t' (fst tp, [t''] ++ snd tp)
--            TypedTerm t' _ _ _               -> stripAppl t' tp
            q@(QualOp _ _ _ _)               -> (Just q, snd tp)
            _                                -> (Nothing, [ct] ++ snd tp)

-- Input: List with CaseMatrix of same leading constructor pattern
-- Functionality: First: Groups CMs so that these CMs are in one list
--                that only differ in their last argument
--                then: reduces list of every CMslist to one CM
concentrate :: [CaseMatrix] -> Env -> CaseMatrix
concentrate cmxs sign = case map (redArgs sign) $ 
                        nub $ map (groupByArgs cmxs) [0..(length cmxs-1)] of
  [h] -> h
  l -> concentrate l sign 


groupByArgs :: [CaseMatrix] -> Int -> [CaseMatrix]
groupByArgs cmxs i
  | and (map null (map args cmxs)) = cmxs
  | otherwise                      = (filter equalPat cmxs)
  where patE = init (args (cmxs !! i))
        equalPat cmx = isSingle (args cmx) || init (args cmx) == patE


redArgs :: Env -> [CaseMatrix] -> CaseMatrix
redArgs sign cmxs
  | and (map (testPatBrand Appl) cmxs)  = redAppl cmxs sign
  | and (map (testPatBrand Tuple) cmxs) = redAppl cmxs sign
  | isSingle cmxs                       = head cmxs
  | otherwise                           = head cmxs
  where testPatBrand pb cmx = pb == patBrand cmx

{- Input: List of CMs thats leading constructor and arguments except
       the last one are equal 
   Functionality: Reduces n CMs to one with same last argument in 
       pattern (perhaps a new variable 
-}
redAppl :: [CaseMatrix] -> Env -> CaseMatrix
redAppl cmxs sign
  | and (map null (map args cmxs)) = head cmxs
  | isSingle cmxs                  = 
      (head cmxs) { args     = init $ args $ head cmxs,
                    newArgs  = last (args $ head cmxs) : newArgs (head cmxs) }
  | and (map termIsVar lastArgs)        = substVar (head cmxs)
  | otherwise                           = substTerm (head cmxs)
   where terms = map term cmxs
         lastArgs = map last (map args cmxs)
         varName = "caseVar" ++ show (length (args (head cmxs)))
         varId = (mkId [(mkSimpleId varName)])
         newVar = QualVar (VarDecl varId (TypeName varId MissingKind 1) 
                           Other [])
         newPeqs = (map newProgEq (zip lastArgs terms))
         newPeqs' = recArgs sign newPeqs
         substVar cmx 
           | null (args cmx)     = cmx
           | isSingle (args cmx) = 
               cmx { args    = [],
                     newArgs = last(args cmx) : (newArgs cmx) }
           | otherwise                =
               cmx { args    = init (args cmx),
                     newArgs = last(args cmx) : (newArgs cmx) }
         substTerm cmx
           | null (args cmx)     = cmx
           | isSingle (args cmx) =
               cmx { args    = [], 
                     newArgs = newVar : (newArgs cmx),
                     term    = CaseTerm newVar newPeqs' [] }
           | otherwise                =
               cmx { args    = init(args cmx), 
                     newArgs = newVar : (newArgs cmx),
                     term    = CaseTerm newVar newPeqs' [] }
         newProgEq (p, t) = ProgEq p t []

-- Input: ProgEqs that were build to replace an argument 
--        with a case statement
-- Functionality: 
recArgs :: Env -> [ProgEq] -> [ProgEq]
recArgs sign peqs 
  | isSingle groupedByCons 
      || null groupedByCons = []
  | otherwise               = doPEQ groupedByCons []
  where consList
          | null peqs = error "No case alternatives."
          | otherwise    = getCons sign (getName (head peqs))
        groupedByCons = map (groupCons peqs) consList
        doPEQ [] res = res
        doPEQ (g:gByCs) res
          | isSingle g = doPEQ gByCs (res ++ g)
          | otherwise  = doPEQ gByCs (res ++ [(toPEQ (testPEQs sign g))])
        toPEQ cmx = ProgEq (shrinkPat cmx) (term cmx) []
        testPEQs sig ps
          | null peqs = error "HasCASL2IsabelleHOL.testPEQs"
          | otherwise = concentrate (matricize ps) sig

-- accumulates arguments of caseMatrix to one pattern
shrinkPat :: CaseMatrix -> As.Term
shrinkPat cmx = 
  case patBrand cmx of
    Appl  -> case cons cmx of
               Just c ->  foldl mkApplT c ((args cmx) ++ (newArgs cmx))
               Nothing -> error "HasCASL2IsabelleHOL.shrinkPat"
    Tuple -> TupleTerm ((args cmx) ++ (newArgs cmx)) []
    QuOp  -> head (args cmx)
    _     -> head (newArgs cmx)
  where mkApplT t1 t2 = ApplTerm t1 t2 []


patIsVar :: ProgEq -> Bool
patIsVar (ProgEq pat _ _) = termIsVar pat

termIsVar :: As.Term -> Bool
termIsVar t = case t of
                QualVar _          -> True
                TypedTerm tr _ _ _ -> termIsVar tr
                TupleTerm ts _     -> and (map termIsVar ts)
                _                  -> False

patHasNoArg :: ProgEq -> Bool
patHasNoArg (ProgEq pat _ _) = termHasNoArg pat

termHasNoArg :: As.Term -> Bool
termHasNoArg t = case t of
                 QualOp _ _ _ _     -> True
                 TypedTerm tr _ _ _ -> termHasNoArg tr
                 _                  -> False

transCaseAlt :: Env -> ProgEq -> (IsaSign.Term, IsaSign.Term)
transCaseAlt sign (ProgEq pat trm _) = 
  (transPat sign pat, (transTerm sign trm))

transPat :: Env -> As.Term -> IsaSign.Term
transPat _ (QualVar (VarDecl var _ _ _)) = 
    IsaSign.Free (transVar var) noType 
transPat sign (ApplTerm term1 term2 _) = 
  termAppl (transPat sign term1) (transPat sign term2)
transPat sign (TypedTerm trm _ _ _) = transPat sign trm
transPat sign (TupleTerm terms _) =
  foldl1 (binConst isaPair) (map (transPat sign) terms)
transPat _ (QualOp _ (InstOpId i _ _) _ _) = con (showIsaT i baseSign)
transPat _ _ =  error "HasCASL2IsabelleHOL.transPat"

