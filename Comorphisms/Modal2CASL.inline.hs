{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich and Uni Bremen 2004
Licence     :  All rights reserved.

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

   
   The possible world encoding comorphism from ModalCASL to CASL.

   We use the Relational Translation by adding one extra parameter of
   type world to each predicate.

   todo:
     - translate / generate formulas from modality formulas .. done
     - correct the overloaded flexible Ops / Preds lookup
     - add a place to mixfix identifiers

-}

module Comorphisms.Modal2CASL (Modal2CASL(..)) where

import Logic.Logic
import Logic.Comorphism
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Map as Map
import Common.AS_Annotation
import Common.Id

-- CASL
import CASL.Logic_CASL 
import CASL.Sublogic
import CASL.Sign
import CASL.AS_Basic_CASL
import CASL.Morphism

-- ModalCASL
import Modal.Logic_Modal
import Modal.AS_Modal
import Modal.ModalSign

import Data.Maybe (mapMaybe)
import Control.Exception (assert)

-- generated function
import Modal.ModalSystems

-- Debugging
import Debug.Trace

-- | The identity of the comorphism
data Modal2CASL = Modal2CASL deriving (Show)

instance Language Modal2CASL -- default definition is okay

instance Comorphism Modal2CASL
               Modal ()
               M_BASIC_SPEC ModalFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               MSign 
               ModalMor
               Symbol RawSymbol ()
               CASL CASL_Sublogics
               CASLBasicSpec CASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CASLSign 
               CASLMor
               Symbol RawSymbol () where
    sourceLogic Modal2CASL = Modal
    sourceSublogic Modal2CASL = ()
    targetLogic Modal2CASL = CASL
    targetSublogic Modal2CASL = CASL_SL
                      { has_sub = True, 
                        has_part = True,
                        has_cons = True,
                        has_eq = True,
                        has_pred = True,
                        which_logic = FOL
                      }
    map_sign Modal2CASL sig = 
	case transSig sig of 
	mme ->  Just (caslSign mme,relFormulas mme)
    map_morphism Modal2CASL = Just . mapMor
    map_sentence Modal2CASL sig = Just . transSen sig
    map_symbol Modal2CASL = Set.single . mapSym

data ModName = SimpleM SIMPLE_ID
	     | SortM   SORT 
	       deriving (Show,Ord,Eq)
 
type ModalityRelMap = Map.Map ModName PRED_NAME
data ModMapEnv = MME { caslSign :: CASLSign,
		       worldSort :: SORT, 
		       modalityRelMap :: ModalityRelMap,
		       flexOps :: Map.Map OP_NAME (Set.Set OpType),
--		       rigOps :: Map.Map OP_NAME (Set.Set OpType),
		       flexPreds :: Map.Map PRED_NAME (Set.Set PredType),
--		       rigPreds :: Map.Map PRED_NAME (Set.Set PredType),
		       relFormulas :: [Named CASLFORMULA]
		     } 

--  (CASL signature,World sort introduced,[introduced relations on possible worlds],)


transSig :: MSign -> ModMapEnv 
transSig sign =
 {-   trace ("Flexible Ops: " ++ show flexibleOps ++
           "\nRigid Ops: "  ++ show rigOps' ++
	   "\nOriginal Ops: " ++ show (opMap sign) ++ "\n" ++
	   "Flexible Preds: " ++ show flexiblePreds ++
           "\nRigid Preds: "  ++ show rigPreds' ++
	   "\nOriginal Preds: " ++ show (predMap sign) ++ "\n"
          )  -}
    MME {caslSign = 
	    (emptySign ()) 
               {sortSet = Set.insert fws sorSet 
	       , sortRel = sortRel sign
	       , opMap = Map.unionWith Set.union flexOps' rigOps' 
	       , assocOps = diffMapSet (assocOps sign) flexibleOps
	       , predMap = Map.unionWith Set.union flexPreds' rigPreds'},
         worldSort = fws,
	 modalityRelMap = relations,
	 flexOps = flexibleOps,
--	 rigOps = rigOps',
	 flexPreds = flexiblePreds,
--	 rigPreds = rigPreds',
	 relFormulas = relFrms}
    where sorSet     = sortSet sign
	  fws        = freshWorldSort sorSet
	  flexOps'   = Map.foldWithKey (addWorld_OP fws) 
		                       Map.empty $ flexibleOps
	  flexPreds' = addWorldRels $ 
	               Map.foldWithKey (addWorld_PRED fws) 
			               Map.empty $ flexiblePreds
	  rigOps'    = rigidOps $ extendedInfo sign
	  rigPreds'  = rigidPreds $ extendedInfo sign
	  flexibleOps     = diffMapSet (opMap sign) rigOps'
	  flexiblePreds   = diffMapSet (predMap sign) rigPreds'
	  resultOfSimpleModies =
	       Map.foldWithKey (\me frms (nm,trFrms) -> 
				    case Id [mkSimpleId "g_R"] 
					            [mkId [me]] [] of
				    relSymb -> 
				      (Map.insert (SimpleM me) relSymb nm,
				       trFrms ++ 
				         transSchemaMFormulas 
				                  fws relSymb frms))
			(Map.empty,[]) 
			(modies $ extendedInfo sign)
	  (relations,relFrms) = 
	      Map.foldWithKey (\me frms (nm,trFrms) -> 
			           case Id [mkSimpleId "g_R_t"] [me] [] of
			           relSymb ->
			             (Map.insert (SortM me) relSymb nm,
				      trFrms ++ 
				      transSchemaMFormulas 
				                 fws relSymb frms))
		                resultOfSimpleModies
				(termModies $ extendedInfo sign)
	  addWorldRels mp = 
               Map.fold (\rs nm -> Map.insert rs 
			                      (Set.single $ PredType [fws,fws])
                                              nm) 
		        mp relations

{- ModalSign { rigidOps :: Map.Map Id (Set.Set OpType)
   , rigidPreds :: Map.Map Id (Set.Set PredType)
   , modies :: Set.Set SIMPLE_ID
   , termModies :: Set.Set Id --SORT
			      }

-}

mapMor :: ModalMor -> CASLMor
mapMor m = Morphism {msource = caslSign $ transSig $ msource m
	           , mtarget = caslSign $ transSig $ mtarget m
                   , sort_map = sort_map m
                   , fun_map = fun_map m
                   , pred_map = pred_map m
	           , extended_map = ()}


mapSym :: Symbol -> Symbol
mapSym = id  -- needs to be changed once modal symbols are added

transSchemaMFormulas :: SORT -> PRED_NAME 
		     -> [AnModFORM] -> [Named CASLFORMULA]
transSchemaMFormulas fws relSymb = 
    mapMaybe (transSchemaMFormula fws relSymb worldVars)

transSen :: MSign -> ModalFORMULA -> CASLFORMULA
transSen msig = mapSenTop (transSig msig) 

mapSenTop :: ModMapEnv -> ModalFORMULA -> CASLFORMULA
mapSenTop mapEnv@(MME{worldSort = fws}) f =
    case f of
    Quantification q@(Universal) vs frm ps ->
	Quantification q (qwv:vs) (mapSen mapEnv wvs frm) ps
    f1 -> Quantification Universal [qwv] (mapSen mapEnv wvs f1) []
    where qwv = Var_decl wvs fws []
	  wvs = [head worldVars]


-- head [VAR] is always the current world variable (for predication) 
mapSen :: ModMapEnv -> [VAR] -> ModalFORMULA -> CASLFORMULA
mapSen mapEnv@(MME{worldSort = fws,flexPreds=fPreds}) vars
       f = case f of 
	   Quantification q vs frm ps ->
		  Quantification q vs (mapSen mapEnv vars frm) ps
	   Conjunction fs ps -> 
	       Conjunction (map (mapSen mapEnv vars) fs) ps 
	   Disjunction fs ps -> 
	       Disjunction (map (mapSen mapEnv vars) fs) ps
	   Implication f1 f2 b ps ->
	       Implication (mapSen mapEnv vars f1) (mapSen mapEnv vars f2) b ps
	   Equivalence f1 f2 ps -> 
	       Equivalence (mapSen mapEnv vars f1) (mapSen mapEnv vars f2) ps
	   Negation frm ps -> Negation (mapSen mapEnv vars frm) ps
	   True_atom ps -> True_atom ps
	   False_atom ps -> False_atom ps
	   Existl_equation t1 t2 ps -> 
	       Existl_equation (mapTERM mapEnv vars t1) (mapTERM mapEnv vars t2) ps
	   Strong_equation t1 t2 ps -> 
		  Strong_equation (mapTERM mapEnv vars t1) (mapTERM mapEnv vars t2) ps
	   Predication pn as qs ->
	       let as'        = map (mapTERM mapEnv vars) as
		   fwsTerm    = sortedWorldTerm fws (head vars) 
		   (pn',as'') =  
		       case pn of
		       Pred_name _ -> error "Modal2CASL: untyped predication" 
		       Qual_pred_name prn pType@(Pred_type sorts pps) ps ->
		         let addTup = (Qual_pred_name (addPlace prn) 
                                             (Pred_type (fws:sorts) pps) ps,
				       fwsTerm:as')
			     defTup = (pn,as') in
		          maybe defTup
			    (\ ts -> assert (not $ Set.isEmpty ts) 
                                 (if Set.member (toPredType pType) ts 
				     then addTup
			             else defTup))
			    (Map.lookup prn fPreds)
	       in Predication pn' as'' qs
	   Definedness t ps -> Definedness (mapTERM mapEnv vars t) ps
	   Membership t ty ps -> Membership (mapTERM mapEnv vars t) ty ps
	   Sort_gen_ax constrs isFree -> Sort_gen_ax constrs isFree
	   ExtFORMULA mf -> mapMSen mapEnv vars mf 
	   _ -> error "Modal2CASL.transSen->mapSen"

mapMSen :: ModMapEnv -> [VAR] -> M_FORMULA -> CASLFORMULA
mapMSen mapEnv@(MME{worldSort=fws,modalityRelMap=pwRelMap}) vars f
   = let trans_f1 = mkId [mkSimpleId "Place Holder for Formula"] 
	 (w1,w2,newVars) = assert (not (null vars)) 
                           (let nVars = 
				 freshWorldVar (vars) : vars
                            in (head vars, head nVars, nVars))
	 getRel mo map' = 
	      Map.findWithDefault 
                    (error ("Modal2CASL: Undefined modality " ++ show mo)) 
		    (modalityToModName mo)
		    map'
	 trans' propSymb trForm nvs f1 = 
	     replacePropPredication propSymb (mapSen mapEnv nvs f1) trForm
     in
     case f of
     Box     moda f1 _ -> 
          case map sentence
               $  concat [inlineAxioms CASL
		       " sort fws \n\
		       \ pred rel : fws * fws; \n\
		       \      trans_f1 : () \n\
		       \ vars w1 : fws \n\
		       \ . forall w2 : fws . rel(w1,w2) => \n\
		       \      trans_f1"
		       | let rel = getRel moda pwRelMap] of 
		   [newFormula] -> trans' trans_f1 newFormula newVars f1
		   _  -> error "Modal2CASL: mapMSen: impossible error"
     Diamond moda f1 _ -> 
          case map sentence
               $  concat [inlineAxioms CASL
		       " sort fws \n\
		       \ pred rel : fws * fws; \n\
		       \      trans_f1 : () \n\
		       \ vars w1 : fws \n\
		       \ . exists w2 : fws . rel(w1,w2) /\\ \n\
		       \      trans_f1"
		       | let rel = getRel moda pwRelMap] of 
		   [newFormula] -> trans' trans_f1 newFormula newVars f1
		   _  -> error "Modal2CASL: mapMSen: impossible error"

-- head [VAR] is always the current world variable (for Application) 
mapTERM :: ModMapEnv -> [VAR] -> TERM M_FORMULA -> TERM ()
mapTERM mapEnv@(MME{worldSort=fws,flexOps=fOps}) vars t = case t of
    Qual_var v ty ps -> Qual_var v ty ps
    Application opsym as qs  -> 
	let as'        = map (mapTERM mapEnv vars) as
	    fwsTerm    = sortedWorldTerm fws (head vars) 
	    addFws (Partial_op_type sorts res pps) = 
		Partial_op_type (fws:sorts) res pps
	    addFws (Total_op_type sorts res pps) = 
		Total_op_type (fws:sorts) res pps
	    (opsym',as'') =  
		case opsym of
		Op_name _ -> error "Modal2CASL: untyped prdication" 
		Qual_op_name on opType ps ->
		    let addTup = (Qual_op_name (addPlace on) 
                                               (addFws opType) ps,
				  fwsTerm:as')
			defTup = (opsym,as') in
		    maybe defTup
			  (\ ts -> assert (not $ Set.isEmpty ts) 
			    (if Set.member (toOpType opType) ts
			        then addTup
			        else defTup))
			  (Map.lookup on fOps)
        in Application opsym' as'' qs
    Sorted_term trm ty ps -> Sorted_term (mapTERM mapEnv vars trm) ty ps 
    Cast trm ty ps -> Cast (mapTERM mapEnv vars trm) ty ps 
    Conditional t1 f t2 ps -> 
       Conditional (mapTERM mapEnv vars t1) 
		   (mapSen mapEnv vars f) 
		   (mapTERM mapEnv vars t2) ps
    _ -> error "Modal2CASL.mapTERM"

addPlace :: Id -> Id
addPlace i@(Id ts ids ps)
    | isMixfix i = Id ((\ (x,y) -> x++mkSimpleId place:y) 
                          (span (not . isPlace) ts)) ids ps
    | otherwise  = i

modalityToModName :: MODALITY -> ModName
modalityToModName (Simple_mod sid) = SimpleM sid
modalityToModName (Term_mod t) =
    case t of 
    Sorted_term _ srt _ -> SortM srt
    _ -> error ("Modal2CASL: modalityToModName: Wrong term: " ++ show t)

sortedWorldTerm :: SORT -> VAR -> TERM ()
sortedWorldTerm fws v = Sorted_term (Qual_var v fws []) fws [] 

replacePropPredication :: PRED_NAME -- ^ propositional symbol to replace
		       -> CASLFORMULA -- ^ Formula to insert
		       -> CASLFORMULA -- ^ Formula with placeholder
		       -> CASLFORMULA
replacePropPredication pSymb frmIns frmToChn =
    case frmToChn of
    Quantification q vs frm ps ->
	Quantification q vs (replacePropPredication pSymb frmIns frm) ps
    Conjunction fs ps -> 
	Conjunction (map (replacePropPredication pSymb frmIns) fs) ps 
    Implication f1 f2 b ps ->
	Implication f1 (replacePropPredication pSymb frmIns f2) b ps
    Predication (Qual_pred_name symb (Pred_type [] []) []) [] [] 
	| symb == pSymb -> frmIns
    p@(Predication _ _ _) -> p 
    _ -> error "Modal2CASL: replacePropPredication: unknown formula to replace"



addWorld_OP :: SORT -> OP_NAME -> Set.Set OpType 
	    -> Map.Map OP_NAME (Set.Set OpType) 
	    -> Map.Map OP_NAME (Set.Set OpType)
addWorld_OP = addWorld_ (\ws t -> t { opArgs =  ws : opArgs t})

addWorld_PRED :: SORT -> PRED_NAME -> Set.Set PredType 
	      -> Map.Map PRED_NAME (Set.Set PredType) 
	      -> Map.Map PRED_NAME (Set.Set PredType)
addWorld_PRED = addWorld_ (\ws t -> t {predArgs = ws : predArgs t})

addWorld_ :: (Ord a) => (SORT -> a -> a) 
	  -> SORT -> Id -> Set.Set a 
	  -> Map.Map OP_NAME (Set.Set a) 
	  -> Map.Map OP_NAME (Set.Set a)
addWorld_ f fws k set mp = Map.insert (addPlace k) (Set.image (f fws) set) mp

-- List of sort ids for possible Worlds
worldSorts :: [SORT]
worldSorts = map mkSORT ("World":map (\x -> "World" ++ show x) [(1::Int)..])
    where mkSORT s = mkId [mkSimpleId s]

freshWorldSort :: Set.Set SORT -> SORT
freshWorldSort _sorSet = mkId [mkSimpleId "g_World"]
    -- head . filter notKnown worldSorts
    -- where notKnown s = not $ s `Set.member` sorSet

-- List of variables for worlds
worldVars :: [SIMPLE_ID]
worldVars = map mkSimpleId $ map (\ x -> "g_w" ++ show x) [(1::Int)..]

freshWorldVar :: [SIMPLE_ID] -> SIMPLE_ID
freshWorldVar vs = head . (filter notKnown) $ worldVars
    where notKnown v = not $ elem v vs


{-
-- construct a relation from a given modality symbol which is new
consRelation :: Pred_map -- ^ map of allready known predicate symbols
             -> 		         
-}
