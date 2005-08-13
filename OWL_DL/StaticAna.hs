{- |
Module      :  $Header$
Copyright   :  Heng Jiang, Uni Bremen 2004-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luettich@tzi.de
Stability   :  provisional
Portability :  portable

-}


module OWL_DL.StaticAna where

import OWL_DL.Sign
import OWL_DL.AS
import Text.XML.HXT.DOM.XmlTreeTypes
-- import Common.Id
-- import List
-- import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import Common.AS_Annotation
import Common.Result
import Common.GlobalAnnotations
import OWL_DL.Namespace
-- import Debug.Trace

basicOWL_DLAnalysis :: 
    (Ontology, Sign, GlobalAnnos) ->
	Result (Ontology,Sign,Sign,[Named Sentence])
basicOWL_DLAnalysis (ontology@(Ontology _ _ ns), inSign, ga) =
    let (integNamespace, transMap) = 
	    integrateNamespaces (namespaceMap inSign) ns
	ontology' = renameNamespace transMap ontology
        Result diags1 (Just (onto, accSign, namedSen)) = 
	    anaOntology ga (inSign {namespaceMap = integNamespace}) ontology'
	diffSign = diffSig accSign inSign
    in  Result diags1 $ Just (onto, diffSign, accSign, namedSen)

anaOntology :: GlobalAnnos -> Sign -> Ontology
            -> Result (Ontology,Sign,[Named Sentence]) 
anaOntology ga inSign ontology =
    case ontology of
     Ontology (Just ontoID) directives ns ->
       anaDirective ga (inSign {ontologyID = ontoID}) 
			(Ontology (Just ontoID) [] ns) directives
     Ontology Prelude.Nothing directives ns ->
	anaDirective ga (inSign {ontologyID = nullID}) 
			 (Ontology Prelude.Nothing [] ns) directives
			  
-- concat the current result with total result 
-- first parameter is an result from current directive
-- second parameter is the total result
concatResult :: Result (Ontology,Sign,[Named Sentence]) 
	     -> Result (Ontology,Sign,[Named Sentence]) 
	     -> Result (Ontology,Sign,[Named Sentence]) 
concatResult (Result diag1 maybeRes1) (Result diag2 maybeRes2) =
    case maybeRes1 of
    Prelude.Nothing -> 
	case maybeRes2 of 
	Prelude.Nothing -> Result (diag2++diag1) Prelude.Nothing
	_ -> Result (diag2++diag1) maybeRes2
    Just (Ontology maybeID1 direc1 _, _, namedSen1) -> 
	case maybeRes2 of
	 Prelude.Nothing -> Result (diag2++diag1) maybeRes1
	 Just (Ontology maybeID2 direc2 ons2, inSign2, namedSen2) ->
         -- the namespace of first ontology muss be same as the second.  
	    if maybeID1 /= maybeID2 then
	       error "unknow error in concatResult"
	       else let -- todo: concat ontology
                        accSign = inSign2 -- insertSign inSign1 inSign2
                        namedSen = namedSen2 ++ namedSen1
                        direc = direc2 ++ direc1
                    in Result (diag2 ++ diag1) 
			 (Just (Ontology maybeID2 direc ons2,accSign,namedSen))

anaDirective :: GlobalAnnos -> Sign -> Ontology -> [Directive]
		-> Result (Ontology,Sign,[Named Sentence])
anaDirective _ _ _ [] = initResult
anaDirective ga inSign onto@(Ontology mID direc ns) (directiv:rest) = 
  case directiv of
    Ax clazz@(Class cId _ _ _ _) -> 
     let (isPrimary, diags1) = checkPrimaryConcept clazz
     in if null diags1 then
	   if isPrimary then 
	     let c = concepts inSign
		 pc = primaryConcepts inSign
		 accSign = inSign { concepts = Set.insert cId c,
				    primaryConcepts = Set.insert cId pc}
	     in  concatResult (Result [] (Just (onto, accSign, [])))
		       (anaDirective ga accSign onto rest)
	    -- normal concept has super concept
	    else let c = concepts inSign
		     accSign = inSign {concepts = Set.insert cId c}
	         in  concatResult (Result [] (Just (onto, accSign, [])))
		       (anaDirective ga accSign onto rest)
	  else concatResult (Result diags1 Prelude.Nothing)
		       (anaDirective ga inSign onto rest)
    Ax (EnumeratedClass cId _ _ _) ->   -- Enumerate is not primary
        let c = concepts inSign
	    accSign = inSign {concepts = Set.insert cId c}
        in  concatResult (Result [] (Just (onto, accSign, [])))
	         (anaDirective ga accSign onto rest)      
    Ax dc@(DisjointClasses des1 des2 deses) ->
      let Result diags1 maybeRes = checkConcept (des1:des2:deses) inSign
      in  case maybeRes of
          Just _ -> 
	    let namedSent = NamedSen { senName = "DisjointClasses",	
				       isAxiom = True,	
				       sentence = OWLAxiom dc
				     }
            in  concatResult (Result diags1 
			      (Just (Ontology mID (direc ++ [directiv]) ns, 
				     inSign, [namedSent])))
	            (anaDirective ga inSign onto rest)  
	  _ -> concatResult (Result diags1 Prelude.Nothing) 
	           (anaDirective ga inSign onto rest)
    Ax ec@(EquivalentClasses des1 deses) ->
      let Result diags1 maybeRes = checkConcept (des1:deses) inSign
      in  case maybeRes of 
          Just _ -> 
	    let namedSent = NamedSen { senName = "EquivalentClasses",	
				       isAxiom = True,	
				       sentence = OWLAxiom ec
				     }
	    in  concatResult (Result diags1 
			       (Just (Ontology mID (direc ++ [directiv]) ns,
				      inSign, [namedSent])))
	             (anaDirective ga inSign onto rest)
 	  _ -> concatResult (Result diags1 Prelude.Nothing) 
	           (anaDirective ga inSign onto rest)
    -- ToDO: build subClassOf from Class constructure. -> done
    Ax (SubClassOf des1@(DC cid1) des2@(DC cid2)) ->
      let Result diags1 maybeRes = checkConcept (des1:des2:[]) inSign
      in  case maybeRes of 
          Just _ -> 
	      let ax = axioms inSign
		  accSign = inSign { axioms = 
				      Set.insert (Subconcept cid1 cid2) ax}
              in  concatResult (Result diags1
				(Just (onto, accSign, [])))
	              (anaDirective ga accSign onto rest)
	  _ -> concatResult (Result diags1 Prelude.Nothing) 
	           (anaDirective ga inSign onto rest)
    Ax (Datatype dtId _ _) -> 
	let d = datatypes inSign
            accSign = inSign {datatypes = Set.insert dtId d}
	in  concatResult (Result [] (Just (onto, accSign, [])))
	          (anaDirective ga accSign onto rest)  
    Ax (DatatypeProperty dpId _ _ _ isFunc domains ranges) ->
	let dvr = dataValuedRoles inSign
	    ax = axioms inSign
	    roleDomains = foldDomain dpId domains ax
	    roleRanges = foldDRange dpId ranges roleDomains
	    accSign = if isFunc then
		         inSign { dataValuedRoles = Set.insert dpId dvr,
				  axioms = Set.insert (FuncRole dpId) 
				                      roleRanges
				}
			 else inSign { dataValuedRoles = Set.insert dpId dvr,
				       axioms = roleRanges
				     }
        in concatResult ( Result [] (Just (onto, accSign, [])))
	          (anaDirective ga accSign onto rest)  
    Ax (ObjectProperty ivId _ _ _ _ _ maybeFunc domains ranges) ->
        let ivr = indValuedRoles inSign
	    ax = axioms inSign
	    roleDomains = foldDomain ivId domains ax
	    roleRanges = foldIRange ivId ranges roleDomains
	    accSign = case maybeFunc of
		         Just Transitive -> 
			     inSign { indValuedRoles = Set.insert ivId ivr,
				      axioms = roleRanges
				    }
			 Just _ ->
			     inSign { indValuedRoles = Set.insert ivId ivr,
				      axioms = Set.insert (FuncRole ivId) 
				                           roleRanges
				    }
			 _ -> inSign { indValuedRoles = Set.insert ivId ivr,
				       axioms = roleRanges
				     }
        in concatResult ( Result [] (Just (onto, accSign, [])))
	          (anaDirective ga accSign onto rest)  
    Ax (AnnotationProperty apid _) -> 
	let accSign = inSign { annotationRoles = 
			            Set.insert apid (annotationRoles inSign)
			     }
      {-
	let namedSent = NamedSen { senName = "AnnotationProperty",	
				   isAxiom = True,	
				   sentence = OWLAxiom ap
				 }
      -}
        in  concatResult (Result [] (Just (onto, accSign, [])))
	        (anaDirective ga accSign onto rest) 
    Ax op@(OntologyProperty _ _ ) ->
	let namedSent = NamedSen { senName = "OntologyProperty",	
				   isAxiom = True,	
				   sentence = OWLAxiom op
				 }
        in concatResult (Result [] (Just (Ontology mID (direc++[directiv]) ns,
					  inSign, [namedSent])))
	        (anaDirective ga inSign onto rest) 
    Ax dep@(DEquivalentProperties pid1 pid2 pids) -> 
      let Result diags1 maybeRes = checkDRole (pid1:pid2:pids) inSign
      in  case maybeRes of
          Just _ -> 
	      let namedSent = 
		      NamedSen { senName = "DataValuedEquivalentProterties",
				 isAxiom = True,	
				 sentence = OWLAxiom dep
			       }
              in  concatResult (Result [] 
				(Just (Ontology mID (direc ++ [directiv]) ns,
				       inSign, [namedSent])))
		      (anaDirective ga inSign onto rest) 
	  _ -> concatResult (Result diags1 Prelude.Nothing) 
	           (anaDirective ga inSign onto rest)
    Ax dsp@(DSubPropertyOf pid1 pid2) ->
      let Result diags1 maybeRes = checkDRole (pid1:pid2:[]) inSign
      in  case maybeRes of
          Just _ -> 
	      let namedSent = 
		      NamedSen { senName = "DataValuedSubPropertyOf",	
				 isAxiom = True,	
				 sentence = OWLAxiom dsp
			       }
	      in  concatResult (Result [] 
				(Just (Ontology mID (direc ++ [directiv]) ns,
				       inSign, [namedSent])))
	              (anaDirective ga inSign onto rest)
	  _ -> concatResult (Result diags1 Prelude.Nothing) 
	           (anaDirective ga inSign onto rest)  
    Ax iep@(IEquivalentProperties pid1 pid2 pids) ->
      let Result diags1 maybeRes = checkORole (pid1:pid2:pids) inSign
      in  case maybeRes of
          Just _ -> 
	      let namedSent = 
		    NamedSen {senName = "IndividualValuedEquivalentProperties",
			      isAxiom = True,	
			      sentence = OWLAxiom iep
			     }
	      in   concatResult (Result [] 
				 (Just (Ontology mID (direc ++ [directiv]) ns,
					inSign, [namedSent])))
	               (anaDirective ga inSign onto rest)
 	  _ -> concatResult (Result diags1 Prelude.Nothing) 
	           (anaDirective ga inSign onto rest)
    Ax isp@(ISubPropertyOf pid1 pid2) -> 
      let Result diags1 maybeRes = checkORole (pid1:pid2:[]) inSign
      in  case maybeRes of
          Just _ -> 
	      let namedSent = 
		      NamedSen { senName = "IndividualValuedSubPropertyOf",
				 isAxiom = True,	
				 sentence = OWLAxiom isp
			       }
              in  concatResult (Result [] 
				(Just (Ontology mID (direc ++ [directiv]) ns,
				       inSign, [namedSent])))
	              (anaDirective ga inSign onto rest) 
 	  _ -> concatResult (Result diags1 Prelude.Nothing) 
	           (anaDirective ga inSign onto rest)
    Fc ind@(Indiv (Individual maybeIID _ types _)) ->
       case maybeIID of
	Prelude.Nothing ->          -- Error (Warnung): Individual without name
	    let namedSent = NamedSen { senName = "Individual",	
				       isAxiom = False,	
				       sentence = OWLFact ind
				     }
            in  concatResult (Result [] 
			      (Just (Ontology mID (direc ++ [directiv]) ns, 
				     inSign, [namedSent])))
	        (anaDirective ga inSign onto rest)
	Just iid -> 
	    let oriInd = individuals inSign
	    in  let (diagL, membershipSet) = msSet iid types ([], Set.empty) 
		    ax = axioms inSign 
		    accSign = 
                       	inSign {individuals = Set.insert iid oriInd,
				axioms = Set.union membershipSet ax
			       }
	        in  concatResult 
			 (Result diagL (Just (onto, accSign, [])))
			 (anaDirective ga accSign onto rest) 
 
	  where 				  
                msSet :: IndividualID -> [Type] 
		      -> ([Diagnosis], Set.Set SignAxiom)
		      -> ([Diagnosis], Set.Set SignAxiom)
		msSet _ [] res = res
		msSet rid (h:r) (diagL, ms) =
		    case h of
		    DC _ ->
			let membership = Conceptmembership rid h
			in  msSet rid r (diagL, Set.insert membership ms)
		    _ -> let membership = Conceptmembership rid h
		             diag' = mkDiag Warning 
				       ("individual " ++ 
					(show rid) ++ 
					" is a member of complex description.")
				       ()
		         in  msSet iid r (diagL ++ [diag'], 
					  Set.insert membership ms)
     
    Fc si@(SameIndividual _ _ _) ->
	let namedSent = NamedSen { senName = "SameIndividual",	
				   isAxiom = False,	
				   sentence = OWLFact si
				 }
        in  concatResult (Result [] (Just (Ontology mID (direc++[directiv]) ns,
					   inSign, [namedSent])))
	        (anaDirective ga inSign onto rest) 
    Fc di@(DifferentIndividuals _ _ _) ->
	let namedSent = NamedSen { senName = "DifferentIndividuals",	
				   isAxiom = False,	
				   sentence = OWLFact di
				 }
        in  concatResult (Result [] (Just (Ontology mID (direc++[directiv]) ns,
					   inSign, [namedSent])))
	        (anaDirective ga inSign onto rest) 
    _ -> concatResult initResult (anaDirective ga inSign onto rest) 
          -- erstmal ignoriere another
 			
    where foldDomain :: ID -> [Description] 
		     -> Set.Set SignAxiom -> Set.Set SignAxiom
	  foldDomain _ [] s = s
	  foldDomain rId (h:r) s = 
	      foldDomain rId r (Set.insert (RoleDomain rId (RDomain h)) s)

          foldDRange :: ID -> [DataRange] 
		     -> Set.Set SignAxiom -> Set.Set SignAxiom
	  foldDRange _ [] s = s
	  foldDRange rId (h:r) s =
	      foldDRange rId r (Set.insert (RoleRange rId (RDRange h)) s)

          foldIRange :: ID -> [Description] 
		     -> Set.Set SignAxiom -> Set.Set SignAxiom
	  foldIRange _ [] s = s
	  foldIRange rId (h:r) s =
	      foldIRange rId r (Set.insert (RoleRange rId (RIRange h)) s)

          -- if CASL_Sort == false then the concept is not primary
          checkPrimaryConcept :: Axiom -> (Bool,[Diagnosis])
	  checkPrimaryConcept (Class cid _ _ annos _) =
	      hasRealCASL_sortWithValue annos True True []
           where
            hasRealCASL_sortWithValue :: [OWL_DL.AS.Annotation] 
				      -> Bool -> Bool 
				      -> [Diagnosis] 
				      -> (Bool, [Diagnosis])
	    hasRealCASL_sortWithValue [] _ res diags1 = (res, diags1)
	    hasRealCASL_sortWithValue 
	      ((DLAnnotation aid tl):r) first res diags1 =
		  if localPart aid == "CASL_Sort" then
		    case tl of
		    TypedL (b, _) -> 
		     if first then
		        if b == "false" then 
			  hasRealCASL_sortWithValue r False False diags1
			  else if b == "true" then
			         hasRealCASL_sortWithValue 
			                     r False True diags1
				 else (False, 
				       ((mkDiag Error 
				          ("CASL_Sort error in " ++ 
					                  (show cid))
				          ()):diags1)
				      )
		      else (False, 
			    ((mkDiag Error 
			        ((show cid)++" has more than two CASL_Sort")
			        ()):diags1)
			   ) 
		    _ -> hasRealCASL_sortWithValue r first res diags1
		    else  hasRealCASL_sortWithValue r first res diags1
	    hasRealCASL_sortWithValue (_:r) first res diags1 = 
		      hasRealCASL_sortWithValue r first res diags1
	  checkPrimaryConcept _ = (False, [])
	  
          checkConcept :: [Description] -> Sign -> Result Bool
	  checkConcept deses sign =
	      checkDes deses sign initResult
	   where
            checkDes :: [Description] -> Sign 
	                    -> Result Bool -> Result Bool
	    checkDes [] _ res = res
	    checkDes (h:r) sign1 res1@(Result diag1 _) =
		case h of
		DC cid -> if checkClass cid sign1 then
			    checkDes r sign1 (res1 {maybeResult = Just True})
			    else let diag2 = 
				      mkDiag Error 
				       (show cid ++ " has not be declared.")
				       ()
				  in Result (diag1 ++ [diag2]) Prelude.Nothing
                UnionOf deses2 -> checkDes (r ++ deses2) sign1 res1
                IntersectionOf deses2 -> checkDes (r ++ deses2) sign1 res1
		ComplementOf des2 -> checkDes (r ++ [des2]) sign1 res1
                _ -> checkDes r sign1 res1		
	  
          checkClass :: ClassID -> Sign -> Bool
	  checkClass cid sign1 =
	      Set.member cid (concepts sign1) 
	  
          checkDRole :: [DatavaluedPropertyID] -> Sign -> Result Bool
	  checkDRole roleIDs sign =
	      checkDRole' roleIDs sign initResult
	    where 
	      checkDRole' :: [DatavaluedPropertyID] -> Sign 
	                    -> Result Bool -> Result Bool
	      checkDRole' [] _ res = res
	      checkDRole' (h:r) sign2 res@(Result diag1 _) =
		  if Set.member h (dataValuedRoles sign2) then
		     checkDRole' r sign2 (res {maybeResult = Just True})
		     else let diag2 = mkDiag Error 
				         (show h ++ " has not be declared.") 
					 ()
		          in Result (diag1 ++ [diag2]) Prelude.Nothing

          checkORole :: [IndividualvaluedPropertyID] -> Sign -> Result Bool
	  checkORole roleIDs sign =
	      checkORole' roleIDs sign initResult
	    where 
	      checkORole' :: [IndividualvaluedPropertyID] -> Sign 
	                    -> Result Bool -> Result Bool
	      checkORole' [] _ res = res
	      checkORole' (h:r) sign3 res@(Result diag1 _) =
		  if Set.member h (indValuedRoles sign3) then
		     checkORole' r sign3 (res {maybeResult = Just True})
		     else let diag2 = mkDiag Error 
				         (show h ++ " has not be declared.") 
					 ()
		          in Result (diag1 ++ [diag2]) Prelude.Nothing
nullID :: ID
nullID = QN "" "" ""

initResult :: Result a
initResult = Result [] Prelude.Nothing

