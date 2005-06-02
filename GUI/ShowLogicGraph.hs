{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  till@tzi.de
Stability   :  provisional
Portability :  non-portable (Logic)

  display the logic graph
   
-}

--   Version 0.9b, 11,06,2004

module GUI.ShowLogicGraph
where

-- for graph display
import DaVinciGraph
import GraphDisp
import GraphConfigure

-- for windows display
import TextDisplay
import Configuration
import qualified HTk
import Debug(debug)


--  data structure
import Comorphisms.LogicGraph
import Logic.Grothendieck
import Logic.Logic
import Logic.Comorphism
import Logic.Prover
import qualified Common.Lib.Map as Map
import Maybe

showLogicGraph ::
   (GraphAllConfig graph graphParms node nodeType nodeTypeParms
      arc arcType arcTypeParms)
   => (Graph graph graphParms node nodeType nodeTypeParms
         arc arcType arcTypeParms)
   -> IO ()
showLogicGraph
   (displaySort ::
       GraphDisp.Graph graph graphParms node nodeType nodeTypeParms arc 
          arcType arcTypeParms) =
    do 
       let graphParms = GraphTitle "Logic Graph" $$
                        OptimiseLayout True $$
                        AllowClose (return True) $$ 
                        emptyGraphParms
           disp s tD = debug (s ++ (show tD))
       logicG <- newGraph displaySort graphParms
       
 --      (killChannel :: Channel ()) <- newChannel   

       let logicNodeMenu = LocalMenu(Menu (Just "Info") 
               [Button "Tools" (\lg -> createTextDisplay ("Parsers, Provers and Cons_Checker of " ++ showTitle lg) (showTools lg) [size(80,25)]),
                Button "Sublogic" (\lg -> createTextDisplay ("Sublogics of " ++ showTitle lg) (showSublogic lg) [size(80,25)]),
                Button "Sublogic Graph" (\lg -> showSubLogicGraph displaySort lg),
                Button "Description" (\lg -> createTextDisplay ("Description of " ++ showTitle lg) (showDescription lg) [size(83,25)])
	       ])
           
           normalNodeTypeParms = 
               logicNodeMenu $$$
               Ellipse $$$
               ValueTitle (return . showTitle) $$$
               Color "green" $$$
               nullNodeParms

           proverNodeTypeParms = 
               logicNodeMenu $$$
               Ellipse $$$
               ValueTitle (return . showTitle) $$$
               Color "lightsteelblue" $$$
               nullNodeParms
      
       normalNodeType <- newNodeType logicG normalNodeTypeParms
       proverNodeType <- newNodeType logicG proverNodeTypeParms

       -- production of the nodes (in a list)
       nodeList <- mapM (newNode' logicG normalNodeType proverNodeType ) (Map.elems(logics logicGraph))
       -- build the map with the node's name and the node.
       let namesAndNodes = Map.fromList (zip (Map.keys(logics logicGraph)) nodeList)
       
           lookupLogic(Logic lid) = fromJust (Map.lookup (language_name lid) namesAndNodes)

           -- eath edge can also show the informations 
           -- (the description of comorphism and names of source/target-Logic as well as
	   -- the sublogics.)
           logicArcMenu = 
	       LocalMenu(Button "Info" 
                 (\c -> case c of
                         Comorphism cid ->
                          let ssid = G_sublogics (sourceLogic cid) (sourceSublogic cid)
                              tsid = G_sublogics (targetLogic cid) (targetSublogic cid)
                          in  createTextDisplay (show c) (showComoDescription c ++ "\n\n" ++
			      "source logic:     " ++ (language_name $ sourceLogic cid) ++
			      "\n\n" ++
                              "target logic:     " ++ (language_name $ targetLogic cid) ++ 
			      "\n" ++
                              "source sublogic:  " ++ showSubTitle ssid ++ "\n" ++
			      "target sublogic:  " ++ showSubTitle tsid)
                              [size(80,25)]))
           normalArcTypeParms = logicArcMenu $$$         -- normal comorphism
                                Color "black" $$$
				ValueTitle (\c -> case c of
                                                  Comorphism cid -> 
					            return $ language_name cid) $$$
                                nullArcTypeParms
                            
           inclArcTypeParms = logicArcMenu $$$           -- inclusion
                               Color "blue" $$$
                               nullArcTypeParms
                  
       normalArcType <- newArcType logicG normalArcTypeParms
       inclArcType   <- newArcType logicG inclArcTypeParms   
       
       let insertComo =            -- for cormophism
             (\c -> 
                case c of
                  Comorphism cid ->
                    let sid = Logic (sourceLogic cid)
                        tid = Logic (targetLogic cid)
                    in  newArc logicG normalArcType c (lookupLogic sid) (lookupLogic tid))   
           insertIncl =            -- for inclusion
             (\i -> 
                case i of
                  Comorphism cid -> 
                    let sid = Logic (sourceLogic cid)
                        tid = Logic (targetLogic cid)
                    in  newArc logicG inclArcType i (lookupLogic sid) (lookupLogic tid))
        
       arcList1 <- mapM insertIncl (Map.elems(inclusions logicGraph))
       arcList2 <- mapM insertComo  [rest | rest <- Map.elems(comorphisms logicGraph), not (rest `elem` (Map.elems(inclusions logicGraph)))] 
                  --(drop (length arcList1) (Map.elems (comorphisms logicGraph)))
       
       redraw logicG
{-       sync(
            (receive killChannel) >>> 
               do
                  putStrLn "Destroy graph"
                  destroy logicG
               
         +> (destroyed logicG)
         )
-}
    where 		
        (nullNodeParms :: nodeTypeParms AnyLogic) = emptyNodeTypeParms
	(nullArcTypeParms :: arcTypeParms AnyComorphism) = emptyArcTypeParms
	(nullSubNodeParms :: nodeTypeParms G_sublogics) = emptyNodeTypeParms
	(nullSubArcTypeParms:: arcTypeParms [Char]) = emptyArcTypeParms
	 
        showSublogic l = 
            case l of
              Logic lid -> unlines (map unwords $ 
                                map (sublogic_names lid) (all_sublogics lid))

	showSubTitle gsl = 
	    case gsl of 
	      G_sublogics lid sls -> unwords $ sublogic_names lid sls

        showTitle l = 
            case l of
              Logic lid -> language_name lid

        showDescription l =
	    case l of
              Logic lid -> description lid


        showComoDescription c =
	    case c of
              Comorphism cid -> description cid

        showTools lg = 
           case lg of
                Logic lid -> showParse lid ++ "\n" ++ showProver lid ++ "\n" ++ showConsChecker lid
	   where
             showProver lid = unlines $ map prover_name (provers lid)

             showConsChecker lid = unlines $ map prover_name (cons_checkers lid)
	     showParse lid =  
                   let s1 =  case parse_basic_spec lid of
			       Just _  -> "Parser for basic specifications.\n"
			       Nothing -> ""
		       s2 =  case parse_symb_items lid of
			       Just _ ->  "Parser for symbol lists.\n"
			       Nothing -> ""
		       s3 =  case parse_symb_map_items lid of
			       Just _ ->  "Parser for symbol maps.\n"
			       Nothing -> ""
		       s4 =  case parse_sentence lid of
			       Just _ ->  "Parser for sentences.\n"
			       Nothing -> ""
		       s5 =  case basic_analysis lid of
			       Just _ ->  "Analysis of basic specifications.\n"
			       Nothing -> ""
		       s6 =  case data_logic lid of	       
			       Just _ ->  "is a process logic.\n" 
			       Nothing -> ""
		   in  (s1 ++ s2 ++ s3 ++ s4 ++ s5 ++ s6)

        newNode' logicG normalNodeType proverNodeType logic = 
             case logic of
                  Logic lid -> if (hasProver lid) then
                                      newNode logicG proverNodeType logic
                               else
		                      newNode logicG normalNodeType logic
             where hasProver lid = 
                       not $ null $ provers lid

        showSubLogicGraph 
	   (displaySort' ::GraphDisp.Graph graph graphParms node nodeType nodeTypeParms arc arcType arcTypeParms) subl =
	  case subl of 
            Logic sublid ->  
	      do 
	         let 
                     graphParms = GraphTitle "SubLogic Graph" $$
				             OptimiseLayout True $$
                                             AllowClose (return True) $$ 
		        		     emptyGraphParms
							    
                 subLogicG <- newGraph displaySort' graphParms 
   
	         let 
                     listG_Sublogics = map (\subl -> G_sublogics sublid subl) (all_sublogics sublid)
                     subNodeMenu = LocalMenu (Menu Nothing [])

                     subNodeTypeParms = 
		         subNodeMenu $$$
		         Ellipse $$$
			 ValueTitle 
			   (\gsl -> case gsl of 
			              G_sublogics lid sls' -> 
			                return (unwords $ sublogic_names lid sls')) $$$
		         Color "yellow" $$$
		         nullSubNodeParms
	         subNodeType <- newNodeType subLogicG subNodeTypeParms
	         
	         subNodeList <- mapM (newNode subLogicG subNodeType) listG_Sublogics 

                 let 
                     slAndNodes = zip listG_Sublogics subNodeList
                     lookupSublogic(g_sl) = 
                          fromJust (lookup (g_sl) slAndNodes)
                     subArcMenu = LocalMenu( Menu Nothing [])
		     subArcTypeParms = subArcMenu $$$
				       Color "green" $$$
				       nullSubArcTypeParms
                 subArcType <- newArcType subLogicG subArcTypeParms
		 
                 let 
                     insertSubArc = 
                       \(node1, node2) -> 
                           newArc subLogicG subArcType "" node1 node2
                 subArcList <- mapM insertSubArc [(lookupSublogic(g1), lookupSublogic(g2)) |
                                    g1 <- listG_Sublogics, g2 <- listG_Sublogics,
                                    g1 < g2, not (any (\g -> g1<g && g<g2)  listG_Sublogics)]
		                 
                 redraw subLogicG


showLG = showLogicGraph daVinciSort

