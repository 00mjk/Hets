{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

   parse SIG-ITEMS, BASIC-ITEMS, BASIC-SPEC 
   Follows Sect. II:3.1 of the CASL Reference Manual.
-}

{- 
   http://www.cofi.info/Documents/CASL/Summary/
   from 25 March 2001

   C.2.1 Basic Specifications with Subsorts
-}

module CASL.Parse_AS_Basic where

import Common.AnnoState
import Common.Id
import Common.Keywords
import Common.Lexer
import CASL.AS_Basic_CASL
import Common.AS_Annotation
import Text.ParserCombinators.Parsec
import CASL.Formula
import CASL.SortItem
import CASL.OpItem

-- ------------------------------------------------------------------------
-- sigItems
-- ------------------------------------------------------------------------

sortItems, typeItems, opItems, predItems, sigItems 
    :: (AParsable s, AParsable f) => [String] -> AParser st (SIG_ITEMS s f)
sortItems ks = itemList ks sortS sortItem Sort_items
typeItems ks = itemList ks typeS datatype Datatype_items
opItems   ks = itemList ks opS opItem Op_items
predItems ks = itemList ks predS predItem Pred_items
sigItems ks = fmap Ext_SIG_ITEMS aparser <|>
	   sortItems ks <|> opItems ks <|> predItems ks <|> typeItems ks

---- helpers ----------------------------------------------------------------

datatypeToFreetype :: (AParsable b, AParsable s, AParsable f) =>
                      SIG_ITEMS s f -> [Pos] -> BASIC_ITEMS b s f 
datatypeToFreetype d pos =
   case d of
     Datatype_items ts ps -> Free_datatype ts (pos ++ ps)
     _ -> error "datatypeToFreetype"

axiomToLocalVarAxioms :: (AParsable b, AParsable s, AParsable f) => 
     BASIC_ITEMS b s f -> [Annotation] -> [VAR_DECL] -> [Pos] 
     -> BASIC_ITEMS b s f
axiomToLocalVarAxioms ai a vs posl =
   case ai of
     Axiom_items ((Annoted ft qs as rs):fs) ds ->  
	 let aft = Annoted ft qs (a++as) rs
	     in Local_var_axioms vs (aft:fs) (posl ++ ds)
     _ -> error "axiomToLocalVarAxioms"

-- ------------------------------------------------------------------------
-- basicItems
-- ------------------------------------------------------------------------

basicItems :: (AParsable b, AParsable s, AParsable f) => 
	      [String] -> AParser st (BASIC_ITEMS b s f)
basicItems ks = fmap Ext_BASIC_ITEMS aparser <|> fmap Sig_items (sigItems ks)
	     <|> do f <- asKey freeS
		    ti <- typeItems ks
		    return (datatypeToFreetype ti (tokPos f))
	     <|> do g <- asKey generatedS
		    do t <- typeItems ks
		       return (Sort_gen [Annoted t [] [] []] $ tokPos g)
		      <|> 
		      do o <- oBraceT
			 is <- annosParser (sigItems ks)
			 c <- cBraceT
                         a <- lineAnnos 
			 return (Sort_gen (init is ++ [appendAnno (last is) a])
				   (toPos g [o] c)) 
	     <|> do v <- pluralKeyword varS
		    (vs, ps) <- varItems ks
		    return (Var_items vs (catPos (v:ps)))
	     <|> do f <- forallT 
		    (vs, ps) <- varDecl ks `separatedBy` anSemi 
		    a <- annos
		    ai <- dotFormulae ks
		    return (axiomToLocalVarAxioms ai a vs 
                           $ catPos (f:ps))
	     <|> dotFormulae ks
             <|> itemList ks axiomS formula Axiom_items

varItems :: [String] -> AParser st ([VAR_DECL], [Token])
varItems ks = 
    do v <- varDecl ks
       do s <- try (addAnnos >> Common.Lexer.semiT) << addLineAnnos
	  do   tryItemEnd (ks ++ startKeyword)
	       return ([v], [s])
	    <|> do (vs, ts) <- varItems ks
		   return (v:vs, s:ts)
         <|> return ([v], [])
             
dotFormulae :: (AParsable b, AParsable s, AParsable f) => 
	       [String] -> AParser st (BASIC_ITEMS b s f)
dotFormulae ks = 
    do d <- dotT
       (fs, ds) <- aFormula ks `separatedBy` dotT
       (m, an) <- optSemi
       let ps = catPos (d:ds) 
	   ns = init fs ++ [appendAnno (last fs) an]
       return $ Axiom_items ns (ps ++ catPos m)

aFormula  :: AParsable f => [String] -> AParser st (Annoted (FORMULA f))
aFormula ks = bind appendAnno (annoParser $ formula ks) lineAnnos

-- ------------------------------------------------------------------------
-- basicSpec
-- ------------------------------------------------------------------------

basicSpec :: (AParsable f, AParsable s, AParsable b) => 
	     [String] -> AParser st (BASIC_SPEC b s f)
basicSpec ks = (fmap Basic_spec $ annosParser $ basicItems ks)
            <|> (oBraceT >> cBraceT >> return (Basic_spec []))
