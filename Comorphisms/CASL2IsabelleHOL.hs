{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski and Uni Bremen 2003
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

   The embedding comorphism from CASL to Isabelle-HOL.
-}

{- todo
    disambiguate names (i.e. those coming from Main)
-}

module Comorphisms.CASL2IsabelleHOL where

import Logic.Logic as Logic
import Logic.Comorphism
import Common.AS_Annotation
import Common.Id
import Common.Result
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import Data.List as List
import Data.Maybe
import Data.Char
-- CASL
import CASL.Logic_CASL 
import CASL.AS_Basic_CASL
import CASL.Sublogic
import CASL.Sign
import CASL.Morphism
import CASL.Quantification 

-- Isabelle
import Isabelle.IsaSign as IsaSign
import Isabelle.IsaConsts
import Isabelle.Logic_Isabelle
import Isabelle.Translate

-- | The identity of the comorphism
data CASL2IsabelleHOL = CASL2IsabelleHOL deriving (Show)

-- Isabelle theories
type IsaTheory = (IsaSign.Sign,[Named IsaSign.Sentence])

-- extended signature translation
type SignTranslator f e = CASL.Sign.Sign f e -> e -> IsaTheory -> IsaTheory

-- extended signature translation for CASL
sigTrCASL :: SignTranslator () ()
sigTrCASL _ _ = id

-- extended formula translation
type FormulaTranslator f e = CASL.Sign.Sign f e -> f -> Term

-- extended formula translation for CASL
formTrCASL :: FormulaTranslator () ()
formTrCASL _ _ = error "CASL2IsabelleHOL: No extended formulas allowed in CASL"

instance Language CASL2IsabelleHOL -- default definition is okay

instance Comorphism CASL2IsabelleHOL
               CASL CASL.Sublogic.CASL_Sublogics
               CASLBasicSpec CASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CASLSign 
               CASLMor
               CASL.Morphism.Symbol CASL.Morphism.RawSymbol ()
               Isabelle () () IsaSign.Sentence () ()
               IsaSign.Sign 
               IsabelleMorphism () () ()  where
    sourceLogic _ = CASL
    sourceSublogic _ = CASL_SL
                      { has_sub = False, -- no subsorting yet ...
                        has_part = False, -- no partiality yet ...
                        has_cons = True,
                        has_eq = True,
                        has_pred = True,
                        which_logic = FOL
                      }
    targetLogic _ = Isabelle
    targetSublogic _ = ()
    map_theory _ = transTheory sigTrCASL formTrCASL
    map_morphism CASL2IsabelleHOL mor = do
       (sig1,_) <- map_sign CASL2IsabelleHOL (Logic.dom CASL mor)
       (sig2,_) <- map_sign CASL2IsabelleHOL (cod CASL mor)
       inclusion Isabelle sig1 sig2
    map_sentence _ sign =
      return . mapSen formTrCASL sign
    map_symbol _ _ = error "CASL2Isabelle.map_symbol"

------------------------------ Ids ---------------------------------


---------------------------- Signature -----------------------------
baseSign :: String
baseSign = "Main"

transTheory :: SignTranslator f e ->
               FormulaTranslator f e ->
               (CASL.Sign.Sign f e, [Named (FORMULA f)])
                   -> Result IsaTheory 
transTheory trSig trForm (sign,sens) = 
  fmap (trSig sign (extendedInfo sign)) $
  return (IsaSign.emptySign {
    baseSig = baseSign,
    tsig = emptyTypeSig {arities = 
               Set.fold (\s -> let s1 = (showIsaT s baseSign) in
                                if s1 `elem` dtTypes then id
                                 else Map.insert s1 [(isaTerm, [])]) 
                               Map.empty (sortSet sign)},
    constTab = Map.foldWithKey insertPreds
                (Map.filterWithKey (isNotIn dtDefs) 
                $ Map.foldWithKey insertOps Map.empty 
                $ opMap sign) $ predMap sign,
    dataTypeTab = dtDefs},      
     map (mapNamed (mapSen trForm sign)) real_sens)  
     -- for now, no new sentences
  where 
    (real_sens, sort_gen_axs) = List.partition 
        (\ s -> case sentence s of
                Sort_gen_ax _ _ -> False
                _ -> True) sens
    dtDefs = topoSort (makeDtDefs sign sort_gen_axs)
    dtTypes = map ((\(Type s _ _) -> s).fst) $ concat dtDefs
    insertOps op ts m = 
     if Set.size ts == 1 
      then Map.insert (showIsaT op baseSign) (transOpType (Set.findMin ts)) m
      else 
      foldl (\m1 (t,i) -> Map.insert (showIsaIT op i baseSign) 
                          (transOpType t) m1) m 
            (zip (Set.toList ts) [1..(Set.size ts)])
    insertPreds pre ts m =
     if Set.size ts == 1 
      then Map.insert (showIsaT pre baseSign) 
               (transPredType (Set.findMin ts)) m
      else
      foldl (\m1 (t,i) -> Map.insert (showIsaIT pre i baseSign) 
                          (transPredType t) m1) m 
            (zip (Set.toList ts) [1..Set.size ts])

-- | filter out constructors from data types  
isNotIn :: DataTypeTab -> VName -> Typ -> Bool
isNotIn l a _ = all (all (isNotIn' a . snd)) l where
    isNotIn' :: VName -> [DataTypeAlt] -> Bool
    isNotIn' c = all ((/= c) . fst)

-- topoSort 
-- A(i) = [[j]] with definition of datatype i needs j
-- inI(i) = [n] i is needed by n other definions
-- (1) L<-[]
-- (2) for i=1 to n do inI(i)<-0 od;
-- (3) for i=1 to n do 
-- (4)   for (j elem A(i)) do inI(j)<-inI(j) + 1 od
-- (5) od;
-- (6) for i=1 to n do 
-- (7)   if inI(i) = 0  then i:L fi 
-- (8) od; 
-- (9) while L != [] do
--(10)   v <- head(L)
--(11)   L <- tail(L)
--(12)   sortedList <- sortedList ++ v
--(13)   for (w elem A(v)) do
--(14)       inI(w) <- inI(w) - 1
--(15)       if inI(w)=0 then L<- L++w fi
--(16)   od;
--(17) od;
topoSort :: [[(Typ, [(a, [Typ])])]] -> [[(Typ, [(a, [Typ])])]]
topoSort [] = []
topoSort dts = whileL (collectL inI_ 1) inI_ adI_ dts
    where 
    (inI_, adI_) =  makeLists [] dts 1 (map (const 0) dts) 
                    $ map (const [0]) dts
    -- generate both A- and inI-list
    makeLists :: [[(Typ, [(a, [Typ])])]] -> [[(Typ, [(a, [Typ])])]] -> 
                 Int -> [Int] -> [[Int]] -> ([Int], [[Int]])
    makeLists _ [] _ inI ad = (inI, ad)
    makeLists as1 (a:as2) n inI ad = 
        if (snd (findIn as1 a n [])) == True then
           makeLists (concat [as1, [a]]) as2 (n+1)  updateIn1 updateAdj1
        else 
           if (snd (findIn as2 a n [])) == True then
              makeLists (concat [as1,[a]]) as2 (n+1) updateIn2 updateAdj2
           else makeLists (concat [as1, [a]]) as2 (n+1) inI ad
        where 
        updateAdj1 = updateAdj ad (fst (findIn as1 a n [])) 0
        updateAdj2 = updateAdj ad (fst (findIn as2 a n [])) n
        updateIn1  = updateIn inI (count (fst (findIn as1 a n []))) n 
        updateIn2  = updateIn inI (count (fst (findIn as1 a n [])) + 
                                   count (fst (findIn as2 a n []))) n
    -- is Type a in the list (b:bs)
    findIn :: [[(Typ, [(a, [Typ])])]] -> [(Typ, [(a, [Typ])])] 
           -> Int -> [Int]-> ([Int], Bool) 
    findIn [] _ _ l = (if (sum l) > 0 then (l, True) else ([], False))
    findIn (b:bs) a n l = findIn bs a n (concat [l, list])
        where
        list = map (compareTypes n (getType (head b))) 
               $ concat (getUsedTypes (snd (head a)))
    compareTypes n t1 t2 = if t1 == t2 then n else 0
    -- returns the typename of a
    getType a = let (Type d _ _) = fst a in d
    -- returns all used types
    getUsedTypes [] = []
    getUsedTypes (b:bs) = (getUsedType (snd b)) :(getUsedTypes bs)
    getUsedType  [] = []
    getUsedType  (c:cs) = let (Type d _ _) = c in d :(getUsedType cs) 
    updateAdj :: [[a]] -> [a] -> Int -> [[a]]
    updateAdj (ad:ads) (c:cs) 0 = (c:ad):(updateAdj ads cs 0)   
    updateAdj (ad:ads) cs n = ad:(updateAdj ads cs (n-1))
    updateAdj ad _ _ = ad
    count as = length (List.filter (> 0) as)
    updateIn [] _ _ = error "topoSort.updateIn"
    updateIn (_ : inIs) c 1 = c:inIs           
    updateIn (inI:inIs) c n = inI:(updateIn inIs c (n-1)) 
    -- Lines 6-8                      
    collectL [] _ = []
    collectL (inI:inIs) i = if inI == 0 then i:(collectL inIs (i+1)) 
                            else (collectL inIs (i+1))

    -- Lines 9-16
    whileL [] _ _ _ = []
    whileL (l:ls) inI adI dtDefs = selElemAt l dtDefs 
                                   : whileL newLs newInIs adI dtDefs
        where 
        newLs = concat [ls, snd(updateInI2 (selElemAt l adI) inI 1 [] [])]
        newInIs = fst(updateInI2 (selElemAt l adI) inI 1 [] [])
        updateInI2 _  []  _ newL ins = (reverse ins, reverse newL)
        updateInI2 [] inI' _ _ _   = (inI', [])
        updateInI2 listOfInd (inI':inIs) n newL ins =
                 let dInI = inI' - 1 in 
                 if n `elem` listOfInd then 
                    if dInI == 0 then
                       updateInI2 listOfInd inIs (n+1) (n:newL) (dInI:ins)
                    else 
                       updateInI2 listOfInd inIs (n+1) newL (dInI:ins)
                 else updateInI2 listOfInd inIs (n+1) newL (inI':ins)
    -- get the l-th value from the list 
    selElemAt :: Int -> [a] -> a
    selElemAt l xs = xs !! (l - 1)                                  

makeDtDefs :: CASL.Sign.Sign f e -> [Named (FORMULA f)] 
               -> [[(Typ,[(String,[Typ])])]]
makeDtDefs sign = delDoubles . (mapMaybe $ makeDtDef sign)
  where
  delDoubles xs = delDouble xs []
  delDouble [] _  = []
  delDouble (x:xs) sortList = let (Type s _a _b) = fst (head x) in
      if (length sortList) == 
         (length (addSortList s sortList)) then
        delDouble xs sortList
      else
        (x:(delDouble xs (s:sortList)))
  addSortList x xs = (List.nub (x :xs))


makeDtDef :: CASL.Sign.Sign f e -> Named (FORMULA f) -> 
             Maybe [(Typ,[(String,[Typ])])]
makeDtDef sign (NamedSen _ (Sort_gen_ax constrs True)) =
  Just(map makeDt srts) 
  where 
  (srts,ops,_maps) = recover_Sort_gen_ax constrs
  makeDt s = (transSort s, map makeOp (List.filter (hasTheSort s) ops))
  makeOp opSym = (transOP_SYMB sign opSym, transArgs opSym)
  hasTheSort s (Qual_op_name _ ot _) = s == res_OP_TYPE ot 
  hasTheSort _ _ = error "CASL2IsabelleHOL.hasTheSort"
  transArgs (Qual_op_name _ ot _) = map transSort $ args_OP_TYPE ot
  transArgs _ = error "CASL2IsabelleHOL.transArgs"
makeDtDef _ _ = Nothing

transSort :: SORT -> Typ
transSort s = Type (showIsaT s baseSign) [] []

transOpType :: OpType -> Typ
transOpType ot = mkCurryFunType (map transSort $ opArgs ot) 
                 $ transSort (opRes ot)

transPredType :: PredType -> Typ
transPredType pt = mkCurryFunType (map transSort $ predArgs pt) boolType


------------------------------ Formulas ------------------------------

var :: String -> Term
--(c) var v = IsaSign.Free v noType isaTerm
var v = IsaSign.Free v noType

transVar :: VAR -> String
transVar v = showIsaT (simpleIdToId v) baseSign

xvar :: Int -> String
xvar i = if i<=26 then [chr (i+ord('a'))] else "x"++show i

rvar :: Int -> String
rvar i = if i<=9 then [chr (i+ord('R'))] else "R"++show i

quantifyIsa :: String -> (String, Typ) -> Term -> Term
quantifyIsa q (v,t) phi =
  App (Const q noType) (Abs (Free v noType) t phi NotCont) NotCont
--(c) App (Const q noType isaTerm) (Abs (Cont v noType isaTerm) t phi NotCont) 
--(c) NotCont
--quantifyIsa :: String -> (String, Typ) -> Term -> Term
--quantifyIsa q (v,t) phi =
-- App (Const q) (Abs [(Free v, t)] phi NotCont) NotCont

quantify :: QUANTIFIER -> (VAR, SORT) -> Term -> Term
quantify q (v,t) phi  = 
  quantifyIsa (qname q) (transVar v, transSort t) phi
  where
  qname Universal = allS
  qname Existential = exS
  qname Unique_existential = ex1S

transOP_SYMB :: CASL.Sign.Sign f e -> OP_SYMB -> String
transOP_SYMB sign (Qual_op_name op ot _) = 
  case (do ots <- Map.lookup op (opMap sign) 
           if Set.size ots == 1 then return $ showIsaT op baseSign
            else do i <- elemIndex (toOpType ot) (Set.toList ots)
                    return $ showIsaIT op (i+1) baseSign) of
    Just str -> str  
    Nothing -> showIsaT op baseSign
transOP_SYMB _ (Op_name _) = error "CASL2Isabelle: unqualified operation"

transPRED_SYMB :: CASL.Sign.Sign f e -> PRED_SYMB -> String
transPRED_SYMB sign (Qual_pred_name p pt _) =
  case (do pts <- Map.lookup p (predMap sign)
           if Set.size pts == 1 then return $ showIsaT p baseSign 
            else do i <- elemIndex (toPredType pt) (Set.toList pts)
                    return $ showIsaIT p (i+1) baseSign) of
    Just str -> str
    Nothing -> error "CASL2Isabelle: showIsaT p baseSign"
transPRED_SYMB _ (Pred_name _) = error "CASL2Isabelle: unqualified predicate"

mapSen :: FormulaTranslator f e -> CASL.Sign.Sign f e -> FORMULA f -> Sentence
mapSen trFrom sign phi = 
  Sentence {senTerm = transFORMULA sign trFrom phi}


transFORMULA :: CASL.Sign.Sign f e -> FormulaTranslator f e 
                -> FORMULA f -> Term
transFORMULA sign tr (Quantification qu vdecl phi _) =
  foldr (quantify qu) (transFORMULA sign tr phi) (flatVAR_DECLs vdecl)
transFORMULA sign tr (Conjunction phis _) =
  if null phis then true
  else foldl1 binConj (map (transFORMULA sign tr) phis)
transFORMULA sign tr (Disjunction phis _) =
  if null phis then false
  else foldl1 binDisj (map (transFORMULA sign tr) phis)
transFORMULA sign tr (Implication phi1 phi2 _ _) =
  binImpl (transFORMULA sign tr phi1) (transFORMULA sign tr phi2)
transFORMULA sign tr (Equivalence phi1 phi2 _) =
  binEqv (transFORMULA sign tr phi1) (transFORMULA sign tr phi2)
transFORMULA sign tr (Negation phi _) =
  termAppl notOp (transFORMULA sign tr phi)
transFORMULA _sign _tr (True_atom _) = true
transFORMULA _sign _tr (False_atom _) = false
transFORMULA sign tr (Predication psymb args _) =
  foldl termAppl
            (con $ transPRED_SYMB sign psymb)
            (map (transTERM sign tr) args)
transFORMULA sign tr (Strong_equation t1 t2 _) =
  binEq (transTERM sign tr t1) (transTERM sign tr t2)
transFORMULA sign tr (ExtFORMULA phi) =
  tr sign phi
transFORMULA _sign _tr _ = 
  error "CASL2Isabelle.transFORMULA"

transTERM :: CASL.Sign.Sign f e
             -> (CASL.Sign.Sign f e -> f -> Term) -> TERM f -> Term
transTERM _sign _tr (Qual_var v _s _) =
  var $ transVar v
transTERM sign tr (Application opsymb args _) =
  foldl termAppl
            (con $ transOP_SYMB sign opsymb)
            (map (transTERM sign tr) args)
transTERM sign tr (Conditional t1 phi t2 _) =
  foldl termAppl (con "If") [transFORMULA sign tr phi,
       transTERM sign tr t1, transTERM sign tr t2]
transTERM _sign _tr _ =
  error "CASL2IsabelleHOL.transTERM" 


